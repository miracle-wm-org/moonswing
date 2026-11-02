import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/modules/clock.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/timers/timer_store.dart';

import 'glyph_finder.dart';

void main() {
  // A Monday afternoon, in ISO week 45.
  final monday = DateTime(2026, 11, 2, 14, 5, 9);

  group('[modules.clock] display keys', () {
    test('default to the date and the time, as the bar always showed', () {
      const config = ClockConfig();
      expect(config.showWeekday, isFalse);
      expect(config.showDate, isTrue);
      expect(config.showYear, isFalse);
      expect(config.showWeekNumber, isFalse);
      expect(config.showTime, isTrue);
      expect(config.showSeconds, isFalse);
      expect(config.hourFormat, ClockHourFormat.h24);
      expect(ClockConfig.fromMap(null), config);
      expect(ClockConfig.fromMap(const {}), config);
      expect(clockParts(config, monday), ['Nov 2', '14:05']);
    });

    test('every key is read', () {
      final config = ClockConfig.fromMap(const {
        'show_weekday': true,
        'show_date': false,
        'show_year': true,
        'show_week_number': true,
        'show_time': false,
        'show_seconds': true,
        'hour_format': '12',
      });
      expect(config.showWeekday, isTrue);
      expect(config.showDate, isFalse);
      expect(config.showYear, isTrue);
      expect(config.showWeekNumber, isTrue);
      expect(config.showTime, isFalse);
      expect(config.showSeconds, isTrue);
      expect(config.hourFormat, ClockHourFormat.h12);
      expect(config, isNot(const ClockConfig()));
    });

    test('a wrongly typed or unknown value costs that key alone', () {
      final config = ClockConfig.fromMap(const {
        'show_weekday': 'yes',
        'show_year': true,
        'hour_format': 'metric',
      });
      expect(config.showWeekday, isFalse);
      expect(config.showYear, isTrue, reason: 'the good key survives');
      expect(config.hourFormat, ClockHourFormat.h24);
    });

    test('hour_format takes the spellings a hand-edited file uses', () {
      for (final raw in <Object>['12', '12h', '12H', ' 12 ', 12]) {
        expect(ClockHourFormat.parse(raw), ClockHourFormat.h12, reason: '$raw');
      }
      for (final raw in <Object>['24', '24h', 24]) {
        expect(ClockHourFormat.parse(raw), ClockHourFormat.h24, reason: '$raw');
      }
      expect(ClockHourFormat.parse(13), isNull);
      expect(ClockHourFormat.parse(null), isNull);
      expect(ClockHourFormat.parse(12.0), isNull);
    });
  });

  group('clockParts', () {
    test('everything on, in order', () {
      const config = ClockConfig(
        showWeekday: true,
        showYear: true,
        showWeekNumber: true,
        showSeconds: true,
      );
      expect(clockParts(config, monday), [
        'Mon',
        'Nov 2',
        '2026',
        'W45',
        '14:05:09',
      ]);
    });

    test('any part can be switched off on its own', () {
      expect(clockParts(const ClockConfig(showDate: false), monday), ['14:05']);
      expect(clockParts(const ClockConfig(showTime: false), monday), ['Nov 2']);
      expect(
        clockParts(
          const ClockConfig(showDate: false, showYear: true, showTime: false),
          monday,
        ),
        ['2026'],
      );
    });

    test('seconds mean nothing without the time', () {
      const config = ClockConfig(showTime: false, showSeconds: true);
      expect(config.showsSeconds, isFalse);
      expect(clockParts(config, monday), ['Nov 2']);
    });

    test('every part off is an empty readout', () {
      const config = ClockConfig(showDate: false, showTime: false);
      expect(config.showsNothing, isTrue);
      expect(clockParts(config, monday), isEmpty);
    });

    test('the 12-hour clock', () {
      const config = ClockConfig(
        showDate: false,
        hourFormat: ClockHourFormat.h12,
      );
      String at(int hour, [int minute = 0]) =>
          clockParts(config, DateTime(2026, 11, 2, hour, minute)).single;
      expect(at(0), '12:00 AM');
      expect(at(0, 30), '12:30 AM');
      expect(at(9, 5), '9:05 AM');
      expect(at(12), '12:00 PM');
      expect(at(14, 5), '2:05 PM');
      expect(at(23, 59), '11:59 PM');
      expect(
        clockParts(
          const ClockConfig(
            showDate: false,
            showSeconds: true,
            hourFormat: ClockHourFormat.h12,
          ),
          monday,
        ),
        ['2:05:09 PM'],
      );
    });

    test('the 24-hour clock pads the hour', () {
      expect(
        clockParts(
          const ClockConfig(showDate: false),
          DateTime(2026, 11, 2, 7, 3),
        ),
        ['07:03'],
      );
    });

    test('the week number is padded to two digits', () {
      expect(
        clockParts(
          const ClockConfig(
            showDate: false,
            showWeekNumber: true,
            showTime: false,
          ),
          DateTime(2026, 1, 28),
        ),
        ['W05'],
      );
    });
  });

  group('isoWeekNumber', () {
    test('weeks start on Monday', () {
      expect(isoWeekNumber(DateTime(2026, 11, 1)), 44); // Sunday
      expect(isoWeekNumber(DateTime(2026, 11, 2)), 45); // Monday
      expect(isoWeekNumber(DateTime(2026, 11, 8)), 45); // Sunday
    });

    test('the first week holds the year\'s first Thursday', () {
      // 2026 starts on a Thursday, so it has 53 weeks and 1 January 2027, a
      // Friday, is still in the last of them.
      expect(isoWeekNumber(DateTime(2026, 1, 1)), 1);
      expect(isoWeekNumber(DateTime(2025, 12, 29)), 1);
      expect(isoWeekNumber(DateTime(2026, 12, 31)), 53);
      expect(isoWeekNumber(DateTime(2027, 1, 1)), 53);
      expect(isoWeekNumber(DateTime(2027, 1, 4)), 1);
      // 2021 starts on a Friday: its first days are in 2020's week 53.
      expect(isoWeekNumber(DateTime(2021, 1, 3)), 53);
      expect(isoWeekNumber(DateTime(2021, 1, 4)), 1);
      // 2024 ends on a Tuesday in 2025's first week.
      expect(isoWeekNumber(DateTime(2024, 12, 31)), 1);
    });

    test('a daylight-saving change cannot drop a day', () {
      // The time of day is ignored, so late on a short day is no different.
      expect(isoWeekNumber(DateTime(2026, 3, 29, 23, 59)), 13);
      expect(isoWeekNumber(DateTime(2026, 10, 25, 23, 59)), 43);
    });
  });

  group('the bar', () {
    Widget host(ClockConfig config, TimersStore timers) => Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: const ThemeConfig(),
        child: Center(
          child: Clock(config: config, timers: timers),
        ),
      ),
    );

    testWidgets('with every part off, shows a clock glyph to click', (
      tester,
    ) async {
      final timers = TimersStore.forTesting();
      addTearDown(timers.dispose);
      await tester.pumpWidget(
        host(const ClockConfig(showDate: false, showTime: false), timers),
      );
      expect(findGlyph(ShellGlyph.clock), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('an edit to the config shows at once', (tester) async {
      final timers = TimersStore.forTesting();
      addTearDown(timers.dispose);
      await tester.pumpWidget(host(const ClockConfig(showTime: false), timers));
      expect(find.byType(Text), findsOneWidget);
      expect(findGlyph(ShellGlyph.clock), findsNothing);

      await tester.pumpWidget(
        host(const ClockConfig(showWeekday: true, showTime: false), timers),
      );
      expect(find.byType(Text), findsNWidgets(2));
    });
  });
}
