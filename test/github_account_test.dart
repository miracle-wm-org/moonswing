import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/github/github_account_store.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_token_store.dart';

import 'github_fakes.dart';

/// The GitHub account every consumer shares: the saved token, the device-flow
/// sign-in behind Settings › Accounts, and the sign-out a rejected token makes.
void main() {
  late Directory tempDir;
  late GithubTokenStore tokens;
  late List<String> opened;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('moonswing-github-account');
    tokens = GithubTokenStore(directory: tempDir.path);
    opened = [];
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  GithubAccountStore accountWith(FakeGithubClient client) {
    final account = GithubAccountStore.forTesting(
      client: client,
      tokens: tokens,
      opener: (url) {
        opened.add(url);
        return true;
      },
    );
    addTearDown(account.dispose);
    return account;
  }

  group('loading', () {
    test('a saved token signs in, and the login follows', () async {
      await tokens.write('saved-token');
      final client = FakeGithubClient();
      final account = accountWith(client);

      await account.load();
      await settle();

      expect(account.loaded, isTrue);
      expect(account.stage, GithubAuthStage.signedIn);
      expect(account.token, 'saved-token');
      expect(account.login, 'octocat');
    });

    test('no token is signed out, and costs no request', () async {
      final client = FakeGithubClient();
      final account = accountWith(client);

      await account.load();

      expect(account.loaded, isTrue);
      expect(account.stage, GithubAuthStage.signedOut);
      expect(client.loginCalls, 0);
    });
  });

  group('withToken', () {
    test('hands the token to the request', () async {
      await tokens.write('saved-token');
      final account = accountWith(FakeGithubClient());

      final seen = await account.withToken((token) async => token);

      expect(seen, 'saved-token');
    });

    test('signed out is an exception, not a request without a token', () async {
      final account = accountWith(FakeGithubClient());

      expect(
        () => account.withToken((token) async => token),
        throwsA(isA<GithubException>()),
      );
    });

    test(
      'a rejected token signs out, says why, and forgets the file',
      () async {
        await tokens.write('saved-token');
        final account = accountWith(FakeGithubClient());
        await account.load();

        await expectLater(
          account.withToken<void>(
            (_) async => throw const GithubAuthException('token revoked'),
          ),
          throwsA(isA<GithubAuthException>()),
        );

        expect(account.stage, GithubAuthStage.signedOut);
        expect(account.error, 'token revoked');
        expect(await tokens.read(), isNull);
      },
    );
  });

  group('the sign-in', () {
    test(
      'publishes the code, opens the browser, and finishes with a token',
      () async {
        final client = FakeGithubClient(
          tokenResults: [
            const GithubTokenPending(),
            const GithubTokenGranted('gho_new'),
          ],
        );
        final account = accountWith(client);

        final signIn = account.signIn();
        // One turn: enough for the device code to land and be published, not
        // enough for the poll to have answered.
        await Future<void>.delayed(Duration.zero);
        expect(account.stage, GithubAuthStage.awaitingAuthorization);
        expect(account.deviceCode?.userCode, 'ABCD-1234');
        expect(opened, [
          'https://github.com/login/device',
        ], reason: 'the browser is opened for the user, as `gh` does');

        await signIn;
        await settle();

        expect(account.stage, GithubAuthStage.signedIn);
        expect(account.deviceCode, isNull);
        expect(client.tokenCalls, 2, reason: 'the first answer was pending');
        expect(await tokens.read(), 'gho_new', reason: 'and it was saved');
        expect(account.login, 'octocat');
      },
    );

    test('a cancelled sign-in does not log the user in afterwards', () async {
      final client = FakeGithubClient(
        tokenResults: [const GithubTokenPending()],
      );
      final account = accountWith(client);

      final signIn = account.signIn();
      await Future<void>.delayed(Duration.zero);
      expect(account.stage, GithubAuthStage.awaitingAuthorization);

      account.cancelSignIn();
      // Whatever the poll does from here — including handing back a token —
      // must not sign anybody in.
      client.tokenResults = [const GithubTokenGranted('gho_late')];
      await signIn;
      await settle();

      expect(account.stage, GithubAuthStage.signedOut);
      expect(account.deviceCode, isNull);
      expect(await tokens.read(), isNull);
    });

    test('a refused sign-in reports why and offers the button again', () async {
      final client = FakeGithubClient()
        ..failDeviceCodeWith = const GithubException(
          'Device flow is not enabled for this app',
        );
      final account = accountWith(client);

      await account.signIn();

      expect(account.stage, GithubAuthStage.signedOut);
      expect(account.error, 'Device flow is not enabled for this app');
    });

    test(
      'an expired code ends the sign-in rather than polling forever',
      () async {
        final client =
            FakeGithubClient(tokenResults: [const GithubTokenPending()])
              ..deviceCode = const GithubDeviceCode(
                deviceCode: 'dc',
                userCode: 'ABCD-1234',
                verificationUri: 'https://github.com/login/device',
                interval: 0,
                // Already expired by the time the first poll comes around.
                expiresIn: -1,
              );
        final account = accountWith(client);

        await account.signIn();

        expect(account.stage, GithubAuthStage.signedOut);
        expect(account.error, contains('expired'));
        expect(client.tokenCalls, 0);
      },
    );

    test('runs against the configured app and scopes', () async {
      final client = RecordingGithubClient();
      final account = GithubAccountStore.forTesting(
        client: client,
        tokens: tokens,
        clientId: 'my-app',
        scopes: 'notifications repo',
      );
      addTearDown(account.dispose);

      await account.signIn();

      expect(client.clientIdSeen, 'my-app');
      expect(client.scopesSeen, 'notifications repo');
    });

    test('signing out drops the token and the login', () async {
      await tokens.write('saved-token');
      final account = accountWith(FakeGithubClient());
      await account.load();
      await settle();

      await account.signOut();

      expect(account.stage, GithubAuthStage.signedOut);
      expect(account.login, isEmpty);
      expect(account.token, isNull);
      expect(await tokens.read(), isNull);
    });
  });
}

/// A fake that remembers what the device-code request was asked for.
class RecordingGithubClient extends FakeGithubClient {
  String? clientIdSeen;
  String? scopesSeen;

  @override
  Future<GithubDeviceCode> requestDeviceCode({
    required String clientId,
    required String scopes,
  }) {
    clientIdSeen = clientId;
    scopesSeen = scopes;
    return super.requestDeviceCode(clientId: clientId, scopes: scopes);
  }
}
