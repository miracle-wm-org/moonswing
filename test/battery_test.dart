// The battery module: which shipped icon a reading picks, the bar's text, the
// sums and words behind the popup, the store's two tiers, and the popup itself.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/modules/battery.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/config.dart';

BatteryReading _reading(int capacity, {bool charging = false}) =>
    BatteryReading(capacity: capacity, charging: charging);

/// A pack at [now] of [full] µWh, moving at [rate] µW.
BatterySample _sample(
  String status, {
  String name = 'BAT0',
  int now = 50000000,
  int full = 100000000,
  int? design,
  int? rate,
  int? cycles,
}) =>
    BatterySample(
      name: name,
      status: status,
      now: now,
      full: full,
      fullDesign: design,
      rate: rate,
      cycleCount: cycles,
    );

/// Writes a `power_supply` directory with one battery called [name] holding
/// [files], plus a mains adapter the store must not mistake for one.
Directory _sysfs(Map<String, Map<String, String>> packs) {
  final root = Directory.systemTemp.createTempSync('battery_test');
  Directory('${root.path}/AC').createSync();
  File('${root.path}/AC/type').writeAsStringSync('Mains\n');
  packs.forEach((name, files) {
    Directory('${root.path}/$name').createSync();
    File('${root.path}/$name/type').writeAsStringSync('Battery\n');
    files.forEach((file, value) {
      File('${root.path}/$name/$file').writeAsStringSync('$value\n');
    });
  });
  return root;
}

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
  });

  group('batteryLabelFor', () {
    test('the bar shows the level and nothing else', () {
      expect(batteryLabelFor(_reading(72)), '72%');
      expect(batteryLabelFor(_reading(72, charging: true)), '72%');
    });

    test('no emoji is left in the rendering', () {
      final label = batteryLabelFor(_reading(50));
      expect(label.contains('🔋'), isFalse);
      expect(label.contains('🔌'), isFalse);
    });
  });

  group('BatteryReading', () {
    test('equality covers everything the bar renders', () {
      expect(_reading(50), _reading(50));
      expect(_reading(50).hashCode, _reading(50).hashCode);
      expect(_reading(50), isNot(_reading(51)));
      expect(_reading(50), isNot(_reading(50, charging: true)));
    });
  });

  group('summariseBatteries', () {
    test('discharging: the time until empty, and the draw', () {
      final summary = summariseBatteries(
        [_sample('Discharging', rate: 20000000)],
      );
      expect(summary.reading, _reading(50));
      expect(summary.details.state, BatteryChargeState.discharging);
      // 50 Wh at 20 W.
      expect(summary.details.timeLeft, const Duration(hours: 2, minutes: 30));
      expect(summary.details.watts, 20.0);
    });

    test('charging: the time until full', () {
      final summary = summariseBatteries(
        [_sample('Charging', now: 75000000, rate: 50000000)],
      );
      expect(summary.reading, _reading(75, charging: true));
      expect(summary.details.state, BatteryChargeState.charging);
      expect(summary.details.timeLeft, const Duration(minutes: 30));
    });

    test('a rate signed negative is still a rate', () {
      final summary = summariseBatteries(
        [_sample('Discharging', rate: -10000000)],
      );
      expect(summary.details.timeLeft, const Duration(hours: 5));
      expect(summary.details.watts, 10.0);
    });

    test('a minute that rounds up carries into the hour', () {
      // 1.999 h used to print as 1:60.
      final summary = summariseBatteries(
        [_sample('Discharging', now: 1999, full: 4000, rate: 1000)],
      );
      expect(summary.details.timeLeft, const Duration(hours: 2));
    });

    test('idle on the charger has no estimate and no draw', () {
      final full = summariseBatteries(
        [_sample('Full', now: 100000000, rate: 0)],
      );
      expect(full.details.state, BatteryChargeState.full);
      expect(full.details.timeLeft, isNull);
      expect(full.details.watts, isNull);

      final held = summariseBatteries(
        [_sample('Not charging', now: 80000000, rate: 1000000)],
      );
      expect(held.details.state, BatteryChargeState.notCharging);
      expect(held.details.timeLeft, isNull);
      expect(held.details.watts, isNull);
    });

    test('one pack discharging while another charges is discharging', () {
      final summary = summariseBatteries([
        _sample('Discharging', name: 'BAT0', rate: 10000000),
        _sample('Charging', name: 'BAT1', rate: 10000000),
      ]);
      expect(summary.reading.charging, isFalse);
      expect(summary.details.state, BatteryChargeState.discharging);
    });

    test('health is wear against design; a cycle count of 0 is absent', () {
      final pack = summariseBatteries([
        _sample('Discharging', full: 87000000, design: 100000000, cycles: 0),
      ]).details.packs.single;
      expect(pack.health, 87);
      expect(pack.cycles, isNull);
    });

    test('a charge-based pack needs a voltage for its watts', () {
      const sample = BatterySample(
        name: 'BAT0',
        status: 'Discharging',
        now: 2000000,
        full: 4000000,
        rate: 1000000,
        voltage: 12000000,
        energyBased: false,
      );
      expect(sample.watts, 12.0);
      expect(
        const BatterySample(name: 'BAT0', rate: 1000000, energyBased: false)
            .watts,
        isNull,
      );
    });
  });

  group('the popup text', () {
    test('formatBatteryDuration', () {
      expect(formatBatteryDuration(const Duration(minutes: 45)), '45 min');
      expect(
        formatBatteryDuration(const Duration(hours: 2, minutes: 5)),
        '2 h 05 min',
      );
    });

    test('the status line says which way the estimate runs', () {
      expect(
        batteryStatusLine(summariseBatteries(
          [_sample('Discharging', rate: 20000000)],
        ).details),
        'Discharging · 2 h 30 min remaining',
      );
      expect(
        batteryStatusLine(summariseBatteries(
          [_sample('Charging', now: 75000000, rate: 50000000)],
        ).details),
        'Charging · 30 min until full',
      );
      expect(
        batteryStatusLine(summariseBatteries([_sample('Full')]).details),
        'Fully charged',
      );
    });

    test('one pack is described without a heading', () {
      final rows = batteryDetailRows(summariseBatteries([
        _sample('Discharging',
            rate: 8400000, full: 90000000, design: 100000000, cycles: 312),
      ]).details);
      expect(rows, const [
        BatteryDetailRow('Power draw', '8.4 W'),
        BatteryDetailRow('Health', '90%'),
        BatteryDetailRow('Cycles', '312'),
      ]);
    });

    test('several packs each get a heading and their own charge', () {
      final rows = batteryDetailRows(summariseBatteries([
        _sample('Charging', name: 'BAT0', now: 20000000, rate: 5000000),
        _sample('Charging', name: 'BAT1', now: 80000000, rate: 5000000),
      ]).details);
      expect(rows, const [
        BatteryDetailRow('Charging at', '10.0 W'),
        BatteryDetailRow.heading('BAT0'),
        BatteryDetailRow('Charge', '20%'),
        BatteryDetailRow.heading('BAT1'),
        BatteryDetailRow('Charge', '80%'),
      ]);
    });
  });

  group('BatteryStore', () {
    late Directory root;

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('reads the pack and its descriptive files from sysfs', () {
      root = _sysfs({
        'BAT0': {
          'status': 'Discharging',
          'energy_now': '30000000',
          'energy_full': '60000000',
          'energy_full_design': '64000000',
          'power_now': '12000000',
          'cycle_count': '41',
          'manufacturer': 'SMP',
          'model_name': '5B10W13930',
          'technology': 'Li-poly',
        },
      });
      final store = BatteryStore.forTesting(sysfsRoot: root.path);
      addTearDown(store.dispose);

      store.acquire();
      expect(store.hasBattery, isTrue);
      expect(store.reading, _reading(50));
      // No popup, no details.
      expect(store.details, isNull);

      store.acquireDetail();
      final details = store.details!;
      expect(details.timeLeft, const Duration(hours: 2, minutes: 30));
      expect(details.watts, 12.0);
      expect(
        details.packs.single,
        const BatteryPackInfo(
          name: 'BAT0',
          capacity: 50,
          health: 94,
          cycles: 41,
          model: 'SMP 5B10W13930',
          technology: 'Li-poly',
        ),
      );

      store.releaseDetail();
      expect(store.details, isNull);
      store.release();
    });

    test('a detail lease taken mid-build notifies nobody', () {
      root = _sysfs({
        'BAT0': {
          'status': 'Discharging',
          'energy_now': '30000000',
          'energy_full': '60000000',
          'power_now': '12000000',
        },
      });
      final store = BatteryStore.forTesting(sysfsRoot: root.path);
      addTearDown(store.dispose);
      store.acquire();

      var bars = 0;
      var popups = 0;
      store.addListener(() => bars++);
      store.detailChanges.addListener(() => popups++);

      // The level moved between the bar's poll and the popup opening: the
      // popup still sees it, and the bars hear of it on the next poll rather
      // than mid-build.
      File('${root.path}/BAT0/energy_now').writeAsStringSync('24000000\n');
      store.acquireDetail();
      expect(store.details!.reading, _reading(40));
      expect(bars, 0);
      expect(popups, 0);

      store.releaseDetail();
      store.release();
    });
  });

  group('the bar and the popup', () {
    late Directory root;

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    testWidgets('the popup carries the estimate and the details',
        (tester) async {
      root = _sysfs({
        'BAT0': {
          'status': 'Discharging',
          'energy_now': '30000000',
          'energy_full': '60000000',
          'energy_full_design': '64000000',
          'power_now': '12000000',
          'technology': 'Li-ion',
        },
      });
      final store = BatteryStore.forTesting(sysfsRoot: root.path);
      store.acquire();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: Align(
              alignment: Alignment.topLeft,
              child: BatteryPopup(store: store),
            ),
          ),
        ),
      );

      expect(find.text('50%'), findsOneWidget);
      expect(
        find.text('Discharging · 2 h 30 min remaining'),
        findsOneWidget,
      );
      expect(find.text('Power draw'), findsOneWidget);
      expect(find.text('12.0 W'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);
      expect(find.text('94%'), findsOneWidget);
      expect(find.text('Li-ion'), findsOneWidget);

      // Closing the popup gives the detail lease back.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(store.details, isNull);

      store.release();
      store.dispose();
    });
  });
}
