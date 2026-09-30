import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/accounts/calendar_event_source.dart';
import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/caldav/caldav_calendar_store.dart';
import 'package:moonswing/caldav/caldav_config.dart';
import 'package:moonswing/google/google_account_file.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_calendar_store.dart';

import 'caldav_fakes.dart';
import 'google_fakes.dart';

String _event(String uid, String summary, String start, String end) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n'
    'BEGIN:VEVENT\r\nUID:$uid\r\nDTSTAMP:20260901T000000Z\r\n'
    'DTSTART:$start\r\nDTEND:$end\r\nSUMMARY:$summary\r\n'
    'END:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
  late Directory dir;
  late FakeCalDavServer server;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('caldav_calendar');
    server = FakeCalDavServer();
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<CalDavAccountStore> signedIn({List<String> urls = const []}) async {
    final accounts = CalDavAccountStore.forTesting(
      directory: dir.path,
      client: server.client,
    );
    await accounts.load();
    for (final url in urls) {
      expect(
        await accounts.signIn(url: url, username: 'me', password: 'secret'),
        isTrue,
        reason: accounts.error,
      );
    }
    return accounts;
  }

  group('several accounts', () {
    test('are kept side by side, and each signs out alone', () async {
      final accounts = await signedIn(
        urls: [FakeCalDavServer.host, '${FakeCalDavServer.host}/dav/'],
      );
      expect(accounts.accounts, hasLength(2));
      expect(
        accounts.accounts.first.eventCalendars.single.name,
        'Home calendar',
      );
      expect(accounts.accounts.first.taskLists.single.name, 'Home tasks');

      final reread = CalDavAccountStore.forTesting(directory: dir.path);
      await reread.load();
      expect(reread.accounts, accounts.accounts);

      await accounts.signOut(accounts.accounts.first.id);
      expect(accounts.accounts.single.url, '${FakeCalDavServer.host}/dav/');
      final after = CalDavAccountStore.forTesting(directory: dir.path);
      await after.load();
      expect(after.accounts.single.url, '${FakeCalDavServer.host}/dav/');
      expect(File(after.path).statSync().mode & 0x1ff, 0x180);
    });

    test('signing in again as one listed replaces it', () async {
      final accounts = await signedIn(
        urls: [FakeCalDavServer.host, FakeCalDavServer.host],
      );
      expect(accounts.accounts, hasLength(1));
    });

    test('a file written with one account reads as a list of one', () async {
      File('${dir.path}/caldav-account.json').writeAsStringSync(
        jsonEncode({
          'url': FakeCalDavServer.host,
          'username': 'me',
          'password': 'secret',
          'task_lists': [
            {'url': FakeCalDavServer.tasksUrl.toString(), 'name': 'Tasks'},
          ],
        }),
      );
      final accounts = CalDavAccountStore.forTesting(
        directory: dir.path,
        client: server.client,
      );
      await accounts.load();
      expect(accounts.accounts.single.taskLists.single.name, 'Tasks');
      expect(accounts.eventCalendars, isEmpty);
      expect(
        accounts.accountOf(FakeCalDavServer.tasksUrl),
        accounts.accounts.single,
      );
      // Looking again finds the calendars of events it never looked for.
      await accounts.refreshAll();
      expect(accounts.eventCalendars.single.url, FakeCalDavServer.eventsUrl);
    });

    test('one failing to refresh says so beside it alone', () async {
      final accounts = await signedIn(urls: [FakeCalDavServer.host]);
      final id = accounts.accounts.single.id;
      server.failWith = 503;
      await accounts.refresh(id);
      expect(accounts.errorOf(id), contains('503'));
      expect(accounts.error, isEmpty);
      // The calendars found before stay.
      expect(accounts.accounts.single.calendars, isNotEmpty);
    });
  });

  group('CalDavCalendarStore', () {
    final from = DateTime(2026, 9, 1);
    final to = DateTime(2026, 10, 1);

    Future<void> settle(CalDavCalendarStore store) async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('reads the chosen calendars for a lease, and nothing else', () async {
      server.events['/dav/calendars/me/events/a.ics'] = _event(
        'a',
        'Dentist',
        '20260915T090000Z',
        '20260915T100000Z',
      );
      final accounts = await signedIn(urls: [FakeCalDavServer.host]);
      final store = CalDavCalendarStore.forTesting(accounts: accounts);
      addTearDown(store.dispose);

      final lease = store.acquire(from, to);
      await settle(store);
      expect(server.lastEventQuery, isNull, reason: 'nothing chosen yet');
      expect(store.active, isFalse);

      store.configure(
        CalDavConfig(calendars: [FakeCalDavServer.eventsUrl.toString()]),
      );
      await settle(store);
      expect(store.active, isTrue);
      expect(server.lastEventQuery, contains('<c:expand'));
      expect(server.lastEventQuery, contains('20260901T'));
      final day = DateTime(2026, 9, 15);
      final events = store.eventsOn(day);
      expect(events.single.summary, 'Dentist');
      expect(store.hasEventsOn(day), isTrue);
      expect(store.owns(events.single), isTrue);
      expect(store.colorOf(events.single), '#0000ff');
      expect(store.calendarLabelOf(events.single), 'Home calendar');
      expect(store.covers(from, to), isTrue);
      lease.release();
      expect(store.leaseCount, 0);
    });

    test('a calendar that fails is named, and keeps its events', () async {
      server.events['/dav/calendars/me/events/a.ics'] = _event(
        'a',
        'Dentist',
        '20260915T090000Z',
        '20260915T100000Z',
      );
      final accounts = await signedIn(urls: [FakeCalDavServer.host]);
      final store = CalDavCalendarStore.forTesting(
        accounts: accounts,
        config: CalDavConfig(
          calendars: [FakeCalDavServer.eventsUrl.toString()],
        ),
      );
      addTearDown(store.dispose);
      store.acquire(from, to);
      await settle(store);
      expect(store.events, hasLength(1));

      server.failWith = 500;
      await store.refresh();
      expect(store.error, contains('500'));
      expect(store.events, hasLength(1));

      server.failWith = null;
      await store.refresh();
      expect(store.error, isEmpty);
    });

    test('switching a calendar off takes its events off at once', () async {
      server.events['/dav/calendars/me/events/a.ics'] = _event(
        'a',
        'Dentist',
        '20260915T090000Z',
        '20260915T100000Z',
      );
      final accounts = await signedIn(urls: [FakeCalDavServer.host]);
      final store = CalDavCalendarStore.forTesting(
        accounts: accounts,
        config: CalDavConfig(
          calendars: [FakeCalDavServer.eventsUrl.toString()],
        ),
      );
      addTearDown(store.dispose);
      store.acquire(from, to);
      await settle(store);
      expect(store.events, isNotEmpty);
      store.configure(const CalDavConfig());
      expect(store.events, isEmpty);
    });

    test('merged with Google, each event is drawn by its own source', () async {
      server.events['/dav/calendars/me/events/a.ics'] = _event(
        'a',
        'Dentist',
        '20260915T090000Z',
        '20260915T100000Z',
      );
      final accounts = await signedIn(urls: [FakeCalDavServer.host]);
      final caldav = CalDavCalendarStore.forTesting(
        accounts: accounts,
        config: CalDavConfig(
          calendars: [FakeCalDavServer.eventsUrl.toString()],
        ),
      );
      addTearDown(caldav.dispose);
      final google = GoogleCalendarStore.forTesting(
        account: GoogleAccountStore.forTesting(
          client: FakeGoogleClient(),
          file: GoogleAccountFile(directory: '${dir.path}/google'),
        ),
      );
      addTearDown(google.dispose);
      caldav.acquire(from, to);
      await settle(caldav);

      final merged = MergedCalendarEvents([google, caldav]);
      final event = merged.eventsOn(DateTime(2026, 9, 15)).single;
      expect(merged.colorOf(event), '#0000ff');
      expect(merged.calendarLabelOf(event), 'Home calendar');
      expect(merged, MergedCalendarEvents([google, caldav]));
    });
  });
}
