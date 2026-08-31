import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/system/disk_reader.dart';
import 'package:graceful_shell/system/models.dart';
import 'package:graceful_shell/system/proc_reader.dart';
import 'package:graceful_shell/system/process_sampler.dart';
import 'package:graceful_shell/system/system_monitor_config.dart';
import 'package:graceful_shell/system/system_stats_store.dart';

/// Counts walks and answers from memory, so no test spawns an isolate or reads
/// the real `/proc`.
class FakeSampler implements ProcessSampler {
  FakeSampler([this.processes = const []]);

  List<ProcessRaw> processes;
  int sampleCount = 0;
  Set<int> lastSkipSet = const {};

  @override
  Future<List<ProcessRaw>> sample(Set<int> skipCmdlineFor) async {
    sampleCount++;
    lastSkipSet = skipCmdlineFor;
    return processes;
  }
}

ProcessRaw fakeProcess({
  int pid = 10,
  String name = 'firefox',
  int threads = 1,
  String? cmdline = '/usr/bin/firefox',
}) {
  return ProcessRaw(
    pid: pid,
    name: name,
    ppid: 1,
    state: 'S',
    threads: threads,
    utimeTicks: 0,
    stimeTicks: 0,
    starttimeTicks: 0,
    rssKb: 100,
    cmdline: cmdline,
  );
}

void main() {
  late Directory proc;
  late Directory sys;

  void writeCpu({required int user, required int idle}) {
    File('${proc.path}/stat').writeAsStringSync(
      'cpu  $user 0 0 $idle 0 0 0 0 0 0\n'
      'cpu0 $user 0 0 $idle 0 0 0 0 0 0\n'
      'btime 1700000000\n',
    );
  }

  setUp(() {
    proc = Directory.systemTemp.createTempSync('stats_store_proc');
    sys = Directory.systemTemp.createTempSync('stats_store_sys');
    writeCpu(user: 0, idle: 0);
    File('${proc.path}/meminfo')
        .writeAsStringSync('MemTotal: 1000 kB\nMemAvailable: 400 kB\n');
    File('${proc.path}/uptime').writeAsStringSync('1000.0 900.0\n');
  });

  tearDown(() {
    proc.deleteSync(recursive: true);
    sys.deleteSync(recursive: true);
  });

  SystemStatsStore build({
    FakeSampler? sampler,
    SystemMonitorConfig config = const SystemMonitorConfig(),
  }) {
    final store = SystemStatsStore.forTesting(
      reader: ProcReader(procRoot: proc.path, sysRoot: sys.path),
      sampler: sampler ?? FakeSampler(),
      // The real DiskReader forks `df`; no test should touch the actual machine.
      disks: DiskReader(runner: (_, _) async => ProcessResult(0, 0, '', '')),
      config: config,
    );
    addTearDown(store.dispose);
    return store;
  }

  group('leases', () {
    test('nothing polls until somebody asks for data', () {
      final store = build();

      expect(store.isPolling, isFalse);
      expect(store.hasData, isFalse);
    });

    test('a light lease does not trigger the expensive process walk', () async {
      // The point of splitting the leases: the bar module wants CPU and memory,
      // and must not pay for a walk of every process in /proc to get them.
      final sampler = FakeSampler([fakeProcess()]);
      final store = build(sampler: sampler);

      store.acquireLight();
      await store.tickForTesting();

      expect(store.isPolling, isTrue);
      expect(store.hasData, isTrue);
      expect(sampler.sampleCount, 0);
      expect(store.processes, isEmpty);
    });

    test('a detail lease samples processes at once, without waiting a poll',
        () async {
      final sampler = FakeSampler([fakeProcess(threads: 4)]);
      final store = build(sampler: sampler);

      store.acquireDetail();
      await Future<void>.delayed(Duration.zero);

      expect(sampler.sampleCount, 1);
      expect(store.processes.single.name, 'firefox');
      expect(store.threadCount, 4);
    });

    test('releasing the last lease stops polling', () async {
      final store = build();

      store.acquireLight();
      expect(store.isPolling, isTrue);

      store.releaseLight();

      // No timer means a hidden tab cannot keep walking /proc — the whole reason
      // the leases exist, given the overlay's IndexedStack keeps tabs alive.
      expect(store.isPolling, isFalse);
    });

    test('leases are refcounted: one of two releases keeps polling', () async {
      // Two monitors each carry the bar module. One panel going away must not
      // blind the other.
      final store = build();

      store.acquireLight();
      store.acquireLight();
      store.releaseLight();

      expect(store.isPolling, isTrue);

      store.releaseLight();
      expect(store.isPolling, isFalse);
    });

    test('the detail walk stops when only a light lease remains', () async {
      final sampler = FakeSampler([fakeProcess()]);
      final store = build(sampler: sampler);

      store.acquireLight();
      store.acquireDetail();
      await store.tickForTesting();
      final whileVisible = sampler.sampleCount;

      // The user switched to the Settings tab.
      store.releaseDetail();
      await store.tickForTesting();

      expect(store.isPolling, isTrue); // the bar still wants its numbers
      expect(sampler.sampleCount, whileVisible); // but nothing walks /proc
    });
  });

  group('cpu', () {
    test('is the busy fraction between two /proc/stat readings', () async {
      final store = build();
      store.acquireLight(); // seeds the baseline at 0/0

      writeCpu(user: 25, idle: 75);
      await store.tickForTesting();

      expect(store.cpuPercent, 25);
    });

    test('the first poll after a lease plants no sample in the history',
        () async {
      // With no baseline there is no real delta, and recording one would put a
      // 0% spike on the front of every graph.
      final store = build();

      store.acquireLight();
      expect(store.history, isEmpty);

      writeCpu(user: 50, idle: 50);
      await store.tickForTesting();

      expect(store.history.length, 1);
      expect(store.history.single.cpuPercent, 50);
    });
  });

  test('the cmdline cache tells the sampler what it can skip', () async {
    final sampler = FakeSampler([fakeProcess(pid: 10)]);
    final store = build(sampler: sampler);

    store.acquireDetail();
    await Future<void>.delayed(Duration.zero);
    await store.tickForTesting();

    // Having read it once, the store never asks again — a command line does not
    // change for the life of a process.
    expect(sampler.lastSkipSet, contains(10));
  });

  test('the cmdline cache drops processes that have exited', () async {
    final sampler = FakeSampler([fakeProcess(pid: 10), fakeProcess(pid: 11)]);
    final store = build(sampler: sampler);

    store.acquireDetail();
    await Future<void>.delayed(Duration.zero);

    sampler.processes = [fakeProcess(pid: 10)];
    // The skip set is captured before the walk, so the eviction lands at the end
    // of this tick and is visible to the next one.
    await store.tickForTesting();
    await store.tickForTesting();

    // Otherwise the cache grows without bound on a machine churning short-lived
    // processes.
    expect(sampler.lastSkipSet, isNot(contains(11)));
    expect(sampler.lastSkipSet, contains(10));
  });

  group('history', () {
    test('is capped at history_samples', () async {
      final store = build(config: const SystemMonitorConfig(historySamples: 10));
      store.acquireLight();

      for (var i = 1; i <= 25; i++) {
        writeCpu(user: i, idle: 100 - i);
        await store.tickForTesting();
      }

      expect(store.historyCapacity, 10);
      expect(store.history.length, 10);
    });

    test('shrinking the capacity keeps the newest samples', () async {
      final store = build(config: const SystemMonitorConfig(historySamples: 60));
      store.acquireLight();
      for (var i = 0; i < 5; i++) {
        await store.tickForTesting();
      }

      store.configure(const SystemMonitorConfig(historySamples: 3));

      expect(store.history.length, 3);
    });
  });

  test('memory is published from /proc/meminfo', () async {
    final store = build();
    store.acquireLight();
    await store.tickForTesting();

    expect(store.memory.totalKb, 1000);
    expect(store.memory.usedKb, 600);
  });

  test('config is clamped, so a poll_seconds of 0 cannot spin the shell', () {
    final config = SystemMonitorConfig.fromMap({'poll_seconds': 0});
    expect(config.pollSeconds, 1);
  });
}
