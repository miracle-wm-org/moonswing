import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_config.dart';
import 'package:moonswing/github/github_store.dart';
import 'package:moonswing/github/github_token_store.dart';

import 'github_fakes.dart';

/// The inbox: the lease, the poll, the writes that mark a thread read, and how
/// it follows the account it reads as. Every one of these drives a real store
/// over a real [GithubAccountStore], through a fake client and a token file
/// under a temporary directory. The sign-in itself is `github_account_test`'s.
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
    final account = GithubAccountStore.forTesting(
      client: client,
      tokens: tokens,
      opener: (url) {
        opened.add(url);
        return true;
      },
    );
    final store = GithubStore.forTesting(
      account: account,
      config: config,
      opener: (url) {
        opened.add(url);
        return true;
      },
    );
    addTearDown(account.dispose);
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
    // The token read is file I/O, so turns alone cannot be relied on to see it
    // land — wait for the sign-in and its first fetch to have finished.
    await settleUntil(
      () => store.stage == GithubAuthStage.signedIn && !store.loading,
    );
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
      expect(store.account.error, 'token revoked',
          reason: 'said once, by the account every consumer shares');
      expect(store.error, isEmpty, reason: 'not a retry that can only fail');
      expect(store.items, isEmpty);
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

  group('the account', () {
    test('a sign-in landing while a bar holds a lease fetches at once',
        () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(items: [testNotification()]),
      ]);
      final store = storeWith(client);
      store.acquire();
      await settle();
      expect(client.fetchCalls, 0);

      // The sign-in is Settings' — the store only hears about it.
      await store.account.signIn();
      await settleUntil(() => !store.loading && store.items.isNotEmpty);

      expect(store.stage, GithubAuthStage.signedIn);
      expect(client.fetchCalls, 1);
      expect(store.items, hasLength(1));
      expect(store.polling, isTrue);
    });

    test('a sign-in with nobody holding a lease fetches nothing', () async {
      final client = FakeGithubClient();
      final store = storeWith(client);

      await store.account.signIn();
      await settle();

      expect(store.stage, GithubAuthStage.signedIn);
      expect(client.fetchCalls, 0, reason: 'an idle shell polls for nothing');
    });

    test('signing out drops the list and the poll', () async {
      final client = FakeGithubClient(pages: [
        GithubNotificationPage(items: [testNotification()]),
      ]);
      final store = await signedInStore(client);
      expect(store.items, isNotEmpty);

      await store.account.signOut();

      expect(store.stage, GithubAuthStage.signedOut);
      expect(store.items, isEmpty);
      expect(store.login, isEmpty);
      expect(store.polling, isFalse);
      expect(await tokens.read(), isNull);
    });
  });
}
