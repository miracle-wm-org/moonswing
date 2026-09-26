// The Claude account for the whole shell: the API key linked under Settings ›
// Accounts, the way `GithubAccountStore` is GitHub's.
//
// The sign-in is a key pasted from the Claude Console rather than a browser
// flow — `claude_api.dart` says why a claude.ai subscription cannot be the
// account — and it is checked before it is kept: a read of the model list,
// which spends no tokens, so a typo is caught in Settings rather than on the
// first question. A key the API later rejects signs the shell out *here*, with
// the reason, rather than every consumer showing a retry that can only fail.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/claude/claude_api.dart';
import 'package:moonswing/claude/claude_key_store.dart';

/// How far along the link is.
enum ClaudeAuthStage {
  /// No key. Settings › Accounts offers the field.
  signedOut,

  /// A key has been typed and is being checked.
  verifying,

  /// There is a key; consumers may make requests.
  signedIn,
}

/// The account, its sign-in, and the key behind every request.
class ClaudeAccountStore extends ChangeNotifier {
  ClaudeAccountStore._({
    ClaudeClient? client,
    ClaudeKeyStore? keys,
    bool Function(String url)? opener,
  }) : _client = client ?? HttpClaudeClient(),
       _keys = keys ?? const ClaudeKeyStore(),
       _open = opener ?? openUriWithDefault;

  static final ClaudeAccountStore instance = ClaudeAccountStore._();

  /// A detached store for tests: an injected client, a key file under a
  /// temporary directory, and an opener that records rather than launching.
  @visibleForTesting
  factory ClaudeAccountStore.forTesting({
    required ClaudeClient client,
    required ClaudeKeyStore keys,
    bool Function(String url)? opener,
  }) => ClaudeAccountStore._(
    client: client,
    keys: keys,
    opener: opener ?? (_) => true,
  );

  final ClaudeClient _client;
  final ClaudeKeyStore _keys;
  final bool Function(String url) _open;

  /// The client consumers make their requests through, so a test that fakes
  /// one fakes both.
  ClaudeClient get client => _client;

  // --- published state -----------------------------------------------------

  ClaudeAuthStage _stage = ClaudeAuthStage.signedOut;
  ClaudeAuthStage get stage => _stage;

  bool get signedIn => _stage == ClaudeAuthStage.signedIn;

  bool get busy => _stage == ClaudeAuthStage.verifying;

  /// Why the last link failed, or why the key was dropped. Empty otherwise.
  String _error = '';
  String get error => _error;

  bool _loaded = false;
  bool get loaded => _loaded;

  String? _key;

  /// The key as Settings shows it: its prefix and last four characters, which
  /// is how the Console itself lists keys — enough to tell two apart, not
  /// enough to use.
  String get keyHint => claudeKeyHint(_key);

  String get _signature => [
    _stage.name,
    _error,
    _loaded,
    // Never the key itself in a string that could be logged.
    _key?.hashCode ?? 0,
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

  /// Reads the saved key. Idempotent.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final key = await _keys.read();
    _loaded = true;
    // A link that finished while the file was being read wins over it.
    if (key != null && _key == null) {
      _key = key;
      _stage = ClaudeAuthStage.signedIn;
    }
    _publish();
  }

  // --- requests ------------------------------------------------------------

  /// Runs [request] with the key. A [ClaudeAuthException] means the key is
  /// gone — deleted in the Console — so the account signs out, with the
  /// reason, and the exception goes on to the caller.
  Future<T> withKey<T>(Future<T> Function(String key) request) async {
    await load();
    final key = _key;
    if (key == null) throw const ClaudeException('Not signed in to Claude');
    try {
      return await request(key);
    } on ClaudeAuthException {
      if (_key == key) await _expire(_rejected);
      rethrow;
    }
  }

  /// The key, for a consumer that streams: [withKey] suits a request that
  /// completes, and a stream is read long after it would have returned. The
  /// consumer reports a rejection through [reportRejected].
  Future<String?> currentKey() async {
    await load();
    return _key;
  }

  /// A request made with [key] was rejected as unauthenticated.
  Future<void> reportRejected(String key) async {
    if (_key == key) await _expire(_rejected);
  }

  static const String _rejected =
      'The Claude API no longer accepts this key. It may have been deleted in '
      'the Console — make a new one and link it again.';

  Future<void> _expire(String message) async {
    await _forget();
    _error = message;
    _publish();
  }

  // --- the sign-in ---------------------------------------------------------

  int _generation = 0;

  /// Checks [raw] against the API and keeps it if it is taken.
  Future<void> signIn(String raw) async {
    final key = raw.trim();
    if (key.isEmpty || _stage == ClaudeAuthStage.verifying) return;
    final generation = ++_generation;
    _stage = ClaudeAuthStage.verifying;
    _error = '';
    _publish();

    try {
      await _client.verifyKey(key);
    } on ClaudeAuthException {
      _fail(
        generation,
        'That key was not accepted. Copy it again from the Console — it is '
        'shown once, when it is created.',
      );
      return;
    } on ClaudeException catch (e) {
      _fail(generation, e.message);
      return;
    } catch (e) {
      debugPrint('claude: $e');
      _fail(generation, 'Could not reach the Claude API');
      return;
    }
    if (generation != _generation) return;

    final saved = await _keys.write(key);
    if (generation != _generation) return;
    _key = key;
    _stage = ClaudeAuthStage.signedIn;
    // A key that could not be saved still links this session; it is said,
    // because it will not survive the next start-up.
    _error = saved ? '' : 'Linked, but the key could not be saved';
    _publish();
  }

  void _fail(int generation, String message) {
    if (generation != _generation) return;
    _stage = ClaudeAuthStage.signedOut;
    _error = message;
    _publish();
  }

  /// Forgets the key. It is not revoked — only the Console can do that, which
  /// is what [openConsoleKeys] is for — and Settings says so.
  Future<void> signOut() async {
    await _forget();
    _error = '';
    _publish();
  }

  Future<void> _forget() async {
    _generation++;
    _key = null;
    _stage = ClaudeAuthStage.signedOut;
    await _keys.clear();
  }

  void clearError() {
    if (_error.isEmpty) return;
    _error = '';
    _publish();
  }

  /// Opens the Console's API keys page: where a key is made, and revoked.
  void openConsoleKeys() => _openOrSay(kClaudeConsoleKeysUrl);

  /// Opens the Console's usage page: what the key has cost.
  void openConsoleUsage() => _openOrSay(kClaudeConsoleUsageUrl);

  void _openOrSay(String url) {
    if (_open(url)) return;
    _error = 'Could not open a browser. Go to $url';
    _publish();
  }

  /// Seeds a store for a widget test, with no client call behind it.
  @visibleForTesting
  void seed({
    ClaudeAuthStage stage = ClaudeAuthStage.signedIn,
    String error = '',
    String key = 'sk-ant-api03-seeded-key-abcd',
  }) {
    _loading = Future.value();
    _loaded = true;
    _stage = stage;
    _error = error;
    _key = stage == ClaudeAuthStage.signedIn ? key : null;
    _publish();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}

/// `sk-ant-api03-…abcd`: a key's prefix up to its last dash-separated field
/// before the secret, and its last four characters. Empty for no key.
String claudeKeyHint(String? key) {
  if (key == null || key.isEmpty) return '';
  if (key.length <= 12) return '…';
  final tail = key.substring(key.length - 4);
  final match = RegExp(r'^(sk-ant-[a-z]+\d*-)').firstMatch(key);
  final head = match?.group(1) ?? key.substring(0, 3);
  return '$head…$tail';
}
