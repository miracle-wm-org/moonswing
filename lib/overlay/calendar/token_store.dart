import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/overlay/calendar/google_oauth.dart';

/// Persists OAuth tokens for each connected calendar account.
///
/// Deliberately not in `config.toml`: the settings UI rewrites that file
/// wholesale, and it is the kind of file people copy between machines and paste
/// into bug reports. Tokens live in their own 0600 file under `XDG_DATA_HOME`.
///
/// TODO: move this to the Secret Service D-Bus API (`org.freedesktop.secrets`),
/// which needs no new dependency since `dbus` is already used by the tray and
/// notification services. It is deferred because it requires an unlocked
/// keyring, which would add a new way for the shell to fail at startup.
class CalendarTokenStore {
  CalendarTokenStore({@visibleForTesting String? path})
      : _path = path ?? resolvePath();

  final String _path;

  /// Mirrors [AppConfig.resolveConfigPath] so the two never drift.
  static String resolvePath() {
    final homeDir = Platform.environment['HOME'] ?? '';
    final dataHome =
        Platform.environment['XDG_DATA_HOME'] ?? '$homeDir/.local/share';
    return '$dataHome/graceful-shell/calendar_tokens.json';
  }

  /// Every stored account, keyed by provider id. A missing or corrupt file
  /// yields an empty map rather than throwing: a mangled token file should cost
  /// the user a reconnect, not a shell that will not start.
  Future<Map<String, OAuthTokens>> loadAll() async {
    try {
      final file = File(_path);
      if (!await file.exists()) return {};

      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return {};

      final tokens = <String, OAuthTokens>{};
      for (final entry in json.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          tokens[entry.key] = OAuthTokens.fromJson(value);
        }
      }
      return tokens;
    } catch (e) {
      debugPrint('Could not read calendar tokens: $e');
      return {};
    }
  }

  Future<void> save(String providerId, OAuthTokens tokens) async {
    final all = await loadAll();
    all[providerId] = tokens;
    await _write(all);
  }

  Future<void> clear(String providerId) async {
    final all = await loadAll();
    if (all.remove(providerId) == null) return;
    await _write(all);
  }

  Future<void> _write(Map<String, OAuthTokens> tokens) async {
    final file = File(_path);
    await file.parent.create(recursive: true);

    // Same tmp-then-rename dance as ConfigStore.save(): a crash mid-write must
    // not leave a half-written file that reads back as corrupt.
    final tmp = File('$_path.tmp');
    await tmp.writeAsString(
      jsonEncode({for (final e in tokens.entries) e.key: e.value.toJson()}),
    );
    await _restrictPermissions(tmp.path);
    await tmp.rename(_path);
  }

  /// Dart has no chmod, so shell out. Done on the temp file before the rename,
  /// so the tokens are never briefly world-readable at their final path.
  Future<void> _restrictPermissions(String path) async {
    try {
      await Process.run('chmod', ['600', path]);
    } catch (e) {
      debugPrint('Could not restrict permissions on $path: $e');
    }
  }
}
