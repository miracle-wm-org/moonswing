import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/system/disk_reader.dart';
import 'package:graceful_shell/system/format.dart';
import 'package:graceful_shell/system/history.dart';

void main() {
  group('formatBytesKb', () {
    test('steps through the units at the right boundaries', () {
      expect(formatBytesKb(512), '512K');
      expect(formatBytesKb(1023), '1023K');
      expect(formatBytesKb(1024), '1.0M');
      expect(formatBytesKb(1024 * 1024), '1.0G');
    });
  });

  group('formatUptime', () {
    test('is days-aware', () {
      // The bug this replaces: the old helper capped at hours, so a browser open
      // for a week read as "147h".
      expect(formatUptime(const Duration(days: 6, hours: 3)), '6d 3h');
    });

    test('falls back through hours, minutes, seconds', () {
      expect(formatUptime(const Duration(hours: 4, minutes: 12)), '4h 12m');
      expect(formatUptime(const Duration(minutes: 2, seconds: 5)), '2m 5s');
      expect(formatUptime(const Duration(seconds: 9)), '9s');
    });
  });

  test('formatTemperature converts to Fahrenheit on request', () {
    expect(formatTemperature(54.4, 'celsius'), '54°C');
    expect(formatTemperature(100, 'fahrenheit'), '212°F');
  });

  test('formatRate reads as a throughput', () {
    expect(formatRate(1536), '1.5K/s');
  });

  group('HistoryBuffer', () {
    test('evicts the oldest past capacity, preserving order', () {
      final buffer = HistoryBuffer<int>(3);
      for (final n in [1, 2, 3, 4, 5]) {
        buffer.add(n);
      }

      expect(buffer.toList(), [3, 4, 5]);
      expect(buffer.length, 3);
    });

    test('resizing down keeps the newest samples', () {
      final buffer = HistoryBuffer<int>(5);
      for (final n in [1, 2, 3, 4, 5]) {
        buffer.add(n);
      }

      buffer.resize(2);

      expect(buffer.toList(), [4, 5]);
    });

    test('an empty buffer lists empty', () {
      expect(HistoryBuffer<int>(4).toList(), isEmpty);
    });
  });

  group('parseDfOutput', () {
    test('parses POSIX df output', () {
      final disks = parseDfOutput('''
Filesystem     1B-blocks         Used    Available Capacity Mounted on
/dev/nvme0n1p2 1000000000    412000000    588000000      41% /
/dev/nvme0n1p1  500000000     88000000    412000000      18% /home
''');

      expect(disks.length, 2);
      expect(disks.first.mountPoint, '/');
      expect(disks.first.usedBytes, 412000000);
      expect(disks.first.usedFraction, closeTo(0.412, 0.001));
    });

    test('a mount point containing spaces is not truncated', () {
      // The mount point is the last column and df does not quote it, so it must
      // be taken as the remainder of the line rather than as one field.
      final disks = parseDfOutput('''
Filesystem 1B-blocks Used Available Capacity Mounted on
/dev/sdb1     100 50 50 50% /media/My Backup Drive
''');

      expect(disks.single.mountPoint, '/media/My Backup Drive');
    });

    test('zero-sized and malformed rows are dropped', () {
      final disks = parseDfOutput('''
Filesystem 1B-blocks Used Available Capacity Mounted on
none 0 0 0 - /proc
garbage
/dev/sda1 100 50 50 50% /
''');

      expect(disks.map((d) => d.mountPoint), ['/']);
    });
  });
}
