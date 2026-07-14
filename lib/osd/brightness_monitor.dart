import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:udev/udev.dart';

/// Watches the display backlight and reports its level as a 0..1 fraction.
///
/// The kernel emits a udev `change` event on the `backlight` subsystem whenever
/// a device's brightness is written, so this is event-driven rather than polled
/// — the same approach the battery module takes with `power_supply`.
///
/// Machines with no backlight (desktops, external-only setups) have an empty
/// `/sys/class/backlight`; there [start] finds no device and the monitor stays
/// silent for the life of the process.
class BrightnessMonitor {
  BrightnessMonitor({String sysfsRoot = '/sys/class/backlight'})
      : _sysfsRoot = sysfsRoot;

  final String _sysfsRoot;

  final _controller = StreamController<double>.broadcast();
  StreamSubscription<UdevDevice>? _udevSubscription;

  Directory? _device;
  int _max = 0;

  /// Last value reported, so a udev event that does not actually move the
  /// brightness (the subsystem fires for other reasons too) is not forwarded.
  double? _last;

  /// Brightness levels as they change, in 0..1.
  Stream<double> get onChanged => _controller.stream;

  /// The brightness right now, or null when there is no usable backlight.
  double? get current => _last;

  /// Finds a backlight device, seeds [current] with its present level, and
  /// starts watching. The seed value is deliberately *not* emitted on
  /// [onChanged] — the shell must not flash an indicator at start-up.
  void start() {
    _device = _findDevice();
    if (_device == null) return;

    _max = _readInt('max_brightness') ?? 0;
    if (_max <= 0) {
      _device = null;
      return;
    }
    _last = _readLevel();

    try {
      _udevSubscription = UdevContext()
          .monitorDevices(subsystems: ['backlight'])
          .listen((_) => _emitIfChanged());
    } catch (_) {
      // udev monitoring unavailable; brightness simply won't be reported.
    }
  }

  void dispose() {
    _udevSubscription?.cancel();
    _controller.close();
  }

  /// Picks the first device under [_sysfsRoot]. Laptops overwhelmingly expose a
  /// single panel backlight; if a machine has several, the first is as good a
  /// choice as any and keeps this free of heuristics.
  Directory? _findDevice() {
    try {
      final root = Directory(_sysfsRoot);
      if (!root.existsSync()) return null;
      for (final entry in root.listSync()) {
        final device = Directory(entry.path);
        if (File('${device.path}/brightness').existsSync() &&
            File('${device.path}/max_brightness').existsSync()) {
          return device;
        }
      }
    } catch (_) {
      // Unreadable sysfs; treat as no backlight.
    }
    return null;
  }

  void _emitIfChanged() {
    final level = _readLevel();
    if (level == null || level == _last) return;
    _last = level;
    if (!_controller.isClosed) _controller.add(level);
  }

  double? _readLevel() {
    final raw = _readInt('brightness');
    if (raw == null || _max <= 0) return null;
    return (raw / _max).clamp(0.0, 1.0);
  }

  int? _readInt(String name) {
    final device = _device;
    if (device == null) return null;
    try {
      return int.tryParse(File('${device.path}/$name').readAsStringSync().trim());
    } catch (e) {
      debugPrint('Could not read backlight $name: $e');
      return null;
    }
  }
}
