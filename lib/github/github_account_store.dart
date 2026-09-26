// The GitHub account for the whole shell: the sign-in under Settings ›
// Accounts that any module or widget can use, the way `GoogleAccountStore` is
// Google's.
//
// It owns the three things every consumer would otherwise repeat:
//
//  * **The sign-in**, which is a *state machine with a timer in it* rather than
//    a dialog: ask for a code, show it, poll until the user has typed it into a
//    browser, save the token. It lives here rather than in a widget because a
//    settings page that owned it would lose it the moment the overlay closed —
//    and it is not tied to anybody's lease for the same reason. It ends on its
//    own when the code expires, a quarter of an hour at most.
//  * **The token**, read once off disk (`github_token_store.dart`) and held in
//    memory, handed to a request through [withToken].
//  * **The failure that changes state.** A token GitHub rejects signs the shell
//    out *here*, with the reason on screen, rather than every consumer showing
//    its own retry that can only fail.
//
// A consumer such as `GithubStore` listens here for the account coming and
// going, and asks [withToken] for each request. It has no widgets of its own; a
// click opens a page through GIO (`app_info.dart`), and tests inject an opener.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_token_store.dart';

/// How far along the sign-in is.
enum GithubAuthStage {
  /// No token. Settings › Accounts offers **Sign in**.
  signedOut,

  /// Asking GitHub for a user code.
  requestingCode,

  /// The code is on screen and the shell is polling for the user to type it in
  /// at github.com/login/device.
  awaitingAuthorization,

  /// There is a token; consumers may make requests.
  signedIn,
}

/// The account, its sign-in, and the token behind every request.
class GithubAccountStore extends ChangeNotifier {
  GithubAccountStore._({
    GithubClient? client,
    GithubTokenStore? tokens,
    bool Function(String url)? opener,
  }) : _client = client ?? const HttpGithubClient(),
       _tokens = tokens ?? const GithubTokenStore(),
       _open = opener ?? openUriWithDefault;

  static final GithubAccountStore instance = GithubAccountStore._();

  /// A detached store for tests: an injected client, a token file under a
  /// temporary directory, and an opener that records rather than launching a
  /// browser. Nothing here opens a socket unless [client] does.
  @visibleForTesting
  factory GithubAccountStore.forTesting({
    required GithubClient client,
    required GithubTokenStore tokens,
    bool Function(String url)? opener,
    String clientId = kGithubDefaultClientId,
    String scopes = kGithubDefaultScopes,
  }) => GithubAccountStore._(
    client: client,
    tokens: tokens,
    opener: opener ?? (_) => true,
  )..configure(clientId: clientId, scopes: scopes);

  final GithubClient _client;
  final GithubTokenStore _tokens;
  final bool Function(String url) _open;

  /// The client consumers make their requests through, so a test that fakes
  /// one fakes both.
  GithubClient get client => _client;

  // --- configuration -------------------------------------------------------

  String _clientId = kGithubDefaultClientId;
  String _scopes = kGithubDefaultScopes;

  /// The OAuth app the device flow runs against and the scopes it asks for —
  /// `[modules.github] client_id` and `scopes`, pushed here by the module's
  /// `fromMap`. They only matter to the *next* sign-in: a token already granted
  /// keeps the scopes it was granted with.
  void configure({required String clientId, required String scopes}) {
    _clientId = clientId.isEmpty ? kGithubDefaultClientId : clientId;
    _scopes = scopes.isEmpty ? kGithubDefaultScopes : scopes;
  }

  /// The scopes the next sign-in asks for, as settings shows them.
  String get scopes => _scopes;

  // --- published state -----------------------------------------------------

  GithubAuthStage _stage = GithubAuthStage.signedOut;
  GithubAuthStage get stage => _stage;

  /// Whether there is a token to make requests with.
  bool get signedIn => _stage == GithubAuthStage.signedIn;

  /// The code the user types, while [stage] is
  /// [GithubAuthStage.awaitingAuthorization]. Null otherwise.
  GithubDeviceCode? _deviceCode;
  GithubDeviceCode? get deviceCode => _deviceCode;

  /// The signed-in account, once `/user` has answered. Empty before that — a
  /// login is a nicety and must not gate anything on a second request.
  String _login = '';
  String get login => _login;

  /// What the account is called on screen.
  String get label => _login.isEmpty ? 'GitHub account' : _login;

  /// Why the last sign-in failed, or why the account was signed out. Empty
  /// otherwise. A failure is a visible state: settings says why, and offers the
  /// way out.
  String _error = '';
  String get error => _error;

  /// True while the sign-in's first request is in flight.
  bool get busy => _stage == GithubAuthStage.requestingCode;

  bool _loaded = false;

  /// Whether the saved token has been read.
  bool get loaded => _loaded;

  /// The token, while signed in. Consumers go through [withToken]; this is for
  /// the ones that only need to know *which* grant they are looking at, so a
  /// list fetched under one account is never shown under the next.
  String? _token;
  String? get token => _token;

  String get _signature => [
    _stage.name,
    _login,
    _error,
    _deviceCode?.userCode ?? '',
    _loaded,
    // The token itself never goes in a string that could be logged; whether it
    // changed is what matters, and its hash says that.
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

  /// Reads the saved token. Idempotent; the start-up task calls it and a
  /// consumer that got there first simply awaits the same read.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final token = await _tokens.read();
    _loaded = true;
    // A sign-in that finished while the file was being read wins over it.
    if (token != null && _token == null) {
      _token = token;
      _stage = GithubAuthStage.signedIn;
      unawaited(_fetchLogin());
    }
    _publish();
  }

  Future<void> _fetchLogin() async {
    final token = _token;
    if (token == null) return;
    try {
      final login = await _client.fetchLogin(token);
      if (login.isEmpty || login == _login || _token != token) return;
      _login = login;
      _publish();
    } on GithubAuthException catch (e) {
      if (_token == token) await _expire(e.message);
    } catch (e) {
      debugPrint('github: could not read the account name: $e');
    }
  }

  // --- requests ------------------------------------------------------------

  /// Runs [request] with the token.
  ///
  /// A [GithubAuthException] from the request means the grant is gone —
  /// revoked on github.com, or expired — so the account signs out, with the
  /// reason, and the exception goes on to the caller.
  Future<T> withToken<T>(Future<T> Function(String token) request) async {
    await load();
    final token = _token;
    if (token == null) throw const GithubException('Not signed in to GitHub');
    try {
      return await request(token);
    } on GithubAuthException catch (e) {
      if (_token == token) await _expire(e.message);
      rethrow;
    }
  }

  Future<void> _expire(String message) async {
    await _forget();
    _error = message;
    _publish();
  }

  // --- the sign-in ---------------------------------------------------------

  /// Bumped by [signOut] and [cancelSignIn]; the device-flow loop compares it
  /// and gives up when it has moved. A cancelled sign-in must not finish half
  /// a minute later and log the user in anyway.
  int _signInGeneration = 0;

  /// Runs the device flow: ask for a code, publish it for settings to show,
  /// then poll until the user has typed it in at github.com.
  ///
  /// Awaitable but not meant to be awaited by a widget — it runs for as long as
  /// the user takes, which is the whole point of publishing the code as state.
  Future<void> signIn() async {
    if (_stage != GithubAuthStage.signedOut) return;
    final generation = ++_signInGeneration;
    _stage = GithubAuthStage.requestingCode;
    _error = '';
    _publish();

    final GithubDeviceCode code;
    try {
      code = await _client.requestDeviceCode(
        clientId: _clientId,
        scopes: _scopes,
      );
    } on GithubException catch (e) {
      _failSignIn(generation, e.message);
      return;
    } catch (e) {
      debugPrint('github: $e');
      _failSignIn(generation, 'Could not reach GitHub');
      return;
    }
    if (generation != _signInGeneration) return;

    _deviceCode = code;
    _stage = GithubAuthStage.awaitingAuthorization;
    _publish();
    // The code is published first: the browser is about to take the focus, and
    // the page behind it must already say what to type into it.
    openVerificationPage();
    await _pollForToken(code, generation);
  }

  /// Opens the page the user types their code into.
  ///
  /// Also called for them the moment the code arrives — which is what
  /// `gh auth login` does — so the button beside the code is a second chance
  /// rather than the only one. A browser that will not open is said out loud:
  /// the code on screen is useless without one.
  void openVerificationPage() {
    final code = _deviceCode;
    if (code == null) return;
    if (_open(code.verificationUri)) return;
    _error = 'Could not open a browser. Go to ${code.verificationUri}';
    _publish();
  }

  /// Opens the account's page on github.com.
  void openProfile() {
    if (_login.isEmpty) return;
    _open('https://github.com/$_login');
  }

  /// Opens github.com's list of authorised applications — the one place a
  /// grant can actually be revoked.
  void openApplications() {
    _open('https://github.com/settings/applications');
  }

  /// The poll loop, at the interval GitHub asked for and no faster: `slow_down`
  /// is the API saying it will start refusing otherwise, and the spec's answer
  /// is five more seconds per occurrence.
  Future<void> _pollForToken(GithubDeviceCode code, int generation) async {
    var interval = Duration(seconds: code.interval);
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));

    while (generation == _signInGeneration) {
      await Future<void>.delayed(interval);
      if (generation != _signInGeneration) return;
      if (DateTime.now().isAfter(deadline)) {
        _failSignIn(generation, 'The sign-in code expired. Try again.');
        return;
      }

      final GithubTokenResult result;
      try {
        result = await _client.pollAccessToken(
          clientId: _clientId,
          deviceCode: code.deviceCode,
        );
      } on GithubException catch (e) {
        _failSignIn(generation, e.message);
        return;
      } catch (e) {
        debugPrint('github: $e');
        _failSignIn(generation, 'Could not reach GitHub');
        return;
      }
      if (generation != _signInGeneration) return;

      switch (result) {
        case GithubTokenPending(slowDown: final slowDown):
          if (slowDown) interval += const Duration(seconds: 5);
        case GithubTokenGranted(token: final token):
          await _completeSignIn(token, generation);
          return;
      }
    }
  }

  Future<void> _completeSignIn(String token, int generation) async {
    final saved = await _tokens.write(token);
    if (generation != _signInGeneration) return;
    _token = token;
    _login = '';
    _deviceCode = null;
    _stage = GithubAuthStage.signedIn;
    // A token that could not be saved still signs this session in: the user did
    // the work, and losing it at the next start-up is better than losing it now.
    // It is not silent, because the sign-in will not have stuck.
    _error = saved ? '' : 'Signed in, but the token could not be saved';
    _publish();
    await _fetchLogin();
  }

  void _failSignIn(int generation, String message) {
    if (generation != _signInGeneration) return;
    _stage = GithubAuthStage.signedOut;
    _deviceCode = null;
    _error = message;
    _publish();
  }

  /// Abandons a sign-in in progress. The poll loop notices on its next turn.
  void cancelSignIn() {
    if (_stage != GithubAuthStage.requestingCode &&
        _stage != GithubAuthStage.awaitingAuthorization) {
      return;
    }
    _signInGeneration++;
    _stage = GithubAuthStage.signedOut;
    _deviceCode = null;
    _publish();
  }

  /// Forgets the token.
  ///
  /// It does *not* revoke the grant — only github.com can do that, which is
  /// what [openApplications] is for — so settings says so rather than implying
  /// the authorisation is gone.
  Future<void> signOut() async {
    await _forget();
    _error = '';
    _publish();
  }

  Future<void> _forget() async {
    _signInGeneration++;
    _token = null;
    _login = '';
    _deviceCode = null;
    _stage = GithubAuthStage.signedOut;
    await _tokens.clear();
  }

  /// Clears a shown failure. The settings row's dismiss.
  void clearError() {
    if (_error.isEmpty) return;
    _error = '';
    _publish();
  }

  /// Seeds a store for a widget test, with no client and no timer behind it.
  @visibleForTesting
  void seed({
    GithubAuthStage stage = GithubAuthStage.signedIn,
    String login = '',
    String error = '',
    GithubDeviceCode? deviceCode,
    String token = 'seeded-token',
  }) {
    _loading = Future.value();
    _loaded = true;
    _stage = stage;
    _login = login;
    _error = error;
    _deviceCode = deviceCode;
    _token = stage == GithubAuthStage.signedIn ? token : null;
    _publish();
  }

  @override
  void dispose() {
    _signInGeneration++;
    super.dispose();
  }
}
