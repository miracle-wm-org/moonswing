import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_store.dart';
import 'package:moonswing/github/github_token_store.dart';
import 'package:moonswing/modules/github.dart';
import 'package:moonswing/scopes.dart';

import 'github_fakes.dart';

/// The bar strip and the card behind it, pumped the way the shell builds them.
void main() {
  late Directory tempDir;
  late GithubTokenStore tokens;
  late List<String> opened;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('moonswing-github-widget');
    tokens = GithubTokenStore(directory: tempDir.path);
    opened = [];
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  GithubStore seeded({
    GithubAuthStage stage = GithubAuthStage.signedIn,
    List<GithubNotification> items = const [],
    String login = '',
    String error = '',
    bool loading = false,
    GithubDeviceCode? deviceCode,
  }) {
    final store = GithubStore.forTesting(
      // The same list the store is seeded with, so the refresh a bar strip's
      // lease kicks off reproduces what is on screen rather than emptying it.
      client: FakeGithubClient(pages: [GithubNotificationPage(items: items)]),
      tokens: tokens,
      opener: (url) {
        opened.add(url);
        return true;
      },
    )..seed(
        stage: stage,
        items: items,
        login: login,
        error: error,
        loading: loading,
        deviceCode: deviceCode,
      );
    addTearDown(store.dispose);
    return store;
  }

  /// The card as the shell pumps it: under a [ThemeScope] and **nothing else**.
  /// Popup content lays out under its own FlutterView, so nothing above it
  /// supplies a [Directionality] — a card that assumed one renders here and
  /// throws in the shell.
  Future<void> pumpPopup(
    WidgetTester tester,
    GithubStore store, {
    Future<ClipboardResult> Function(String text)? copy,
  }) async {
    await tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            // What `_GithubNotificationsState._togglePopup` passes: both axes
            // pinned, which is what the popup's window is sized to.
            constraints: const BoxConstraints(
              minWidth: kGithubPopupWidth,
              maxWidth: kGithubPopupWidth,
              minHeight: kGithubPopupHeight,
              maxHeight: kGithubPopupHeight,
            ),
            child: GithubPopup(
              store: store,
              copy: copy ?? (_) async => ClipboardResult.copied,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpBar(WidgetTester tester, GithubStore store,
      {bool showCount = true}) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Center(
            child: GithubNotifications(store: store, showCount: showCount),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the bar strip', () {
    testWidgets('shows the unread count, and nothing when there is none',
        (tester) async {
      final store = seeded(items: [
        testNotification(id: '1'),
        testNotification(id: '2'),
        testNotification(id: '3', unread: false),
      ]);

      await pumpBar(tester, store);

      expect(find.text('2'), findsOneWidget);
      expect(store.leaseCount, 1, reason: 'the strip holds the lease');
    });

    testWidgets('show_count off leaves the mark alone', (tester) async {
      final store = seeded(items: [testNotification()]);

      await pumpBar(tester, store, showCount: false);

      expect(find.text('1'), findsNothing);
    });

    testWidgets('releases its lease when it leaves the bar', (tester) async {
      final store = seeded();
      await pumpBar(tester, store);
      expect(store.leaseCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(store.leaseCount, 0, reason: 'an idle shell polls for nothing');
    });
  });

  group('the card', () {
    testWidgets('renders with no Directionality above it', (tester) async {
      final store = seeded(
        login: 'octocat',
        items: [testNotification(title: 'Add a GitHub module')],
      );

      await pumpPopup(tester, store);

      expect(tester.takeException(), isNull);
      expect(find.text('octocat'), findsOneWidget);
      expect(find.text('Add a GitHub module'), findsOneWidget);
      expect(
        find.text('miracle-wm-org/moonswing · Review requested'),
        findsOneWidget,
      );
    });

    testWidgets('offers a sign-in when there is no account', (tester) async {
      final store = seeded(stage: GithubAuthStage.signedOut);

      await pumpPopup(tester, store);

      expect(find.text('Sign in with GitHub'), findsOneWidget);
      expect(find.textContaining('password never reaches'), findsOneWidget);
    });

    testWidgets('shows the code to type, and copies it on a click',
        (tester) async {
      final copied = <String>[];
      final store = seeded(
        stage: GithubAuthStage.awaitingAuthorization,
        deviceCode: const GithubDeviceCode(
          deviceCode: 'dc',
          userCode: 'ABCD-1234',
          verificationUri: 'https://github.com/login/device',
          interval: 5,
          expiresIn: 900,
        ),
      );

      await pumpPopup(tester, store, copy: (text) async {
        copied.add(text);
        return ClipboardResult.copied;
      });

      expect(find.text('ABCD-1234'), findsOneWidget);
      expect(
        find.text('Enter this code at github.com/login/device'),
        findsOneWidget,
      );

      await tester.tap(find.text('ABCD-1234'));
      await tester.pumpAndSettle();
      expect(copied, ['ABCD-1234']);
      expect(find.text('Copied'), findsOneWidget);

      // And the second chance at the browser, for a user whose default handler
      // did not come up the first time.
      await tester.tap(find.text('Open GitHub'));
      await tester.pumpAndSettle();
      expect(opened, ['https://github.com/login/device']);
    });

    testWidgets('a clipboard that is not installed says which package to get',
        (tester) async {
      final store = seeded(
        stage: GithubAuthStage.awaitingAuthorization,
        deviceCode: const GithubDeviceCode(
          deviceCode: 'dc',
          userCode: 'ABCD-1234',
          verificationUri: 'https://github.com/login/device',
          interval: 5,
          expiresIn: 900,
        ),
      );

      await pumpPopup(
        tester,
        store,
        copy: (_) async => ClipboardResult.unavailable,
      );
      await tester.tap(find.text('ABCD-1234'));
      await tester.pumpAndSettle();

      expect(
        find.text('Install wl-clipboard to copy it, or type it in'),
        findsOneWidget,
      );
    });

    testWidgets('an empty inbox says so rather than showing nothing',
        (tester) async {
      final store = seeded();

      await pumpPopup(tester, store);

      expect(find.text('No unread notifications'), findsOneWidget);
    });

    testWidgets('a failure is visible, with the list it failed to refresh',
        (tester) async {
      final store = seeded(
        items: [testNotification(title: 'Still here')],
        error: 'GitHub rate limit reached',
      );

      await pumpPopup(tester, store);

      expect(find.text('GitHub rate limit reached'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Still here'), findsOneWidget);
    });

    testWidgets('is the fixed height whatever is in it', (tester) async {
      // The card is the size the window was mapped at, in every state it has:
      // one thread, fifty, none, and a sign-in form. Each of these used to size
      // the surface, and only the first one that did got the placement it asked
      // for.
      for (final store in [
        seeded(items: [testNotification(id: '1')]),
        seeded(items: [
          for (var i = 0; i < 50; i++) testNotification(id: '$i'),
        ]),
        seeded(),
        seeded(stage: GithubAuthStage.signedOut),
      ]) {
        await pumpPopup(tester, store);

        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(GithubPopup)).height,
          kGithubPopupHeight,
        );
      }
    });

    testWidgets('scrolls a list longer than the card', (tester) async {
      final store = seeded(items: [
        for (var i = 0; i < 50; i++)
          testNotification(id: '$i', title: 'Thread $i'),
      ]);

      await pumpPopup(tester, store);

      // Off the bottom of a fixed-height card, so it is the *list* that has to
      // reach it rather than the card growing until it fits.
      expect(find.text('Thread 49'), findsNothing);

      await tester.drag(
        find.byType(ListView),
        const Offset(0, -4000),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Thread 49'), findsOneWidget);
      expect(find.text('Thread 0'), findsNothing);
    });

    testWidgets('clicking a row opens it and marks it read', (tester) async {
      final store = seeded(items: [testNotification(id: '9')]);

      await pumpPopup(tester, store);
      await tester.tap(find.text('Fix the thing'));
      await tester.pumpAndSettle();

      expect(
        opened,
        ['https://github.com/miracle-wm-org/moonswing/pull/1'],
      );
      expect(store.unreadCount, 0);
    });
  });
}
