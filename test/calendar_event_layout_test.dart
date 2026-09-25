import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/overlay/calendar/event_layout.dart';

final DateTime day = DateTime(2026, 9, 25);

GoogleEvent at(
  String id,
  int hour,
  int minute,
  int length, {
  DateTime? on,
  bool allDay = false,
}) {
  final start = (on ?? day).add(Duration(hours: hour, minutes: minute));
  return GoogleEvent(
    id: id,
    calendarId: 'primary',
    summary: id,
    start: start,
    end: start.add(Duration(minutes: length)),
    allDay: allDay,
  );
}

Map<String, (int, int, int, int)> placed(List<GoogleEvent> events) => {
  for (final p in layoutDay(events, day))
    p.event.id: (p.top, p.bottom, p.column, p.columns),
};

void main() {
  group('layoutDay', () {
    test('an event on its own has the whole width', () {
      expect(placed([at('a', 10, 0, 30)]), {'a': (600, 630, 0, 1)});
    });

    test('overlapping events share the width, lanes reused', () {
      // a and b overlap; c overlaps b only; d starts once all are done.
      expect(
        placed([
          at('a', 9, 0, 60),
          at('b', 9, 30, 60),
          at('c', 10, 0, 30),
          at('d', 11, 0, 30),
        ]),
        {
          'a': (540, 600, 0, 2),
          'b': (570, 630, 1, 2),
          // a's lane is free again by ten.
          'c': (600, 630, 0, 2),
          'd': (660, 690, 0, 1),
        },
      );
    });

    test('a short event gets a box to click; one across midnight is cut', () {
      expect(placed([at('tiny', 12, 0, 0)])['tiny'], (720, 740, 0, 1));
      expect(placed([at('late', 23, 50, 5)])['late'], (
        1420,
        1440,
        0,
        1,
      ), reason: 'kept inside the day');
      expect(placed([at('night', -2, 0, 180)])['night'], (
        0,
        60,
        0,
        1,
      ), reason: 'the part before midnight is the day before\'s');
    });

    test('an event of a day or longer is a banner, not a box', () {
      expect(isTimedForGrid(at('a', 10, 0, 30)), isTrue);
      expect(isTimedForGrid(at('conf', 9, 0, 24 * 60 * 2)), isFalse);
      expect(isTimedForGrid(at('h', 0, 0, 24 * 60, allDay: true)), isFalse);
    });
  });

  group('labels', () {
    test('when an event happens', () {
      expect(
        eventWhenLabel(at('a', 10, 0, 30)),
        'Friday 25 September · 10:00–10:30',
      );
      expect(
        eventWhenLabel(at('late', 23, 0, 60)),
        'Friday 25 September · 23:00–00:00',
        reason: 'an end at midnight is still the same day',
      );
      expect(
        eventWhenLabel(at('h', 0, 0, 24 * 60, allDay: true)),
        'Friday 25 September · All day',
      );
      expect(
        eventWhenLabel(at('trip', 0, 0, 3 * 24 * 60, allDay: true)),
        'Friday 25 September – Sunday 27 September · All day',
      );
      expect(
        eventWhenLabel(at('overnight', 22, 0, 180)),
        'Friday 25 September 22:00 – Saturday 26 September 01:00',
      );
    });

    test('the part of an event on a given day', () {
      final overnight = at('o', 22, 0, 180);
      expect(eventTimeLabel(overnight, day), '22:00–…');
      expect(eventTimeLabel(overnight, DateTime(2026, 9, 26)), '…–01:00');
    });

    test('weeks', () {
      final monday = weekOf(day, DateTime.monday);
      expect(monday.first, DateTime(2026, 9, 21));
      expect(monday.last, DateTime(2026, 9, 27));
      expect(weekOf(day, DateTime.sunday).first, DateTime(2026, 9, 20));
      expect(weekRangeLabel(monday), '21 – 27 Sep 2026');
      expect(
        weekRangeLabel(weekOf(DateTime(2026, 10, 1), DateTime.monday)),
        '28 Sep – 4 Oct 2026',
      );
      expect(
        weekRangeLabel(weekOf(DateTime(2026, 1, 1), DateTime.monday)),
        '29 Dec 2025 – 4 Jan 2026',
      );
    });
  });
}
