import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/timers/timer_format.dart';

void main() {
  group('formatTimerDuration', () {
    test('pads minutes and seconds under an hour', () {
      expect(formatTimerDuration(Duration.zero), '00:00');
      expect(formatTimerDuration(const Duration(seconds: 5)), '00:05');
      expect(formatTimerDuration(const Duration(seconds: 65)), '01:05');
      expect(
        formatTimerDuration(const Duration(minutes: 59, seconds: 59)),
        '59:59',
      );
    });

    test('grows an hours field only once there is one', () {
      expect(formatTimerDuration(const Duration(hours: 1)), '1:00:00');
      expect(
        formatTimerDuration(const Duration(hours: 12, minutes: 3, seconds: 4)),
        '12:03:04',
      );
    });

    test('truncates sub-second remainders rather than rounding up', () {
      // A countdown parked at 4.9s must not read 00:05 for the whole of its
      // last second — the readout would then sit on 00:05 and jump to 00:00.
      expect(formatTimerDuration(const Duration(milliseconds: 4900)), '00:04');
    });

    test('reads a negative duration as zero, never as a minus sign', () {
      expect(formatTimerDuration(const Duration(seconds: -3)), '00:00');
    });
  });

  group('parseDurationInput', () {
    test('reads a bare number as minutes', () {
      expect(parseDurationInput('5'), const Duration(minutes: 5));
      expect(parseDurationInput(' 25 '), const Duration(minutes: 25));
    });

    test('reads the colon form', () {
      expect(
        parseDurationInput('1:30'),
        const Duration(minutes: 1, seconds: 30),
      );
      expect(parseDurationInput('90:00'), const Duration(minutes: 90));
      expect(
        parseDurationInput('1:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      expect(parseDurationInput(':30'), const Duration(seconds: 30));
    });

    test('bounds every colon group but the first', () {
      expect(parseDurationInput('5:90'), isNull);
      expect(parseDurationInput('1:60:00'), isNull);
      expect(parseDurationInput('1:2:3:4'), isNull);
    });

    test('reads the unit form, summing repeats', () {
      expect(parseDurationInput('90s'), const Duration(seconds: 90));
      expect(parseDurationInput('5m'), const Duration(minutes: 5));
      expect(
        parseDurationInput('1h30m'),
        const Duration(hours: 1, minutes: 30),
      );
      expect(
        parseDurationInput('1h 30m 10s'),
        const Duration(hours: 1, minutes: 30, seconds: 10),
      );
    });

    test('refuses input that is only partly a duration', () {
      expect(parseDurationInput('5 apples'), isNull);
      expect(parseDurationInput('abc'), isNull);
      expect(parseDurationInput('5x'), isNull);
      expect(parseDurationInput('m5'), isNull);
    });

    test('refuses empty, zero and out-of-range', () {
      expect(parseDurationInput(''), isNull);
      expect(parseDurationInput('   '), isNull);
      expect(parseDurationInput('0'), isNull);
      expect(parseDurationInput('0:00'), isNull);
      expect(parseDurationInput('100h'), isNull);
      expect(parseDurationInput('999999'), isNull);
    });

    test('accepts the cap itself', () {
      expect(parseDurationInput('99h'), kMaxTimerDuration);
    });
  });
}
