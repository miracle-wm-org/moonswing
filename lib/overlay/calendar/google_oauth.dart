import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:graceful_shell/overlay/calendar/provider.dart';

/// Google's OAuth 2.0 endpoints for the "installed app" (desktop) flow.
const String kGoogleAuthEndpoint =
    'https://accounts.google.com/o/oauth2/v2/auth';
const String kGoogleTokenEndpoint = 'https://oauth2.googleapis.com/token';
const String kGoogleRevokeEndpoint = 'https://oauth2.googleapis.com/revoke';

/// Read-only calendar access, plus the two scopes that make Google return an
/// `id_token` — that carries the account's email address, so we can show which
/// account is connected without a second API call.
const List<String> kGoogleCalendarScopes = [
  'https://www.googleapis.com/auth/calendar.readonly',
  'openid',
  'email',
];

const String _verifierChars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// A PKCE code verifier: 64 chars from the RFC 7636 unreserved set.
String generateCodeVerifier([Random? rng]) {
  final random = rng ?? Random.secure();
  return List.generate(
    64,
    (_) => _verifierChars[random.nextInt(_verifierChars.length)],
  ).join();
}

/// The S256 challenge for [verifier]: base64url(sha256(verifier)), unpadded.
String codeChallengeS256(String verifier) {
  final digest = sha256.convert(ascii.encode(verifier));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

/// An anti-CSRF `state` value, echoed back on the redirect and checked there.
String generateState([Random? rng]) {
  final random = rng ?? Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Uri buildAuthUrl({
  required String clientId,
  required String redirectUri,
  required List<String> scopes,
  required String codeChallenge,
  required String state,
}) {
  return Uri.parse(kGoogleAuthEndpoint).replace(queryParameters: {
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'scope': scopes.join(' '),
    'code_challenge': codeChallenge,
    'code_challenge_method': 'S256',
    'state': state,
    // Without both of these Google only issues a refresh token on the very
    // first consent, so a re-connect after a disconnect would come back with an
    // access token that dies in an hour and no way to renew it.
    'access_type': 'offline',
    'prompt': 'consent',
  });
}

/// Pulls the authorization code out of the loopback redirect.
///
/// Throws [CalendarAuthException] if the user denied consent or if `state` does
/// not match — a mismatch means the request did not originate from this flow.
String parseRedirect(Uri uri, {required String expectedState}) {
  final params = uri.queryParameters;

  final error = params['error'];
  if (error != null) {
    final description = params['error_description'];
    throw CalendarAuthException(description == null
        ? 'Google returned "$error".'
        : 'Google returned "$error": $description');
  }

  if (params['state'] != expectedState) {
    throw const CalendarAuthException(
        'Sign-in response did not match the request. Please try again.');
  }

  final code = params['code'];
  if (code == null || code.isEmpty) {
    throw const CalendarAuthException('Google did not return an authorization code.');
  }
  return code;
}

/// Decodes an `id_token`'s payload segment.
///
/// The signature is not verified: the token came straight back from Google's
/// token endpoint over TLS, so there is no untrusted party in between. Returns
/// null for anything that is not a well-formed JWT.
Map<String, dynamic>? decodeIdTokenPayload(String idToken) {
  final parts = idToken.split('.');
  if (parts.length != 3) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final json = jsonDecode(decoded);
    return json is Map<String, dynamic> ? json : null;
  } catch (_) {
    return null;
  }
}

/// One account's OAuth credentials.
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.email,
    this.scope,
  });

  final String accessToken;

  /// Null only if Google withheld one — see the `prompt=consent` note above.
  final String? refreshToken;

  final DateTime expiresAt;
  final String? email;
  final String? scope;

  /// Whether the access token is spent, with a skew so a request never starts
  /// with a token that will expire mid-flight.
  bool isExpired({DateTime? now, Duration skew = const Duration(seconds: 60)}) {
    final t = now ?? DateTime.now();
    return !t.add(skew).isBefore(expiresAt);
  }

  OAuthTokens copyWith({String? accessToken, DateTime? expiresAt}) {
    return OAuthTokens(
      accessToken: accessToken ?? this.accessToken,
      expiresAt: expiresAt ?? this.expiresAt,
      refreshToken: refreshToken,
      email: email,
      scope: scope,
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        if (refreshToken != null) 'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        if (email != null) 'email': email,
        if (scope != null) 'scope': scope,
      };

  factory OAuthTokens.fromJson(Map<String, dynamic> json) {
    return OAuthTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      email: json['email'] as String?,
      scope: json['scope'] as String?,
    );
  }

  /// Parses a response from Google's token endpoint.
  ///
  /// A refresh response omits `refresh_token`, so [existingRefreshToken] is
  /// carried forward — dropping it would silently downgrade the account to
  /// access-token-only and force a re-consent an hour later.
  factory OAuthTokens.fromTokenResponse(
    Map<String, dynamic> body, {
    DateTime? now,
    String? existingRefreshToken,
    String? existingEmail,
  }) {
    final issuedAt = now ?? DateTime.now();
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;

    String? email = existingEmail;
    final idToken = body['id_token'] as String?;
    if (idToken != null) {
      email = decodeIdTokenPayload(idToken)?['email'] as String? ?? email;
    }

    return OAuthTokens(
      accessToken: body['access_token'] as String? ?? '',
      refreshToken: body['refresh_token'] as String? ?? existingRefreshToken,
      expiresAt: issuedAt.add(Duration(seconds: expiresIn)),
      email: email,
      scope: body['scope'] as String?,
    );
  }
}

/// Drives Google's installed-app OAuth flow.
///
/// Binds an ephemeral loopback port, opens the consent page in the user's
/// browser, and waits for Google to redirect back with an authorization code,
/// which it exchanges for tokens. Google allows any `127.0.0.1` port for a
/// client registered as a "Desktop app", so no port needs to be pre-registered.
class GoogleOAuthFlow {
  GoogleOAuthFlow({
    required this.clientId,
    required this.clientSecret,
    this.timeout = const Duration(minutes: 3),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String clientId;
  final String clientSecret;
  final Duration timeout;
  final http.Client _http;

  HttpServer? _server;

  /// Runs the whole flow. [onUrl] receives the consent URL, so the UI can offer
  /// it for copy-paste when `xdg-open` is unavailable (a bare TTY, a sandbox).
  Future<OAuthTokens> authorize({void Function(Uri url)? onUrl}) async {
    final verifier = generateCodeVerifier();
    final state = generateState();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;

    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final authUrl = buildAuthUrl(
        clientId: clientId,
        redirectUri: redirectUri,
        scopes: kGoogleCalendarScopes,
        codeChallenge: codeChallengeS256(verifier),
        state: state,
      );

      onUrl?.call(authUrl);
      unawaited(_openBrowser(authUrl));

      final code = await _awaitRedirect(server, state);
      return await _exchangeCode(
        code: code,
        verifier: verifier,
        redirectUri: redirectUri,
      );
    } finally {
      await _closeServer();
    }
  }

  /// Aborts an in-flight [authorize]: closing the server makes the pending
  /// request future complete with an error, which unwinds the flow.
  Future<void> cancel() => _closeServer();

  Future<void> _closeServer() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _openBrowser(Uri url) async {
    try {
      await Process.run('xdg-open', [url.toString()]);
    } catch (e) {
      // Not fatal: the UI also shows the URL for the user to copy.
      debugPrint('Could not launch browser for Google sign-in: $e');
    }
  }

  Future<String> _awaitRedirect(HttpServer server, String state) async {
    final completer = Completer<String>();

    final subscription = server.listen((request) async {
      String? code;
      Object? failure;
      try {
        code = parseRedirect(request.uri, expectedState: state);
      } catch (e) {
        failure = e;
      }

      await _respond(request, ok: failure == null);

      if (completer.isCompleted) return;
      if (failure != null) {
        completer.completeError(failure);
      } else {
        completer.complete(code);
      }
    }, onError: (Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    }, onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(
            const CalendarAuthException('Google sign-in was cancelled.'));
      }
    });

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw const CalendarAuthException(
            'Timed out waiting for Google sign-in.'),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _respond(HttpRequest request, {required bool ok}) async {
    final message = ok
        ? 'Graceful Shell is connected. You can close this tab.'
        : 'Sign-in failed. Return to Graceful Shell and try again.';
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write('<!doctype html><meta charset="utf-8">'
          '<title>Graceful Shell</title>'
          '<body style="font-family:system-ui;display:grid;place-items:center;'
          'height:100vh;margin:0;background:#2c2c2c;color:#f3f4f4">'
          '<p>$message</p></body>');
    await request.response.close();
  }

  Future<OAuthTokens> _exchangeCode({
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    // Desktop clients still send client_secret alongside the PKCE verifier;
    // Google's docs are explicit that it is not treated as a real secret here.
    final response = await _http.post(Uri.parse(kGoogleTokenEndpoint), body: {
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': code,
      'code_verifier': verifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
    });

    final body = _decodeTokenResponse(response);
    return OAuthTokens.fromTokenResponse(body);
  }

  /// Trades a refresh token for a fresh access token.
  ///
  /// A revoked or expired grant comes back as `invalid_grant`; that surfaces as
  /// [CalendarAuthException] so the caller knows to drop the account rather than
  /// retry.
  Future<OAuthTokens> refresh(OAuthTokens tokens) async {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null) {
      throw const CalendarAuthException(
          'This account has no refresh token. Please reconnect.');
    }

    final response = await _http.post(Uri.parse(kGoogleTokenEndpoint), body: {
      'client_id': clientId,
      'client_secret': clientSecret,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    });

    final body = _decodeTokenResponse(response);
    return OAuthTokens.fromTokenResponse(
      body,
      existingRefreshToken: refreshToken,
      existingEmail: tokens.email,
    );
  }

  Future<void> revoke(OAuthTokens tokens) async {
    final token = tokens.refreshToken ?? tokens.accessToken;
    if (token.isEmpty) return;
    try {
      await _http.post(Uri.parse(kGoogleRevokeEndpoint), body: {'token': token});
    } catch (e) {
      // Local disconnect must succeed even if Google is unreachable.
      debugPrint('Could not revoke Google token: $e');
    }
  }

  Map<String, dynamic> _decodeTokenResponse(http.Response response) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw CalendarFetchException(
          'Google returned an unreadable response (HTTP ${response.statusCode}).');
    }

    if (response.statusCode == 200) return body;

    final error = body['error'] as String? ?? 'unknown_error';
    final description = body['error_description'] as String?;
    final message = description == null ? error : '$error: $description';

    // invalid_grant means the grant itself is dead — retrying cannot fix it.
    if (error == 'invalid_grant' || error == 'invalid_client') {
      throw CalendarAuthException('Google rejected the sign-in ($message).');
    }
    throw CalendarFetchException('Google token request failed ($message).');
  }
}
