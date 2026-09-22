import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/moon/moon_format.dart';

void main() {
  group('formatMoonTime', () {
    test('pads to HH:mm, like every other clock in the shell', () {
      expect(formatMoonTime(DateTime(2026, 8, 25, 5, 4)), '05:04');
      expect(formatMoonTime(DateTime(2026, 8, 25, 23, 59)), '23:59');
      expect(formatMoonTime(DateTime(2026, 8, 25)), '00:00');
    });
  });

  group('formatMoonDate', () {
    test('drops the year within the reference year and keeps it outside', () {
      final date = DateTime(2026, 8, 28);
      expect(formatMoonDate(date), '28 Aug');
      expect(formatMoonDate(date, reference: DateTime(2026, 1, 1)), '28 Aug');
      expect(
        formatMoonDate(date, reference: DateTime(2025, 12, 31)),
        '28 Aug 2026',
      );
    });
  });

  group('formatMoonCountdown', () {
    final now = DateTime(2026, 8, 25, 20, 0);

    test('counts calendar days once it is past midnight', () {
      // A full Moon at one in the morning is "tomorrow", not "in 5 hours" —
      // nobody planning an evening reads it the other way.
      expect(formatMoonCountdown(DateTime(2026, 8, 26, 1), now), 'tomorrow');
      expect(formatMoonCountdown(DateTime(2026, 8, 31, 4), now), 'in 6 days');
    });

    test('counts hours and minutes inside the day', () {
      expect(formatMoonCountdown(DateTime(2026, 8, 25, 23, 30), now),
          'in 3 hours');
      expect(formatMoonCountdown(DateTime(2026, 8, 25, 20, 40), now),
          'in 40 minutes');
      expect(formatMoonCountdown(DateTime(2026, 8, 25, 21, 5), now),
          'in an hour');
      expect(formatMoonCountdown(DateTime(2026, 8, 25, 20, 0, 30), now),
          'within the minute');
    });

    test('a moment already past reads as now, never as a negative', () {
      expect(formatMoonCountdown(DateTime(2026, 8, 25, 19), now), 'now');
    });
  });

  group('numbers', () {
    test('kilometres are grouped', () {
      expect(formatKilometres(384400), '384,400 km');
      expect(formatKilometres(356508.6), '356,509 km');
      expect(formatKilometres(999), '999 km');
      expect(formatKilometres(1000), '1,000 km');
    });

    test('light time is the distance in a unit that feels like one', () {
      expect(formatLightTime(384400), '1.28 light-seconds');
    });
  });
}
