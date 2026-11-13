// The GitLab account for the whole shell: the one linkage under Settings ›
// Accounts that anything reading GitLab uses, the way `GithubAccountStore` is
// GitHub's.
//
// It owns what every consumer would otherwise repeat:
//
//  * **The connect**, which is a form rather than a browser flow (see
//    `gitlab_api.dart` for why a personal access token): the instance and the
//    token are tried against `/user` before anything is kept, so a typo is a
//    message on the card rather than a dashboard that silently reads nothing.
//    Not tied to anybody's lease, and cancellable — a mistyped host may never
//    answer.
//  * **The token**, read once off disk and held in memory, handed to a request
//    through [withToken] with the instance it belongs to.
//  * **The failure that changes state.** A token GitLab rejects — they expire —
//    signs the shell out *here*, once, with the reason on the card.
//
// No widgets of its own; tests inject a client, a temporary token directory and
// an opener.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/gitlab/gitlab_api.dart';
import 'package:moonswing/gitlab/gitlab_token_store.dart';

/// How far along the account is.
enum GitlabAuthStage {
  /// No token. Settings › Accounts offers the form.
  signedOut,

  /// A token is being tried against the instance.
  connecting,

  /// There is a token; consumers may make requests.
  signedIn,
}

/// The account, its connect, and the token behind every request.
class GitlabAccountStore extends ChangeNotifier {
  GitlabAccountStore._({
    GitlabClient? client,
    GitlabTokenStore? tokens,
    bool Function(String url)? opener,
  }) : _client = client ?? const HttpGitlabClient(),
       _tokens = tokens ?? const GitlabTokenStore(),
       _open = opener ?? openUriWithDefault;

  static final GitlabAccountStore instance = GitlabAccountStore._();

  /// A detached store for tests: nothing here opens a socket unless [client]
  /// does, or a browser unless [opener] does.
  @visibleForTesting
  factory GitlabAccountStore.forTesting({
    required GitlabClient client,
    required GitlabTokenStore tokens,
    bool Function(String url)? opener,
  }) => GitlabAccountStore._(
    client: client,
    tokens: tokens,
    opener: opener ?? (_) => true,
  );

  final GitlabClient _client;
  final GitlabTokenStore _tokens;
  final bool Function(String url) _open;

  /// The client consumers read through, so a test that fakes one fakes both.
  GitlabClient get client => _client;

  // --- published state -----------------------------------------------------

  GitlabAuthStage _stage = GitlabAuthStage.signedOut;
  GitlabAuthStage get stage => _stage;

  bool get signedIn => _stage == GitlabAuthStage.signedIn;
  bool get connecting => _stage == GitlabAuthStage.connecting;

  Uri? _instance;

  /// The instance the account is on, while signed in.
  Uri? get instanceUri => _instance;

  /// `gitlab.com`, or the self-managed host — how the card and the Code tab
  /// say which GitLab this is.
  String get host => _instance?.host ?? '';

  String _username = '';
  String get username => _username;

  String _name = '';

  /// The display name, where the instance gave one.
  String get name => _name;

  /// What the account is called on screen: `user@host` off gitlab.com, since
  /// the same name on two instances is two people.
  String get label {
    if (_username.isEmpty) return 'GitLab account';
    return host == kGitlabDefaultHost ? _username : '$_username@$host';
  }

  String _error = '';

  /// Why the last connect failed, or why the account was signed out.
  String get error => _error;

  bool _loaded = false;
  bool get loaded => _loaded;

  String? _token;

  /// The token, while signed in — for consumers that only need to know
  /// *which* grant they are looking at, so a list read under one account is
  /// never shown under the next. Requests go through [withToken].
  String? get token => _token;

  String get _signature => [
    _stage.name,
    _instance,
    _username,
    _name,
    _error,
    _loaded,
    _token?.hashCode ?? 0,
  ].join('|');

  String _published = '';

  void _publish() {
    final signature = _signature;
    if (signature == _published) return;
    _published = signature;
    notifyListeners();
  }

  // --- loading -------------------------------------------------------------

  Future<void>? _loading;

  /// Reads the saved account. Idempotent.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final saved = await _tokens.read();
    _loaded = true;
    final instance = saved == null ? null : gitlabInstanceUri(saved.instance);
    // A connect that finished while the file was being read wins over it.
    if (saved != null && instance != null && _token == null) {
      _instance = instance;
      _token = saved.token;
      _username = saved.username;
      _name = saved.name;
      _stage = GitlabAuthStage.signedIn;
    }
    _publish();
  }

  // --- requests ------------------------------------------------------------

  /// Runs [request] with the instance and token. A [GitlabAuthException] from
  /// it signs the account out, with the reason, and goes on to the caller.
  Future<T> withToken<T>(
    Future<T> Function(Uri instance, String token) request,
  ) async {
    await load();
    final token = _token;
    final instance = _instance;
    if (token == null || instance == null) {
      throw const GitlabException('Not signed in to GitLab');
    }
    try {
      return await request(instance, token);
    } on GitlabAuthException catch (e) {
      if (_token == token) {
        await _forget();
        _error = e.message;
        _publish();
      }
      rethrow;
    }
  }

  // --- connecting ----------------------------------------------------------

  /// Bumped by a cancel or a sign-out; a connect that comes back to a moved
  /// generation is dropped rather than signing the user in after all.
  int _generation = 0;

  /// Tries [token] against [host] and keeps the account if it answers.
  /// Returns whether it was kept.
  Future<bool> connect({required String host, required String token}) async {
    if (_stage == GitlabAuthStage.connecting) return false;
    final instance = gitlabInstanceUri(host);
    final trimmed = token.trim();
    if (instance == null) {
      _error = 'That is not the address of a GitLab instance';
      _publish();
      return false;
    }
    if (trimmed.isEmpty) {
      _error = 'Paste a personal access token';
      _publish();
      return false;
    }
    final generation = ++_generation;
    final previous = _stage;
    _stage = GitlabAuthStage.connecting;
    _error = '';
    _publish();

    final GitlabUser user;
    try {
      user = await _client.fetchUser(instance: instance, token: trimmed);
    } on GitlabAuthException {
      if (generation != _generation) return false;
      _stage = previous;
      _error = 'GitLab did not accept that token';
      _publish();
      return false;
    } on GitlabException catch (e) {
      if (generation != _generation) return false;
      _stage = previous;
      _error = e.message;
      _publish();
      return false;
    } catch (e) {
      debugPrint('gitlab: $e');
      if (generation != _generation) return false;
      _stage = previous;
      _error = 'Could not reach ${instance.host}';
      _publish();
      return false;
    }
    if (generation != _generation) return false;

    final saved = await _tokens.write(
      GitlabSavedAccount(
        instance: instance.toString(),
        token: trimmed,
        username: user.username,
        name: user.name,
      ),
    );
    if (generation != _generation) return false;
    _instance = instance;
    _token = trimmed;
    _username = user.username;
    _name = user.name;
    _stage = GitlabAuthStage.signedIn;
    // A token that could not be saved still signs this session in; it says
    // so, because it will not have stuck.
    _error = saved ? '' : 'Signed in, but the token could not be saved';
    _publish();
    return true;
  }

  /// Abandons a connect in flight.
  void cancelConnect() {
    if (_stage != GitlabAuthStage.connecting) return;
    _generation++;
    _stage = _token == null
        ? GitlabAuthStage.signedOut
        : GitlabAuthStage.signedIn;
    _publish();
  }

  /// Forgets the token. It does not revoke it — only the instance can, from
  /// its token page, which [openTokenPage] opens.
  Future<void> signOut() async {
    await _forget();
    _error = '';
    _publish();
  }

  Future<void> _forget() async {
    _generation++;
    _token = null;
    _instance = null;
    _username = '';
    _name = '';
    _stage = GitlabAuthStage.signedOut;
    await _tokens.clear();
  }

  void clearError() {
    if (_error.isEmpty) return;
    _error = '';
    _publish();
  }

  // --- pages ---------------------------------------------------------------

  /// Opens [host]'s page for making a token, with the name and scope filled
  /// in — the signed-in instance's when [host] is null. Says so when there is
  /// no browser.
  void openTokenPage([String? host]) {
    final instance =
        (host == null ? null : gitlabInstanceUri(host)) ??
        _instance ??
        gitlabInstanceUri(kGitlabDefaultHost)!;
    final url = gitlabTokenPage(instance).toString();
    if (_open(url)) return;
    _error = 'Could not open a browser. Go to $url';
    _publish();
  }

  /// Opens the account's profile.
  void openProfile() {
    final instance = _instance;
    if (instance == null || _username.isEmpty) return;
    _open(instance.replace(path: '/$_username').toString());
  }

  /// Seeds a store for a widget test, with no client behind it.
  @visibleForTesting
  void seed({
    GitlabAuthStage stage = GitlabAuthStage.signedIn,
    String host = kGitlabDefaultHost,
    String username = 'tanuki',
    String error = '',
    String token = 'seeded-token',
  }) {
    _loading = Future.value();
    _loaded = true;
    _stage = stage;
    final signedIn = stage == GitlabAuthStage.signedIn;
    _instance = signedIn ? gitlabInstanceUri(host) : null;
    _username = signedIn ? username : '';
    _token = signedIn ? token : null;
    _error = error;
    _publish();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
