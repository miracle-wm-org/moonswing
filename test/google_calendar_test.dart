import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/google/google_account_file.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/google/google_config.dart';
import 'package:moonswing/google/google_todo_sync.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

import 'google_fakes.dart';

GoogleEvent event(
  String id,
  DateTime start, {
  Duration length = const Duration(minutes: 30),
  String calendar = 'primary',
  bool allDay = false,
  bool cancelled = false,
}) => GoogleEvent(
  id: id,
  calendarId: calendar,
  summary: 'Event $id',
  start: start,
  end: start.add(length),
  allDay: allDay,
  cancelled: cancelled,
  meetingLink: 'https://meet.google.com/$id',
);

/// Lets queued microtasks and the fake client's futures run.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Directory tempDir;
  late FakeGoogleClient client;
  late GoogleAccountStore account;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('moonswing-google-cal');
    final file = GoogleAccountFile(directory: tempDir.path);
    await file.write(
      const GoogleAccountData(clientId: 'id', refreshToken: 'r'),
    );
    client = FakeGoogleClient();
    account = GoogleAccountStore.forTesting(client: client, file: file);
    await account.load();
  });

  tearDown(() {
    account.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('GoogleCalendarStore', () {
    test('fetches nothing until a lease asks, then the leased span', () async {
      client.events = {
        'primary': [
          event('a', DateTime(2026, 9, 25, 10)),
          event('b', DateTime(2026, 9, 25, 14), cancelled: true),
          event(
            'all',
            DateTime(2026, 9, 25),
            allDay: true,
            length: const Duration(days: 1),
          ),
          event('oct', DateTime(2026, 10, 3, 9)),
        ],
      };
      final store = GoogleCalendarStore.forTesting(account: account);
      addTearDown(store.dispose);
      await settle();
      expect(client.eventCalls, 0);

      final lease = store.acquire(DateTime(2026, 9, 1), DateTime(2026, 10, 1));
      await settle();
      expect(client.eventCalls, 1);
      expect(
        store.covers(DateTime(2026, 9, 25), DateTime(2026, 9, 26)),
        isTrue,
      );
      // All-day first, then by start; cancelled left out.
      expect(store.eventsOn(DateTime(2026, 9, 25)).map((e) => e.id), [
        'all',
        'a',
      ]);
      expect(store.hasEventsOn(DateTime(2026, 9, 25)), isTrue);
      expect(store.hasEventsOn(DateTime(2026, 9, 26)), isFalse);

      // A window already covered is not fetched again.
      lease.update(DateTime(2026, 9, 2), DateTime(2026, 9, 30));
      await settle();
      expect(client.eventCalls, 1);

      // One that is not, is.
      lease.update(DateTime(2026, 10, 1), DateTime(2026, 11, 1));
      await settle();
      expect(client.eventCalls, 2);
      expect(store.hasEventsOn(DateTime(2026, 10, 3)), isTrue);

      lease.release();
      expect(store.leaseCount, 0);
    });

    test('every configured calendar is read', () async {
      client.events = {
        'primary': [event('a', DateTime(2026, 9, 25, 10))],
        'team': [event('t', DateTime(2026, 9, 25, 9), calendar: 'team')],
      };
      final store = GoogleCalendarStore.forTesting(
        account: account,
        config: const GoogleConfig(calendars: ['primary', 'team']),
      );
      addTearDown(store.dispose);
      store.acquire(DateTime(2026, 9, 25), DateTime(2026, 9, 26));
      await settle();
      expect(store.eventsOn(DateTime(2026, 9, 25)).map((e) => e.key), [
        'team/t',
        'primary/a',
      ]);

      // Dropping a calendar refetches rather than waiting out an interval.
      store.configure(const GoogleConfig(calendars: ['primary']));
      await settle();
      expect(store.eventsOn(DateTime(2026, 9, 25)).map((e) => e.key), [
        'primary/a',
      ]);
    });

    test(
      'a failure keeps the last answer on screen, with the reason',
      () async {
        client.events = {
          'primary': [event('a', DateTime(2026, 9, 25, 10))],
        };
        final store = GoogleCalendarStore.forTesting(account: account);
        addTearDown(store.dispose);
        store.acquire(DateTime(2026, 9, 25), DateTime(2026, 9, 26));
        await settle();

        client.eventsError = const GoogleException('Could not reach Google');
        await store.refresh();
        expect(store.error, 'Could not reach Google');
        expect(store.eventsOn(DateTime(2026, 9, 25)), hasLength(1));

        client.eventsError = null;
        await store.refresh();
        expect(store.error, isEmpty);
      },
    );

    test('signing out takes the account\'s events with it', () async {
      client.events = {
        'primary': [event('a', DateTime(2026, 9, 25, 10))],
      };
      final store = GoogleCalendarStore.forTesting(account: account);
      addTearDown(store.dispose);
      store.acquire(DateTime(2026, 9, 25), DateTime(2026, 9, 26));
      await settle();
      await account.signOut();
      expect(store.events, isEmpty);
      expect(
        store.covers(DateTime(2026, 9, 25), DateTime(2026, 9, 26)),
        isFalse,
      );
    });
  });

  group('GoogleTodoSync', () {
    test('today\'s timed meetings land on the board while it is on', () async {
      final now = DateTime(2026, 9, 25, 10, 5);
      client.events = {
        'primary': [
          event('standup', DateTime(2026, 9, 25, 10)),
          event('review', DateTime(2026, 9, 25, 15)),
          event(
            'holiday',
            DateTime(2026, 9, 25),
            allDay: true,
            length: const Duration(days: 1),
          ),
        ],
      };
      final calendar = GoogleCalendarStore.forTesting(account: account);
      addTearDown(calendar.dispose);
      final todo = TodoStore.forTesting(now: () => now, items: const []);
      addTearDown(todo.dispose);
      final sync = GoogleTodoSync(
        account: account,
        calendar: calendar,
        todo: todo,
        now: () => now,
        autoTimers: false,
      );
      addTearDown(sync.dispose);

      sync.configure(const GoogleConfig());
      await settle();
      expect(sync.active, isFalse);
      expect(client.eventCalls, 0, reason: 'off means no requests at all');

      sync.configure(const GoogleConfig(todoSync: true));
      await settle();
      expect(sync.active, isTrue);
      expect(todo.itemsIn(TodoColumn.inProgress).map((i) => i.title), [
        'Event standup',
      ]);
      expect(todo.itemsIn(TodoColumn.todo).map((i) => i.title), [
        'Event review',
      ]);
      expect(todo.items, hasLength(2), reason: 'all-day events stay off');

      sync.configure(const GoogleConfig());
      expect(sync.active, isFalse);
      expect(calendar.leaseCount, 0);
    });

    test('a failed fetch abandons nothing', () async {
      final now = DateTime(2026, 9, 25, 9);
      client.eventsError = const GoogleException('offline');
      final calendar = GoogleCalendarStore.forTesting(account: account);
      addTearDown(calendar.dispose);
      final existing = TodoItem(
        id: 'm',
        title: 'Event standup',
        body: '',
        column: TodoColumn.todo,
        created: now,
        external: TodoExternal(
          source: TodoExternal.googleCalendar,
          key: 'primary/standup',
          title: 'Event standup',
          start: DateTime(2026, 9, 25, 10),
          end: DateTime(2026, 9, 25, 10, 30),
        ),
      );
      final todo = TodoStore.forTesting(now: () => now, items: [existing]);
      addTearDown(todo.dispose);
      final sync = GoogleTodoSync(
        account: account,
        calendar: calendar,
        todo: todo,
        now: () => now,
        autoTimers: false,
      );
      addTearDown(sync.dispose);
      sync.configure(const GoogleConfig(todoSync: true));
      await settle();
      expect(calendar.error, 'offline');
      expect(todo.item('m')!.column, TodoColumn.todo);
    });
  });
}
