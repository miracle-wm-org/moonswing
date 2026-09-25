// The Google account for the whole shell: one sign-in under Settings › Accounts
// that any module or widget can use.
//
// It owns the three things every consumer would otherwise repeat:
//
//  * **The sign-in**, a state machine with a socket in it (see
//    `google_oauth.dart`): open the browser, wait for the redirect, trade the
//    code for tokens. A settings page that owned it would lose it the moment
//    the overlay closed.
//  * **The access token.** It lives for an hour. [withAccessToken] refreshes it
//    shortly before it expires, and one refresh is shared by every caller that
//    asks at once. A 401 from an API is answered with one fresh token and one
//    retry before it counts as the grant being gone.
//  * **The failure that changes state.** A dead grant (revoked, expired, or
//    issued to a client since replaced) returns the account to signed out with
//    the reason on screen, rather than every consumer showing its own retry
//    that can only fail.
//
// A consumer such as `GoogleCalendarStore` listens here for the account coming
// and going, and asks [withAccessToken] for each request.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/google/google_account_file.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_oauth.dart';

/// How far along the account is.
enum GoogleAuthStage {
  /// No OAuth client yet. Settings asks for its ID and secret.
  needsClient,

  /// A client, but no grant. Settings offers **Sign in**.
  signedOut,

  /// The consent page is open in the browser and the shell is waiting for it
  /// to redirect back.
  awaitingBrowser,

  /// There is a grant; consumers may make requests.
  signedIn,
}

/// The account, its sign-in, and the access token behind every request.
class GoogleAccountStore extends ChangeNotifier {
  GoogleAccountStore._({
    GoogleClient? client,
    GoogleAccountFile? file,
    bool Function(String url)? opener,
    DateTime Function()? now,
  }) : _client = client ?? const HttpGoogleClient(),
       _file = file ?? const GoogleAccountFile(),
       _open = opener ?? openUriWithDefault,
       _now = now ?? DateTime.now;

  static final GoogleAccountStore instance = GoogleAccountStore._();

  /// A detached store for tests: an injected client, a file under a temporary
  /// directory, and an opener that stands in for the browser.
  @visibleForTesting
  factory GoogleAccountStore.forTesting({
    required GoogleClient client,
    required GoogleAccountFile file,
    bool Function(String url)? opener,
    DateTime Function()? now,
  }) => GoogleAccountStore._(
    client: client,
    file: file,
    opener: opener ?? (_) => true,
    now: now,
  );

  final GoogleClient _client;
  final GoogleAccountFile _file;
  final bool Function(String url) _open;
  final DateTime Function() _now;

  /// The client [GoogleCalendarStore] and other consumers make their requests
  /// through, so a test that fakes one fakes both.
  GoogleClient get client => _client;

  // --- published state -----------------------------------------------------

  GoogleAccountData _data = const GoogleAccountData();

  GoogleAuthStage _stage = GoogleAuthStage.needsClient;
  GoogleAuthStage get stage => _stage;

  bool get signedIn => _stage == GoogleAuthStage.signedIn;

  /// The signed-in address. Empty when it is not known yet.
  String get email => _data.email;

  /// The client ID in use, for the settings field.
  String get clientId => _data.clientId;

  /// Whether a secret is saved. The secret itself is never shown back.
  bool get hasClientSecret => _data.clientSecret.isNotEmpty;

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

  /// Whether the saved account has been read.
  bool get loaded => _loaded;

  /// True while the code is being traded for tokens.
  bool get busy => _exchanging;

  String get _signature => [
    _stage.name,
    _data.email,
    _data.clientId,
    _data.clientSecret.isNotEmpty,
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

  GoogleAuthStage _restingStage() {
    if (!_data.hasClient) return GoogleAuthStage.needsClient;
    return _data.refreshToken == null
        ? GoogleAuthStage.signedOut
        : GoogleAuthStage.signedIn;
  }

  // --- loading -------------------------------------------------------------

  Future<void>? _loading;

  /// Reads the saved account. Idempotent; the start-up task calls it and a
  /// consumer that got there first simply awaits the same read.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final data = await _file.read();
    // A sign-in or a client edit that raced the read wins.
    if (!_loaded && _data == const GoogleAccountData()) {
      _data = data;
      _stage = _restingStage();
    }
    _loaded = true;
    _publish();
  }

  // --- the client ----------------------------------------------------------

  /// Saves the OAuth client. Either half may be given alone, since settings
  /// commits the two fields separately.
  ///
  /// A grant belongs to the client that asked for it, so changing the client
  /// while signed in signs out: the old refresh token would be refused.
  Future<void> setClient({String? id, String? secret}) async {
    await load();
    final nextId = id?.trim() ?? _data.clientId;
    final nextSecret = secret?.trim() ?? _data.clientSecret;
    if (nextId == _data.clientId && nextSecret == _data.clientSecret) return;
    final old = _data;
    if (_stage == GoogleAuthStage.awaitingBrowser) cancelSignIn();
    _data = GoogleAccountData(clientId: nextId, clientSecret: nextSecret);
    _access = null;
    _error = '';
    _stage = _restingStage();
    _publish();
    if (old.refreshToken case final token?) unawaited(_revoke(token));
    if (!await _file.write(_data)) {
      _error = 'The client could not be saved';
      _publish();
    }
  }

  // --- the sign-in ---------------------------------------------------------

  /// Bumped by [cancelSignIn] and [signOut]; a sign-in compares it after every
  /// await and gives up when it has moved, so a cancelled one cannot finish a
  /// minute later and sign the user in anyway.
  int _generation = 0;
  GoogleLoopbackSession? _session;

  /// Runs the sign-in: open the consent page, wait for the browser to come
  /// back, trade the code, save the grant.
  ///
  /// Not meant to be awaited by a widget. It runs for as long as the user
  /// takes, which is why its progress is published as [stage].
  Future<void> signIn() async {
    await load();
    if (_stage != GoogleAuthStage.signedOut) return;
    final generation = ++_generation;
    final data = _data;
    _stage = GoogleAuthStage.awaitingBrowser;
    _error = '';
    _publish();

    GoogleLoopbackSession? session;
    try {
      session = await GoogleLoopbackSession.start(
        clientId: data.clientId,
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
        clientId: data.clientId,
        clientSecret: data.clientSecret,
        code: code,
        codeVerifier: session.codeVerifier,
        redirectUri: session.redirectUri,
      );
      if (generation != _generation) return;
      final refresh = tokens.refreshToken;
      if (refresh == null) {
        throw const GoogleException('Google sent no refresh token');
      }
      _access = tokens;
      final email = await _fetchEmail(tokens.accessToken);
      if (generation != _generation) return;

      _data = GoogleAccountData(
        clientId: data.clientId,
        clientSecret: data.clientSecret,
        refreshToken: refresh,
        email: email,
      );
      _stage = GoogleAuthStage.signedIn;
      if (!await _file.write(_data)) {
        _error = 'Signed in, but the sign-in could not be saved';
      }
    } on GoogleSignInAborted catch (e) {
      if (generation != _generation) return;
      _stage = _restingStage();
      _error = e.message == 'Cancelled' ? '' : e.message;
    } on GoogleException catch (e) {
      if (generation != _generation) return;
      _access = null;
      _stage = _restingStage();
      _error = e.message;
    } catch (e) {
      if (generation != _generation) return;
      _access = null;
      _stage = _restingStage();
      _error = 'Could not start the sign-in';
      debugPrint('google: sign-in failed: $e');
    } finally {
      if (generation == _generation) {
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
    if (_stage != GoogleAuthStage.awaitingBrowser) return;
    _generation++;
    final session = _session;
    _session = null;
    _authUrl = null;
    _exchanging = false;
    if (session != null) unawaited(session.close());
    _stage = _restingStage();
    _publish();
  }

  /// Signs out: the grant is revoked at Google and forgotten here. The client
  /// stays, so signing back in is one click.
  Future<void> signOut() async {
    cancelSignIn();
    final token = _data.refreshToken;
    _generation++;
    _data = _data.signedOut();
    _access = null;
    _error = '';
    _stage = _restingStage();
    _publish();
    if (token != null) unawaited(_revoke(token));
    if (!await _file.write(_data)) {
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

  // --- the access token ----------------------------------------------------

  GoogleTokens? _access;
  Future<String>? _refreshing;

  /// How long before expiry a token is replaced, so a request never leaves
  /// with one about to lapse in flight.
  static const Duration _kExpiryMargin = Duration(seconds: 60);

  Future<String> _accessToken() {
    final access = _access;
    if (access != null &&
        access.expiresAt.isAfter(_now().add(_kExpiryMargin))) {
      return Future.value(access.accessToken);
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final data = _data;
    final refresh = data.refreshToken;
    if (refresh == null) {
      throw const GoogleException('Not signed in to Google');
    }
    final generation = _generation;
    try {
      final tokens = await _client.refreshAccessToken(
        clientId: data.clientId,
        clientSecret: data.clientSecret,
        refreshToken: refresh,
      );
      if (generation == _generation) _access = tokens;
      return tokens.accessToken;
    } on GoogleAuthException catch (e) {
      if (generation == _generation) await _expire(e.message);
      rethrow;
    }
  }

  /// The grant is gone. Back to signed out, with the reason on screen.
  Future<void> _expire(String message) async {
    _generation++;
    _data = _data.signedOut();
    _access = null;
    _stage = _restingStage();
    _error = message;
    _publish();
    await _file.write(_data);
  }

  /// Runs [request] with a current access token.
  ///
  /// A [GoogleAuthException] from the request, which is a 401, is answered with
  /// one fresh token and one retry, since a token can be revoked before its
  /// hour is up. A second one means the grant itself is gone: the account
  /// signs out and the exception goes on to the caller.
  Future<T> withAccessToken<T>(Future<T> Function(String token) request) async {
    await load();
    if (!signedIn) throw const GoogleException('Not signed in to Google');
    final generation = _generation;
    try {
      return await request(await _accessToken());
    } on GoogleAuthException {
      if (generation != _generation || !signedIn) rethrow;
      _access = null;
      try {
        return await request(await _accessToken());
      } on GoogleAuthException catch (e) {
        if (generation == _generation && signedIn) await _expire(e.message);
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
