// The battery module's pure half: which shipped icon a reading picks, the text
// beside it, and the equality the store's "nothing new" guard rests on.

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/modules/battery.dart';

BatteryReading _reading(int capacity, {bool charging = false, String? time}) =>
    BatteryReading(capacity: capacity, charging: charging, time: time);

void main() {
  group('batteryIconFor', () {
    test('charging is the plug, whatever the level', () {
      for (final capacity in [0, 42, 100]) {
        expect(
          batteryIconFor(_reading(capacity, charging: true)),
          ShellGlyph.plug,
        );
      }
    });

    test('otherwise the level, in five steps', () {
      expect(batteryIconFor(_reading(100)), ShellGlyph.batteryFull);
      expect(batteryIconFor(_reading(90)), ShellGlyph.batteryFull);
      expect(
          batteryIconFor(_reading(89)), ShellGlyph.batteryThreeQuarters);
      expect(
          batteryIconFor(_reading(65)), ShellGlyph.batteryThreeQuarters);
      expect(batteryIconFor(_reading(64)), ShellGlyph.batteryHalf);
      expect(batteryIconFor(_reading(40)), ShellGlyph.batteryHalf);
      expect(batteryIconFor(_reading(39)), ShellGlyph.batteryQuarter);
      expect(batteryIconFor(_reading(15)), ShellGlyph.batteryQuarter);
      expect(batteryIconFor(_reading(14)), ShellGlyph.batteryEmpty);
      expect(batteryIconFor(_reading(0)), ShellGlyph.batteryEmpty);
    });

    test('no emoji is left in the rendering', () {
      final label = batteryLabelFor(_reading(50, time: '1:30'));
      expect(label.contains('🔋'), isFalse);
      expect(label.contains('🔌'), isFalse);
    });
  });

  group('batteryLabelFor', () {
    test('a bare percentage when no estimate stands', () {
      expect(batteryLabelFor(_reading(72)), '72%');
      expect(batteryLabelFor(_reading(72, charging: true)), '72%');
    });

    test('the estimate says which direction it runs', () {
      expect(
        batteryLabelFor(_reading(72, time: '1:05')),
        '72% (1:05 remaining)',
      );
      expect(
        batteryLabelFor(_reading(72, charging: true, time: '0:20')),
        '72% (0:20 until full)',
      );
    });
  });

  group('BatteryReading', () {
    test('equality covers everything the bar renders', () {
      expect(_reading(50, time: '1:00'), _reading(50, time: '1:00'));
      expect(
        _reading(50, time: '1:00').hashCode,
        _reading(50, time: '1:00').hashCode,
      );
      expect(_reading(50, time: '1:00'), isNot(_reading(51, time: '1:00')));
      expect(_reading(50, time: '1:00'), isNot(_reading(50, time: '1:01')));
      expect(
        _reading(50, time: '1:00'),
        isNot(_reading(50, charging: true, time: '1:00')),
      );
    });
  });
}
