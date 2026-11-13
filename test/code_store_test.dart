import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/code/code_config.dart';
import 'package:moonswing/code/code_model.dart';
import 'package:moonswing/code/code_store.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_store.dart';
import 'package:moonswing/github/github_token_store.dart';
import 'package:moonswing/gitlab/gitlab_account_store.dart';
import 'package:moonswing/gitlab/gitlab_api.dart';
import 'package:moonswing/gitlab/gitlab_token_store.dart';

import 'code_fakes.dart';
import 'github_fakes.dart';

/// The GitLab account and the Code tab's store: a connect that checks the token
/// first, a saved account that survives a restart, and one leased read of both
/// forges that keeps its last answer through a failure.
void main() {
  late Directory tempDir;
  late List<String> opened;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('moonswing-code');
    opened = [];
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  GitlabAccountStore gitlab(FakeGitlabClient client) {
    final store = GitlabAccountStore.forTesting(
      client: client,
      tokens: GitlabTokenStore(directory: '${tempDir.path}/gitlab'),
      opener: (url) {
        opened.add(url);
        return true;
      },
    );
    addTearDown(store.dispose);
    return store;
  }

  GithubAccountStore github() {
    final store = GithubAccountStore.forTesting(
      client: FakeGithubClient(),
      tokens: GithubTokenStore(directory: '${tempDir.path}/github'),
    );
    addTearDown(store.dispose);
    return store;
  }

  group('GitlabAccountStore', () {
    test('connect asks the instance who the token is, then keeps it', () async {
      final client = FakeGitlabClient();
      final store = gitlab(client);
      await store.load();
      expect(store.stage, GitlabAuthStage.signedOut);

      final kept = await store.connect(
        host: 'https://git.example.org/group/project',
        token: '  glpat-secret  ',
      );
      expect(kept, isTrue);
      expect(client.lastInstance.toString(), 'https://git.example.org');
      expect(client.lastToken, 'glpat-secret');
      expect(store.signedIn, isTrue);
      expect(store.label, 'tanuki@git.example.org');

      // A restart reads the same account back, and the file is the owner's.
      final again = gitlab(FakeGitlabClient());
      await again.load();
      expect(again.signedIn, isTrue);
      expect(again.username, 'tanuki');
      expect(again.token, 'glpat-secret');
      final mode = File(
        '${tempDir.path}/gitlab/gitlab-account',
      ).statSync().mode;
      expect(mode & 0x3F, 0, reason: 'no access for group or others');
    });

    test('a refused token is said, and nothing is kept', () async {
      final client = FakeGitlabClient()
        ..failUserWith = const GitlabAuthException();
      final store = gitlab(client);
      expect(await store.connect(host: 'gitlab.com', token: 'bad'), isFalse);
      expect(store.signedIn, isFalse);
      expect(store.error, 'GitLab did not accept that token');
      expect(
        File('${tempDir.path}/gitlab/gitlab-account').existsSync(),
        isFalse,
      );

      expect(await store.connect(host: 'nope', token: 'x'), isFalse);
      expect(store.error, contains('not the address'));
    });

    test(
      'a rejected token signs the account out, once, with the reason',
      () async {
        final store = gitlab(FakeGitlabClient());
        await store.connect(host: 'gitlab.com', token: 'tok');
        await expectLater(
          store.withToken<void>(
            (_, _) async => throw const GitlabAuthException('expired'),
          ),
          throwsA(isA<GitlabAuthException>()),
        );
        expect(store.signedIn, isFalse);
        expect(store.error, 'expired');
      },
    );

    test('the token page opens on the instance being typed', () {
      final store = gitlab(FakeGitlabClient());
      store.openTokenPage('git.example.org');
      expect(
        opened.single,
        'https://git.example.org/-/user_settings/personal_access_tokens'
        '?name=Moonswing&scopes=read_api',
      );
    });
  });

  group('CodeStore', () {
    late DateTime now;

    CodeStore code({
      required GithubAccountStore github,
      required GitlabAccountStore gitlab,
      required FakeCodeGithubClient client,
    }) {
      final store = CodeStore.forTesting(
        github: github,
        gitlab: gitlab,
        githubClient: client,
        opener: (url) {
          opened.add(url);
          return true;
        },
        clock: () => now,
      );
      addTearDown(store.dispose);
      return store;
    }

    setUp(() => now = DateTime(2026, 11, 13, 12));

    test('reads nothing until leased, then both forges at once', () async {
      final hub = github()..seed(login: 'octocat');
      final lab = gitlab(
        FakeGitlabClient(snapshot: CodeSnapshot(inbox: [testTodo()])),
      )..seed();
      final client = FakeCodeGithubClient(
        snapshot: CodeSnapshot(reviews: [testItem()]),
      );
      final store = code(github: hub, gitlab: lab, client: client);
      await pumpEventQueue();
      expect(client.calls, 0);

      store.acquire();
      await pumpEventQueue();
      expect(client.calls, 1);
      expect(client.lastLogin, 'octocat');
      expect(client.lastSince, now.subtract(const Duration(days: 7)));
      expect(store.snapshotOf(CodeProvider.github)?.reviews, hasLength(1));
      expect(store.snapshotOf(CodeProvider.gitlab)?.inbox, hasLength(1));
      expect(store.polling, isTrue);

      store.release();
      expect(store.polling, isFalse);
    });

    test('a failed read keeps the last answer, with the reason', () async {
      final hub = github()..seed();
      final lab = gitlab(FakeGitlabClient())
        ..seed(stage: GitlabAuthStage.signedOut);
      final client = FakeCodeGithubClient(
        snapshot: CodeSnapshot(authored: [testItem()]),
      );
      final store = code(github: hub, gitlab: lab, client: client);
      store.acquire();
      addTearDown(store.release);
      await pumpEventQueue();

      client.failWith = const GithubException('GitHub rate limit reached');
      await store.refresh();
      expect(store.errorOf(CodeProvider.github), 'GitHub rate limit reached');
      expect(store.snapshotOf(CodeProvider.github)?.authored, hasLength(1));

      client.failWith = null;
      await store.refresh();
      expect(store.errorOf(CodeProvider.github), isEmpty);
    });

    test(
      'a read that finds nothing new notifies only for its spinner',
      () async {
        final hub = github()..seed();
        final lab = gitlab(FakeGitlabClient())
          ..seed(stage: GitlabAuthStage.signedOut);
        final client = FakeCodeGithubClient(
          snapshot: CodeSnapshot(reviews: [testItem()]),
        );
        final store = code(github: hub, gitlab: lab, client: client);
        store.acquire();
        addTearDown(store.release);
        await pumpEventQueue();

        var notified = 0;
        store.addListener(() => notified++);
        await store.refresh();
        // Busy on, busy off — and nothing for the lists, which did not move.
        expect(notified, 2);

        notified = 0;
        store.configure(const CodeConfig());
        expect(notified, 0, reason: 'the same config is no change');
        store.configure(const CodeConfig(staleDays: 3));
        expect(notified, 1, reason: 'a new threshold changes what is drawn');
      },
    );

    test('signing out drops that forge, signing in reads it', () async {
      final hub = github()..seed();
      final lab = gitlab(
        FakeGitlabClient(snapshot: CodeSnapshot(assigned: [testItem()])),
      )..seed(stage: GitlabAuthStage.signedOut);
      final store = code(
        github: hub,
        gitlab: lab,
        client: FakeCodeGithubClient(),
      );
      store.acquire();
      addTearDown(store.release);
      await pumpEventQueue();
      expect(store.linkedProviders, [CodeProvider.github]);

      lab.seed(username: 'tanuki');
      await pumpEventQueue();
      expect(store.linkedProviders, CodeProvider.values);
      expect(store.snapshotOf(CodeProvider.gitlab)?.assigned, hasLength(1));

      await lab.signOut();
      expect(store.snapshotOf(CodeProvider.gitlab), isNull);
      expect(store.snapshots.keys, [CodeProvider.github]);
    });

    test(
      'a to-do marked done goes at once, and comes back if refused',
      () async {
        final hub = github()..seed(stage: GithubAuthStage.signedOut);
        final client = FakeGitlabClient(
          snapshot: CodeSnapshot(
            inbox: [
              testTodo(id: 'a'),
              testTodo(id: 'b'),
            ],
          ),
        );
        final lab = gitlab(client)..seed();
        final store = code(
          github: hub,
          gitlab: lab,
          client: FakeCodeGithubClient(),
        );
        store.acquire();
        addTearDown(store.release);
        await pumpEventQueue();

        final first = store.snapshotOf(CodeProvider.gitlab)!.inbox.first;
        await store.markTodoDone(first);
        expect(client.done, ['a']);
        expect(store.snapshotOf(CodeProvider.gitlab)!.inbox.map((n) => n.id), [
          'b',
        ]);

        client.failWriteWith = const GitlabException(
          'Marking to-dos done needs a token with the api scope',
        );
        await store.markAllTodosDone();
        expect(store.snapshotOf(CodeProvider.gitlab)!.inbox, hasLength(1));
        expect(store.actionError, contains('api scope'));
      },
    );
  });
}
