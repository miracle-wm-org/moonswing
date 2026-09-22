import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moonswing/config_reader.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/scopes.dart';
import 'package:udev/udev.dart';

class BatteryConfig {
  final int pollSeconds;

  const BatteryConfig({this.pollSeconds = 30});

  factory BatteryConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BatteryConfig();
    return BatteryConfig(
      pollSeconds: map.intOr('poll_seconds', 30),
    );
  }
}

/// One reading of the pack, as the bar renders it.
///
/// The store publishes this rather than the line of text it used to compose,
/// so the glyph is the widget's decision and the arithmetic is the store's —
/// and so a reading can be compared: `==` is what lets a poll that found
/// nothing new stay silent (see [BatteryStore._readBattery]).
@immutable
class BatteryReading {
  const BatteryReading({
    required this.capacity,
    required this.charging,
    this.time,
  });

  /// Charge across every battery in the machine, 0-100.
  final int capacity;

  /// On mains and filling — not merely "not discharging", which is what a
  /// laptop sitting at 100% on the charger reports.
  final bool charging;

  /// `h:mm` until full or until empty, when the rate files gave one; null
  /// while idle, and null rather than a figure the estimate cannot support.
  final String? time;

  @override
  bool operator ==(Object other) =>
      other is BatteryReading &&
      other.capacity == capacity &&
      other.charging == charging &&
      other.time == time;

  @override
  int get hashCode => Object.hash(capacity, charging, time);
}

/// The glyph for [reading], from the icon font the shell already ships.
///
/// Charging is the plug, which is what the emoji before it said. Anything else
/// is the level itself: the one battery emoji was the same picture for a full
/// pack and a dying one, and five steps is what an icon set can say instead.
FaIconData batteryIconFor(BatteryReading reading) {
  if (reading.charging) return FontAwesomeIcons.plug;
  if (reading.capacity >= 90) return FontAwesomeIcons.batteryFull;
  if (reading.capacity >= 65) return FontAwesomeIcons.batteryThreeQuarters;
  if (reading.capacity >= 40) return FontAwesomeIcons.batteryHalf;
  if (reading.capacity >= 15) return FontAwesomeIcons.batteryQuarter;
  return FontAwesomeIcons.batteryEmpty;
}

/// The text beside [batteryIconFor]'s glyph.
String batteryLabelFor(BatteryReading reading) {
  final time = reading.time;
  if (time == null) return '${reading.capacity}%';
  return reading.charging
      ? '${reading.capacity}% ($time until full)'
      : '${reading.capacity}% ($time remaining)';
}

/// The battery reading for the whole shell.
///
/// The singleton-`ChangeNotifier` shape with `SystemStatsStore`'s lease rule: the
/// store reads `/sys/class/power_supply` and holds the udev subscription only
/// while at least one widget holds a lease. A two-monitor setup used to run one
/// timer and one udev watch per bar.
class BatteryStore extends ChangeNotifier {
  BatteryStore._();

  static final BatteryStore instance = BatteryStore._();

  @visibleForTesting
  factory BatteryStore.forTesting({
    BatteryConfig config = const BatteryConfig(),
  }) {
    final store = BatteryStore._();
    store.configure(config);
    return store;
  }

  BatteryConfig _config = const BatteryConfig();

  /// Applies [config]; the module's `fromMap` pushes it here. A cadence change
  /// while leased restarts the timer at the new interval.
  void configure(BatteryConfig config) {
    final cadenceChanged = config.pollSeconds != _config.pollSeconds;
    _config = config;
    if (cadenceChanged && _timer != null) {
      _stopTimer();
      _startTimer();
    }
  }

  // --- published state -----------------------------------------------------

  BatteryReading? _reading;

  /// The last reading, or null until the first one lands.
  BatteryReading? get reading => _reading;

  bool _hasBattery = false;
  bool get hasBattery => _hasBattery;

  // --- polling state -------------------------------------------------------

  int _leases = 0;
  Timer? _timer;
  StreamSubscription<UdevDevice>? _udevSubscription;

  /// Battery paths never change while the shell runs (a hotplugged battery is
  /// a laptop being reassembled), so detection runs once, on the first lease
  /// ever — re-running it would duplicate the paths.
  bool _detected = false;
  final List<String> _batteryPaths = [];

  /// Take a lease. The first active lease detects batteries, starts the udev
  /// watch, starts polling, and reads immediately so the bar never waits a
  /// full interval for its first reading.
  void acquire() {
    _leases++;
    if (_timer != null) return;
    if (!_detected) {
      _detected = true;
      _detectBatteries();
    }
    if (_hasBattery) _monitorPowerSupply();
    _startTimer();
    _readBattery();
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases == 0) {
      _stopTimer();
      _udevSubscription?.cancel();
      _udevSubscription = null;
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(
      Duration(seconds: _config.pollSeconds),
      (_) => _readBattery(),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _detectBatteries() {
    try {
      final dir = Directory('/sys/class/power_supply');
      if (!dir.existsSync()) return;

      for (final entry in dir.listSync()) {
        final typeFile = File('${entry.path}/type');
        if (typeFile.existsSync()) {
          final type = typeFile.readAsStringSync().trim();
          if (type == 'Battery') {
            _batteryPaths.add(entry.path);
          }
        }
      }

      _hasBattery = _batteryPaths.isNotEmpty;
    } catch (_) {
      // No battery available
    }
  }

  void _monitorPowerSupply() {
    if (_udevSubscription != null) return;
    try {
      final context = UdevContext();
      _udevSubscription =
          context.monitorDevices(subsystems: ['power_supply']).listen((_) {
        _readBattery();
      });
    } catch (_) {
      // udev monitoring unavailable, fall back to polling only
    }
  }

  void _readBattery() {
    if (_batteryPaths.isEmpty) return;

    try {
      int totalEnergyNow = 0;
      int totalEnergyFull = 0;
      int totalRate = 0;
      bool anyCharging = false;
      bool anyDischarging = false;

      for (final path in _batteryPaths) {
        final status = _readFile('$path/status');
        if (status == 'Charging') anyCharging = true;
        if (status == 'Discharging') anyDischarging = true;

        // Try energy-based files first (µWh / µW)
        var now = _readFileInt('$path/energy_now');
        var full = _readFileInt('$path/energy_full');
        var rate = _readFileInt('$path/power_now');

        // Fall back to charge-based files (µAh / µA)
        if (now == null || full == null) {
          now = _readFileInt('$path/charge_now');
          full = _readFileInt('$path/charge_full');
          rate = _readFileInt('$path/current_now');
        }

        if (now != null) totalEnergyNow += now;
        if (full != null) totalEnergyFull += full;
        if (rate != null) totalRate += rate;
      }

      final capacity = totalEnergyFull > 0
          ? (totalEnergyNow * 100 / totalEnergyFull).round()
          : 0;

      final String? timeStr;
      if (totalRate > 0 && (anyCharging || anyDischarging)) {
        final double hours;
        if (anyCharging && !anyDischarging) {
          hours = (totalEnergyFull - totalEnergyNow) / totalRate;
        } else {
          hours = totalEnergyNow / totalRate;
        }

        if (hours >= 0 && hours <= 100) {
          final h = hours.floor();
          final m = ((hours - h) * 60).round();
          timeStr = '$h:${m.toString().padLeft(2, '0')}';
        } else {
          timeStr = null;
        }
      } else {
        timeStr = null;
      }

      final reading = BatteryReading(
        capacity: capacity,
        charging: anyCharging && !anyDischarging,
        time: timeStr,
      );

      // Every bar on every monitor listens, and udev speaks up for any change
      // in the subsystem — a charger's own current included. A reading that
      // renders identically is not news.
      if (reading == _reading) return;
      _reading = reading;
      notifyListeners();
    } catch (_) {
      // Silently fail
    }
  }

  String _readFile(String path) {
    return File(path).readAsStringSync().trim();
  }

  int? _readFileInt(String path) {
    try {
      return int.tryParse(File(path).readAsStringSync().trim());
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _stopTimer();
    _udevSubscription?.cancel();
    super.dispose();
  }
}

class Battery extends StatefulWidget {
  const Battery({super.key});

  @override
  BatteryState createState() => BatteryState();
}

class BatteryState extends State<Battery> {
  final BatteryStore _store = BatteryStore.instance;

  @override
  void initState() {
    super.initState();
    _store.acquire();
  }

  @override
  void dispose() {
    _store.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final reading = _store.reading;
        if (!_store.hasBattery || reading == null) {
          return const SizedBox.shrink();
        }

        final theme = ThemeScope.of(context);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              batteryIconFor(reading),
              size: 12,
              color: theme.foreground,
            ),
            const SizedBox(width: 4),
            Text(
              batteryLabelFor(reading),
              style: TextStyle(fontSize: 16, color: theme.foreground),
            ),
          ],
        );
      },
    );
  }
}

final Module batteryModule = Module.simple<BatteryConfig>(
  configKey: 'battery',
  fromMap: (map) {
    final config = BatteryConfig.fromMap(map);
    // The store, not the widget, owns the config: polling continues across
    // widget rebuilds, and every bar instance shares the one poller.
    BatteryStore.instance.configure(config);
    return config;
  },
  builder: (context, config) => const Battery(),
);
