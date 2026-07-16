import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/system/models.dart';
import 'package:graceful_shell/system/process_reader.dart';

/// The arithmetic that turns two raw snapshots into table rows. No I/O — this is
/// exactly why the isolate returns raw counters and the store does the maths.
ProcessRaw raw({
  required int pid,
  String name = 'proc',
  int cpuTicks = 0,
  int starttime = 0,
  int rssKb = 0,
  String? cmdline = '/bin/proc',
}) {
  return ProcessRaw(
    pid: pid,
    name: name,
    ppid: 1,
    state: 'S',
    threads: 1,
    utimeTicks: cpuTicks,
    stimeTicks: 0,
    starttimeTicks: starttime,
    rssKb: rssKb,
    cmdline: cmdline,
  );
}

List<ProcessRow> compute({
  required List<ProcessRaw> current,
  required List<ProcessRaw> previous,
  int deltaTotalJiffies = 800,
  int coreCount = 4,
  double uptimeSeconds = 1000,
  CpuPercentMode mode = CpuPercentMode.machine,
  Map<int, String> cmdlineCache = const {},
}) {
  return computeProcessRows(
    current: current,
    previous: {for (final p in previous) p.pid: p},
    deltaTotalJiffies: deltaTotalJiffies,
    coreCount: coreCount,
    systemUptimeSeconds: uptimeSeconds,
    cmdlineCache: cmdlineCache,
    mode: mode,
  );
}

void main() {
  group('cpu percent', () {
    test('machine mode is the share of all cores, so rows sum to the total', () {
      // 200 of the machine's 800 jiffies over the interval: one core out of four
      // saturated, which is 25% of the machine.
      final rows = compute(
        previous: [raw(pid: 10, cpuTicks: 0)],
        current: [raw(pid: 10, cpuTicks: 200)],
      );

      expect(rows.single.cpuPercent, 25);
    });

    test('core mode is top-style, so a threaded process can exceed 100', () {
      final rows = compute(
        previous: [raw(pid: 10, cpuTicks: 0)],
        current: [raw(pid: 10, cpuTicks: 400)],
        mode: CpuPercentMode.core,
      );

      // Half the machine's jiffies on a 4-core box = two cores = 200%.
      expect(rows.single.cpuPercent, 200);
    });

    test('a process seen for the first time reports 0, not a lifetime average', () {
      final rows = compute(previous: [], current: [raw(pid: 10, cpuTicks: 5000)]);

      expect(rows.single.cpuPercent, 0);
    });

    test('a recycled PID does not inherit the old process\'s counters', () {
      // Same PID, different start time: the kernel handed 10 to something new.
      // Diffing against the old process would report a wildly negative or
      // enormous number depending on which had run longer.
      final rows = compute(
        previous: [raw(pid: 10, cpuTicks: 9000, starttime: 100)],
        current: [raw(pid: 10, cpuTicks: 5, starttime: 999)],
      );

      expect(rows.single.cpuPercent, 0);
    });

    test('a zero jiffy delta does not divide by zero', () {
      final rows = compute(
        previous: [raw(pid: 10, cpuTicks: 0)],
        current: [raw(pid: 10, cpuTicks: 200)],
        deltaTotalJiffies: 0,
      );

      expect(rows.single.cpuPercent, 0);
    });
  });

  test('a process that exited is dropped from the rows', () {
    final rows = compute(
      previous: [raw(pid: 10), raw(pid: 11)],
      current: [raw(pid: 10)],
    );

    expect(rows.map((r) => r.pid), [10]);
  });

  group('uptime', () {
    test('is system uptime minus the process start offset', () {
      // Started 400 seconds (40000 ticks at 100 Hz) after boot, on a machine
      // that has been up 1000 seconds.
      final rows = compute(
        previous: [],
        current: [raw(pid: 10, starttime: 40000)],
        uptimeSeconds: 1000,
      );

      expect(rows.single.uptime, const Duration(seconds: 600));
    });

    test('never goes negative when the samples race each other', () {
      final rows = compute(
        previous: [],
        current: [raw(pid: 10, starttime: 200000)],
        uptimeSeconds: 1000,
      );

      expect(rows.single.uptime, Duration.zero);
    });
  });

  group('cmdline', () {
    test('a skipped cmdline is filled in from the cache', () {
      final rows = compute(
        previous: [],
        current: [raw(pid: 10, cmdline: null)],
        cmdlineCache: {10: '/usr/bin/firefox -P'},
      );

      expect(rows.single.cmdline, '/usr/bin/firefox -P');
      expect(rows.single.isKernelThread, isFalse);
    });

    test('an empty cmdline is a kernel thread', () {
      final rows = compute(previous: [], current: [raw(pid: 2, cmdline: '')]);

      expect(rows.single.isKernelThread, isTrue);
    });
  });

  test('processStartTime resolves ticks-since-boot to a wall clock', () {
    final boot = DateTime(2026, 7, 14, 9, 0);

    // 60000 ticks at 100 Hz = 600 seconds = ten minutes after boot.
    expect(processStartTime(60000, boot), DateTime(2026, 7, 14, 9, 10));
  });
}
