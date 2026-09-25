import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/google/google_account_file.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/overlay/calendar/calendar_agenda.dart';
import 'package:moonswing/overlay/settings/accounts.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

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
    GoogleAccountData data,
  ) async {
    final account = await tester.runAsync(() async {
      final file = GoogleAccountFile(directory: '${tempDir.path}/state');
      if (data != const GoogleAccountData()) await file.write(data);
      final store = GoogleAccountStore.forTesting(client: client, file: file);
      await store.load();
      return store;
    });
    return account!;
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
      final account = await accountWith(tester, const GoogleAccountData());
      final calendar = GoogleCalendarStore.forTesting(account: account);
      await tester.pumpWidget(
        _host(
          AccountsSettingsPage(
            account: account,
            calendar: calendar,
            config: await config(tester, ''),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Client ID'), findsNothing);
      expect(find.text('Client secret'), findsNothing);
      expect(find.text('Calendars'), findsNothing);
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
      final calendar = GoogleCalendarStore.forTesting(account: account!);
      await tester.pumpWidget(
        _host(
          AccountsSettingsPage(
            account: account,
            calendar: calendar,
            config: await config(tester, ''),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('no Google sign-in configured'),
        findsOneWidget,
      );
      expect(find.text('Sign in with Google'), findsNothing);
    });

    testWidgets('signed in: who, which calendars, and what for', (
      tester,
    ) async {
      final account = await accountWith(
        tester,
        const GoogleAccountData(
          clientId: 'id',
          refreshToken: 'r',
          email: 'me@example.com',
        ),
      );
      final calendar = GoogleCalendarStore.forTesting(account: account);
      final store = await config(tester, '');
      await tester.pumpWidget(
        _host(
          AccountsSettingsPage(
            account: account,
            calendar: calendar,
            config: store,
          ),
        ),
      );
      // The account was loaded in the real zone, so what awaits it finishes
      // there too.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Signed in as me@example.com'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
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
  });

  group('CalendarAgenda', () {
    testWidgets('lists the day, with a Join for a call', (tester) async {
      final account = await accountWith(
        tester,
        const GoogleAccountData(clientId: 'id', refreshToken: 'r'),
      );
      final day = DateTime(2026, 9, 25);
      client.events = {
        'primary': [
          GoogleEvent(
            id: 'a',
            calendarId: 'primary',
            summary: 'Standup',
            start: DateTime(2026, 9, 25, 10),
            end: DateTime(2026, 9, 25, 10, 15),
            meetingLink: 'https://meet.google.com/abc',
            htmlLink: 'https://calendar.google.com/event?eid=a',
          ),
          GoogleEvent(
            id: 'b',
            calendarId: 'primary',
            summary: 'Lunch',
            start: DateTime(2026, 9, 25, 12),
            end: DateTime(2026, 9, 25, 13),
          ),
        ],
      };
      final calendar = GoogleCalendarStore.forTesting(account: account);
      final lease = calendar.acquire(day, DateTime(2026, 9, 26));
      addTearDown(lease.release);
      await tester.runAsync(() => calendar.refresh());

      final opened = <String>[];
      await tester.pumpWidget(
        _host(
          CalendarAgenda(
            store: calendar,
            day: day,
            onOpen: (url) {
              opened.add(url);
              return true;
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Standup'), findsOneWidget);
      expect(find.text('10:00–10:15'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);

      await tester.tap(find.text('Join'));
      await tester.tap(find.text('Standup'));
      expect(opened, [
        'https://meet.google.com/abc',
        'https://calendar.google.com/event?eid=a',
      ]);

      await tester.pumpWidget(
        _host(
          CalendarAgenda(
            store: calendar,
            day: DateTime(2026, 9, 26),
            onOpen: (_) => true,
          ),
          key: UniqueKey(),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Nothing on Saturday 26 Sep'), findsOneWidget);
    });
  });
}
