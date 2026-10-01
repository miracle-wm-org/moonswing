import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/caldav/caldav_calendar_store.dart';
import 'package:moonswing/caldav/caldav_config.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/github/github_account_store.dart';
import 'package:moonswing/github/github_token_store.dart';
import 'package:moonswing/google/google_account_file.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/clock/minute_clock_store.dart';
import 'package:moonswing/overlay/calendar/calendar_events.dart';
import 'package:moonswing/overlay/calendar/calendar_tab.dart';
import 'package:moonswing/timers/timer_store.dart';
import 'package:moonswing/overlay/settings/accounts.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_highlight.dart';
import 'package:moonswing/overlay/settings/settings_search.dart';
import 'package:moonswing/overlay/settings/shell/calendar.dart';
import 'package:moonswing/scopes.dart';

import 'caldav_fakes.dart';
import 'github_fakes.dart';
import 'google_fakes.dart';

Widget _host(Widget child, {Key? key}) => Directionality(
  textDirection: TextDirection.ltr,
  child: DefaultTextStyle(
    style: const TextStyle(fontSize: 14),
    child: ThemeScope(
      theme: const ThemeConfig(),
      child: Overlay(
        key: key,
        initialEntries: [
          OverlayEntry(
            builder: (_) => SizedBox(width: 720, height: 640, child: child),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  late Directory tempDir;
  late FakeGoogleClient client;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('moonswing-google-ui');
    client = FakeGoogleClient()
      ..calendars = const [
        GoogleCalendar(id: 'me@example.com', summary: 'Me', primary: true),
        GoogleCalendar(id: 'team@group.calendar.google.com', summary: 'Team'),
      ];
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Real file I/O, so through [WidgetTester.runAsync].
  Future<GoogleAccountStore> accountWith(
    WidgetTester tester,
    List<GoogleAccountData> accounts,
  ) async {
    final account = await tester.runAsync(() async {
      final file = GoogleAccountFile(directory: '${tempDir.path}/state');
      if (accounts.isNotEmpty) await file.write(accounts);
      final store = GoogleAccountStore.forTesting(client: client, file: file);
      await store.load();
      return store;
    });
    return account!;
  }

  /// The GitHub card is on the same page; signed out and offline, so these
  /// tests see only Google's rows and never read a real token file.
  GithubAccountStore githubSignedOut() {
    final github = GithubAccountStore.forTesting(
      client: FakeGithubClient(),
      tokens: GithubTokenStore(directory: '${tempDir.path}/github'),
    )..seed(stage: GithubAuthStage.signedOut);
    addTearDown(github.dispose);
    return github;
  }

  /// CalDAV accounts signed in to the in-memory server, one per address;
  /// none by default, and never the real account file.
  Future<CalDavAccountStore> caldavWith(
    WidgetTester tester, {
    FakeCalDavServer? server,
    List<String> urls = const [],
  }) async {
    final store = await tester.runAsync(() async {
      final accounts = CalDavAccountStore.forTesting(
        directory: '${tempDir.path}/caldav',
        client: (server ?? FakeCalDavServer()).client,
      );
      await accounts.load();
      for (final url in urls) {
        await accounts.signIn(url: url, username: 'me', password: 'secret');
      }
      return accounts;
    });
    return store!;
  }

  Future<ConfigStore> config(WidgetTester tester, String contents) async {
    final store = await tester.runAsync(() async {
      final path = '${tempDir.path}/config.toml';
      await File(path).writeAsString(contents);
      return ConfigStore.loadFrom(path);
    });
    addTearDown(store!.dispose);
    return store;
  }

  group('Settings › Accounts', () {
    testWidgets('signed out: one button, and nothing to paste', (tester) async {
      final account = await accountWith(tester, const []);
      await tester.pumpWidget(
        _host(
          AccountsSettingsPage(github: githubSignedOut(), account: account),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Client ID'), findsNothing);
      expect(find.text('Client secret'), findsNothing);
      expect(find.text('Calendar settings'), findsNothing);
    });

    testWidgets('a build with no client says so', (tester) async {
      final account = await tester.runAsync(() async {
        final store = GoogleAccountStore.forTesting(
          client: client,
          file: GoogleAccountFile(directory: '${tempDir.path}/state'),
          clientId: '',
          clientSecret: '',
        );
        await store.load();
        return store;
      });
      await tester.pumpWidget(
        _host(
          AccountsSettingsPage(github: githubSignedOut(), account: account!),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('no Google sign-in configured'),
        findsOneWidget,
      );
      expect(find.text('Sign in with Google'), findsNothing);
    });

    testWidgets('signed in: who, and a link to the calendar settings', (
      tester,
    ) async {
      final account = await accountWith(tester, const [
        GoogleAccountData(
          clientId: 'id',
          refreshToken: 'r',
          email: 'me@example.com',
        ),
      ]);
      final jumps = <SettingsField>[];
      await tester.pumpWidget(
        _host(
          SettingsHighlightScope(
            controller: SettingsHighlightController(),
            onJump: jumps.add,
            child: AccountsSettingsPage(
              github: githubSignedOut(),
              account: account,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('me@example.com'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Add account'), findsOneWidget);
      // The calendars themselves are Shell › Calendar's, not this page's.
      expect(find.byType(SettingsToggle), findsNothing);
      expect(find.text('Me (primary)'), findsNothing);

      await tester.tap(find.text('Calendar settings'));
      await tester.pump();
      expect(jumps, [SettingsCatalog.googleCalendars]);
      expect(jumps.single.route.category, 'shell');
      expect(jumps.single.route.shellCategory, 'Calendar');
    });
  });

  group('Settings › Shell › Calendar', () {
    Future<void> pumpPane(
      WidgetTester tester, {
      required GoogleAccountStore account,
      required GoogleCalendarStore calendar,
      required ConfigStore config,
      CalDavAccountStore? caldav,
      void Function(SettingsField)? onJump,
    }) async {
      caldav ??= await caldavWith(tester);
      await tester.pumpWidget(
        _host(
          SettingsHighlightScope(
            controller: SettingsHighlightController(),
            onJump: onJump,
            child: CustomScrollView(
              slivers: [
                CalendarSection(
                  store: config,
                  account: account,
                  calendar: calendar,
                  caldav: caldav,
                ),
              ],
            ),
          ),
        ),
      );
      // The account was loaded in the real zone, so what awaits it finishes
      // there too.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('signed out: the week start, and a link to Accounts', (
      tester,
    ) async {
      final account = await accountWith(tester, const []);
      final jumps = <SettingsField>[];
      await pumpPane(
        tester,
        account: account,
        calendar: GoogleCalendarStore.forTesting(account: account),
        config: await config(tester, ''),
        onJump: jumps.add,
      );

      expect(find.text('Week starts on'), findsOneWidget);
      expect(find.byType(SettingsToggle), findsNothing);
      await tester.tap(find.text('Link an account in Accounts'));
      await tester.pump();
      expect(jumps, [SettingsCatalog.googleAccount]);
      expect(jumps.single.route.category, 'accounts');
    });

    testWidgets('signed in: the account, its calendars, and what for', (
      tester,
    ) async {
      final account = await accountWith(tester, const [
        GoogleAccountData(
          clientId: 'id',
          refreshToken: 'r',
          email: 'me@example.com',
        ),
      ]);
      final calendar = GoogleCalendarStore.forTesting(account: account);
      final store = await config(tester, '');
      await pumpPane(
        tester,
        account: account,
        calendar: calendar,
        config: store,
      );

      // Headed by the account, in the section label's capitals.
      expect(find.text('ME@EXAMPLE.COM'), findsOneWidget);
      expect(find.text('Me (primary)'), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);
      expect(
        find.text("Put today's meetings on the todo board"),
        findsOneWidget,
      );

      // The primary calendar is on by default; switching Team on adds it.
      final toggles = tester
          .widgetList<SettingsToggle>(find.byType(SettingsToggle))
          .toList();
      expect(toggles[0].value, isTrue);
      expect(toggles[1].value, isFalse);
      await tester.tap(find.byType(SettingsToggle).at(1));
      await tester.pumpAndSettle();
      expect(store.get<List>(['google', 'calendars']), [
        'primary',
        'team@group.calendar.google.com',
      ]);
      // The write's debounce is a pending timer; `flush` settles it.
      await tester.runAsync(store.flush);
    });

    testWidgets('two accounts: a section each, one list of ids', (
      tester,
    ) async {
      final account = await accountWith(tester, const [
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
      ]);
      client.calendarsByRefresh = {
        'r': const [
          GoogleCalendar(id: 'me@example.com', summary: 'Me', primary: true),
        ],
        'w': const [
          GoogleCalendar(id: 'me@work.example', summary: 'Work', primary: true),
        ],
      };
      final calendar = GoogleCalendarStore.forTesting(account: account);
      final store = await config(tester, '');
      await pumpPane(
        tester,
        account: account,
        calendar: calendar,
        config: store,
      );

      // One section per account, headed by its address.
      expect(find.text('ME@EXAMPLE.COM'), findsOneWidget);
      expect(find.text('ME@WORK.EXAMPLE'), findsOneWidget);
      expect(find.text('Reload'), findsNWidgets(2));
      expect(find.text('Me (primary)'), findsOneWidget);
      expect(find.text('Work (primary)'), findsOneWidget);

      // Both primaries are on under `primary`; switching the work one off
      // spells the other out.
      await tester.tap(find.byType(SettingsToggle).at(1));
      await tester.pumpAndSettle();
      expect(store.get<List>(['google', 'calendars']), ['me@example.com']);
      // And back on folds them into `primary` again.
      await tester.tap(find.byType(SettingsToggle).at(1));
      await tester.pumpAndSettle();
      expect(store.get<List>(['google', 'calendars']), ['primary']);
      await tester.runAsync(store.flush);
    });

    testWidgets('CalDAV: a section per server, a switch per calendar', (
      tester,
    ) async {
      final google = await accountWith(tester, const []);
      final caldav = await caldavWith(
        tester,
        urls: [FakeCalDavServer.host, '${FakeCalDavServer.host}/dav/'],
      );
      expect(caldav.accounts, hasLength(2));
      final store = await config(tester, '');
      await pumpPane(
        tester,
        account: google,
        calendar: GoogleCalendarStore.forTesting(account: google),
        config: store,
        caldav: caldav,
      );

      // One section per server, each listing its calendar of events (and not
      // its task list), then the section saying what they are used for.
      expect(find.text('ME ON DAV.EXAMPLE.COM'), findsNWidgets(2));
      expect(find.text('Home calendar'), findsNWidgets(2));
      expect(find.text('Home tasks'), findsNothing);
      expect(find.text('Show CalDAV events in the calendar'), findsOneWidget);

      final toggles = tester
          .widgetList<SettingsToggle>(find.byType(SettingsToggle))
          .toList();
      expect(toggles[0].value, isFalse, reason: 'none are shown by default');
      await tester.tap(find.byType(SettingsToggle).first);
      await tester.pumpAndSettle();
      expect(store.get<List>(['caldav', 'calendars']), [
        FakeCalDavServer.eventsUrl.toString(),
      ]);
      await tester.tap(find.byType(SettingsToggle).first);
      await tester.pumpAndSettle();
      expect(store.get<List>(['caldav', 'calendars']), isEmpty);
      await tester.runAsync(store.flush);
    });

    testWidgets('CalDAV signed out: a link to Accounts', (tester) async {
      final google = await accountWith(tester, const []);
      final jumps = <SettingsField>[];
      await pumpPane(
        tester,
        account: google,
        calendar: GoogleCalendarStore.forTesting(account: google),
        config: await config(tester, ''),
        onJump: jumps.add,
      );
      await tester.tap(find.text('Add a server in Accounts'));
      await tester.pump();
      expect(jumps, [SettingsCatalog.caldavAccount]);
    });
  });

  group('Calendar tab events', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    Future<GoogleCalendarStore> calendarWith(WidgetTester tester) async {
      final account = await accountWith(tester, const [
        GoogleAccountData(
          clientId: 'id',
          refreshToken: 'r',
          email: 'me@example.com',
        ),
      ]);
      client.events = {
        'primary': [
          GoogleEvent(
            id: 'a',
            calendarId: 'primary',
            summary: 'Standup',
            start: today.add(const Duration(hours: 10)),
            end: today.add(const Duration(hours: 10, minutes: 15)),
            meetingLink: 'https://meet.google.com/abc',
            meetingName: 'Google Meet',
            htmlLink: 'https://calendar.google.com/event?eid=a',
            description: 'Bring the numbers.',
            descriptionLinks: const ['https://docs.google.com/document/d/1'],
          ),
          GoogleEvent(
            id: 'h',
            calendarId: 'primary',
            summary: 'Holiday',
            start: today,
            end: today.add(const Duration(days: 1)),
            allDay: true,
          ),
        ],
      };
      return GoogleCalendarStore.forTesting(account: account);
    }

    Future<List<String>> pumpTab(
      WidgetTester tester,
      GoogleCalendarStore calendar,
    ) async {
      final opened = <String>[];
      final timers = TimersStore.forTesting(now: () => now);
      addTearDown(timers.dispose);
      await tester.pumpWidget(
        _host(
          CalendarTab(
            active: true,
            weekStart: DateTime.monday,
            worldClocks: const [],
            timers: timers,
            google: calendar,
            showGoogleEvents: true,
            minuteClock: MinuteClockStore.forTesting(clock: () => now),
            openUrl: (url) {
              opened.add(url);
              return true;
            },
          ),
        ),
      );
      // The lease fetches through the account, which was loaded in the real
      // zone: each await on it resumes there, so the fetch crosses between
      // the two zones a few times before it lands.
      for (var i = 0; i < 5 && calendar.events.isEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pump();
      expect(calendar.events, isNotEmpty);
      return opened;
    }

    testWidgets('bars on the day, and a click opens the event', (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final calendar = await calendarWith(tester);
      final opened = await pumpTab(tester, calendar);

      // No list under the month any more: the events are in the cell.
      expect(find.byType(MonthDayEvents), findsWidgets);
      expect(find.text('10:00 Standup'), findsOneWidget);
      expect(find.text('Holiday'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('10:00 Standup'));
      await tester.pump();
      expect(find.text('Bring the numbers.'), findsOneWidget);
      expect(find.text('Join Google Meet'), findsOneWidget);
      expect(find.text('Open in Google Calendar'), findsOneWidget);
      expect(find.text('Google Doc'), findsOneWidget);

      await tester.tap(find.text('Join Google Meet'));
      await tester.pump();
      expect(opened, ['https://meet.google.com/abc']);
      expect(find.text('Bring the numbers.'), findsNothing, reason: 'closed');

      // Escape closes it too.
      await tester.tap(find.text('Holiday'));
      await tester.pump();
      expect(find.textContaining('All day'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.textContaining('All day'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('week and day views place the event by its time', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final calendar = await calendarWith(tester);
      await pumpTab(tester, calendar);

      await tester.tap(find.text('Week'));
      await tester.pump();
      expect(find.byType(CalendarTimeGrid), findsOneWidget);
      expect(find.byType(EventBlock), findsOneWidget);
      expect(find.text('Standup'), findsOneWidget);
      expect(find.text('Holiday'), findsOneWidget, reason: 'the all-day row');
      expect(tester.takeException(), isNull);

      // Ten o'clock sits ten hours down the grid from midnight.
      final block = tester.getRect(find.byType(EventBlock));
      final column = tester.getRect(
        find
            .ancestor(of: find.byType(EventBlock), matching: find.byType(Stack))
            .first,
      );
      expect(block.top - column.top, closeTo(10 * kHourExtent, 1));
      // Opened scrolled to the working day, not to midnight.
      final position = tester
          .state<ScrollableState>(
            find
                .ancestor(
                  of: find.byType(EventBlock),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(
        position.pixels,
        closeTo(
          math.min(
            (now.hour - 1).clamp(0, 16) * kHourExtent,
            position.maxScrollExtent,
          ),
          1,
        ),
        reason: 'an hour before now, since today is in the week',
      );

      await tester.tap(find.text('Day'));
      await tester.pump();
      expect(find.byType(EventBlock), findsOneWidget);
      await tester.ensureVisible(find.byType(EventBlock));
      await tester.pump();
      await tester.tap(find.text('Standup'));
      await tester.pump();
      expect(find.text('Join Google Meet'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Calendar tab CalDAV events', () {
    testWidgets('drawn beside no Google account at all', (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      String utc(DateTime t) {
        final u = t.toUtc();
        String two(int n) => n.toString().padLeft(2, '0');
        return '${u.year}${two(u.month)}${two(u.day)}T'
            '${two(u.hour)}${two(u.minute)}00Z';
      }

      final start = DateTime(now.year, now.month, now.day, 14);
      final server = FakeCalDavServer();
      server.events['/dav/calendars/me/events/a.ics'] =
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:a\r\n'
          'DTSTART:${utc(start)}\r\n'
          'DTEND:${utc(start.add(const Duration(hours: 1)))}\r\n'
          'SUMMARY:Dentist\r\nLOCATION:Main Street\r\n'
          'END:VEVENT\r\nEND:VCALENDAR\r\n';
      final accounts = await caldavWith(
        tester,
        server: server,
        urls: [FakeCalDavServer.host],
      );
      final caldav = CalDavCalendarStore.forTesting(
        accounts: accounts,
        config: CalDavConfig(
          calendars: [FakeCalDavServer.eventsUrl.toString()],
        ),
      );
      addTearDown(caldav.dispose);
      final google = await accountWith(tester, const []);
      final timers = TimersStore.forTesting(now: () => now);
      addTearDown(timers.dispose);

      await tester.pumpWidget(
        _host(
          CalendarTab(
            active: true,
            weekStart: DateTime.monday,
            worldClocks: const [],
            timers: timers,
            google: GoogleCalendarStore.forTesting(account: google),
            showGoogleEvents: true,
            caldav: caldav,
            showCalDavEvents: true,
            minuteClock: MinuteClockStore.forTesting(clock: () => now),
          ),
        ),
      );
      for (var i = 0; i < 5 && caldav.events.isEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pump();
      expect(caldav.events, isNotEmpty);
      expect(find.text('14:00 Dentist'), findsOneWidget);

      await tester.tap(find.text('14:00 Dentist'));
      await tester.pump();
      expect(find.text('Home calendar'), findsOneWidget);
      expect(find.text('Main Street'), findsOneWidget);
      expect(find.text('Open in Google Calendar'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
    });
  });
}
