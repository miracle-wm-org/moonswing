import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/caldav/caldav_events.dart';

const _calendar = 'https://dav.example.com/dav/calendars/me/events/';

String _ics(String events) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n'
    '$events'
    'END:VCALENDAR\r\n';

String _event(String uid, String props) =>
    'BEGIN:VEVENT\r\nUID:$uid\r\nDTSTAMP:20260901T000000Z\r\n'
    '$props'
    'END:VEVENT\r\n';

void main() {
  final from = DateTime(2026, 9, 1);
  final to = DateTime(2026, 10, 1);

  List<dynamic> read(String data, {ZoneConverter? zone}) => eventsFromICalendar(
    data,
    calendarId: _calendar,
    account: 'me@https://dav.example.com',
    from: from,
    to: to,
    zone: zone,
  );

  test('a timed event in UTC, with what the details show', () {
    final events = read(
      _ics(
        _event(
          'standup',
          'DTSTART:20260915T090000Z\r\nDTEND:20260915T093000Z\r\n'
              'SUMMARY:Standup\r\n'
              'LOCATION:https://meet.example.com/abc\r\n'
              'DESCRIPTION:Bring notes\\, please\r\n'
              'URL:https://example.com/agenda\r\n',
        ),
      ),
    );
    final e = events.single;
    expect(e.summary, 'Standup');
    expect(e.start, DateTime.utc(2026, 9, 15, 9).toLocal());
    expect(e.end, DateTime.utc(2026, 9, 15, 9, 30).toLocal());
    expect(e.allDay, isFalse);
    expect(e.calendarId, _calendar);
    expect(e.meetingLink, 'https://meet.example.com/abc');
    expect(e.description, 'Bring notes, please');
    expect(e.htmlLink, isNull);
    expect(e.links.map((l) => l.url), contains('https://example.com/agenda'));
    expect(e.key, '$_calendar/standup');
  });

  test('a TZID time goes through the zone converter, else reads as local', () {
    final data = _ics(
      _event(
        'tz',
        'DTSTART;TZID=Europe/Berlin:20260915T100000\r\n'
            'DURATION:PT1H\r\nSUMMARY:Zoned\r\n',
      ),
    );
    final converted = read(
      data,
      zone: (wall, tzid) =>
          tzid == 'Europe/Berlin' ? wall.add(const Duration(hours: 5)) : null,
    ).single;
    expect(converted.start, DateTime(2026, 9, 15, 15));
    expect(converted.end, DateTime(2026, 9, 15, 16));

    final unknown = read(data, zone: (_, _) => null).single;
    expect(unknown.start, DateTime(2026, 9, 15, 10));
  });

  test('an all-day event spans whole days, a missing end is one day', () {
    final events = read(
      _ics(
        _event(
              'trip',
              'DTSTART;VALUE=DATE:20260910\r\nDTEND;VALUE=DATE:20260913\r\n'
                  'SUMMARY:Trip\r\n',
            ) +
            _event(
              'holiday',
              'DTSTART;VALUE=DATE:20260920\r\nSUMMARY:Holiday\r\n',
            ),
      ),
    );
    final trip = events.firstWhere((e) => e.summary == 'Trip');
    expect(trip.allDay, isTrue);
    expect(trip.start, DateTime(2026, 9, 10));
    expect(trip.end, DateTime(2026, 9, 13));
    final holiday = events.firstWhere((e) => e.summary == 'Holiday');
    expect(holiday.end, DateTime(2026, 9, 21));
  });

  test('cancelled is kept but marked, and outside the window is dropped', () {
    final events = read(
      _ics(
        _event(
              'off',
              'DTSTART:20260915T090000Z\r\nDTEND:20260915T100000Z\r\n'
                  'STATUS:CANCELLED\r\nSUMMARY:Off\r\n',
            ) +
            _event(
              'later',
              'DTSTART:20261115T090000Z\r\nDTEND:20261115T100000Z\r\n'
                  'SUMMARY:Later\r\n',
            ),
      ),
    );
    expect(events.single.summary, 'Off');
    expect(events.single.cancelled, isTrue);
  });

  test('occurrences the server expanded keep apart by RECURRENCE-ID', () {
    final events = read(
      _ics(
        _event(
              'weekly',
              'RECURRENCE-ID:20260907T090000Z\r\n'
                  'DTSTART:20260907T090000Z\r\nDTEND:20260907T100000Z\r\n'
                  'SUMMARY:Weekly\r\n',
            ) +
            _event(
              'weekly',
              'RECURRENCE-ID:20260914T090000Z\r\n'
                  'DTSTART:20260914T110000Z\r\nDTEND:20260914T120000Z\r\n'
                  'SUMMARY:Weekly (moved)\r\n',
            ),
      ),
    );
    expect(events, hasLength(2));
    expect(events.map((e) => e.key).toSet(), hasLength(2));
  });

  test('a recurring event the server did not expand is expanded here', () {
    final events = read(
      _ics(
        _event(
              'weekly',
              'DTSTART:20260803T090000\r\nDTEND:20260803T100000\r\n'
                  'RRULE:FREQ=WEEKLY;BYDAY=MO,WE\r\n'
                  'EXDATE:20260909T090000\r\n'
                  'SUMMARY:Gym\r\n',
            ) +
            // One occurrence moved to the afternoon.
            _event(
              'weekly',
              'RECURRENCE-ID:20260914T090000\r\n'
                  'DTSTART:20260914T170000\r\nDTEND:20260914T180000\r\n'
                  'SUMMARY:Gym (late)\r\n',
            ),
      ),
    );
    final starts = [for (final e in events) e.start]..sort();
    expect(starts, [
      DateTime(2026, 9, 2, 9),
      DateTime(2026, 9, 7, 9),
      // 9 September is excluded.
      DateTime(2026, 9, 14, 17),
      DateTime(2026, 9, 16, 9),
      DateTime(2026, 9, 21, 9),
      DateTime(2026, 9, 23, 9),
      DateTime(2026, 9, 28, 9),
      DateTime(2026, 9, 30, 9),
    ]);
    expect(events.map((e) => e.key).toSet(), hasLength(events.length));
  });

  group('expandRecurrence', () {
    final start = DateTime(2026, 1, 31, 8);
    final until = DateTime(2026, 7, 1);

    test('monthly skips the months without the day', () {
      expect(expandRecurrence(start, 'FREQ=MONTHLY', until: until), [
        DateTime(2026, 1, 31, 8),
        DateTime(2026, 3, 31, 8),
        DateTime(2026, 5, 31, 8),
      ]);
    });

    test('count and interval', () {
      expect(
        expandRecurrence(start, 'FREQ=DAILY;INTERVAL=2;COUNT=3', until: until),
        [
          DateTime(2026, 1, 31, 8),
          DateTime(2026, 2, 2, 8),
          DateTime(2026, 2, 4, 8),
        ],
      );
    });

    test('count still counts what falls before the window', () {
      expect(
        expandRecurrence(
          start,
          'FREQ=DAILY;COUNT=3',
          until: until,
          after: DateTime(2026, 2, 1, 12),
        ),
        [DateTime(2026, 2, 2, 8)],
      );
    });

    test('a rule it cannot read is its first occurrence alone', () {
      expect(expandRecurrence(start, 'FREQ=MONTHLY;BYDAY=2MO', until: until), [
        start,
      ]);
    });
  });

  test('DURATION', () {
    expect(parseICalDuration('PT1H30M'), const Duration(minutes: 90));
    expect(parseICalDuration('P1W'), const Duration(days: 7));
    expect(parseICalDuration('-PT15M'), const Duration(minutes: -15));
    expect(parseICalDuration('P'), Duration.zero);
    expect(parseICalDuration('PT'), isNull);
    expect(parseICalDuration('nonsense'), isNull);
  });
}
