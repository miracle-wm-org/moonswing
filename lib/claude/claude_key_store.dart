// Where the Claude API key lives between sessions:
// `~/.local/state/moonswing/anthropic-api-key`, at 0600 in a 0700 directory.
//
// Every reason `github_token_store.dart` gives for a file in the XDG *state*
// directory — rather than `config.toml`, which is pasted into bug reports, or
// a keyring, which is a second daemon and a prompt at login — holds here, and
// more so: this key spends money.
//
// Flutter-free, so the store above it stays testable off a temporary directory.

import 'dart:io';

import 'package:moonswing/native/libc.dart';

/// Reads, writes and clears the saved key.
class ClaudeKeyStore {
  const ClaudeKeyStore({String? directory}) : _directory = directory;

  /// Overridden by tests. Null means the real one, resolved per call.
  final String? _directory;

  String get directory => _directory ?? _defaultDirectory();

  String get path => '$directory/anthropic-api-key';

  static String _defaultDirectory() {
    final env = Platform.environment;
    final state = env['XDG_STATE_HOME'];
    if (state != null && state.isNotEmpty) return '$state/moonswing';
    final home = env['HOME'] ?? '.';
    return '$home/.local/state/moonswing';
  }

  /// The saved key, or null when there is none. Never throws: an unreadable
  /// file and a signed-out shell have the same answer, which is the key field.
  Future<String?> read() async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final key = (await file.readAsString()).trim();
      return key.isEmpty ? null : key;
    } catch (_) {
      return null;
    }
  }

  /// Saves [key]. Returns whether it landed; the caller says so if not.
  Future<bool> write(String key) async {
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) await dir.create(recursive: true);
      // Narrowed before the file is created inside it, so the key is never
      // world-readable for even an instant.
      chmodPath(directory, 0x1C0); // 0700
      final file = File(path);
      // Created empty and narrowed *before* the key is written into it.
      await file.writeAsString('', flush: true);
      chmodPath(path, 0x180); // 0600
      await file.writeAsString('$key\n', flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Forgets the key, whatever state the file is in.
  Future<void> clear() async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The session has already dropped the key; nothing useful to surface.
    }
  }
}
