// Where the GitLab account lives between sessions: the instance, the token, and
// who the token belongs to.
//
// Beside GitHub's token in the XDG *state* directory, for the reasons
// `github_token_store.dart` gives — never in `config.toml`, which is
// hand-edited, pasted into bug reports and world-readable — in a directory
// narrowed to 0700 before the file is written into it, and the file at 0600.
// One small JSON object rather than a bare token, because a GitLab token means
// nothing without the instance that issued it.
//
// Flutter-free, so the store above it stays testable off a temporary directory.

import 'dart:convert';
import 'dart:io';

import 'package:moonswing/native/libc.dart';

/// What is saved: enough to make a request and to say as whom.
class GitlabSavedAccount {
  const GitlabSavedAccount({
    required this.instance,
    required this.token,
    required this.username,
    this.name = '',
  });

  /// `https://gitlab.com` — see `gitlabInstanceUri`.
  final String instance;
  final String token;
  final String username;
  final String name;

  Map<String, String> toJson() => {
    'instance': instance,
    'token': token,
    'username': username,
    'name': name,
  };

  /// Null for anything missing the three fields a request needs.
  static GitlabSavedAccount? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    String field(String key) {
      final value = json[key];
      return value is String ? value.trim() : '';
    }

    final instance = field('instance');
    final token = field('token');
    final username = field('username');
    if (instance.isEmpty || token.isEmpty || username.isEmpty) return null;
    return GitlabSavedAccount(
      instance: instance,
      token: token,
      username: username,
      name: field('name'),
    );
  }
}

/// Reads, writes and clears the saved account.
class GitlabTokenStore {
  const GitlabTokenStore({String? directory}) : _directory = directory;

  /// Overridden by tests. Null resolves the real one per call.
  final String? _directory;

  String get directory => _directory ?? _defaultDirectory();

  String get path => '$directory/gitlab-account';

  static String _defaultDirectory() {
    final env = Platform.environment;
    final state = env['XDG_STATE_HOME'];
    if (state != null && state.isNotEmpty) return '$state/moonswing';
    final home = env['HOME'] ?? '.';
    return '$home/.local/state/moonswing';
  }

  /// The saved account, or null. Never throws: an unreadable file is a signed
  /// out shell, and the card's form is the answer to both.
  Future<GitlabSavedAccount?> read() async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return GitlabSavedAccount.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  /// Saves [account]. Returns whether it landed.
  Future<bool> write(GitlabSavedAccount account) async {
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) await dir.create(recursive: true);
      chmodPath(directory, 0x1C0); // 0700
      final file = File(path);
      // Created empty and narrowed *before* the token is written into it, so
      // the secret is never on disk under the umask's mode.
      if (!await file.exists()) await file.writeAsString('');
      chmodPath(path, 0x180); // 0600
      await file.writeAsString(jsonEncode(account.toJson()), flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The session has already dropped the token.
    }
  }
}
