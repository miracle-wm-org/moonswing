import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/overlay.dart';
import 'package:moonswing/overlay/system/overview_page.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/system/disk_reader.dart';
import 'package:moonswing/system/models.dart';
import 'package:moonswing/system/proc_reader.dart';
import 'package:moonswing/system/process_sampler.dart';
import 'package:moonswing/system/system_stats_store.dart';

class FakeSampler implements ProcessSampler {
  @override
  Future<List<ProcessRaw>> sample(Set<int> skipCmdlineFor) async => const [];
}

/// The overview lays a chart and a stack of bars inside `IntrinsicHeight` rows,
/// and *both* of those were originally built on a `LayoutBuilder` — which
/// reports no intrinsic dimensions and threw during layout, blanking the whole
/// page. Nothing in the store or the readers could have caught that, so the page
/// gets pumped for real.
void main() {
  late Directory proc;

  setUp(() {
    proc = Directory.systemTemp.createTempSync('overview');
    File('${proc.path}/stat').writeAsStringSync(
      'cpu  10 0 0 90 0 0 0 0 0 0\n'
      'cpu0 5 0 0 45 0 0 0 0 0 0\n'
      'cpu1 5 0 0 45 0 0 0 0 0 0\n'
      'btime 1700000000\n',
    );
    File('${proc.path}/meminfo').writeAsStringSync(
      'MemTotal: 1000 kB\nMemAvailable: 400 kB\n'
      'Cached: 200 kB\nSwapTotal: 500 kB\nSwapFree: 400 kB\n',
    );
    File('${proc.path}/uptime').writeAsStringSync('90000.0 80000.0\n');
    File('${proc.path}/loadavg').writeAsStringSync('1.20 0.90 0.75 1/100 2\n');
  });

  tearDown(() => proc.deleteSync(recursive: true));

  Future<SystemStatsStore> seededStore() async {
    final store = SystemStatsStore.forTesting(
      reader: ProcReader(procRoot: proc.path, sysRoot: proc.path),
      sampler: FakeSampler(),
      disks: DiskReader(
        runner: (_, _) async => ProcessResult(
          0,
          0,
          'Filesystem 1B-blocks Used Available Capacity Mounted on\n'
              '/dev/sda1 1000 400 600 40% /\n',
          '',
        ),
      ),
    );
    addTearDown(store.dispose);

    store.acquireDetail();
    await store.tickForTesting();
    store.releaseDetail();
    return store;
  }

  Future<void> pumpOverview(
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
              child: OverviewPage(store: store),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The tab's usable area inside the overlay panel, which is no longer a fixed
  /// box — it scales with the monitor between these two clamps.
  Size tabArea(Size panel) => Size(panel.width, panel.height - 76);

  testWidgets('every card lays out without throwing', (tester) async {
    await pumpOverview(tester, await seededStore());

    expect(tester.takeException(), isNull);
    // Headings are set as written now, not upper-cased by the card: they are
    // section headings above the surface rather than captions inside it.
    for (final card in ['CPU', 'Memory', 'Vitals', 'Network', 'Disks']) {
      expect(find.text(card), findsOneWidget, reason: '$card card is missing');
    }
  });

  testWidgets('shows the real figures, not placeholders', (tester) async {
    await pumpOverview(tester, await seededStore());

    // 600K used of 1000K, and one core per cpuN line.
    expect(find.textContaining('600K / 1000K'), findsOneWidget);
    expect(find.text('CPU0'), findsOneWidget);
    expect(find.text('CPU1'), findsOneWidget);
    expect(find.textContaining('1.20'), findsOneWidget); // load average
    expect(find.text('1d 1h'), findsOneWidget); // uptime, 90000s
    expect(find.text('/'), findsOneWidget); // the disk's mount point
  });

  testWidgets('lays out at both extremes of the responsive panel',
      (tester) async {
    // The overlay panel is no longer a fixed box: it scales with the monitor
    // between kOverlayPanelMinSize and kOverlayPanelMaxSize. The cards use
    // Expanded, but the vitals column and the core grid are fixed-width, so both
    // ends of that range get pumped.
    final store = await seededStore();

    // physicalSize is in device pixels and the test view's ratio defaults to 3,
    // so without this the surface would be a third of the size we ask for.
    tester.view.devicePixelRatio = 1.0;
    // Registered before the assertions, not after: a failing expect() would skip
    // the teardown and leak the resized view into every later test.
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final panel in [kOverlayPanelMinSize, kOverlayPanelMaxSize]) {
      tester.view.physicalSize = panel;
      await pumpOverview(tester, store, size: tabArea(panel));

      expect(tester.takeException(), isNull,
          reason: 'overview overflowed at $panel');
      expect(find.text('CPU'), findsOneWidget);

      // The page is taller than the shortest panel and the list is lazy, so
      // the last card has to be scrolled to rather than merely looked for —
      // asserting it was present would only have said it was above the fold.
      await tester.scrollUntilVisible(find.text('Disks'), 120);
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'overview overflowed at $panel once scrolled');
      expect(find.text('Disks'), findsOneWidget);
    }
  });

  testWidgets('a machine with no swap, sensors, or disks still renders',
      (tester) async {
    File('${proc.path}/meminfo')
        .writeAsStringSync('MemTotal: 1000 kB\nMemAvailable: 400 kB\n');
    final store = SystemStatsStore.forTesting(
      reader: ProcReader(procRoot: proc.path, sysRoot: proc.path),
      sampler: FakeSampler(),
      disks: DiskReader(runner: (_, _) async => ProcessResult(1, 1, '', '')),
    );
    addTearDown(store.dispose);
    store.acquireLight();
    await store.tickForTesting();
    store.releaseLight();

    await pumpOverview(tester, store);

    expect(tester.takeException(), isNull);
    expect(find.text('none'), findsOneWidget); // swap
    expect(find.text('No filesystems reported'), findsOneWidget);
  });
}
