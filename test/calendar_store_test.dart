import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/overlay/calendar/calendar_store.dart';
import 'package:graceful_shell/overlay/calendar/event.dart';
import 'package:graceful_shell/overlay/calendar/provider.dart';

/// A provider that answers from memory, so the store's state machine can be
/// exercised without a network or a Google account.
class FakeProvider implements CalendarProvider {
  FakeProvider({this.connected = true, this.events = const []});

  bool connected;
  List<CalendarEvent> events;

  /// Thrown by the next fetchEvents call, if set.
  Object? failWith;

  int fetchCount = 0;

  /// Gates fetchEvents so a test can hold two calls in flight at once.
  Completer<void>? gate;

  @override
  String get id => 'google';

  @override
  CalendarProviderKind get kind => CalendarProviderKind.google;

  @override
  bool get isConfigured => true;

  @override
  bool get isConnected => connected;

  @override
  CalendarAccount? get account => connected
      ? const CalendarAccount(
          id: 'google',
          kind: CalendarProviderKind.google,
          label: 'Google Calendar',
          email: 'user@gmail.com',
        )
      : null;

  @override
  Future<void> restore() async {}

  @override
  Future<void> connect({void Function(Uri url)? onUrl}) async {
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<List<CalendarEvent>> fetchEvents(DateTime from, DateTime to) async {
    fetchCount++;
    if (gate != null) await gate!.future;

    final failure = failWith;
    if (failure != null) {
      // An auth failure means the provider drops its own tokens, exactly as
      // GoogleCalendarProvider does before rethrowing.
      if (failure is CalendarAuthException) connected = false;
      throw failure;
    }
    return events;
  }
}

CalendarEvent _event(DateTime day, {String title = 'Standup'}) {
  return CalendarEvent(
    id: title,
    calendarId: 'primary',
    title: title,
    start: DateTime(day.year, day.month, day.day, 9),
    end: DateTime(day.year, day.month, day.day, 9, 30),
  );
}

void main() {
  final month = DateTime(2026, 7, 1);
  final day = DateTime(2026, 7, 13);

  test('ensureMonth loads events and reaches ready', () async {
    final provider = FakeProvider(events: [_event(day)]);
    final store = CalendarStore.forTesting([provider]);

    await store.ensureMonth(month);

    expect(store.state, CalendarSyncState.ready);
    expect(store.error, isNull);
    expect(store.lastSync, isNotNull);
    expect(store.hasEvents(day), isTrue);
    expect(store.eventsOn(day).single.title, 'Standup');
    expect(store.hasEvents(DateTime(2026, 7, 14)), isFalse);
  });

  test('with no connected account it fetches nothing and stays idle', () async {
    final provider = FakeProvider(connected: false);
    final store = CalendarStore.forTesting([provider]);

    await store.ensureMonth(month);

    expect(provider.fetchCount, 0);
    expect(store.state, CalendarSyncState.idle);
    expect(store.eventsByDay, isEmpty);
  });

  test('a second call for a fresh month does not refetch', () async {
    final provider = FakeProvider(events: [_event(day)]);
    final store = CalendarStore.forTesting([provider]);

    await store.ensureMonth(month);
    await store.ensureMonth(month);

    expect(provider.fetchCount, 1);
  });

  test('force refetches even when the month is fresh', () async {
    final provider = FakeProvider(events: [_event(day)]);
    final store = CalendarStore.forTesting([provider]);

    await store.ensureMonth(month);
    await store.ensureMonth(month, force: true);

    expect(provider.fetchCount, 2);
  });

  test('paging to a new month refetches', () async {
    final provider = FakeProvider(events: [_event(day)]);
    final store = CalendarStore.forTesting([provider]);

    await store.ensureMonth(month);
    await store.ensureMonth(DateTime(2026, 8, 1));

    expect(provider.fetchCount, 2);
  });

  test('concurrent calls for the same month share one fetch', () async {
    final provider = FakeProvider(events: [_event(day)])
      ..gate = Completer<void>();
    final store = CalendarStore.forTesting([provider]);

    final first = store.ensureMonth(month);
    final second = store.ensureMonth(month);
    provider.gate!.complete();
    await Future.wait([first, second]);

    expect(provider.fetchCount, 1);
  });

  test('a transient failure keeps the tokens and the events already loaded',
      () async {
    final provider = FakeProvider(events: [_event(day)]);
    final store = CalendarStore.forTesting([provider]);

    await store.ensureMonth(month);
    provider.failWith = const CalendarFetchException('offline');
    await store.ensureMonth(month, force: true);

    expect(store.state, CalendarSyncState.error);
    expect(store.error, 'offline');
    // The grid must stay usable offline, so the last good events survive.
    expect(store.hasEvents(day), isTrue);
    expect(store.hasConnectedAccount, isTrue);
  });

  test('an auth failure disconnects the account and clears its events', () async {
    final provider = FakeProvider(events: [_event(day)]);
    final store = CalendarStore.forTesting([provider]);

    await store.ensureMonth(month);
    expect(store.hasEvents(day), isTrue);

    provider.failWith = const CalendarAuthException('grant revoked');
    await store.ensureMonth(month, force: true);

    expect(store.state, CalendarSyncState.idle);
    expect(store.error, 'grant revoked');
    expect(store.hasConnectedAccount, isFalse);
    expect(store.eventsByDay, isEmpty);
  });

  test('disconnect clears events and drops the account', () async {
    final provider = FakeProvider(events: [_event(day)]);
    final store = CalendarStore.forTesting([provider]);

    await store.ensureMonth(month);
    await store.disconnect('google');

    expect(store.hasConnectedAccount, isFalse);
    expect(store.eventsByDay, isEmpty);
    expect(store.lastSync, isNull);
    expect(store.state, CalendarSyncState.idle);
  });

  test('connect signs in and loads the current month', () async {
    final provider = FakeProvider(connected: false, events: [_event(day)]);
    final store = CalendarStore.forTesting([provider]);

    await store.connect('google');

    expect(store.hasConnectedAccount, isTrue);
    expect(provider.fetchCount, 1);
    expect(store.state, CalendarSyncState.ready);
  });

  test('a failed connect reports the error and stays disconnected', () async {
    final provider = _RefusingProvider();
    final store = CalendarStore.forTesting([provider]);

    await store.connect('google');

    expect(store.hasConnectedAccount, isFalse);
    expect(store.state, CalendarSyncState.idle);
    expect(store.error, 'consent denied');
  });

  test('notifies listeners as the sync state changes', () async {
    final store = CalendarStore.forTesting([FakeProvider(events: [_event(day)])]);
    var notifications = 0;
    store.addListener(() => notifications++);

    await store.ensureMonth(month);

    expect(notifications, greaterThan(0));
  });
}

class _RefusingProvider extends FakeProvider {
  _RefusingProvider() : super(connected: false);

  @override
  Future<void> connect({void Function(Uri url)? onUrl}) async {
    throw const CalendarAuthException('consent denied');
  }
}
