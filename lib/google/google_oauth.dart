// The Google sign-in's browser half: the loopback redirect and PKCE.
//
// Google's device flow — the one the GitHub sign-in uses — allows only a short
// list of scopes and Calendar is not on it, so this is the flow Google
// documents for installed applications instead: open the consent page in the
// user's browser with a redirect to `http://127.0.0.1:<port>`, listen on that
// port, and take the authorization code off the one request the browser makes
// back. The port is whatever the kernel hands out; Google's Desktop clients
// accept any loopback port without registering it.
//
// Two things keep a code from being stolen or planted:
//
//  * **PKCE** (RFC 7636, S256). The code is useless without the verifier, which
//    never leaves this process — another program that read the redirect off a
//    process list could not redeem it.
//  * **`state`**, a random value the redirect must echo. A request without it
//    — a stale tab, a page on some website poking at localhost — is answered
//    400 and ignored, and the session goes on waiting for the real one.
//
// Flutter-free (`dart:io` and `package:crypto`), so the test drives a real
// socket.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The PKCE challenge for [verifier]: base64url of its SHA-256, unpadded.
String pkceChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

const String _kUnreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

String _randomString(Random random, int length) => String.fromCharCodes([
  for (var i = 0; i < length; i++)
    _kUnreserved.codeUnitAt(random.nextInt(_kUnreserved.length)),
]);

/// One sign-in attempt: a listening socket, the URL to open, and the code the
/// browser eventually brings back.
class GoogleLoopbackSession {
  GoogleLoopbackSession._(
    this._server, {
    required this.authUrl,
    required this.redirectUri,
    required this.codeVerifier,
    required this.state,
  });

  /// Binds the socket and builds the consent URL. Nothing is opened yet — the
  /// caller hands [authUrl] to the browser.
  static Future<GoogleLoopbackSession> start({
    required String clientId,
    required String scope,
    Duration timeout = const Duration(minutes: 5),
    Random? random,
  }) async {
    final rng = random ?? Random.secure();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';
    final verifier = _randomString(rng, 64);
    final state = _randomString(rng, 32);
    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scope,
      'code_challenge': pkceChallenge(verifier),
      'code_challenge_method': 'S256',
      'state': state,
      // Offline plus a forced consent screen is what guarantees a refresh
      // token: Google sends one only on a consent, and a second sign-in with
      // the same client would otherwise come back without it.
      'access_type': 'offline',
      'prompt': 'consent',
    }).toString();
    final session = GoogleLoopbackSession._(
      server,
      authUrl: authUrl,
      redirectUri: redirectUri,
      codeVerifier: verifier,
      state: state,
    );
    session._listen(timeout);
    return session;
  }

  final HttpServer _server;

  /// The consent page to open in the browser.
  final String authUrl;

  /// Where Google sends the browser back to — passed again at the exchange,
  /// which must match it exactly.
  final String redirectUri;

  /// The PKCE secret, sent only with the code exchange.
  final String codeVerifier;

  final String state;

  final Completer<String> _code = Completer<String>();
  Timer? _timeout;

  /// Completes with the authorization code, or with a [GoogleSignInAborted]
  /// when the user declines, the session times out or [close] is called first.
  Future<String> get code => _code.future;

  void _listen(Duration timeout) {
    // A session closed with nobody awaiting [code] must not surface as an
    // unhandled error; anyone who does await it still gets the error.
    _code.future.ignore();
    _timeout = Timer(timeout, () {
      _finish(error: const GoogleSignInAborted('The sign-in timed out'));
    });
    _server.listen(_handle, onError: (_) {}, cancelOnError: false);
  }

  Future<void> _handle(HttpRequest request) async {
    final params = request.uri.queryParameters;
    // A browser also asks for /favicon.ico, and anything else on this port is
    // not the redirect.
    if (request.uri.path != '/' || params['state'] != state) {
      request.response.statusCode = HttpStatus.badRequest;
      await _reply(request, 'This is not the sign-in you started.');
      return;
    }
    final error = params['error'];
    final code = params['code'];
    if (error != null) {
      await _reply(request, 'Sign-in cancelled. You can close this tab.');
      _finish(
        error: GoogleSignInAborted(
          error == 'access_denied'
              ? 'The sign-in was declined'
              : 'Google refused the sign-in ($error)',
        ),
      );
      return;
    }
    if (code == null || code.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await _reply(request, 'Google sent no code back.');
      return;
    }
    await _reply(
      request,
      'Signed in. You can close this tab and go back to Moonswing.',
    );
    _finish(code: code);
  }

  static Future<void> _reply(HttpRequest request, String message) async {
    try {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><meta charset="utf-8"><title>Moonswing</title>'
        '<body style="font:16px sans-serif;margin:4em auto;max-width:32em">'
        '<p>${const HtmlEscape().convert(message)}</p></body>',
      );
      await request.response.close();
    } catch (_) {
      // A browser that hung up is no reason to lose the code it brought.
    }
  }

  void _finish({String? code, Object? error}) {
    if (_code.isCompleted) return;
    if (code != null) {
      _code.complete(code);
    } else {
      _code.completeError(error ?? const GoogleSignInAborted('Cancelled'));
    }
    unawaited(close());
  }

  /// Stops listening. A session closed before the code arrived completes
  /// [code] with [GoogleSignInAborted].
  Future<void> close() async {
    _timeout?.cancel();
    _timeout = null;
    if (!_code.isCompleted) {
      _code.completeError(const GoogleSignInAborted('Cancelled'));
    }
    await _server.close(force: true);
  }
}

/// The browser half ended without a code.
class GoogleSignInAborted implements Exception {
  const GoogleSignInAborted(this.message);

  final String message;

  @override
  String toString() => message;
}
