import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/overlay/calendar/google_oauth.dart';
import 'package:graceful_shell/overlay/calendar/provider.dart';

String _unsignedJwt(Map<String, dynamic> payload) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${seg({'alg': 'none'})}.${seg(payload)}.signature';
}

void main() {
  group('PKCE', () {
    test('codeChallengeS256 matches the RFC 7636 Appendix B vector', () {
      expect(
        codeChallengeS256('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('the challenge is unpadded base64url', () {
      final challenge = codeChallengeS256(generateCodeVerifier());
      expect(challenge, isNot(contains('=')));
      expect(challenge, isNot(contains('+')));
      expect(challenge, isNot(contains('/')));
    });

    test('verifiers are RFC-legal and not repeated', () {
      final a = generateCodeVerifier();
      final b = generateCodeVerifier();
      expect(a, isNot(b));
      for (final v in [a, b]) {
        expect(v.length, inInclusiveRange(43, 128));
        expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
      }
    });
  });

  group('buildAuthUrl', () {
    final url = buildAuthUrl(
      clientId: 'cid',
      redirectUri: 'http://127.0.0.1:1234',
      scopes: kGoogleCalendarScopes,
      codeChallenge: 'challenge',
      state: 'st4te',
    );

    test('carries the PKCE and offline-access parameters', () {
      final q = url.queryParameters;
      expect(q['code_challenge'], 'challenge');
      expect(q['code_challenge_method'], 'S256');
      expect(q['response_type'], 'code');
      // Without these Google withholds the refresh token on a reconnect.
      expect(q['access_type'], 'offline');
      expect(q['prompt'], 'consent');
      expect(q['redirect_uri'], 'http://127.0.0.1:1234');
      expect(q['state'], 'st4te');
    });

    test('requests read-only calendar access plus the identity scopes', () {
      final scopes = url.queryParameters['scope']!.split(' ');
      expect(scopes, contains('https://www.googleapis.com/auth/calendar.readonly'));
      expect(scopes, containsAll(['openid', 'email']));
      // Read-only for now: nothing here should let the shell mutate a calendar.
      expect(scopes.any((s) => s.endsWith('/auth/calendar')), isFalse);
    });
  });

  group('parseRedirect', () {
    test('returns the code on success', () {
      final uri = Uri.parse('http://127.0.0.1:1/?code=abc123&state=st');
      expect(parseRedirect(uri, expectedState: 'st'), 'abc123');
    });

    test('rejects a mismatched state', () {
      final uri = Uri.parse('http://127.0.0.1:1/?code=abc&state=other');
      expect(
        () => parseRedirect(uri, expectedState: 'st'),
        throwsA(isA<CalendarAuthException>()),
      );
    });

    test('surfaces the error description when consent is denied', () {
      final uri = Uri.parse(
          'http://127.0.0.1:1/?error=access_denied&error_description=User+said+no&state=st');
      expect(
        () => parseRedirect(uri, expectedState: 'st'),
        throwsA(isA<CalendarAuthException>()
            .having((e) => e.message, 'message', contains('User said no'))),
      );
    });

    test('rejects a response with no code at all', () {
      expect(
        () => parseRedirect(Uri.parse('http://127.0.0.1:1/?state=st'),
            expectedState: 'st'),
        throwsA(isA<CalendarAuthException>()),
      );
    });
  });

  group('decodeIdTokenPayload', () {
    test('extracts the email claim', () {
      final jwt = _unsignedJwt({'email': 'user@gmail.com', 'sub': '1'});
      expect(decodeIdTokenPayload(jwt)!['email'], 'user@gmail.com');
    });

    test('returns null for a malformed token', () {
      expect(decodeIdTokenPayload('not-a-jwt'), isNull);
      expect(decodeIdTokenPayload('a.b.c'), isNull);
    });
  });

  group('OAuthTokens', () {
    final now = DateTime(2026, 7, 13, 12);

    test('isExpired applies a 60s skew', () {
      final tokens = OAuthTokens(
        accessToken: 'a',
        expiresAt: now.add(const Duration(minutes: 5)),
      );
      expect(tokens.isExpired(now: now), isFalse);
      // 30s of life left is less than the skew, so treat it as already spent.
      expect(
        tokens.isExpired(now: now.add(const Duration(minutes: 4, seconds: 30))),
        isTrue,
      );
    });

    test('fromTokenResponse derives expiry and email', () {
      final tokens = OAuthTokens.fromTokenResponse({
        'access_token': 'at',
        'refresh_token': 'rt',
        'expires_in': 3600,
        'id_token': _unsignedJwt({'email': 'user@gmail.com'}),
      }, now: now);

      expect(tokens.accessToken, 'at');
      expect(tokens.refreshToken, 'rt');
      expect(tokens.email, 'user@gmail.com');
      expect(tokens.expiresAt, now.add(const Duration(hours: 1)));
    });

    test('a refresh response carries the existing refresh token forward', () {
      // Google omits refresh_token when refreshing; dropping it would strand
      // the account with no way to renew once the access token dies.
      final tokens = OAuthTokens.fromTokenResponse(
        {'access_token': 'new', 'expires_in': 3600},
        now: now,
        existingRefreshToken: 'rt',
        existingEmail: 'user@gmail.com',
      );
      expect(tokens.refreshToken, 'rt');
      expect(tokens.email, 'user@gmail.com');
    });

    test('round-trips through JSON', () {
      final tokens = OAuthTokens(
        accessToken: 'at',
        refreshToken: 'rt',
        expiresAt: now,
        email: 'user@gmail.com',
        scope: 'a b',
      );
      final restored = OAuthTokens.fromJson(tokens.toJson());
      expect(restored.accessToken, 'at');
      expect(restored.refreshToken, 'rt');
      expect(restored.expiresAt, now);
      expect(restored.email, 'user@gmail.com');
      expect(restored.scope, 'a b');
    });
  });
}
