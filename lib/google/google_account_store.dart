// The Google accounts for the whole shell: the sign-ins under Settings ›
// Accounts that any module or widget can use. There may be several — a work
// and a personal calendar side by side — and every consumer reads all of them.
//
// It owns the three things every consumer would otherwise repeat:
//
//  * **The sign-in**, a state machine with a socket in it (see
//    `google_oauth.dart`): open the browser, wait for the redirect, trade the
//    code for tokens. A settings page that owned it would lose it the moment
//    the overlay closed. A sign-in *adds* an account; signing in again as an
//    account already here replaces its grant rather than listing it twice.
//  * **The access tokens**, one per account. Each lives for an hour.
//    [withAccessToken] refreshes it shortly before it expires, and one refresh
//    is shared by every caller that asks at once. A 401 from an API is
//    answered with one fresh token and one retry before it counts as the
//    grant being gone.
//  * **The failure that changes state.** A dead grant (revoked, expired, or
//    issued to a client since replaced) removes that account, with the reason
//    on screen, rather than every consumer showing its own retry that can only
//    fail. The other accounts are untouched.
//
// Every sign-in runs as the project's own OAuth client (`google_client.dart`),
// so there is nothing for the user to set up first. A grant saved under any
// other client — the user's own, from before the shell shipped one, or a client
// the project has since rotated away from — cannot be refreshed with this one,
// and is revoked and dropped on load with a message saying why.
//
// A consumer such as `GoogleCalendarStore` listens here for accounts coming
// and going, and asks [withAccessToken] for each request.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/google/google_account_file.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_client.dart';
import 'package:moonswing/google/google_oauth.dart';

/// How far along the account is.
enum GoogleAuthStage {
  /// This build carries no OAuth client (`google_client.dart` was blanked),
  /// so there is no sign-in to offer.
  unavailable,

  /// A client, but no account. Settings offers **Sign in**.
  signedOut,

  /// The consent page is open in the browser and the shell is waiting for it
  /// to redirect back. Accounts already signed in stay usable meanwhile.
  awaitingBrowser,

  /// At least one account; consumers may make requests.
  signedIn,
}

/// One signed-in account, as consumers see it.
class GoogleAccount {
  const GoogleAccount({required this.id, required this.email});

  /// Stable for as long as the account is signed in: the address, or when
  /// Google did not say it, a digest of the grant (never the grant itself,
  /// since the id ends up in event keys the todo board stores).
  final String id;

  /// Empty when unknown.
  final String email;

  /// What the account is called on screen.
  String get label => email.isEmpty ? 'Google account' : email;

  @override
  bool operator ==(Object other) =>
      other is GoogleAccount && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}

/// An account's mutable half: the saved grant and the token minted from it.
class _Account {
  _Account(this.data);

  GoogleAccountData data;
  GoogleTokens? access;
  Future<String>? refreshing;

  /// Bumped when the account is removed, so a request in flight for it cannot
  /// act on an account that is gone.
  int generation = 0;

  String get id {
    if (data.email.isNotEmpty) return data.email;
    final digest = sha256.convert(utf8.encode(data.refreshToken ?? ''));
    return 'google-${digest.toString().substring(0, 12)}';
  }

  GoogleAccount get public => GoogleAccount(id: id, email: data.email);
}

/// The account, its sign-in, and the access token behind every request.
class GoogleAccountStore extends ChangeNotifier {
  GoogleAccountStore._({
    GoogleClient? client,
    GoogleAccountFile? file,
    bool Function(String url)? opener,
    DateTime Function()? now,
    String clientId = kGoogleClientId,
    String clientSecret = kGoogleClientSecret,
  }) : _client = client ?? const HttpGoogleClient(),
       _file = file ?? const GoogleAccountFile(),
       _open = opener ?? openUriWithDefault,
       _now = now ?? DateTime.now,
       _clientId = clientId,
       _clientSecret = clientSecret;

  static final GoogleAccountStore instance = GoogleAccountStore._();

  /// A detached store for tests: an injected client, a file under a temporary
  /// directory, an opener that stands in for the browser, and OAuth client
  /// credentials that are not the shipped ones.
  @visibleForTesting
  factory GoogleAccountStore.forTesting({
    required GoogleClient client,
    required GoogleAccountFile file,
    bool Function(String url)? opener,
    DateTime Function()? now,
    String clientId = 'id',
    String clientSecret = 'secret',
  }) => GoogleAccountStore._(
    client: client,
    file: file,
    opener: opener ?? (_) => true,
    now: now,
    clientId: clientId,
    clientSecret: clientSecret,
  );

  final GoogleClient _client;
  final GoogleAccountFile _file;
  final bool Function(String url) _open;
  final DateTime Function() _now;

  /// The OAuth client every sign-in and refresh runs as.
  final String _clientId;
  final String _clientSecret;

  bool get _hasClient => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  /// The client [GoogleCalendarStore] and other consumers make their requests
  /// through, so a test that fakes one fakes both.
  GoogleClient get client => _client;

  // --- published state -----------------------------------------------------

  final List<_Account> _accounts = [];

  /// Every signed-in account, in the order they were added.
  List<GoogleAccount> get accounts =>
      List.unmodifiable(_accounts.map((a) => a.public));

  _Account? _find(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  bool _signingIn = false;

  GoogleAuthStage get stage {
    if (!_hasClient) return GoogleAuthStage.unavailable;
    if (_signingIn) return GoogleAuthStage.awaitingBrowser;
    return _accounts.isEmpty
        ? GoogleAuthStage.signedOut
        : GoogleAuthStage.signedIn;
  }

  /// Whether any account is signed in, a sign-in of another in progress or
  /// not.
  bool get signedIn => _hasClient && _accounts.isNotEmpty;

  /// The consent page, while [stage] is [GoogleAuthStage.awaitingBrowser], so
  /// settings can offer to open it again.
  String? _authUrl;
  String? get authUrl => _authUrl;

  /// Why the last thing failed, or empty. A failure is a visible state: the
  /// settings row says why, and offers the way out.
  String _error = '';
  String get error => _error;

  bool _exchanging = false;
  bool _loaded = false;

  /// Whether the saved accounts have been read.
  bool get loaded => _loaded;

  /// True while the code is being traded for tokens.
  bool get busy => _exchanging;

  String get _signature => [
    stage.name,
    for (final a in _accounts) a.id,
    _authUrl ?? '',
    _error,
    _exchanging,
    _loaded,
  ].join('|');

  String _published = '';

  void _publish() {
    final signature = _signature;
    if (signature == _published) return;
    _published = signature;
    notifyListeners();
  }

  Future<bool> _save() => _file.write([for (final a in _accounts) a.data]);

  // --- loading -------------------------------------------------------------

  Future<void>? _loading;

  /// Reads the saved accounts. Idempotent; the start-up task calls it and a
  /// consumer that got there first simply awaits the same read.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final saved = await _file.read();
    final orphans = <String>[];
    final kept = <GoogleAccountData>[];
    for (final data in saved) {
      if (data.clientId.isNotEmpty && data.clientId != _clientId) {
        // Issued to another client: ours would be refused refreshing it.
        orphans.add(data.refreshToken!);
      } else {
        kept.add(data);
      }
    }
    // A sign-in that raced the read comes after what was saved.
    final raced = [..._accounts];
    _accounts
      ..clear()
      ..addAll(kept.map(_Account.new));
    for (final a in raced) {
      _accounts.removeWhere((k) => k.id == a.id);
      _accounts.add(a);
    }
    if (orphans.isNotEmpty) {
      _error =
          'Google sign-in now uses Moonswing\'s own app. Sign in again to '
          'reconnect your account.';
    }
    _loaded = true;
    _publish();
    if (orphans.isNotEmpty || raced.isNotEmpty) {
      for (final token in orphans) {
        unawaited(_revoke(token));
      }
      await _save();
    }
  }

  // --- the sign-in ---------------------------------------------------------

  /// Bumped by [cancelSignIn]; a sign-in compares it after every await and
  /// gives up when it has moved, so a cancelled one cannot finish a minute
  /// later and sign the user in anyway.
  int _generation = 0;
  GoogleLoopbackSession? _session;

  /// Runs a sign-in, adding the account it lands on: open the consent page,
  /// wait for the browser to come back, trade the code, save the grant.
  ///
  /// Not meant to be awaited by a widget. It runs for as long as the user
  /// takes, which is why its progress is published as [stage].
  Future<void> signIn() async {
    await load();
    if (!_hasClient || _signingIn) return;
    final generation = ++_generation;
    _signingIn = true;
    _error = '';
    _publish();

    GoogleLoopbackSession? session;
    try {
      session = await GoogleLoopbackSession.start(
        clientId: _clientId,
        scope: kGoogleCalendarScope,
      );
      if (generation != _generation) {
        unawaited(session.close());
        return;
      }
      _session = session;
      _authUrl = session.authUrl;
      _publish();
      openConsentPage();

      final code = await session.code;
      if (generation != _generation) return;
      _exchanging = true;
      _publish();

      final tokens = await _client.exchangeCode(
        clientId: _clientId,
        clientSecret: _clientSecret,
        code: code,
        codeVerifier: session.codeVerifier,
        redirectUri: session.redirectUri,
      );
      if (generation != _generation) return;
      final refresh = tokens.refreshToken;
      if (refresh == null) {
        throw const GoogleException('Google sent no refresh token');
      }
      final email = await _fetchEmail(tokens.accessToken);
      if (generation != _generation) return;

      final account = _Account(
        GoogleAccountData(
          clientId: _clientId,
          refreshToken: refresh,
          email: email,
        ),
      )..access = tokens;
      // Signing in again as an account already here replaces its grant. The
      // old one is not revoked: a revocation reaches the whole grant, which
      // for the same client and user now includes the new token.
      final at = _accounts.indexWhere((a) => a.id == account.id);
      if (at < 0) {
        _accounts.add(account);
      } else {
        _accounts[at].generation++;
        _accounts[at] = account;
      }
      _signingIn = false;
      if (!await _save()) {
        _error = 'Signed in, but the sign-in could not be saved';
      }
    } on GoogleSignInAborted catch (e) {
      if (generation != _generation) return;
      _error = e.message == 'Cancelled' ? '' : e.message;
    } on GoogleException catch (e) {
      if (generation != _generation) return;
      _error = e.message;
    } catch (e) {
      if (generation != _generation) return;
      _error = 'Could not start the sign-in';
      debugPrint('google: sign-in failed: $e');
    } finally {
      if (generation == _generation) {
        _signingIn = false;
        _exchanging = false;
        _authUrl = null;
        _session = null;
        _publish();
      }
    }
  }

  /// The primary calendar's id is the account's address. A failure costs the
  /// address on the settings row, never the sign-in.
  Future<String> _fetchEmail(String accessToken) async {
    try {
      final calendars = await _client.listCalendars(accessToken);
      for (final calendar in calendars) {
        if (calendar.primary) return calendar.id;
      }
    } catch (e) {
      debugPrint('google: could not read the account address: $e');
    }
    return '';
  }

  /// Opens the consent page. Also called for the user the moment the sign-in
  /// starts, so the button beside it is a second chance. A browser that will
  /// not open is said out loud, with the address to paste.
  void openConsentPage() {
    final url = _authUrl;
    if (url == null) return;
    if (_open(url)) return;
    _error = 'Could not open a browser. Open this address yourself: $url';
    _publish();
  }

  /// Abandons a sign-in in progress.
  void cancelSignIn() {
    if (!_signingIn) return;
    _generation++;
    final session = _session;
    _session = null;
    _authUrl = null;
    _exchanging = false;
    _signingIn = false;
    if (session != null) unawaited(session.close());
    _publish();
  }

  /// Signs [id] out: its grant is revoked at Google and forgotten here. The
  /// other accounts stay signed in.
  Future<void> signOut(String id) async {
    final account = _find(id);
    if (account == null) return;
    _accounts.remove(account);
    account.generation++;
    account.access = null;
    _error = '';
    _publish();
    final token = account.data.refreshToken;
    if (token != null) unawaited(_revoke(token));
    if (!await _save()) {
      _error = 'Signed out, but the saved sign-in could not be removed';
      _publish();
    }
  }

  Future<void> _revoke(String token) async {
    try {
      await _client.revoke(token);
    } catch (e) {
      debugPrint('google: could not revoke the old grant: $e');
    }
  }

  // --- the access tokens ---------------------------------------------------

  /// How long before expiry a token is replaced, so a request never leaves
  /// with one about to lapse in flight.
  static const Duration _kExpiryMargin = Duration(seconds: 60);

  Future<String> _accessToken(_Account account) {
    final access = account.access;
    if (access != null &&
        access.expiresAt.isAfter(_now().add(_kExpiryMargin))) {
      return Future.value(access.accessToken);
    }
    return account.refreshing ??= _refresh(
      account,
    ).whenComplete(() => account.refreshing = null);
  }

  Future<String> _refresh(_Account account) async {
    final refresh = account.data.refreshToken;
    if (refresh == null) {
      throw const GoogleException('Not signed in to Google');
    }
    final generation = account.generation;
    try {
      final tokens = await _client.refreshAccessToken(
        clientId: _clientId,
        clientSecret: _clientSecret,
        refreshToken: refresh,
      );
      if (generation == account.generation) account.access = tokens;
      return tokens.accessToken;
    } on GoogleAuthException catch (e) {
      if (generation == account.generation) await _expire(account, e.message);
      rethrow;
    }
  }

  /// [account]'s grant is gone. It is removed, with the reason on screen.
  Future<void> _expire(_Account account, String message) async {
    if (!_accounts.remove(account)) return;
    account.generation++;
    account.access = null;
    _error = account.data.email.isEmpty
        ? message
        : '${account.data.email}: $message';
    _publish();
    await _save();
  }

  /// Runs [request] with a current access token for the account [id].
  ///
  /// A [GoogleAuthException] from the request, which is a 401, is answered with
  /// one fresh token and one retry, since a token can be revoked before its
  /// hour is up. A second one means the grant itself is gone: the account
  /// signs out and the exception goes on to the caller.
  Future<T> withAccessToken<T>(
    String id,
    Future<T> Function(String token) request,
  ) async {
    await load();
    final account = _find(id);
    if (account == null) {
      throw const GoogleException('Not signed in to Google');
    }
    final generation = account.generation;
    try {
      return await request(await _accessToken(account));
    } on GoogleAuthException {
      if (generation != account.generation) rethrow;
      account.access = null;
      try {
        return await request(await _accessToken(account));
      } on GoogleAuthException catch (e) {
        if (generation == account.generation) {
          await _expire(account, e.message);
        }
        rethrow;
      }
    }
  }

  /// Clears a shown failure. The settings row's dismiss.
  void clearError() {
    if (_error.isEmpty) return;
    _error = '';
    _publish();
  }

  @override
  void dispose() {
    cancelSignIn();
    super.dispose();
  }
}
