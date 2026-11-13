import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/code/code_dashboard.dart';
import 'package:moonswing/code/code_model.dart';
import 'package:moonswing/code/code_store.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_store.dart';
import 'package:moonswing/github/github_token_store.dart';
import 'package:moonswing/gitlab/gitlab_account_store.dart';
import 'package:moonswing/gitlab/gitlab_token_store.dart';
import 'package:moonswing/scopes.dart';

import 'code_fakes.dart';
import 'github_fakes.dart';

/// The overview's Code tab: the way to Accounts while nothing is linked, the
/// board once something is, its filters, and the leases it holds only while
/// showing.
void main() {
  late Directory tempDir;
  late List<String> opened;
  final now = DateTime(2026, 11, 13, 12);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('moonswing-code-ui');
    opened = [];
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ({
    CodeStore code,
    GithubStore inbox,
    GithubAccountStore github,
    GitlabAccountStore gitlab,
  })
  stores({
    bool github = true,
    bool gitlab = false,
    CodeSnapshot githubSnapshot = const CodeSnapshot(),
    CodeSnapshot gitlabSnapshot = const CodeSnapshot(),
    List<GithubNotification> notifications = const [],
  }) {
    final hub =
        GithubAccountStore.forTesting(
          client: FakeGithubClient(
            pages: [GithubNotificationPage(items: notifications)],
          ),
          tokens: GithubTokenStore(directory: '${tempDir.path}/github'),
        )..seed(
          stage: github ? GithubAuthStage.signedIn : GithubAuthStage.signedOut,
          login: 'octocat',
        );
    final lab =
        GitlabAccountStore.forTesting(
          client: FakeGitlabClient(snapshot: gitlabSnapshot),
          tokens: GitlabTokenStore(directory: '${tempDir.path}/gitlab'),
        )..seed(
          stage: gitlab ? GitlabAuthStage.signedIn : GitlabAuthStage.signedOut,
        );
    final inbox = GithubStore.forTesting(account: hub);
    final code = CodeStore.forTesting(
      github: hub,
      gitlab: lab,
      githubClient: FakeCodeGithubClient(snapshot: githubSnapshot),
      opener: (url) {
        opened.add(url);
        return true;
      },
      clock: () => now,
    );
    addTearDown(() {
      code.dispose();
      inbox.dispose();
      hub.dispose();
      lab.dispose();
    });
    return (code: code, inbox: inbox, github: hub, gitlab: lab);
  }

  Widget host(Widget child, {Size size = const Size(1200, 760)}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 13),
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => Center(
                    child: SizedBox.fromSize(size: size, child: child),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(child));
    // The accounts' load and the first read are futures; let them land.
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
  }

  testWidgets('with nothing linked it offers the way to Accounts', (
    tester,
  ) async {
    final s = stores(github: false);
    var asked = 0;
    await pump(
      tester,
      CodeDashboard(
        active: true,
        store: s.code,
        inbox: s.inbox,
        onOpenAccounts: () => asked++,
      ),
    );

    expect(
      find.text('Everything waiting on you, in one place'),
      findsOneWidget,
    );
    await tester.tap(find.text('Connect an account'));
    expect(asked, 1);
  });

  testWidgets('the board: summary, groups, stale work, and the inbox', (
    tester,
  ) async {
    final s = stores(
      gitlab: true,
      githubSnapshot: CodeSnapshot(
        reviews: [
          testItem(
            id: 'r1',
            title: 'Review the rim',
            author: 'alice',
            updatedAt: now.subtract(const Duration(days: 4)),
          ),
        ],
        authored: [
          testItem(
            id: 'a1',
            title: 'Float the bar',
            checks: CodeChecks.failing,
            updatedAt: now.subtract(const Duration(hours: 3)),
          ),
        ],
        merged: [
          testItem(
            id: 'm1',
            title: 'Shipped thing',
            mergedAt: now.subtract(const Duration(days: 1)),
          ),
        ],
      ),
      gitlabSnapshot: CodeSnapshot(
        inbox: [testTodo(title: 'Tidy the tanuki', updatedAt: now)],
      ),
      notifications: [testNotification(title: 'Mentioned in a thread')],
    );
    await pump(
      tester,
      CodeDashboard(active: true, store: s.code, inbox: s.inbox),
    );

    // Both accounts are named in the toolbar.
    expect(find.text('octocat'), findsOneWidget);
    expect(find.text('tanuki'), findsOneWidget);

    expect(find.text('Review the rim'), findsOneWidget);
    expect(find.text('Float the bar'), findsOneWidget);
    expect(find.text('Checks failing'), findsOneWidget);
    expect(find.text('1 need you'), findsNothing);
    expect(find.text('1 needs you'), findsOneWidget);
    // Four days on a two-day review threshold is stale, and said so.
    expect(find.text('1 waiting too long'), findsOneWidget);
    expect(find.text('1 stale'), findsOneWidget);
    expect(find.text('No open issues assigned to you.'), findsOneWidget);

    // One inbox for both forges.
    expect(find.text('Mentioned in a thread'), findsOneWidget);
    expect(find.text('Tidy the tanuki'), findsOneWidget);
    expect(find.text('Shipped thing'), findsOneWidget);

    await tester.tap(find.text('Float the bar'));
    expect(opened.single, contains('/pull/a1'));
  });

  testWidgets('the Stale tile narrows every list to what has gone quiet', (
    tester,
  ) async {
    final s = stores(
      githubSnapshot: CodeSnapshot(
        reviews: [
          testItem(
            id: 'old',
            title: 'Old review',
            updatedAt: now.subtract(const Duration(days: 9)),
          ),
          testItem(id: 'new', title: 'New review', updatedAt: now),
        ],
      ),
    );
    await pump(
      tester,
      CodeDashboard(active: true, store: s.code, inbox: s.inbox),
    );
    expect(find.text('New review'), findsOneWidget);

    await tester.tap(find.text('Stale'));
    await tester.pump();
    expect(find.text('Old review'), findsOneWidget);
    expect(find.text('New review'), findsNothing);

    await tester.tap(find.text('Stale'));
    await tester.pump();
    expect(find.text('New review'), findsOneWidget);
  });

  testWidgets('the leases are held only while the tab is showing', (
    tester,
  ) async {
    final s = stores();
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pump(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, show, _) => show
            ? ValueListenableBuilder<bool>(
                valueListenable: active,
                builder: (context, value, _) =>
                    CodeDashboard(active: value, store: s.code, inbox: s.inbox),
              )
            : const SizedBox(),
      ),
    );
    expect(s.code.leaseCount, 0);
    expect(s.inbox.leaseCount, 0);

    active.value = true;
    await tester.pump();
    expect(s.code.leaseCount, 1);
    expect(s.inbox.leaseCount, 1);

    active.value = false;
    await tester.pump();
    expect(s.code.leaseCount, 0);

    active.value = true;
    await tester.pump();
    shown.value = false;
    await tester.pump();
    expect(s.code.leaseCount, 0);
    expect(s.inbox.leaseCount, 0);
  });

  testWidgets('a narrow tab is one column, and nothing animates at rest', (
    tester,
  ) async {
    final s = stores(
      githubSnapshot: CodeSnapshot(authored: [testItem(updatedAt: now)]),
    );
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        CodeDashboard(active: true, store: s.code, inbox: s.inbox),
        size: const Size(700, 600),
      ),
    );
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
