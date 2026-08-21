import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';
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

class Battery extends StatefulWidget {
  const Battery({super.key, required this.config});

  final BatteryConfig config;

  @override
  BatteryState createState() => BatteryState();
}

class BatteryState extends State<Battery> {
  String _batteryText = '';
  bool _hasBattery = false;
  final List<String> _batteryPaths = [];
  Timer? _refreshTimer;
  StreamSubscription<UdevDevice>? _udevSubscription;

  @override
  void initState() {
    super.initState();
    _detectBatteries();
    _refreshTimer = Timer.periodic(
      Duration(seconds: widget.config.pollSeconds),
      (_) => _readBattery(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _udevSubscription?.cancel();
    super.dispose();
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

      if (_batteryPaths.isNotEmpty) {
        _hasBattery = true;
        _monitorPowerSupply();
        _readBattery();
      }
    } catch (_) {
      // No battery available
    }
  }

  void _monitorPowerSupply() {
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

      if (!mounted) return;
      setState(() {
        if (anyCharging && !anyDischarging) {
          _batteryText = timeStr != null
              ? '🔌 $capacity% ($timeStr until full)'
              : '🔌 $capacity%';
        } else if (anyDischarging) {
          _batteryText = timeStr != null
              ? '🔋 $capacity% ($timeStr remaining)'
              : '🔋 $capacity%';
        } else {
          _batteryText = '🔋 $capacity%';
        }
      });
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
  Widget build(BuildContext context) {
    if (!_hasBattery || _batteryText.isEmpty) return const SizedBox.shrink();

    return Text(
      _batteryText,
      style: TextStyle(fontSize: 16, color: ThemeScope.of(context).foreground),
    );
  }
}

class BatteryModule extends Module {
  BatteryConfig _config = const BatteryConfig();

  @override
  String get configKey => 'battery';

  @override
  void loadConfig(Map<String, dynamic>? map) {
    _config = BatteryConfig.fromMap(map);
  }

  @override
  WidgetBuilder get builder => (context) => Battery(config: _config);
}
