// Where the GitHub access token lives between sessions.
//
// Not in `config.toml`. That file is hand-edited, pasted into bug reports,
// rewritten by the settings UI on every keystroke and world-readable like any
// other config; a bearer token is none of those things. It goes in the XDG
// *state* directory instead — `~/.local/state/moonswing/github-token` —
// which is exactly what that directory is for, in a directory narrowed to 0700
// before the file is written into it, and the file itself at 0600.
//
// There is no keyring here on purpose. The Secret Service API would mean a
// second D-Bus dependency, a prompt at login on a machine whose keyring is
// locked, and a feature that silently does nothing wherever no keyring daemon
// is running. `gh` stores its token as a plain file for the same reasons.
//
// Flutter-free, so the store above it stays testable off a temporary directory.

import 'dart:io';

import 'package:moonswing/native/libc.dart';

/// Reads, writes and clears the saved token.
class GithubTokenStore {
  const GithubTokenStore({String? directory}) : _directory = directory;

  /// Overridden by tests, which point this at a temporary directory. Null means
  /// the real one, resolved per call so a test that sets `XDG_STATE_HOME`
  /// cannot be defeated by a value cached at start-up.
  final String? _directory;

  /// The directory the token file sits in.
  String get directory => _directory ?? _defaultDirectory();

  /// The token file itself.
  String get path => '$directory/github-token';

  static String _defaultDirectory() {
    final env = Platform.environment;
    final state = env['XDG_STATE_HOME'];
    if (state != null && state.isNotEmpty) return '$state/moonswing';
    final home = env['HOME'] ?? '.';
    return '$home/.local/state/moonswing';
  }

  /// The saved token, or null when there is none.
  ///
  /// Never throws: an unreadable token file is indistinguishable from a signed
  /// out shell as far as everything above this is concerned, and the sign-in
  /// button is the answer to both.
  Future<String?> read() async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final token = (await file.readAsString()).trim();
      return token.isEmpty ? null : token;
    } catch (_) {
      return null;
    }
  }

  /// Saves [token], creating the directory if it is not there.
  ///
  /// Returns whether it landed. A false answer is not fatal — the session keeps
  /// the token it is holding and the user simply signs in again next time —
  /// but the caller says so rather than pretending the sign-in stuck.
  Future<bool> write(String token) async {
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) await dir.create(recursive: true);
      // Narrowed before the file is created inside it, so the token is never
      // world-readable for even an instant.
      chmodPath(directory, 0x1C0); // 0700
      final file = File(path);
      await file.writeAsString('$token\n', flush: true);
      chmodPath(path, 0x180); // 0600
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Forgets the token. Signing out must work whatever state the file is in, so
  /// a missing file and a failed delete are both simply done.
  Future<void> clear() async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing useful to surface: the session has already dropped the token.
    }
  }
}
