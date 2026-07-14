import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/overlay/calendar/event.dart';
import 'package:graceful_shell/overlay/calendar/google_provider.dart';

CalendarEvent _event({
  String id = 'e',
  String title = 'Event',
  required DateTime start,
  required DateTime end,
  bool allDay = false,
}) {
  return CalendarEvent(
    id: id,
    calendarId: 'primary',
    title: title,
    start: start,
    end: end,
    allDay: allDay,
  );
}

void main() {
  group('daysSpanned', () {
    test('a single timed event covers one day', () {
      final e = _event(
        start: DateTime(2026, 7, 13, 9),
        end: DateTime(2026, 7, 13, 9, 30),
      );
      expect(daysSpanned(e), [DateTime(2026, 7, 13)]);
    });

    test('an event ending exactly at midnight does not leak into the next day', () {
      final e = _event(
        start: DateTime(2026, 7, 13, 23),
        end: DateTime(2026, 7, 14),
      );
      expect(daysSpanned(e), [DateTime(2026, 7, 13)]);
    });

    test('a three-day all-day event covers all three days', () {
      final e = _event(
        start: DateTime(2026, 7, 13),
        end: DateTime(2026, 7, 15),
        allDay: true,
      );
      expect(daysSpanned(e), [
        DateTime(2026, 7, 13),
        DateTime(2026, 7, 14),
        DateTime(2026, 7, 15),
      ]);
    });

    test('spans a month boundary', () {
      final e = _event(
        start: DateTime(2026, 7, 31),
        end: DateTime(2026, 8, 1),
        allDay: true,
      );
      expect(daysSpanned(e), [DateTime(2026, 7, 31), DateTime(2026, 8, 1)]);
    });
  });

  group('groupByDay', () {
    test('puts a multi-day event in every bucket it touches', () {
      final trip = _event(
        id: 'trip',
        title: 'Trip',
        start: DateTime(2026, 7, 13),
        end: DateTime(2026, 7, 15),
        allDay: true,
      );
      final byDay = groupByDay([trip]);
      expect(byDay.keys, hasLength(3));
      expect(byDay[DateTime(2026, 7, 14)], [trip]);
    });

    test('sorts all-day first, then by start, then by title', () {
      final standup = _event(
        id: 'b',
        title: 'Standup',
        start: DateTime(2026, 7, 13, 9),
        end: DateTime(2026, 7, 13, 9, 15),
      );
      final review = _event(
        id: 'c',
        title: 'Review',
        start: DateTime(2026, 7, 13, 14),
        end: DateTime(2026, 7, 13, 15),
      );
      // Same start as standup, sorts after it on title.
      final apples = _event(
        id: 'd',
        title: 'Zebras',
        start: DateTime(2026, 7, 13, 9),
        end: DateTime(2026, 7, 13, 9, 15),
      );
      final holiday = _event(
        id: 'a',
        title: 'Holiday',
        start: DateTime(2026, 7, 13),
        end: DateTime(2026, 7, 13),
        allDay: true,
      );

      final day = groupByDay([review, apples, standup, holiday])[
          DateTime(2026, 7, 13)]!;
      expect(day.map((e) => e.title),
          ['Holiday', 'Standup', 'Zebras', 'Review']);
    });

    test('an empty input yields an empty map', () {
      expect(groupByDay([]), isEmpty);
    });
  });

  group('parseGoogleEvent', () {
    CalendarEvent? parse(Map<String, dynamic> json) =>
        parseGoogleEvent(json, calendarId: 'primary', color: const Color(0xFF853953));

    test('maps a timed event, converting the offset to local time', () {
      final event = parse({
        'id': 'evt1',
        'summary': 'Standup',
        'location': 'Room 2',
        'start': {'dateTime': '2026-07-13T09:00:00Z'},
        'end': {'dateTime': '2026-07-13T09:30:00Z'},
      })!;

      expect(event.id, 'evt1');
      expect(event.title, 'Standup');
      expect(event.location, 'Room 2');
      expect(event.allDay, isFalse);
      expect(event.calendarId, 'primary');
      expect(event.color, const Color(0xFF853953));

      // The wall-clock time depends on the machine's zone, so assert on the
      // instant rather than on the hour.
      expect(event.start.isUtc, isFalse);
      expect(event.start.toUtc(), DateTime.utc(2026, 7, 13, 9));
      expect(event.duration, const Duration(minutes: 30));
    });

    test("converts Google's exclusive all-day end into an inclusive one", () {
      // A one-day event on the 13th arrives as start 13th, end 14th.
      final event = parse({
        'id': 'holiday',
        'summary': 'Holiday',
        'start': {'date': '2026-07-13'},
        'end': {'date': '2026-07-14'},
      })!;

      expect(event.allDay, isTrue);
      expect(event.start, DateTime(2026, 7, 13));
      expect(event.end, DateTime(2026, 7, 13));
      expect(daysSpanned(event), [DateTime(2026, 7, 13)]);
    });

    test('a three-day all-day event spans exactly three days', () {
      final event = parse({
        'id': 'trip',
        'summary': 'Trip',
        'start': {'date': '2026-07-13'},
        'end': {'date': '2026-07-16'},
      })!;

      expect(event.start, DateTime(2026, 7, 13));
      expect(event.end, DateTime(2026, 7, 15));
      expect(daysSpanned(event), hasLength(3));
    });

    test('drops cancelled events', () {
      expect(
        parse({
          'id': 'gone',
          'status': 'cancelled',
          'start': {'date': '2026-07-13'},
          'end': {'date': '2026-07-14'},
        }),
        isNull,
      );
    });

    test('drops an event with no start', () {
      expect(parse({'id': 'x', 'summary': 'No start'}), isNull);
    });

    test('an event with no summary gets a placeholder title', () {
      final event = parse({
        'id': 'untitled',
        'start': {'dateTime': '2026-07-13T09:00:00Z'},
        'end': {'dateTime': '2026-07-13T10:00:00Z'},
      })!;
      expect(event.title, '(No title)');
    });
  });
}
