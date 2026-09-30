// The CalDAV accounts behind Settings › Accounts — any number of them, each a
// server, a user name and a password — and the calendars found on each: task
// lists for the todo board, calendars of events for the Calendar tab.
//
// Not `config.toml`, for the reason `github/github_token_store.dart` gives:
// a password is none of the things a config file is. It is one JSON file in the
// XDG *state* directory — `~/.local/state/moonswing/caldav-account.json` — in
// a directory narrowed to 0700 before the file is written, and the file itself
// at 0600. An app password, where the server offers one, is what the form asks
// for. A file written by a build that kept one account is read as a list of
// one, and rewritten as a list the next time anything is saved.
//
// Signing in *is* discovery: an address is only kept once the server has
// answered it with the user's calendars, so a typo or a wrong password is
// said on the form rather than on the todo board an hour later. Signing in
// again as an account already listed (the same address and user name)
// replaces it rather than listing it twice.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:moonswing/caldav/caldav_client.dart';
import 'package:moonswing/native/libc.dart';

/// A CalDAV server, the credentials for it, and the calendars found there.
@immutable
class CalDavAccount {
  const CalDavAccount({
    required this.url,
    required this.username,
    required this.password,
    this.trustedCertificate,
    this.calendars = const [],
  });

  /// What the user typed: the server, a principal, or one calendar.
  final String url;
  final String username;
  final String password;

  /// The SHA-256 fingerprint of a certificate the user chose to trust for
  /// this server beyond what the system trusts, or null.
  final String? trustedCertificate;

  /// Every calendar collection found on the account, as of sign-in or the
  /// last refresh: task lists and calendars of events alike.
  final List<CalDavCollection> calendars;

  /// Which account this is, across the list: the address and the user name.
  /// Two sign-ins with the same id are the same account.
  String get id => '$username@${url.trim()}';

  /// The collections that can hold tasks.
  List<CalDavCollection> get taskLists => [
    for (final c in calendars)
      if (c.holdsTasks) c,
  ];

  /// The collections that can hold events.
  List<CalDavCollection> get eventCalendars => [
    for (final c in calendars)
      if (c.holdsEvents) c,
  ];

  CalDavAccount copyWith({
    Object? trustedCertificate = _keep,
    List<CalDavCollection>? calendars,
  }) => CalDavAccount(
    url: url,
    username: username,
    password: password,
    trustedCertificate: identical(trustedCertificate, _keep)
        ? this.trustedCertificate
        : trustedCertificate as String?,
    calendars: calendars ?? this.calendars,
  );

  static const Object _keep = Object();

  /// "me on dav.example.com".
  String get label {
    final host = Uri.tryParse(url.trim())?.host ?? url;
    return username.isEmpty ? host : '$username on $host';
  }

  @override
  bool operator ==(Object other) =>
      other is CalDavAccount &&
      other.url == url &&
      other.username == username &&
      other.password == password &&
      other.trustedCertificate == trustedCertificate &&
      listEquals(other.calendars, calendars);

  @override
  int get hashCode => Object.hash(
    url,
    username,
    password,
    trustedCertificate,
    Object.hashAll(calendars),
  );
}

/// The signed-in CalDAV accounts, and the calendars on each.
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

  List<CalDavAccount> _accounts = const [];
  bool _loaded = false;
  Future<void>? _loading;

  // The sign-in form's state: one form, however many accounts.
  bool _busy = false;
  String _error = '';
  CalDavCertificate? _untrusted;

  // Each account's own refresh: under way, why it failed, and what it was
  // refused over — so one server being down is said beside that server.
  final Set<String> _refreshing = {};
  final Map<String, String> _errors = {};
  final Map<String, CalDavCertificate> _untrustedOf = {};

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

  /// Every signed-in account, in the order they were added.
  List<CalDavAccount> get accounts => _accounts;

  /// Whether any account is signed in.
  bool get signedIn => _accounts.isNotEmpty;

  /// The account with [id], or null.
  CalDavAccount? accountWithId(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Every task list on every account, the first account's first.
  List<CalDavCollection> get taskLists => [
    for (final a in _accounts) ...a.taskLists,
  ];

  /// Every calendar of events on every account.
  List<CalDavCollection> get eventCalendars => [
    for (final a in _accounts) ...a.eventCalendars,
  ];

  /// The account [collection] was found on: the one listing it, else the one
  /// on the same server, else — with only one account — that one.
  CalDavAccount? accountOf(Uri collection) {
    final key = CalDavClient.hrefKey(collection, collection.path);
    for (final a in _accounts) {
      for (final c in a.calendars) {
        if (c.url.origin == collection.origin &&
            CalDavClient.hrefKey(c.url, c.url.path) == key) {
          return a;
        }
      }
    }
    for (final a in _accounts) {
      final server = calDavServerUri(a.url);
      if (server != null && server.origin == collection.origin) return a;
    }
    return _accounts.length == 1 ? _accounts.single : null;
  }

  /// Whether [load] has finished.
  bool get loaded => _loaded;

  /// A sign-in is under way, or any account is being refreshed.
  bool get busy => _busy || _refreshing.isNotEmpty;

  /// A [signIn] is waiting on the server, and [cancelSignIn] would stop it.
  bool get signingIn => _signingIn;

  /// Why the last sign-in failed, or empty.
  String get error => _error;

  /// The certificate the last sign-in was refused over, which the user may
  /// choose to trust; null otherwise.
  CalDavCertificate? get untrustedCertificate => _untrusted;

  /// Whether the account with [id] is being refreshed.
  bool refreshing(String id) => _refreshing.contains(id);

  /// Why the account with [id] could not be refreshed, or empty.
  String errorOf(String id) => _errors[id] ?? '';

  /// The certificate the account with [id] was last refused over, or null.
  CalDavCertificate? untrustedCertificateOf(String id) => _untrustedOf[id];

  /// Every account's refresh error, each named by its account when there is
  /// more than one. Empty when every account answered.
  String get refreshError => [
    for (final a in _accounts)
      if (_errors[a.id] case final e?)
        _accounts.length > 1 ? '${a.label}: $e' : e,
  ].join('\n');

  /// Clears the sign-in form's error.
  void clearError() {
    if (_error.isEmpty && _untrusted == null) return;
    _error = '';
    _untrusted = null;
    notifyListeners();
  }

  /// Clears the account with [id]'s refresh error.
  void clearErrorOf(String id) {
    final had = _errors.remove(id) != null;
    if (_untrustedOf.remove(id) == null && !had) return;
    notifyListeners();
  }

  /// A client for [account].
  CalDavClient clientFor(CalDavAccount account) => CalDavClient(
    username: account.username,
    password: account.password,
    trustedCertificate: account.trustedCertificate,
    client: _httpClient,
  );

  /// A client for the account [collection] is on, or null when none is.
  CalDavClient? clientForCollection(Uri collection) {
    final a = accountOf(collection);
    return a == null ? null : clientFor(a);
  }

  /// Reads the saved accounts, once.
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
          final read = <CalDavAccount>[
            // One account, as a build that kept only one wrote it.
            if (json.containsKey('url')) ?_accountFromJson(json),
            if (json['accounts'] case final List<Object?> list)
              for (final a in list) ?_accountFromJson(a),
          ];
          final seen = <String>{};
          _accounts = List.unmodifiable([
            for (final a in read)
              if (seen.add(a.id)) a,
          ]);
        }
      }
    } catch (e) {
      // An unreadable file reads as signed out; signing in again rewrites it.
      debugPrint('caldav: could not read $path: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Signs in: asks the server at [url] for the calendars [username] can see,
  /// and adds the account only if it answers with at least one. Returns
  /// whether it did; [error] says why not, and [untrustedCertificate] what the
  /// server presented when that was the reason. [trustedCertificate] is a
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
      final calendars = await CalDavClient(
        username: username,
        password: password,
        client: connection,
      ).discoverCalendars(server);
      if (attempt != _signInAttempt) return false;
      if (calendars.isEmpty) {
        _error =
            '${server.host} answered, but has no calendars or task lists for '
            '$username. Make one in your calendar app, or give the address of '
            'one.';
        return false;
      }
      final account = CalDavAccount(
        url: url.trim(),
        username: username,
        password: password,
        trustedCertificate: trustedCertificate,
        calendars: calendars,
      );
      _put(account);
      _errors.remove(account.id);
      _untrustedOf.remove(account.id);
      await _save();
      return true;
    } on CalDavException catch (e) {
      if (attempt == _signInAttempt) {
        _error = e.message;
        _untrusted = e is CalDavUntrustedCertificate ? e.certificate : null;
      }
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

  /// Adds [account], or replaces the one with its id where it stands.
  void _put(CalDavAccount account) {
    final at = _accounts.indexWhere((a) => a.id == account.id);
    _accounts = List.unmodifiable(
      at < 0
          ? [..._accounts, account]
          : [
              for (var i = 0; i < _accounts.length; i++)
                i == at ? account : _accounts[i],
            ],
    );
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

  /// Asks the server of the account with [id] for its calendars again.
  Future<void> refresh(String id) async {
    final a = accountWithId(id);
    final server = a == null ? null : calDavServerUri(a.url);
    if (a == null || server == null || !_refreshing.add(id)) return;
    _errors.remove(id);
    _untrustedOf.remove(id);
    notifyListeners();
    try {
      final calendars = await clientFor(a).discoverCalendars(server);
      // Signed out, or signed in again, while it was asked.
      final now = accountWithId(id);
      if (now != null && now.password == a.password) {
        _put(now.copyWith(calendars: calendars));
        await _save();
      }
    } on CalDavException catch (e) {
      if (accountWithId(id) != null) {
        _errors[id] = e.message;
        if (e is CalDavUntrustedCertificate) _untrustedOf[id] = e.certificate;
      }
    } finally {
      _refreshing.remove(id);
      notifyListeners();
    }
  }

  /// Asks every account's server for its calendars again.
  Future<void> refreshAll() =>
      Future.wait([for (final a in _accounts) refresh(a.id)]);

  /// Asks for the task lists again: every account's.
  Future<void> refreshTaskLists() => refreshAll();

  /// Trusts the certificate with [fingerprint] for the account with [id] —
  /// a self-signed one that was renewed — and asks for its calendars again
  /// over it. Signed out, the form signs in with it instead.
  Future<void> trustCertificate(String id, String fingerprint) async {
    final a = accountWithId(id);
    if (a == null) return;
    _put(a.copyWith(trustedCertificate: fingerprint));
    await _save();
    await refresh(id);
  }

  /// Forgets the account with [id]. Must work whatever state the file is in.
  Future<void> signOut(String id) async {
    if (accountWithId(id) == null) return;
    _accounts = List.unmodifiable([
      for (final a in _accounts)
        if (a.id != id) a,
    ]);
    _errors.remove(id);
    _untrustedOf.remove(id);
    notifyListeners();
    if (_accounts.isEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // The session has already dropped it.
      }
    } else {
      await _save();
    }
  }

  /// Forgets every account.
  Future<void> signOutAll() async {
    for (final a in [..._accounts]) {
      await signOut(a.id);
    }
  }

  Future<void> _save() async {
    if (_accounts.isEmpty) return;
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) await dir.create(recursive: true);
      // Narrowed before the file is created inside it, so the password is
      // never world-readable for even an instant.
      chmodPath(directory, 0x1C0); // 0700
      final tmp = File('$path.tmp');
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'accounts': [
            for (final a in _accounts)
              {
                'url': a.url,
                'username': a.username,
                'password': a.password,
                'trusted_certificate': ?a.trustedCertificate,
                'calendars': [
                  for (final c in a.calendars)
                    {
                      'url': c.url.toString(),
                      'name': c.name,
                      'color': ?c.color,
                      'components': (c.components.toList()..sort()),
                    },
                ],
              },
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

  static CalDavAccount? _accountFromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    String text(String key) => json[key] is String ? json[key] as String : '';
    return CalDavAccount(
      url: url,
      username: text('username'),
      password: text('password'),
      trustedCertificate: json['trusted_certificate'] is String
          ? json['trusted_certificate'] as String
          : null,
      calendars: [
        if (json['calendars'] case final List<Object?> list)
          for (final c in list) ?_collectionFromJson(c),
        // What a build that kept only task lists wrote.
        if (json['task_lists'] case final List<Object?> list)
          for (final c in list) ?_collectionFromJson(c, fallback: 'VTODO'),
      ],
    );
  }

  static CalDavCollection? _collectionFromJson(
    Object? json, {
    String? fallback,
  }) {
    if (json is! Map) return null;
    final url = json['url'] is String ? Uri.tryParse(json['url']) : null;
    final name = json['name'];
    if (url == null || !url.hasScheme || name is! String) return null;
    return CalDavCollection(
      url: url,
      name: name,
      color: json['color'] is String ? json['color'] as String : null,
      components: {
        if (json['components'] case final List<Object?> list)
          for (final c in list)
            if (c is String && c.isNotEmpty) c.toUpperCase(),
        ?fallback,
      },
    );
  }
}
