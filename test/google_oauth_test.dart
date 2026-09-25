import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_oauth.dart';

/// Plays the browser: follows the consent URL's redirect back to the loopback
/// socket with [params], and answers the status the shell gave it.
Future<int> redirect(String authUrl, Map<String, String> params) async {
  final auth = Uri.parse(authUrl);
  final back = Uri.parse(
    auth.queryParameters['redirect_uri']!,
  ).replace(queryParameters: params);
  final client = HttpClient();
  try {
    final request = await client.getUrl(back);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// The browser half of the Google sign-in, over a real socket.
void main() {
  test('the PKCE challenge is unpadded base64url of the SHA-256', () {
    // Computed independently: python3 -c "import hashlib, base64;
    // print(base64.urlsafe_b64encode(hashlib.sha256(b'...').digest()))".
    expect(
      pkceChallenge('dBjftJeZ4CVP-mJ92K1RjVBQnXn_UaBvAcy9cDSDCKw'),
      'PyGMyQV3OcoTZWlvytOJh6TDhaoE9h2ud_dXus2fAg0',
    );
    expect(pkceChallenge('x'), isNot(contains('=')));
  });

  test('the consent URL carries everything a refresh token needs', () async {
    final session = await GoogleLoopbackSession.start(
      clientId: 'client.apps.googleusercontent.com',
      scope: kGoogleCalendarScope,
    );
    addTearDown(session.close);
    final params = Uri.parse(session.authUrl).queryParameters;
    expect(params['client_id'], 'client.apps.googleusercontent.com');
    expect(params['redirect_uri'], session.redirectUri);
    expect(session.redirectUri, startsWith('http://127.0.0.1:'));
    expect(params['code_challenge'], pkceChallenge(session.codeVerifier));
    expect(params['code_challenge_method'], 'S256');
    expect(params['access_type'], 'offline');
    expect(params['prompt'], 'consent');
    expect(params['scope'], kGoogleCalendarScope);
    expect(params['state'], session.state);
    expect(session.codeVerifier.length, greaterThanOrEqualTo(43));
  });

  test('the redirect brings the code back', () async {
    final session = await GoogleLoopbackSession.start(
      clientId: 'id',
      scope: kGoogleCalendarScope,
    );
    final status = await redirect(session.authUrl, {
      'state': session.state,
      'code': '4/abc',
    });
    expect(status, 200);
    expect(await session.code, '4/abc');
  });

  test('a request without the state is refused and ignored', () async {
    final session = await GoogleLoopbackSession.start(
      clientId: 'id',
      scope: kGoogleCalendarScope,
    );
    expect(await redirect(session.authUrl, {'code': 'planted'}), 400);
    expect(
      await redirect(session.authUrl, {'state': 'wrong', 'code': 'planted'}),
      400,
    );
    // Still waiting for the real one.
    expect(
      await redirect(session.authUrl, {'state': session.state, 'code': 'real'}),
      200,
    );
    expect(await session.code, 'real');
  });

  test('a declined consent ends the session with the reason', () async {
    final session = await GoogleLoopbackSession.start(
      clientId: 'id',
      scope: kGoogleCalendarScope,
    );
    await redirect(session.authUrl, {
      'state': session.state,
      'error': 'access_denied',
    });
    await expectLater(
      session.code,
      throwsA(
        isA<GoogleSignInAborted>().having(
          (e) => e.message,
          'message',
          'The sign-in was declined',
        ),
      ),
    );
  });

  test('closing or timing out ends the wait', () async {
    final cancelled = await GoogleLoopbackSession.start(
      clientId: 'id',
      scope: kGoogleCalendarScope,
    );
    await cancelled.close();
    await expectLater(cancelled.code, throwsA(isA<GoogleSignInAborted>()));

    final timed = await GoogleLoopbackSession.start(
      clientId: 'id',
      scope: kGoogleCalendarScope,
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      timed.code,
      throwsA(
        isA<GoogleSignInAborted>().having(
          (e) => e.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });
}
