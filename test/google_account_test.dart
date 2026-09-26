import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/google/google_account_file.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_client.dart';

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
      const accounts = [
        GoogleAccountData(
          clientId: 'id',
          refreshToken: 'r',
          email: 'me@example.com',
        ),
        GoogleAccountData(
          clientId: 'id',
          refreshToken: 'w',
          email: 'me@work.example',
        ),
      ];
      expect(await file.read(), isEmpty);
      expect(await file.write(accounts), isTrue);
      expect(await file.read(), accounts);
      expect(File(file.path).statSync().mode & 0x1FF, 0x180, reason: '0600');
      expect(
        Directory(file.directory).statSync().mode & 0x1FF,
        0x1C0,
        reason: '0700',
      );
      await file.clear();
      expect(await file.read(), isEmpty);
    });

    test('a single-account file reads as a list of one', () async {
      Directory(file.directory).createSync(recursive: true);
      File(file.path).writeAsStringSync(
        jsonEncode({
          'client_id': 'id',
          'refresh_token': 'r',
          'email': 'me@example.com',
        }),
      );
      expect(await file.read(), const [
        GoogleAccountData(
          clientId: 'id',
          refreshToken: 'r',
          email: 'me@example.com',
        ),
      ]);
    });

    test(
      'a damaged file is no account, and a bad entry costs that entry',
      () async {
        Directory(file.directory).createSync(recursive: true);
        File(file.path).writeAsStringSync('{not json');
        expect(await file.read(), isEmpty);
        File(file.path).writeAsStringSync(
          jsonEncode({
            'accounts': [
              {'client_id': 'id', 'client_secret': 5, 'refresh_token': ''},
              'nonsense',
              {'client_id': 'id', 'refresh_token': 'r', 'email': 7},
            ],
          }),
        );
        expect(await file.read(), const [
          GoogleAccountData(clientId: 'id', refreshToken: 'r'),
        ]);
      },
    );

    test('a secret saved by an older shell is dropped on rewrite', () async {
      Directory(file.directory).createSync(recursive: true);
      File(file.path).writeAsStringSync(
        jsonEncode({
          'client_id': 'id',
          'client_secret': 'theirs',
          'refresh_token': 'r',
        }),
      );
      final data = await file.read();
      expect(data, const [
        GoogleAccountData(clientId: 'id', refreshToken: 'r'),
      ]);
      await file.write(data);
      expect(File(file.path).readAsStringSync(), isNot(contains('secret')));
    });
  });

  group('GoogleAccountStore', () {
    test('offers the sign-in straight away', () async {
      final store = GoogleAccountStore.forTesting(
        client: FakeGoogleClient(),
        file: file,
      );
      await store.load();
      expect(store.stage, GoogleAuthStage.signedOut);
      expect(store.error, isEmpty);
    });

    test('a build with no client has no sign-in to offer', () async {
      final store = GoogleAccountStore.forTesting(
        client: FakeGoogleClient(),
        file: file,
        clientId: '',
        clientSecret: '',
      );
      await store.load();
      expect(store.stage, GoogleAuthStage.unavailable);
      await store.signIn();
      expect(store.stage, GoogleAuthStage.unavailable);
    });

    test('the shipped client is the default', () async {
      final store = GoogleAccountStore.forTesting(
        client: FakeGoogleClient(),
        file: file,
        clientId: kGoogleClientId,
        clientSecret: kGoogleClientSecret,
      );
      await store.load();
      expect(kGoogleClientId, endsWith('.apps.googleusercontent.com'));
      expect(store.stage, GoogleAuthStage.signedOut);
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
        unawaited(store.signIn());
        await untilStage(store, GoogleAuthStage.signedIn);
        // The stage moves before the grant is written; the exchange is over
        // once it has landed.
        for (var i = 0; i < 200 && store.busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        expect(client.exchanges, 1);
        expect(client.lastRedirectUri, startsWith('http://127.0.0.1:'));
        expect(store.accounts.map((a) => a.email), ['me@example.com']);
        expect(store.error, isEmpty);
        final saved = (await file.read()).single;
        expect(saved.refreshToken, 'refresh-for-4/code');
        expect(saved.clientId, 'id', reason: 'the client the grant is for');
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
        await file.write(const [
          GoogleAccountData(clientId: 'id', refreshToken: 'r'),
        ]);
        final store = GoogleAccountStore.forTesting(
          client: client,
          file: file,
          now: () => now,
        );
        await store.load();
        final id = store.accounts.single.id;
        expect(id, isNot(contains('r')), reason: 'never the grant itself');

        client.refreshGate = Completer<void>();
        final first = store.withAccessToken(id, (t) async => t);
        final second = store.withAccessToken(id, (t) async => t);
        await Future<void>.delayed(Duration.zero);
        client.refreshGate!.complete();
        client.refreshGate = null;
        expect(await first, 'access-1');
        expect(await second, 'access-1');
        expect(client.refreshes, 1);

        // Still good: no refresh.
        now = now.add(const Duration(minutes: 30));
        expect(await store.withAccessToken(id, (t) async => t), 'access-1');
        expect(client.refreshes, 1);

        // Within the margin of expiry: refreshed.
        now = now.add(const Duration(minutes: 29, seconds: 30));
        expect(await store.withAccessToken(id, (t) async => t), 'access-2');
        expect(client.refreshes, 2);
      },
    );

    test('a 401 gets one fresh token and one retry', () async {
      final client = FakeGoogleClient();
      await file.write(const [
        GoogleAccountData(clientId: 'id', refreshToken: 'r'),
      ]);
      final store = GoogleAccountStore.forTesting(client: client, file: file);
      await store.load();
      client.unauthorizedEvents = 1;
      final events = await store.withAccessToken(
        store.accounts.single.id,
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

    test('a dead grant signs that account out and says why', () async {
      final client = FakeGoogleClient()
        ..refreshError = const GoogleAuthException('revoked');
      await file.write(const [
        GoogleAccountData(clientId: 'id', refreshToken: 'r'),
      ]);
      final store = GoogleAccountStore.forTesting(client: client, file: file);
      await store.load();
      await expectLater(
        store.withAccessToken(store.accounts.single.id, (t) async => t),
        throwsA(isA<GoogleAuthException>()),
      );
      expect(store.stage, GoogleAuthStage.signedOut);
      expect(store.error, 'revoked');
      expect(await file.read(), isEmpty);
    });

    test('signing out revokes the grant and forgets it', () async {
      final client = FakeGoogleClient();
      await file.write(const [
        GoogleAccountData(
          clientId: 'id',
          refreshToken: 'r',
          email: 'me@example.com',
        ),
      ]);
      final store = GoogleAccountStore.forTesting(client: client, file: file);
      await store.load();
      await store.signOut('me@example.com');
      expect(store.stage, GoogleAuthStage.signedOut);
      expect(store.accounts, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(client.revoked, ['r']);
      expect(await file.read(), isEmpty);
    });

    test(
      'a second sign-in adds an account; signing one out keeps the other',
      () async {
        final client = FakeGoogleClient();
        await file.write(const [
          GoogleAccountData(
            clientId: 'id',
            refreshToken: 'r',
            email: 'me@example.com',
          ),
        ]);
        final store = GoogleAccountStore.forTesting(
          client: client,
          file: file,
          opener: browserThatConsents('4/work'),
        );
        await store.load();
        client.calendars = const [
          GoogleCalendar(id: 'me@work.example', summary: 'Work', primary: true),
        ];
        final usableMeanwhile = <bool>[];
        void watch() {
          if (store.stage == GoogleAuthStage.awaitingBrowser) {
            usableMeanwhile.add(store.signedIn);
          }
        }

        store.addListener(watch);
        unawaited(store.signIn());
        for (var i = 0; i < 200 && (await file.read()).length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        store.removeListener(watch);
        expect(usableMeanwhile, isNotEmpty);
        expect(
          usableMeanwhile,
          everyElement(isTrue),
          reason: 'the first stays',
        );
        expect(store.stage, GoogleAuthStage.signedIn);
        expect(store.accounts.map((a) => a.email), [
          'me@example.com',
          'me@work.example',
        ]);
        expect((await file.read()).map((a) => a.refreshToken), [
          'r',
          'refresh-for-4/work',
        ]);

        // Each account has its own token.
        final tokens = [
          for (final a in store.accounts)
            await store.withAccessToken(a.id, (t) async => t),
        ];
        expect(tokens.toSet(), hasLength(2));

        await store.signOut('me@example.com');
        expect(store.accounts.map((a) => a.email), ['me@work.example']);
        expect(store.stage, GoogleAuthStage.signedIn);
        expect((await file.read()).map((a) => a.email), ['me@work.example']);
      },
    );

    test('signing in again as the same account replaces its grant', () async {
      final client = FakeGoogleClient();
      await file.write(const [
        GoogleAccountData(
          clientId: 'id',
          refreshToken: 'old',
          email: 'me@example.com',
        ),
      ]);
      final store = GoogleAccountStore.forTesting(
        client: client,
        file: file,
        opener: browserThatConsents('again'),
      );
      await store.load();
      unawaited(store.signIn());
      for (
        var i = 0;
        i < 200 && (await file.read()).single.refreshToken == 'old';
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.accounts, hasLength(1));
      expect((await file.read()).single.refreshToken, 'refresh-for-again');
      expect(client.revoked, isEmpty, reason: 'that would revoke the new one');
    });

    test(
      'a grant from another client is revoked and dropped, saying why',
      () async {
        final client = FakeGoogleClient();
        await file.write(const [
          GoogleAccountData(
            clientId: 'their-own',
            refreshToken: 'r',
            email: 'me@example.com',
          ),
        ]);
        final store = GoogleAccountStore.forTesting(client: client, file: file);
        await store.load();
        expect(store.stage, GoogleAuthStage.signedOut);
        expect(store.accounts, isEmpty);
        expect(store.error, contains("Moonswing's own app"));
        expect(await file.read(), isEmpty);
        await Future<void>.delayed(Duration.zero);
        expect(client.revoked, ['r']);
      },
    );

    test('a grant saved with no client recorded is kept', () async {
      final client = FakeGoogleClient();
      await file.write(const [GoogleAccountData(refreshToken: 'r')]);
      final store = GoogleAccountStore.forTesting(client: client, file: file);
      await store.load();
      expect(store.stage, GoogleAuthStage.signedIn);
      expect(client.revoked, isEmpty);
    });
  });
}
