// Where the Google account lives between sessions: the grant Google handed back
// and the address it belongs to.
//
// Not in `config.toml`, for `github_token_store.dart`'s reasons — that file is
// hand-edited, pasted into bug reports and world-readable, and a refresh token
// is a standing grant to read somebody's calendar. The file is
// `~/.local/state/moonswing/google-account.json`, in a directory narrowed to
// 0700 before it is written, and itself 0600.
//
// The OAuth client is the project's own (`google_client.dart`) and is not
// saved. Only its ID is, beside the grant, as the record of which client that
// grant was issued to: a refresh token is bound to its client, so one saved
// under any other — a client the user once pasted in themselves, or one the
// project has since rotated away from — can never be refreshed and is dropped
// on load. Files written before the shell shipped its own client also carry a
// `client_secret`; it is ignored, and gone at the next write.
//
// Flutter-free, so the store above it stays testable off a temporary directory.

import 'dart:convert';
import 'dart:io';

import 'package:moonswing/native/libc.dart';

/// What is saved.
class GoogleAccountData {
  const GoogleAccountData({
    this.clientId = '',
    this.refreshToken,
    this.email = '',
  });

  /// The client [refreshToken] was issued to. Empty when unknown.
  final String clientId;

  /// Null while signed out.
  final String? refreshToken;

  /// The signed-in address, for the settings row. Empty when unknown.
  final String email;

  /// Drops the grant. The client it was issued to goes with it, since there
  /// is nothing left for it to describe.
  GoogleAccountData signedOut() => const GoogleAccountData();

  Map<String, Object?> toJson() => {
    if (clientId.isNotEmpty) 'client_id': clientId,
    if (refreshToken != null) 'refresh_token': refreshToken,
    if (email.isNotEmpty) 'email': email,
  };

  /// A wrongly-typed key costs that key.
  static GoogleAccountData fromJson(Object? json) {
    if (json is! Map) return const GoogleAccountData();
    String text(String key) =>
        json[key] is String ? (json[key] as String).trim() : '';
    final refresh = text('refresh_token');
    return GoogleAccountData(
      clientId: text('client_id'),
      refreshToken: refresh.isEmpty ? null : refresh,
      email: text('email'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GoogleAccountData &&
      other.clientId == clientId &&
      other.refreshToken == refreshToken &&
      other.email == email;

  @override
  int get hashCode => Object.hash(clientId, refreshToken, email);
}

/// Reads, writes and clears the saved account.
class GoogleAccountFile {
  const GoogleAccountFile({String? directory}) : _directory = directory;

  /// Overridden by tests. Null means the real one, resolved per call.
  final String? _directory;

  String get directory => _directory ?? _defaultDirectory();

  String get path => '$directory/google-account.json';

  static String _defaultDirectory() {
    final env = Platform.environment;
    final state = env['XDG_STATE_HOME'];
    if (state != null && state.isNotEmpty) return '$state/moonswing';
    final home = env['HOME'] ?? '.';
    return '$home/.local/state/moonswing';
  }

  /// The saved account, or an empty one. Never throws: an unreadable file and
  /// no file are the same thing to everything above this, and the settings
  /// page is the answer to both.
  Future<GoogleAccountData> read() async {
    try {
      final file = File(path);
      if (!await file.exists()) return const GoogleAccountData();
      return GoogleAccountData.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return const GoogleAccountData();
    }
  }

  /// Saves [data]. Returns whether it landed; a false answer is not fatal —
  /// the session keeps what it holds — but the caller says so.
  Future<bool> write(GoogleAccountData data) async {
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) await dir.create(recursive: true);
      // Narrowed before the file is created inside it, so the grant is never
      // world-readable for even an instant.
      chmodPath(directory, 0x1C0); // 0700
      final file = File(path);
      // Created empty and narrowed before anything secret is written into it.
      if (!await file.exists()) await file.create();
      chmodPath(path, 0x180); // 0600
      await file.writeAsString('${jsonEncode(data.toJson())}\n', flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Forgets everything. A missing file and a failed delete are both done.
  Future<void> clear() async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
