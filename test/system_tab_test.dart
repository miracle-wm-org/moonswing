import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/overlay.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/system/process_table.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/system/disk_reader.dart';
import 'package:graceful_shell/system/models.dart';
import 'package:graceful_shell/system/proc_reader.dart';
import 'package:graceful_shell/system/process_killer.dart';
import 'package:graceful_shell/system/process_reader.dart';
import 'package:graceful_shell/system/process_sampler.dart';
import 'package:graceful_shell/system/system_monitor_config.dart';
import 'package:graceful_shell/system/system_stats_store.dart';

class FakeSampler implements ProcessSampler {
  FakeSampler(this.processes);

  final List<ProcessRaw> processes;

  @override
  Future<List<ProcessRaw>> sample(Set<int> skipCmdlineFor) async => processes;
}

/// Records what it was asked to kill instead of signalling anything.
class RecordingKiller implements ProcessKiller {
  final List<int> terminated = [];
  final List<int> forceKilled = [];
  KillOutcome outcome = KillOutcome.signalled;

  @override
  Future<KillOutcome> terminate(int pid, {required int expectedStarttimeTicks}) async {
    terminated.add(pid);
    return outcome;
  }

  @override
  Future<KillOutcome> forceKill(int pid, {required int expectedStarttimeTicks}) async {
    forceKilled.add(pid);
    return outcome;
  }

  @override
  bool isStillRunning(int pid, int expectedStarttimeTicks) => false;
}

ProcessRaw process({
  required int pid,
  required String name,
  int cpuTicks = 0,
  int rssKb = 0,
  int starttime = 0,
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
    cmdline: '/usr/bin/$name',
  );
}

void main() {
  late Directory proc;
  late RecordingKiller killer;

  setUp(() {
    proc = Directory.systemTemp.createTempSync('system_tab');
    File('${proc.path}/stat').writeAsStringSync(
      'cpu  0 0 0 0 0 0 0 0 0 0\ncpu0 0 0 0 0 0 0 0 0 0 0\nbtime 1700000000\n',
    );
    File('${proc.path}/meminfo')
        .writeAsStringSync('MemTotal: 1000000 kB\nMemAvailable: 400000 kB\n');
    File('${proc.path}/uptime').writeAsStringSync('100000.0 90000.0\n');
    killer = RecordingKiller();
  });

  tearDown(() => proc.deleteSync(recursive: true));

  /// A store fed from a fake /proc, already carrying one detail sample.
  Future<SystemStatsStore> storeWith(
    List<ProcessRaw> processes, {
    SystemMonitorConfig config = const SystemMonitorConfig(),
  }) async {
    final store = SystemStatsStore.forTesting(
      reader: ProcReader(procRoot: proc.path, sysRoot: proc.path),
      sampler: FakeSampler(processes),
      // Must be injected: the real DiskReader shells out to `df`, and a real
      // process never completes inside testWidgets' fake-async zone.
      disks: DiskReader(runner: (_, __) async => ProcessResult(0, 0, '', '')),
      killer: killer,
      config: config,
    );
    addTearDown(store.dispose);

    // Take the leases just long enough to publish one sample, then let go.
    // ProcessTable does not lease anything itself — SystemTab does — and a live
    // poll timer would trip testWidgets' pending-timer check.
    store.acquireDetail();
    await store.tickForTesting();
    store.releaseDetail();

    return store;
  }

  Future<void> pumpTable(
    WidgetTester tester,
    SystemStatsStore store, {
    Size size = const Size(800, 440),
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: ProcessTable(store: store),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The order the rows are actually laid out in, top to bottom.
  List<String> renderedOrder(WidgetTester tester, List<String> names) {
    final positions = {
      for (final name in names)
        name: tester.getTopLeft(find.text(name)).dy,
    };
    final sorted = names.toList()
      ..sort((a, b) => positions[a]!.compareTo(positions[b]!));
    return sorted;
  }

  testWidgets('sorts by CPU descending out of the box', (tester) async {
    final store = await storeWith([
      process(pid: 10, name: 'idle-thing', cpuTicks: 0),
      process(pid: 11, name: 'busy-thing', cpuTicks: 50),
    ]);
    await pumpTable(tester, store);

    // Both processes are new, so neither has a CPU baseline; the PID tiebreaker
    // is what gives a stable order at all. Sorting descending by (cpu, pid)
    // therefore puts the higher PID first.
    expect(renderedOrder(tester, ['idle-thing', 'busy-thing']),
        ['busy-thing', 'idle-thing']);
  });

  testWidgets('clicking a header sorts by it, and clicking again reverses',
      (tester) async {
    final store = await storeWith([
      process(pid: 10, name: 'alpha'),
      process(pid: 11, name: 'zulu'),
    ]);
    await pumpTable(tester, store);

    await tester.tap(find.text('NAME'));
    await tester.pump();
    expect(renderedOrder(tester, ['alpha', 'zulu']), ['alpha', 'zulu']);

    await tester.tap(find.text('NAME'));
    await tester.pump();
    expect(renderedOrder(tester, ['alpha', 'zulu']), ['zulu', 'alpha']);
  });

  testWidgets('sorts by memory', (tester) async {
    final store = await storeWith([
      process(pid: 10, name: 'small', rssKb: 100),
      process(pid: 11, name: 'large', rssKb: 900000),
    ]);
    await pumpTable(tester, store);

    await tester.tap(find.text('MEMORY'));
    await tester.pump();

    expect(renderedOrder(tester, ['small', 'large']), ['large', 'small']);
  });

  testWidgets('lays out at both extremes of the responsive panel',
      (tester) async {
    // The columns are fixed-width and only the name column flexes, so the
    // narrowest panel is where the row would overflow if the widths grew.
    final store = await storeWith([process(pid: 3412, name: 'firefox')]);

    // physicalSize is in device pixels and the test view's ratio defaults to 3,
    // so without this the surface would be a third of the size we ask for.
    tester.view.devicePixelRatio = 1.0;
    // Registered before the assertions, not after: a failing expect() would skip
    // the teardown and leak the resized view into every later test.
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final panel in [kOverlayPanelMinSize, kOverlayPanelMaxSize]) {
      tester.view.physicalSize = panel;
      await pumpTable(tester, store,
          size: Size(panel.width, panel.height - 76));

      expect(tester.takeException(), isNull,
          reason: 'process table overflowed at $panel');
      expect(find.text('firefox'), findsOneWidget);
    }
  });

  testWidgets('the filter narrows the table', (tester) async {
    final store = await storeWith([
      process(pid: 10, name: 'firefox'),
      process(pid: 11, name: 'systemd'),
    ]);
    await pumpTable(tester, store);

    expect(find.text('systemd'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'fire');
    await tester.pump();

    expect(find.text('firefox'), findsOneWidget);
    expect(find.text('systemd'), findsNothing);
  });

  testWidgets('kernel threads are hidden unless asked for', (tester) async {
    final withThread = [
      process(pid: 10, name: 'firefox'),
      ProcessRaw(
        pid: 2,
        name: 'kthreadd',
        ppid: 0,
        state: 'S',
        threads: 1,
        utimeTicks: 0,
        stimeTicks: 0,
        starttimeTicks: 0,
        rssKb: 0,
        cmdline: '', // no command line at all — that is what makes it a kernel thread
      ),
    ];

    await pumpTable(tester, await storeWith(withThread));
    expect(find.text('kthreadd'), findsNothing);

    await pumpTable(
      tester,
      await storeWith(withThread,
          config: const SystemMonitorConfig(showKernelThreads: true)),
    );
    expect(find.text('kthreadd'), findsOneWidget);
  });

  testWidgets('clicking a row reveals its detail', (tester) async {
    final store = await storeWith([process(pid: 3412, name: 'firefox')]);
    await pumpTable(tester, store);

    expect(find.text('/usr/bin/firefox'), findsNothing);

    await tester.tap(find.text('firefox'));
    await tester.pump();

    expect(find.text('/usr/bin/firefox'), findsOneWidget);
    expect(find.textContaining('sleeping'), findsOneWidget);
  });

  group('kill', () {
    /// Hovers the row, which is what reveals its kill button, then taps it.
    Future<void> tapKill(WidgetTester tester, String name) async {
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text(name)));
      await tester.pump();

      // FaIcon is not a Material Icon, so find.byIcon does not see it.
      await tester.tap(find.byWidgetPredicate((w) =>
          w is SettingsIconButton && w.icon == FontAwesomeIcons.xmark));
      await tester.pump();
    }

    testWidgets('confirms before signalling anything', (tester) async {
      final store = await storeWith([process(pid: 3412, name: 'firefox')]);
      await pumpTable(tester, store);

      await tapKill(tester, 'firefox');

      // Nothing has been signalled yet — the card is only asking.
      expect(killer.terminated, isEmpty);
      expect(find.text('Quit firefox?'), findsOneWidget);

      await tester.tap(find.text('Quit'));
      await tester.pump();

      expect(killer.terminated, [3412]);
    });

    testWidgets('cancelling signals nothing', (tester) async {
      final store = await storeWith([process(pid: 3412, name: 'firefox')]);
      await pumpTable(tester, store);

      await tapKill(tester, 'firefox');
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(killer.terminated, isEmpty);
      expect(find.text('Quit firefox?'), findsNothing);
    });

    testWidgets('a permission failure is explained rather than swallowed',
        (tester) async {
      killer.outcome = KillOutcome.permissionDenied;
      final store = await storeWith([process(pid: 812, name: 'nginx')]);
      await pumpTable(tester, store);

      await tapKill(tester, 'nginx');
      await tester.tap(find.text('Quit'));
      await tester.pump();

      // A row that just sits there unchanged reads as a bug in the shell.
      expect(find.textContaining('permission denied'), findsOneWidget);
    });

    testWidgets('confirm_kill = false signals straight away', (tester) async {
      final store = await storeWith(
        [process(pid: 3412, name: 'firefox')],
        config: const SystemMonitorConfig(confirmKill: false),
      );
      await pumpTable(tester, store);

      await tapKill(tester, 'firefox');

      expect(find.text('Quit firefox?'), findsNothing);
      expect(killer.terminated, [3412]);
    });
  });
}
