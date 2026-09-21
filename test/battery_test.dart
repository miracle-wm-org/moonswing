// The battery module's pure half: which shipped icon a reading picks, the text
// beside it, and the equality the store's "nothing new" guard rests on.

import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/modules/battery.dart';

BatteryReading _reading(int capacity, {bool charging = false, String? time}) =>
    BatteryReading(capacity: capacity, charging: charging, time: time);

void main() {
  group('batteryIconFor', () {
    test('charging is the plug, whatever the level', () {
      for (final capacity in [0, 42, 100]) {
        expect(
          batteryIconFor(_reading(capacity, charging: true)),
          FontAwesomeIcons.plug,
        );
      }
    });

    test('otherwise the level, in five steps', () {
      expect(batteryIconFor(_reading(100)), FontAwesomeIcons.batteryFull);
      expect(batteryIconFor(_reading(90)), FontAwesomeIcons.batteryFull);
      expect(
          batteryIconFor(_reading(89)), FontAwesomeIcons.batteryThreeQuarters);
      expect(
          batteryIconFor(_reading(65)), FontAwesomeIcons.batteryThreeQuarters);
      expect(batteryIconFor(_reading(64)), FontAwesomeIcons.batteryHalf);
      expect(batteryIconFor(_reading(40)), FontAwesomeIcons.batteryHalf);
      expect(batteryIconFor(_reading(39)), FontAwesomeIcons.batteryQuarter);
      expect(batteryIconFor(_reading(15)), FontAwesomeIcons.batteryQuarter);
      expect(batteryIconFor(_reading(14)), FontAwesomeIcons.batteryEmpty);
      expect(batteryIconFor(_reading(0)), FontAwesomeIcons.batteryEmpty);
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
