import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/google/google_account_file.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_api.dart';

import 'google_fakes.dart';

/// Plays the browser for a sign-in: follows the consent URL straight back to
/// the loopback socket with a code, as Google would after a consent.
bool Function(String url) browserThatConsents(String code) => (url) {
  final auth = Uri.parse(url);
  final back = Uri.parse(auth.queryParameters['redirect_uri']!).replace(
    queryParameters: {'state': auth.queryParameters['state']!, 'code': code},
  );
  unawaited(() async {
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(back)).close();
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  }());
  return true;
};

/// Waits for [store] to reach [stage].
Future<void> untilStage(GoogleAccountStore store, GoogleAuthStage stage) async {
  for (var i = 0; i < 200 && store.stage != stage; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(store.stage, stage);
}

void main() {
  late Directory tempDir;
  late GoogleAccountFile file;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('moonswing-google');
    file = GoogleAccountFile(directory: '${tempDir.path}/state');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('GoogleAccountFile', () {
    test('round-trips, and is readable by nobody else', () async {
      const data = GoogleAccountData(
        clientId: 'id',
        clientSecret: 'secret',
        refreshToken: 'r',
        email: 'me@example.com',
      );
      expect(await file.read(), const GoogleAccountData());
      expect(await file.write(data), isTrue);
      expect(await file.read(), data);
      expect(File(file.path).statSync().mode & 0x1FF, 0x180, reason: '0600');
      expect(
        Directory(file.directory).statSync().mode & 0x1FF,
        0x1C0,
        reason: '0700',
      );
      await file.clear();
      expect(await file.read(), const GoogleAccountData());
    });

    test(
      'a damaged file is no account, and a wrong key costs that key',
      () async {
        Directory(file.directory).createSync(recursive: true);
        File(file.path).writeAsStringSync('{not json');
        expect(await file.read(), const GoogleAccountData());
        File(file.path).writeAsStringSync(
          jsonEncode({
            'client_id': 'id',
            'client_secret': 5,
            'refresh_token': '',
          }),
        );
        final data = await file.read();
        expect(data.clientId, 'id');
        expect(data.clientSecret, isEmpty);
        expect(data.refreshToken, isNull);
        expect(data.hasClient, isFalse);
      },
    );
  });

  group('GoogleAccountStore', () {
    test('asks for a client first, then offers the sign-in', () async {
      final store = GoogleAccountStore.forTesting(
        client: FakeGoogleClient(),
        file: file,
      );
      await store.load();
      expect(store.stage, GoogleAuthStage.needsClient);
      await store.setClient(id: 'id');
      expect(store.stage, GoogleAuthStage.needsClient);
      await store.setClient(secret: 'secret');
      expect(store.stage, GoogleAuthStage.signedOut);
      expect(store.hasClientSecret, isTrue);
      expect((await file.read()).clientId, 'id');
    });

    test(
      'a sign-in through the browser saves the grant and the address',
      () async {
        final client = FakeGoogleClient();
        final store = GoogleAccountStore.forTesting(
          client: client,
          file: file,
          opener: browserThatConsents('4/code'),
        );
        await store.setClient(id: 'id', secret: 'secret');
        unawaited(store.signIn());
        await untilStage(store, GoogleAuthStage.signedIn);

        expect(client.exchanges, 1);
        expect(client.lastRedirectUri, startsWith('http://127.0.0.1:'));
        expect(store.email, 'me@example.com');
        expect(store.error, isEmpty);
        final saved = await file.read();
        expect(saved.refreshToken, 'refresh-for-4/code');
        expect(saved.email, 'me@example.com');

        // A new store over the same file comes up signed in.
        final again = GoogleAccountStore.forTesting(client: client, file: file);
        await again.load();
        expect(again.stage, GoogleAuthStage.signedIn);
      },
    );

    test('a cancelled sign-in goes back quietly', () async {
      final store = GoogleAccountStore.forTesting(
        client: FakeGoogleClient(),
        file: file,
      );
      await store.setClient(id: 'id', secret: 'secret');
      unawaited(store.signIn());
      await untilStage(store, GoogleAuthStage.awaitingBrowser);
      store.cancelSignIn();
      expect(store.stage, GoogleAuthStage.signedOut);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.stage, GoogleAuthStage.signedOut);
      expect(store.error, isEmpty);
    });

    test(
      'the access token is refreshed near expiry, once for everyone',
      () async {
        var now = DateTime(2026, 9, 25, 9);
        final client = FakeGoogleClient(now: () => now);
        await file.write(
          const GoogleAccountData(
            clientId: 'id',
            clientSecret: 'secret',
            refreshToken: 'r',
          ),
        );
        final store = GoogleAccountStore.forTesting(
          client: client,
          file: file,
          now: () => now,
        );
        await store.load();

        client.refreshGate = Completer<void>();
        final first = store.withAccessToken((t) async => t);
        final second = store.withAccessToken((t) async => t);
        await Future<void>.delayed(Duration.zero);
        client.refreshGate!.complete();
        client.refreshGate = null;
        expect(await first, 'access-1');
        expect(await second, 'access-1');
        expect(client.refreshes, 1);

        // Still good: no refresh.
        now = now.add(const Duration(minutes: 30));
        expect(await store.withAccessToken((t) async => t), 'access-1');
        expect(client.refreshes, 1);

        // Within the margin of expiry: refreshed.
        now = now.add(const Duration(minutes: 29, seconds: 30));
        expect(await store.withAccessToken((t) async => t), 'access-2');
        expect(client.refreshes, 2);
      },
    );

    test('a 401 gets one fresh token and one retry', () async {
      final client = FakeGoogleClient();
      await file.write(
        const GoogleAccountData(
          clientId: 'id',
          clientSecret: 'secret',
          refreshToken: 'r',
        ),
      );
      final store = GoogleAccountStore.forTesting(client: client, file: file);
      client.unauthorizedEvents = 1;
      final events = await store.withAccessToken(
        (t) => client.listEvents(
          accessToken: t,
          calendarId: 'primary',
          from: DateTime(2026),
          to: DateTime(2027),
        ),
      );
      expect(events, isEmpty);
      expect(client.accessTokensSeen, ['access-1', 'access-2']);
      expect(store.signedIn, isTrue);
    });

    test('a dead grant signs out, says why, and keeps the client', () async {
      final client = FakeGoogleClient()
        ..refreshError = const GoogleAuthException('revoked');
      await file.write(
        const GoogleAccountData(
          clientId: 'id',
          clientSecret: 'secret',
          refreshToken: 'r',
        ),
      );
      final store = GoogleAccountStore.forTesting(client: client, file: file);
      await expectLater(
        store.withAccessToken((t) async => t),
        throwsA(isA<GoogleAuthException>()),
      );
      expect(store.stage, GoogleAuthStage.signedOut);
      expect(store.error, 'revoked');
      final saved = await file.read();
      expect(saved.refreshToken, isNull);
      expect(saved.clientId, 'id');
    });

    test('signing out revokes the grant and forgets it', () async {
      final client = FakeGoogleClient();
      await file.write(
        const GoogleAccountData(
          clientId: 'id',
          clientSecret: 'secret',
          refreshToken: 'r',
          email: 'me@example.com',
        ),
      );
      final store = GoogleAccountStore.forTesting(client: client, file: file);
      await store.load();
      await store.signOut();
      expect(store.stage, GoogleAuthStage.signedOut);
      expect(store.email, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(client.revoked, ['r']);
      expect((await file.read()).refreshToken, isNull);
    });

    test('a new client drops a grant the old one was given', () async {
      final client = FakeGoogleClient();
      await file.write(
        const GoogleAccountData(
          clientId: 'id',
          clientSecret: 'secret',
          refreshToken: 'r',
        ),
      );
      final store = GoogleAccountStore.forTesting(client: client, file: file);
      await store.setClient(id: 'other');
      expect(store.stage, GoogleAuthStage.signedOut);
      expect((await file.read()).refreshToken, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(client.revoked, ['r']);
    });
  });
}
