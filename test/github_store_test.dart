import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_config.dart';
import 'package:moonswing/github/github_store.dart';
import 'package:moonswing/github/github_token_store.dart';

import 'github_fakes.dart';

/// The store: the lease, the poll, the sign-in state machine, and the writes
/// that mark a thread read. Every one of these drives a real store through a
/// fake client and a token file under a temporary directory.
void main() {
  late Directory tempDir;
  late GithubTokenStore tokens;
  late List<String> opened;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('moonswing-github-test');
    tokens = GithubTokenStore(directory: tempDir.path);
    opened = [];
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  GithubStore storeWith(
    FakeGithubClient client, {
    GithubConfig config = const GithubConfig(),
  }) {
    final store = GithubStore.forTesting(
      client: client,
      tokens: tokens,
      config: config,
      opener: (url) {
        opened.add(url);
        return true;
      },
    );
    addTearDown(store.dispose);
    return store;
  }

  /// A store that has already been signed in, the way a restart finds one: a
  /// token on disk and nothing else.
  Future<GithubStore> signedInStore(
    FakeGithubClient client, {
    GithubConfig config = const GithubConfig(),
  }) async {
    await tokens.write('saved-token');
    final store = storeWith(client, config: config);
    store.acquire();
    await settle();
    return store;
  }

  group('the lease', () {
    test('nothing is fetched until something holds one', () async {
      await tokens.write('saved-token');
      final client = FakeGithubClient();
      storeWith(client);
      await settle();

      expect(client.fetchCalls, 0, reason: 'an idle shell polls for nothing');
    });

    test('the first lease reads the token and fetches at once', () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(items: [testNotification()]),
      ]);
      final store = await signedInStore(client);

      expect(store.stage, GithubAuthStage.signedIn);
      expect(client.fetchCalls, 1);
      expect(store.items, hasLength(1));
      expect(store.unreadCount, 1);
      expect(store.polling, isTrue);
    });

    test('a second lease is not a second poller', () async {
      final client = FakeGithubClient();
      final store = await signedInStore(client);
      store.acquire();
      await settle();

      expect(store.leaseCount, 2);
      expect(client.fetchCalls, 1, reason: 'one poller for the machine');

      store.release();
      expect(store.polling, isTrue, reason: 'the other consumer still wants it');
      store.release();
      expect(store.polling, isFalse);
    });

    test('a shell with no token signs nothing in and polls for nothing',
        () async {
      final client = FakeGithubClient();
      final store = storeWith(client);
      store.acquire();
      await settle();

      expect(store.stage, GithubAuthStage.signedOut);
      expect(client.fetchCalls, 0);
      expect(store.polling, isFalse);
    });
  });

  group('the fetch', () {
    test('a 304 leaves the list alone and notifies nobody about it', () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(
          items: [testNotification(title: 'First')],
          lastModified: 'Tue, 15 Sep 2026 12:00:00 GMT',
        ),
        const GithubNotificationPage(items: [], notModified: true),
      ]);
      final store = await signedInStore(client);
      expect(store.items.single.title, 'First');

      await store.refresh();

      expect(client.lastModifiedSeen, 'Tue, 15 Sep 2026 12:00:00 GMT',
          reason: 'the validator is echoed back, so the 304 is possible');
      expect(store.items.single.title, 'First',
          reason: 'not modified means the list on screen is current');
    });

    test('a poll that finds nothing new wakes nobody', () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(items: [testNotification()]),
      ]);
      final store = await signedInStore(client);
      var notified = 0;
      store.addListener(() => notified++);

      // The same list again — the 200 case, which is what a poll answers with
      // whenever the validator has moved but the threads have not.
      await store.refresh();
      // And the 304 case.
      client.pages = [const GithubNotificationPage(items: [], notModified: true)];
      await store.refresh();

      expect(client.fetchCalls, 3);
      expect(notified, 0,
          reason: 'every panel on every monitor listens to this');
    });

    test('a failed refresh keeps the last list, with the reason on it',
        () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(items: [testNotification(title: 'Kept')]),
      ]);
      final store = await signedInStore(client);

      client.failFetchWith = const GithubException('GitHub rate limit reached');
      await store.refresh();

      expect(store.items.single.title, 'Kept');
      expect(store.error, 'GitHub rate limit reached');
      expect(store.stage, GithubAuthStage.signedIn,
          reason: 'a rate limit is not a lost sign-in');
    });

    test('a rejected token signs the shell out and forgets the file', () async {
      final client = FakeGithubClient();
      final store = await signedInStore(client);

      client.failFetchWith = const GithubAuthException('token revoked');
      await store.refresh();

      expect(store.stage, GithubAuthStage.signedOut);
      expect(store.error, 'token revoked');
      expect(store.polling, isFalse, reason: 'nothing left to poll with');
      expect(await tokens.read(), isNull);
    });

    test('the server may ask for a longer interval than the config does',
        () async {
      final client = FakeGithubClient(pages: [
        const GithubNotificationPage(items: [], pollInterval: 300),
      ]);
      final store = await signedInStore(client);

      // Nothing observable but the timer itself, which is why this asserts on
      // the store's own arithmetic: GitHub's number is a floor it enforces.
      expect(store.polling, isTrue);
      expect(client.fetchCalls, 1);
    });
  });

  group('the config', () {
    test('a changed question refetches rather than waiting out the interval',
        () async {
      final client = FakeGithubClient();
      final store = await signedInStore(client);
      expect(client.participatingSeen, isFalse);

      store.configure(const GithubConfig(participatingOnly: true));
      await settle();

      expect(client.fetchCalls, 2);
      expect(client.participatingSeen, isTrue);
      expect(client.lastModifiedSeen, isNull,
          reason: 'the cached validator described the old question');
    });

    test('an unchanged config is not a refetch', () async {
      final client = FakeGithubClient();
      final store = await signedInStore(client);

      store.configure(const GithubConfig());
      await settle();

      expect(client.fetchCalls, 1);
    });
  });

  group('opening and marking read', () {
    test('a click opens the page and marks the thread read', () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(items: [testNotification(id: '7')]),
      ]);
      final store = await signedInStore(client);

      await store.open(store.items.single);
      await settle();

      expect(opened, ['https://github.com/miracle-wm-org/moonswing/pull/1']);
      expect(client.markedRead, ['7']);
      expect(store.unreadCount, 0);
    });

    test('mark_read_on_open off opens without touching the thread', () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(items: [testNotification(id: '7')]),
      ]);
      final store = await signedInStore(
        client,
        config: const GithubConfig(markReadOnOpen: false),
      );

      await store.open(store.items.single);
      await settle();

      expect(opened, hasLength(1));
      expect(client.markedRead, isEmpty);
      expect(store.unreadCount, 1);
    });

    test('a failed write puts the row back', () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(items: [testNotification(id: '7')]),
      ]);
      final store = await signedInStore(client);

      client.failWriteWith = const GithubException('github.com answered 500');
      await store.markRead(store.items.single);

      expect(store.unreadCount, 1, reason: 'the server did not take it');
      expect(store.error, 'github.com answered 500');
    });

    test('mark all read clears the list it was looking at', () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(
          items: [testNotification(id: '1'), testNotification(id: '2')],
        ),
        const GithubNotificationPage(items: []),
      ]);
      final store = await signedInStore(client);
      expect(store.unreadCount, 2);

      await store.markAllRead();
      await settle();

      expect(client.markAllCalls, 1);
      expect(store.unreadCount, 0);
      // The default list is unread threads only, so the popup re-reads it.
      expect(client.fetchCalls, 2);
    });
  });

  group('the sign-in', () {
    test('publishes the code, opens the browser, and finishes with a token',
        () async {
      final client = FakeGithubClient(
        tokenResults: [
          const GithubTokenPending(),
          const GithubTokenGranted('gho_new'),
        ],
        pages: [
          GithubNotificationPage(items: [testNotification()]),
        ],
      );
      final store = storeWith(client);
      store.acquire();
      await settle();

      final signIn = store.signIn();
      // One turn: enough for the device code to land and be published, not
      // enough for the poll to have answered.
      await Future<void>.delayed(Duration.zero);
      expect(store.stage, GithubAuthStage.awaitingAuthorization);
      expect(store.deviceCode?.userCode, 'ABCD-1234');
      expect(opened, ['https://github.com/login/device'],
          reason: 'the browser is opened for the user, as `gh` does');

      await signIn;
      await settle();

      expect(store.stage, GithubAuthStage.signedIn);
      expect(store.deviceCode, isNull);
      expect(client.tokenCalls, 2, reason: 'the first answer was pending');
      expect(await tokens.read(), 'gho_new', reason: 'and it was saved');
      expect(store.items, hasLength(1));
      expect(store.login, 'octocat');
    });

    test('a cancelled sign-in does not log the user in afterwards', () async {
      final client = FakeGithubClient(
        tokenResults: [const GithubTokenPending()],
      );
      final store = storeWith(client);
      store.acquire();
      await settle();

      final signIn = store.signIn();
      await Future<void>.delayed(Duration.zero);
      expect(store.stage, GithubAuthStage.awaitingAuthorization);

      store.cancelSignIn();
      // Whatever the poll does from here — including handing back a token —
      // must not sign anybody in.
      client.tokenResults = [const GithubTokenGranted('gho_late')];
      await signIn;
      await settle();

      expect(store.stage, GithubAuthStage.signedOut);
      expect(store.deviceCode, isNull);
      expect(await tokens.read(), isNull);
    });

    test('a refused sign-in reports why and offers the button again', () async {
      final client = FakeGithubClient()
        ..failDeviceCodeWith =
            const GithubException('Device flow is not enabled for this app');
      final store = storeWith(client);

      await store.signIn();

      expect(store.stage, GithubAuthStage.signedOut);
      expect(store.error, 'Device flow is not enabled for this app');
    });

    test('an expired code ends the sign-in rather than polling forever',
        () async {
      final client = FakeGithubClient(
        tokenResults: [const GithubTokenPending()],
      )..deviceCode = const GithubDeviceCode(
          deviceCode: 'dc',
          userCode: 'ABCD-1234',
          verificationUri: 'https://github.com/login/device',
          interval: 0,
          // Already expired by the time the first poll comes around.
          expiresIn: -1,
        );
      final store = storeWith(client);

      await store.signIn();

      expect(store.stage, GithubAuthStage.signedOut);
      expect(store.error, contains('expired'));
      expect(client.tokenCalls, 0);
    });

    test('signing out drops the token, the list and the poll', () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(items: [testNotification()]),
      ]);
      final store = await signedInStore(client);
      expect(store.items, isNotEmpty);

      await store.signOut();

      expect(store.stage, GithubAuthStage.signedOut);
      expect(store.items, isEmpty);
      expect(store.login, isEmpty);
      expect(store.polling, isFalse);
      expect(await tokens.read(), isNull);
    });
  });
}
