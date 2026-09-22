import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/overlay/calendar/month.dart';

void main() {
  group('daysInMonth', () {
    test('handles leap years', () {
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2025, 2), 28);
      expect(daysInMonth(2000, 2), 29);
      expect(daysInMonth(2100, 2), 28);
    });

    test('handles 30- and 31-day months', () {
      expect(daysInMonth(2026, 1), 31);
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 12), 31);
    });
  });

  group('addMonths', () {
    test('lands on the first, never overflowing a short month', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
      expect(addMonths(DateTime(2026, 3, 15), -1), DateTime(2026, 2, 1));
    });

    test('rolls across year boundaries', () {
      expect(addMonths(DateTime(2026, 12, 5), 1), DateTime(2027, 1, 1));
      expect(addMonths(DateTime(2026, 1, 5), -1), DateTime(2025, 12, 1));
    });
  });

  group('buildMonthGrid', () {
    test('always returns exactly 42 days', () {
      for (var month = 1; month <= 12; month++) {
        expect(buildMonthGrid(2026, month).days, hasLength(42));
      }
    });

    test('leading reflects the weekday the month starts on', () {
      // 1 July 2026 is a Wednesday.
      expect(DateTime(2026, 7, 1).weekday, DateTime.wednesday);
      expect(buildMonthGrid(2026, 7).leading, 3); // Sun, Mon, Tue
      expect(buildMonthGrid(2026, 7, weekStart: DateTime.monday).leading, 2);
    });

    test('a Sunday-starting month has no leading days when weeks start Sunday', () {
      // 1 February 2026 is a Sunday.
      expect(DateTime(2026, 2, 1).weekday, DateTime.sunday);
      expect(buildMonthGrid(2026, 2).leading, 0);
      expect(buildMonthGrid(2026, 2, weekStart: DateTime.monday).leading, 6);
    });

    test('isInMonth marks exactly the in-month cells', () {
      final grid = buildMonthGrid(2026, 7);
      final inMonth = [
        for (var i = 0; i < 42; i++)
          if (grid.isInMonth(i)) grid.days[i],
      ];
      expect(inMonth, hasLength(31));
      expect(inMonth.first, DateTime(2026, 7, 1));
      expect(inMonth.last, DateTime(2026, 7, 31));
      expect(inMonth.every((d) => d.month == 7), isTrue);
    });

    test('days are strictly consecutive across every month 2020-2030', () {
      // Guards the DST hazard: building days with add(Duration(days: 1)) would
      // duplicate or skip a day around a clock change.
      for (var year = 2020; year <= 2030; year++) {
        for (var month = 1; month <= 12; month++) {
          final grid = buildMonthGrid(year, month);
          for (var i = 1; i < grid.days.length; i++) {
            final prev = grid.days[i - 1];
            final expected = DateTime(prev.year, prev.month, prev.day + 1);
            expect(grid.days[i], expected,
                reason: 'gap at index $i of $year-$month');
          }

          final inMonth = grid.days.where((d) => d.month == month && d.year == year);
          expect(inMonth, hasLength(daysInMonth(year, month)),
              reason: 'wrong in-month day count for $year-$month');
        }
      }
    });
  });

  test('isSameDay ignores the time of day', () {
    expect(isSameDay(DateTime(2026, 7, 13, 0, 1), DateTime(2026, 7, 13, 23, 59)),
        isTrue);
    expect(isSameDay(DateTime(2026, 7, 13), DateTime(2026, 7, 14)), isFalse);
  });
}
