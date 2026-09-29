import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/accounts/accounts_scope.dart';
import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_store.dart';
import 'package:moonswing/github/github_token_store.dart';
import 'package:moonswing/google/google_account_file.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/overlay/settings/accounts/caldav_account.dart';
import 'package:moonswing/overlay/settings/accounts/github_account.dart';
import 'package:moonswing/overlay/settings/accounts.dart';
import 'package:moonswing/scopes.dart';

import 'caldav_fakes.dart';
import 'github_fakes.dart';
import 'google_fakes.dart';

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: DefaultTextStyle(
    style: const TextStyle(fontSize: 14),
    child: ThemeScope(
      theme: const ThemeConfig(),
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => SizedBox(width: 720, height: 900, child: child),
          ),
        ],
      ),
    ),
  ),
);

/// Settings › Accounts' GitHub card, the scope every consumer reads the
/// accounts through, and the brand marks.
void main() {
  late Directory tempDir;
  late GithubTokenStore tokens;
  late List<String> opened;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('moonswing-accounts-ui');
    tokens = GithubTokenStore(directory: tempDir.path);
    opened = [];
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  GithubAccountStore github(FakeGithubClient client) {
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

  Future<void> pumpCard(
    WidgetTester tester,
    GithubAccountStore account, {
    Future<ClipboardResult> Function(String text)? copy,
  }) async {
    await tester.pumpWidget(
      _host(
        GithubAccountCard(
          account: account,
          copy: copy ?? (_) async => ClipboardResult.copied,
        ),
      ),
    );
    // A sign-in under way has a spinner on it, which never settles.
    if (account.stage == GithubAuthStage.awaitingAuthorization) {
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  const code = GithubDeviceCode(
    deviceCode: 'dc',
    userCode: 'ABCD-1234',
    verificationUri: 'https://github.com/login/device',
    interval: 5,
    expiresIn: 900,
  );

  group('the GitHub card', () {
    testWidgets('signed out: says what happens, then offers the sign-in', (
      tester,
    ) async {
      final account = github(FakeGithubClient())
        ..seed(stage: GithubAuthStage.signedOut);

      await pumpCard(tester, account);

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Sign in with GitHub'), findsOneWidget);
      expect(find.textContaining('password never reaches'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
      expect(
        find.text('GitHub notifications'),
        findsOneWidget,
        reason: 'the footer names what reads the account',
      );
    });

    testWidgets('the button runs the device flow and shows the code', (
      tester,
    ) async {
      final client = FakeGithubClient(
        tokenResults: [const GithubTokenPending()],
      );
      final account = github(client);
      await tester.runAsync(account.load);

      await pumpCard(tester, account);
      await tester.tap(find.text('Sign in with GitHub'));
      // The device-code request, then one frame for the card to follow it.
      await tester.pump();
      await tester.pump();

      expect(account.stage, GithubAuthStage.awaitingAuthorization);
      expect(find.text('ABCD-1234'), findsOneWidget);
      expect(find.text('Signing in…'), findsOneWidget);
      expect(opened, ['https://github.com/login/device']);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(account.stage, GithubAuthStage.signedOut);
      // Let the zero-interval poll loop notice and wind down.
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('shows the code to type, and copies it on a click', (
      tester,
    ) async {
      final copied = <String>[];
      final account = github(FakeGithubClient())
        ..seed(stage: GithubAuthStage.awaitingAuthorization, deviceCode: code);

      await pumpCard(
        tester,
        account,
        copy: (text) async {
          copied.add(text);
          return ClipboardResult.copied;
        },
      );

      expect(
        find.text('Enter this code at github.com/login/device'),
        findsOneWidget,
      );
      await tester.tap(find.text('ABCD-1234'));
      await tester.pump();
      expect(copied, ['ABCD-1234']);
      expect(find.text('Copied'), findsOneWidget);

      // And the second chance at the browser, for a user whose default handler
      // did not come up the first time.
      await tester.tap(find.text('Open GitHub'));
      await tester.pump();
      expect(opened, ['https://github.com/login/device']);
    });

    testWidgets('a clipboard that is not installed says which package to get', (
      tester,
    ) async {
      final account = github(FakeGithubClient())
        ..seed(stage: GithubAuthStage.awaitingAuthorization, deviceCode: code);

      await pumpCard(
        tester,
        account,
        copy: (_) async => ClipboardResult.unavailable,
      );
      await tester.tap(find.text('ABCD-1234'));
      await tester.pump();

      expect(
        find.text('Install wl-clipboard to copy it, or type it in'),
        findsOneWidget,
      );
    });

    testWidgets('signed in: the login, and a sign-out that works', (
      tester,
    ) async {
      final account = github(FakeGithubClient())..seed(login: 'octocat');

      await pumpCard(tester, account);

      expect(find.text('octocat'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Access: notifications'), findsOneWidget);

      await tester.tap(find.text('Sign out'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(account.stage, GithubAuthStage.signedOut);
      expect(find.text('Sign in with GitHub'), findsOneWidget);
    });

    testWidgets('a failure is on the card, and can be dismissed', (
      tester,
    ) async {
      final account = github(FakeGithubClient())
        ..seed(stage: GithubAuthStage.signedOut, error: 'token revoked');

      await pumpCard(tester, account);
      expect(find.text('token revoked'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('token revoked'), findsNothing);
    });
  });

  group('the page', () {
    testWidgets('reads its accounts off the AccountsScope', (tester) async {
      final googleAccount = await tester.runAsync(() async {
        final store = GoogleAccountStore.forTesting(
          client: FakeGoogleClient(),
          file: GoogleAccountFile(directory: '${tempDir.path}/google'),
        );
        await store.load();
        return store;
      });
      addTearDown(googleAccount!.dispose);
      final calendar = GoogleCalendarStore.forTesting(account: googleAccount);
      final account = github(FakeGithubClient())..seed(login: 'octocat');
      final caldav = CalDavAccountStore.forTesting(
        directory: '${tempDir.path}/caldav',
      );

      await tester.pumpWidget(
        _host(
          AccountsScope(
            google: googleAccount,
            googleCalendar: calendar,
            github: account,
            caldav: caldav,
            child: const AccountsSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Every card, the scope's GitHub account on one of them.
      expect(find.text('Google'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('octocat'), findsOneWidget);
      expect(find.text('CalDAV'), findsOneWidget);
      expect(find.byType(BrandMark), findsNWidgets(3));
    });
  });

  group('the CalDAV card', () {
    Future<void> pump(WidgetTester tester, CalDavAccountStore store) async {
      await tester.pumpWidget(
        _host(SingleChildScrollView(child: CalDavAccountCard(account: store))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('signs in by finding the task lists', (tester) async {
      final server = FakeCalDavServer();
      final store = CalDavAccountStore.forTesting(
        directory: '${tempDir.path}/caldav',
        client: server.client,
      );
      await pump(tester, store);
      expect(find.text('Connect'), findsOneWidget);

      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'ftp://dav.example.com');
      await tester.pump();
      expect(find.textContaining('has to start with https://'), findsOneWidget);
      await tester.enterText(fields.at(0), 'http://dav.example.com');
      await tester.pump();
      expect(find.textContaining('unencrypted'), findsOneWidget);

      await tester.enterText(fields.at(0), FakeCalDavServer.host);
      await tester.enterText(fields.at(1), 'me');
      await tester.enterText(fields.at(2), 'secret');
      await tester.pump();
      // The request and the file write are real I/O.
      await tester.runAsync(
        () => store.signIn(
          url: FakeCalDavServer.host,
          username: 'me',
          password: 'secret',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('me on dav.example.com'), findsOneWidget);
      expect(find.text('Task list: Home tasks'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('a refused sign-in is said on the card', (tester) async {
      final server = FakeCalDavServer();
      final store = CalDavAccountStore.forTesting(
        directory: '${tempDir.path}/caldav',
        client: server.client,
      );
      await tester.runAsync(
        () => store.signIn(
          url: FakeCalDavServer.host,
          username: 'me',
          password: 'wrong',
        ),
      );
      await pump(tester, store);
      expect(find.textContaining('refused the user name'), findsOneWidget);
      expect(store.account, isNull);
    });
  });

  group('AccountsScope', () {
    testWidgets('falls back to the shell-wide stores with nothing above it', (
      tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      );

      // A popup's content has no scope above it, and must still see the one
      // account its opener does.
      expect(
        AccountsScope.githubOf(captured),
        same(GithubAccountStore.instance),
      );
      expect(
        AccountsScope.githubNotificationsOf(captured),
        same(GithubStore.instance),
      );
      expect(
        AccountsScope.googleOf(captured),
        same(GoogleAccountStore.instance),
      );
      expect(
        AccountsScope.googleCalendarOf(captured),
        same(GoogleCalendarStore.instance),
      );
    });

    testWidgets('hands out what it was given', (tester) async {
      final account = github(FakeGithubClient());
      late BuildContext captured;
      await tester.pumpWidget(
        AccountsScope(
          github: account,
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(AccountsScope.githubOf(captured), same(account));
      // What it was not given still falls through to the shell's.
      expect(
        AccountsScope.googleOf(captured),
        same(GoogleAccountStore.instance),
      );
    });
  });

  group('BrandMark', () {
    testWidgets('draws each service on its own tile', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(AccountBrand.google, size: 40),
              BrandMark(AccountBrand.github, size: 40),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(GoogleG), findsOneWidget);
      for (final mark in tester.widgetList(find.byType(BrandMark))) {
        expect(tester.getSize(find.byWidget(mark)), const Size(40, 40));
      }
    });
  });
}
