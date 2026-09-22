import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/system/models.dart';
import 'package:moonswing/system/proc_reader.dart';

/// A fake `/proc` and `/sys` in a temp directory, so no test reads the real one.
void main() {
  late Directory proc;
  late Directory sys;

  setUp(() {
    proc = Directory.systemTemp.createTempSync('proc_reader_proc');
    sys = Directory.systemTemp.createTempSync('proc_reader_sys');
  });

  tearDown(() {
    proc.deleteSync(recursive: true);
    sys.deleteSync(recursive: true);
  });

  ProcReader reader() => ProcReader(procRoot: proc.path, sysRoot: sys.path);

  void write(String path, String contents) {
    final file = File('${proc.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  void writeThermalZone(String name, String type, int milliCelsius) {
    final zone = Directory('${sys.path}/class/thermal/$name')
      ..createSync(recursive: true);
    File('${zone.path}/type').writeAsStringSync('$type\n');
    File('${zone.path}/temp').writeAsStringSync('$milliCelsius\n');
  }

  group('readCpu', () {
    test('parses the aggregate line, the cores, and btime', () {
      write('stat', '''
cpu  100 20 30 400 10 0 5 0 0 0
cpu0 50 10 15 200 5 0 2 0 0 0
cpu1 50 10 15 200 5 0 3 0 0 0
intr 12345
btime 1700000000
''');

      final sample = reader().readCpu()!;

      expect(sample.coreCount, 2);
      // The aggregate must not be mistaken for a core: "cpu " and "cpu0" both
      // start with "cpu".
      expect(sample.aggregate.user, 100);
      expect(sample.cores[0].user, 50);
      expect(sample.bootTime,
          DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true)
              .toLocal());
    });

    test('counts iowait as idle and sums every column into the total', () {
      write('stat', 'cpu  10 0 0 80 10 0 0 0 0 0\n');
      final aggregate = reader().readCpu()!.aggregate;

      expect(aggregate.idle, 90); // idle 80 + iowait 10
      expect(aggregate.total, 100);
    });

    test('usage between two samples is the non-idle fraction', () {
      const prev = CpuTimes(user: 0, nice: 0, system: 0, idle: 0, total: 0);
      const curr = CpuTimes(user: 25, nice: 0, system: 0, idle: 75, total: 100);

      expect(CpuTimes.usageBetween(prev, curr), 25);
    });

    test('a missing /proc/stat returns null rather than throwing', () {
      expect(reader().readCpu(), isNull);
    });
  });

  group('readMemory', () {
    test('parses totals, swap, and the cache breakdown', () {
      write('meminfo', '''
MemTotal:       32000000 kB
MemFree:         2000000 kB
MemAvailable:   20000000 kB
Buffers:          500000 kB
Cached:          9000000 kB
SwapCached:            0 kB
SwapTotal:       8000000 kB
SwapFree:        7900000 kB
''');

      final memory = reader().readMemory();

      expect(memory.totalKb, 32000000);
      expect(memory.availableKb, 20000000);
      // Used is total minus *available*, not minus free: reclaimable page cache
      // is not memory the machine has committed.
      expect(memory.usedKb, 12000000);
      expect(memory.cachedKb, 9000000);
      expect(memory.swapUsedKb, 100000);
    });

    test('falls back when MemAvailable is absent (pre-3.14 kernels)', () {
      write('meminfo', '''
MemTotal:        1000 kB
MemFree:          200 kB
Buffers:          100 kB
Cached:           300 kB
''');

      expect(reader().readMemory().availableKb, 600);
    });

    test('a missing /proc/meminfo yields an empty sample, not a crash', () {
      final memory = reader().readMemory();
      expect(memory.totalKb, 0);
      expect(memory.usedFraction, 0);
    });
  });

  test('readLoad parses the three averages', () {
    write('loadavg', '1.23 0.90 0.75 2/1234 5678\n');
    final load = reader().readLoad()!;

    expect(load.one, 1.23);
    expect(load.fifteen, 0.75);
  });

  test('readUptimeSeconds takes the first field', () {
    write('uptime', '270040.12 1234567.89\n');
    expect(reader().readUptimeSeconds(), 270040.12);
  });

  test('readCpuModel takes the first model name', () {
    write('cpuinfo', '''
processor	: 0
model name	: AMD Ryzen 7 7840U w/ Radeon 780M Graphics
processor	: 1
model name	: AMD Ryzen 7 7840U w/ Radeon 780M Graphics
''');

    expect(reader().readCpuModel(),
        'AMD Ryzen 7 7840U w/ Radeon 780M Graphics');
  });

  group('readNet', () {
    test('sums every interface except loopback', () {
      write('net/dev', '''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets
    lo:  999999    1000    0    0    0     0          0         0  999999    1000
  eth0:    1000      10    0    0    0     0          0         0     500       5
 wlan0:    2000      20    0    0    0     0          0         0    1500      15
''');

      final net = reader().readNet()!;

      expect(net.rxBytes, 3000); // lo excluded
      expect(net.txBytes, 2000);
    });

    test('a counter reset reports zero, never a negative rate', () {
      const prev = NetSample(rxBytes: 5000, txBytes: 5000);
      const curr = NetSample(rxBytes: 100, txBytes: 100);

      final rate = computeNetRate(prev, curr, const Duration(seconds: 1));

      expect(rate.rxBytesPerSecond, 0);
    });

    test('rate is bytes over the elapsed interval', () {
      const prev = NetSample(rxBytes: 0, txBytes: 0);
      const curr = NetSample(rxBytes: 2048, txBytes: 1024);

      final rate = computeNetRate(prev, curr, const Duration(seconds: 2));

      expect(rate.rxBytesPerSecond, 1024);
      expect(rate.txBytesPerSecond, 512);
    });
  });

  group('readTemperatureCelsius', () {
    test('prefers a CPU package zone over an unrelated one', () {
      writeThermalZone('thermal_zone0', 'acpitz', 45000);
      writeThermalZone('thermal_zone1', 'x86_pkg_temp', 62000);

      expect(reader().readTemperatureCelsius(), 62.0);
    });

    test('falls back to the first zone when none look like a CPU', () {
      writeThermalZone('thermal_zone0', 'acpitz', 41000);

      expect(reader().readTemperatureCelsius(), 41.0);
    });

    test('a machine with no thermal zones returns null', () {
      expect(reader().readTemperatureCelsius(), isNull);
    });
  });
}
