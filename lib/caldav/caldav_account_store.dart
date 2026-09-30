// The CalDAV account behind Settings › Accounts: a server, a user name and a
// password, and the task lists found there.
//
// Not `config.toml`, for the reason `github/github_token_store.dart` gives:
// a password is none of the things a config file is. It is one JSON file in the
// XDG *state* directory — `~/.local/state/moonswing/caldav-account.json` — in
// a directory narrowed to 0700 before the file is written, and the file itself
// at 0600. An app password, where the server offers one, is what the form asks
// for.
//
// Signing in *is* discovery: the address is only kept once the server has
// answered it with the user's task lists, so a typo or a wrong password is
// said on the form rather than on the todo board an hour later.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:moonswing/caldav/caldav_client.dart';
import 'package:moonswing/native/libc.dart';

/// A CalDAV server and the credentials for it.
@immutable
class CalDavAccount {
  const CalDavAccount({
    required this.url,
    required this.username,
    required this.password,
    this.trustedCertificate,
  });

  /// What the user typed: the server, a principal, or one calendar.
  final String url;
  final String username;
  final String password;

  /// The SHA-256 fingerprint of a certificate the user chose to trust for
  /// this server beyond what the system trusts, or null.
  final String? trustedCertificate;

  CalDavAccount withTrustedCertificate(String? fingerprint) => CalDavAccount(
    url: url,
    username: username,
    password: password,
    trustedCertificate: fingerprint,
  );

  /// "me on dav.example.com".
  String get label {
    final host = Uri.tryParse(url)?.host ?? url;
    return username.isEmpty ? host : '$username on $host';
  }

  @override
  bool operator ==(Object other) =>
      other is CalDavAccount &&
      other.url == url &&
      other.username == username &&
      other.password == password &&
      other.trustedCertificate == trustedCertificate;

  @override
  int get hashCode => Object.hash(url, username, password, trustedCertificate);
}

/// The signed-in CalDAV account, and the task lists on it.
class CalDavAccountStore extends ChangeNotifier {
  CalDavAccountStore._({String? directory, http.Client? client})
    : _directory = directory,
      _httpClient = client;

  static final CalDavAccountStore instance = CalDavAccountStore._();

  /// A store over [directory], asking [client] rather than the network.
  @visibleForTesting
  factory CalDavAccountStore.forTesting({
    required String directory,
    http.Client? client,
  }) => CalDavAccountStore._(directory: directory, client: client);

  final String? _directory;
  final http.Client? _httpClient;

  CalDavAccount? _account;
  List<CalDavCollection> _taskLists = const [];
  bool _loaded = false;
  Future<void>? _loading;
  bool _busy = false;
  String _error = '';
  CalDavCertificate? _untrusted;

  /// Counts sign-in attempts, so one [cancelSignIn] abandoned can tell, when
  /// its server finally answers, that nobody is waiting for it any more.
  int _signInAttempt = 0;
  bool _signingIn = false;

  /// The connection a sign-in with no injected client runs over, closed by
  /// [cancelSignIn] so the request is dropped rather than left to time out.
  http.Client? _signInConnection;

  /// The directory the account file sits in, resolved per call so a test that
  /// sets `XDG_STATE_HOME` is not defeated by a value cached at start-up.
  String get directory {
    final override = _directory;
    if (override != null) return override;
    final env = Platform.environment;
    final state = env['XDG_STATE_HOME'];
    if (state != null && state.isNotEmpty) return '$state/moonswing';
    return '${env['HOME'] ?? '.'}/.local/state/moonswing';
  }

  /// The account file.
  String get path => '$directory/caldav-account.json';

  /// The signed-in account, or null.
  CalDavAccount? get account => _account;

  /// The task lists found on the account, as of sign-in or the last
  /// [refreshTaskLists].
  List<CalDavCollection> get taskLists => _taskLists;

  /// Whether [load] has finished.
  bool get loaded => _loaded;

  /// A sign-in or a refresh is under way.
  bool get busy => _busy;

  /// A [signIn] is waiting on the server, and [cancelSignIn] would stop it.
  bool get signingIn => _signingIn;

  /// Why the last sign-in or refresh failed, or empty.
  String get error => _error;

  /// The certificate the last sign-in or refresh was refused over, which the
  /// user may choose to trust; null otherwise.
  CalDavCertificate? get untrustedCertificate => _untrusted;

  void clearError() {
    if (_error.isEmpty && _untrusted == null) return;
    _error = '';
    _untrusted = null;
    notifyListeners();
  }

  void _failed(CalDavException e) {
    _error = e.message;
    _untrusted = e is CalDavUntrustedCertificate ? e.certificate : null;
  }

  /// A client for [account], or null when signed out.
  CalDavClient? client() {
    final a = _account;
    if (a == null) return null;
    return CalDavClient(
      username: a.username,
      password: a.password,
      trustedCertificate: a.trustedCertificate,
      client: _httpClient,
    );
  }

  /// Reads the saved account, once.
  Future<void> load() => _loading ??= _load();

  /// Removes the file the todo board's old WebDAV backup servers kept their
  /// passwords in, which sits beside this one: nothing reads it any more, and
  /// a password left behind is a password leaked. Best-effort.
  Future<void> removeLegacyBackupServers() async {
    try {
      final legacy = File('$directory/todo-backup-servers.json');
      if (await legacy.exists()) await legacy.delete();
    } catch (e) {
      debugPrint('caldav: could not remove the old backup servers file: $e');
    }
  }

  Future<void> _load() async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          final url = json['url'];
          if (url is String && url.isNotEmpty) {
            String text(String key) =>
                json[key] is String ? json[key] as String : '';
            _account = CalDavAccount(
              url: url,
              username: text('username'),
              password: text('password'),
              trustedCertificate: json['trusted_certificate'] is String
                  ? json['trusted_certificate'] as String
                  : null,
            );
            _taskLists = [
              if (json['task_lists'] case final List<Object?> lists)
                for (final l in lists) ?_collectionFromJson(l),
            ];
          }
        }
      }
    } catch (e) {
      // An unreadable file reads as signed out; signing in again rewrites it.
      debugPrint('caldav: could not read $path: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Signs in: asks the server at [url] for the task lists [username] can
  /// see, and keeps the account only if it answers. Returns whether it did;
  /// [error] says why not, and [untrustedCertificate] what the server
  /// presented when that was the reason. [trustedCertificate] is a
  /// fingerprint to accept beyond the system's trust store.
  Future<bool> signIn({
    required String url,
    required String username,
    required String password,
    String? trustedCertificate,
  }) async {
    final server = calDavServerUri(url);
    if (server == null) {
      _error = 'The address has to start with https:// (or http://).';
      notifyListeners();
      return false;
    }
    final attempt = ++_signInAttempt;
    final connection =
        _httpClient ??
        (_signInConnection = CalDavHttpClient(
          trustedCertificate: trustedCertificate,
        ));
    _busy = true;
    _signingIn = true;
    _error = '';
    _untrusted = null;
    notifyListeners();
    try {
      final lists = await CalDavClient(
        username: username,
        password: password,
        client: connection,
      ).discoverTaskLists(server);
      if (attempt != _signInAttempt) return false;
      if (lists.isEmpty) {
        _error =
            '${server.host} answered, but has no task lists for $username. '
            'Make one in your calendar app, or give the address of one.';
        return false;
      }
      _account = CalDavAccount(
        url: url.trim(),
        username: username,
        password: password,
        trustedCertificate: trustedCertificate,
      );
      _taskLists = lists;
      await _save();
      return true;
    } on CalDavException catch (e) {
      if (attempt == _signInAttempt) _failed(e);
      return false;
    } finally {
      // A cancelled attempt has already been wound down by [cancelSignIn],
      // and a newer one owns the flags now.
      if (attempt == _signInAttempt) {
        if (_httpClient == null) {
          connection.close();
          _signInConnection = null;
        }
        _busy = false;
        _signingIn = false;
        notifyListeners();
      }
    }
  }

  /// Abandons a [signIn] still waiting on its server — the address or the
  /// user name was mistyped, and the server behind it may take the whole
  /// timeout to say so, or never answer at all. Nothing is kept and no error
  /// is shown; that attempt's [signIn] returns false.
  void cancelSignIn() {
    if (!_signingIn) return;
    _signInAttempt++;
    _signInConnection?.close();
    _signInConnection = null;
    _busy = false;
    _signingIn = false;
    _error = '';
    _untrusted = null;
    notifyListeners();
  }

  /// Asks the server for its task lists again.
  Future<void> refreshTaskLists() async {
    final a = _account;
    final server = a == null ? null : calDavServerUri(a.url);
    final client = this.client();
    if (server == null || client == null) return;
    _busy = true;
    _error = '';
    _untrusted = null;
    notifyListeners();
    try {
      _taskLists = await client.discoverTaskLists(server);
      await _save();
    } on CalDavException catch (e) {
      _failed(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Trusts the certificate with [fingerprint] for the signed-in account —
  /// a self-signed one that was renewed — and asks for the task lists again
  /// over it. Signed out, the form signs in with it instead.
  Future<void> trustCertificate(String fingerprint) async {
    final a = _account;
    if (a == null) return;
    _account = a.withTrustedCertificate(fingerprint);
    await _save();
    await refreshTaskLists();
  }

  /// Forgets the account. Must work whatever state the file is in.
  Future<void> signOut() async {
    _account = null;
    _taskLists = const [];
    _error = '';
    _untrusted = null;
    notifyListeners();
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The session has already dropped it.
    }
  }

  Future<void> _save() async {
    final a = _account;
    if (a == null) return;
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) await dir.create(recursive: true);
      // Narrowed before the file is created inside it, so the password is
      // never world-readable for even an instant.
      chmodPath(directory, 0x1C0); // 0700
      final tmp = File('$path.tmp');
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'url': a.url,
          'username': a.username,
          'password': a.password,
          'trusted_certificate': ?a.trustedCertificate,
          'task_lists': [
            for (final l in _taskLists)
              {'url': l.url.toString(), 'name': l.name, 'color': ?l.color},
          ],
        }),
        flush: true,
      );
      chmodPath(tmp.path, 0x180); // 0600
      await tmp.rename(path);
    } catch (e) {
      _error = 'Signed in, but the account could not be saved to $path: $e';
    }
  }

  static CalDavCollection? _collectionFromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'] is String ? Uri.tryParse(json['url']) : null;
    final name = json['name'];
    if (url == null || !url.hasScheme || name is! String) return null;
    return CalDavCollection(
      url: url,
      name: name,
      color: json['color'] is String ? json['color'] as String : null,
    );
  }
}
