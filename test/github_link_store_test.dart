import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/github/github_account_store.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_link_store.dart';
import 'package:moonswing/github/github_links.dart';
import 'package:moonswing/github/github_token_store.dart';

import 'github_fakes.dart';

const GithubIssue _issue = GithubIssue(
  number: 12,
  title: 'Fix the thing',
  state: GithubIssueState.open,
  isPullRequest: true,
);

GithubRef _ref(int number) =>
    parseGithubRef('https://github.com/o/r/pull/$number')!;

void main() {
  late Directory tempDir;
  late FakeGithubClient client;
  late GithubAccountStore account;
  late DateTime now;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('github-links-');
    client = FakeGithubClient()..issues['o/r/12'] = _issue;
    account = GithubAccountStore.forTesting(
      client: client,
      tokens: GithubTokenStore(directory: tempDir.path),
    );
    now = DateTime(2026, 10, 5, 12);
  });

  tearDown(() {
    account.dispose();
    tempDir.deleteSync(recursive: true);
  });

  GithubLinkStore store() {
    final links = GithubLinkStore.forTesting(
      account: account,
      clock: () => now,
    );
    addTearDown(links.dispose);
    return links;
  }

  test('signed out, it is off and reads nothing', () async {
    account.seed(stage: GithubAuthStage.signedOut);
    final links = store();
    expect(links.enabled, isFalse);
    final state = links.watch(_ref(12));
    await settle();
    expect(state.value, GithubLinkState.pending);
    expect(client.issueCalls, isEmpty);
  });

  test(
    'reads a link once, never inside watch, and shares the answer',
    () async {
      account.seed();
      final links = store();
      final first = links.watch(_ref(12));
      final again = links.watch(
        parseGithubRef('https://github.com/O/R/issues/12')!,
      );
      expect(identical(first, again), isTrue);
      // Queued, not made: nothing has gone out before watch returned.
      expect(client.issueCalls, isEmpty);
      await settle();
      expect(client.issueCalls, ['o/r/12']);
      expect(first.value, const GithubLinkState(issue: _issue));
    },
  );

  test(
    'an answer stands for freshFor, then the next look reads it again',
    () async {
      account.seed();
      final links = store();
      links.watch(_ref(12));
      await settle();
      now = now.add(const Duration(minutes: 9));
      links.watch(_ref(12));
      await settle();
      expect(client.issueCalls, hasLength(1));
      now = now.add(const Duration(minutes: 2));
      links.watch(_ref(12));
      await settle();
      expect(client.issueCalls, hasLength(2));
    },
  );

  test(
    'a failure is shown, retried sooner, and keeps the last good title',
    () async {
      account.seed();
      final links = store();
      final state = links.watch(_ref(12));
      await settle();

      client.failIssueWith = const GithubException(
        'Could not reach api.github.com',
      );
      now = now.add(const Duration(minutes: 11));
      links.watch(_ref(12));
      await settle();
      expect(state.value.issue, _issue);
      expect(state.value.error, 'Could not reach api.github.com');

      // A failure waits retryAfter, not freshFor.
      client.failIssueWith = null;
      now = now.add(const Duration(seconds: 61));
      links.watch(_ref(12));
      await settle();
      expect(state.value, const GithubLinkState(issue: _issue));
    },
  );

  test('a link GitHub will not show is a failure with the reason', () async {
    account.seed();
    final links = store();
    final state = links.watch(_ref(99));
    await settle();
    expect(state.value.issue, isNull);
    expect(state.value.error, 'Not found');
    expect(state.value.loading, isFalse);
  });

  test('reads at most four at once', () async {
    account.seed();
    client.issueGate = Completer<void>();
    final links = store();
    for (var n = 1; n <= 6; n++) {
      links.watch(_ref(n));
    }
    await settle();
    expect(client.issueCalls, hasLength(4));
    client.issueGate!.complete();
    await settle();
    expect(client.issueCalls, hasLength(6));
  });

  test('a new account drops every answer and says so', () async {
    account.seed(token: 'one');
    final links = store();
    final before = links.watch(_ref(12));
    await settle();
    var notified = 0;
    links.addListener(() => notified++);

    account.seed(token: 'two');
    expect(notified, 1);
    final after = links.watch(_ref(12));
    expect(identical(before, after), isFalse);
    expect(after.value, GithubLinkState.pending);
    await settle();
    expect(after.value.issue, _issue);
    expect(client.issueCalls, hasLength(2));

    account.seed(stage: GithubAuthStage.signedOut);
    expect(notified, 2);
    expect(links.enabled, isFalse);
  });

  test('an answer read under the old account is never shown', () async {
    account.seed(token: 'one');
    client.issueGate = Completer<void>();
    final links = store();
    final before = links.watch(_ref(12));
    await settle();
    account.seed(token: 'two');
    client.issueGate!.complete();
    await settle();
    expect(before.value, GithubLinkState.pending);
  });
}
