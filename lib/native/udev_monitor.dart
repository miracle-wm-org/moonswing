import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:moonswing/native/ffi_util.dart';
import 'package:moonswing/native/glib_source.dart';

typedef _UdevNewC = ffi.Pointer<ffi.Void> Function();
typedef _UnrefC = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>);
typedef _MonitorNewC = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void> udev, ffi.Pointer<Utf8> name);
typedef _AddMatchC = ffi.Int32 Function(ffi.Pointer<ffi.Void> monitor,
    ffi.Pointer<Utf8> subsystem, ffi.Pointer<Utf8> devtype);
typedef _AddMatchDart = int Function(ffi.Pointer<ffi.Void> monitor,
    ffi.Pointer<Utf8> subsystem, ffi.Pointer<Utf8> devtype);
typedef _MonitorIntC = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _MonitorIntDart = int Function(ffi.Pointer<ffi.Void>);

class _Libudev {
  _Libudev(ffi.DynamicLibrary lib)
      : newContext = lib.lookupFunction<_UdevNewC, _UdevNewC>('udev_new'),
        unref = lib.lookupFunction<_UnrefC, _UnrefC>('udev_unref'),
        monitorNew = lib.lookupFunction<_MonitorNewC, _MonitorNewC>(
            'udev_monitor_new_from_netlink'),
        addMatch = lib.lookupFunction<_AddMatchC, _AddMatchDart>(
            'udev_monitor_filter_add_match_subsystem_devtype'),
        enableReceiving = lib.lookupFunction<_MonitorIntC, _MonitorIntDart>(
            'udev_monitor_enable_receiving'),
        getFd = lib.lookupFunction<_MonitorIntC, _MonitorIntDart>(
            'udev_monitor_get_fd'),
        receive = lib.lookupFunction<_UnrefC, _UnrefC>(
            'udev_monitor_receive_device'),
        deviceUnref = lib.lookupFunction<_UnrefC, _UnrefC>('udev_device_unref'),
        monitorUnref =
            lib.lookupFunction<_UnrefC, _UnrefC>('udev_monitor_unref');

  final _UdevNewC newContext;
  final _UnrefC unref;
  final _MonitorNewC monitorNew;
  final _AddMatchDart addMatch;
  final _MonitorIntDart enableReceiving;
  final _MonitorIntDart getFd;
  final _UnrefC receive;
  final _UnrefC deviceUnref;
  final _UnrefC monitorUnref;

  static final _Libudev? instance = () {
    final lib = openFirstLibrary(const ['libudev.so.1', 'libudev.so']);
    return lib == null ? null : _Libudev(lib);
  }();
}

/// Reports udev events on [subsystems] — a kernel attribute changing under
/// `/sys/class/<subsystem>` — on the Dart thread.
///
/// Read through a GLib fd watch on the monitor's netlink socket, draining it on
/// every wakeup, rather than `package:udev`'s `monitorDevices`: that one polls
/// the socket from a second isolate and receives on this one, so between the
/// poll firing and this isolate getting round to the read the socket stays
/// readable and the poll loop spins, posting a message per iteration. One
/// backlight write queued tens of thousands of them here, and the shell froze
/// until it had answered every one.
///
/// [onEvent] runs once per wakeup however many events were drained — every
/// caller re-reads sysfs rather than looking at the event — and also on a
/// wakeup that drained nothing (an overflowed socket reports an error), since
/// a lost event is exactly when a re-read is owed.
///
/// Throws when libudev is missing, the monitor cannot be set up, or there is
/// no GLib main loop to watch it on (`flutter_tester`); callers treat any of
/// those as "not watched".
class UdevMonitor {
  UdevMonitor({
    required List<String> subsystems,
    required void Function() onEvent,
  }) : _onEvent = onEvent {
    final lib = _Libudev.instance;
    if (lib == null) throw StateError('libudev is not installed');
    _lib = lib;

    final udev = lib.newContext();
    if (udev == ffi.nullptr) throw StateError('udev_new failed');
    _udev = udev;
    try {
      final monitor = using((arena) {
        final m = lib.monitorNew(udev, 'udev'.toNativeUtf8(allocator: arena));
        if (m == ffi.nullptr) {
          throw StateError('udev_monitor_new_from_netlink failed');
        }
        _monitor = m;
        for (final subsystem in subsystems) {
          final res = lib.addMatch(
              m, subsystem.toNativeUtf8(allocator: arena), ffi.nullptr);
          if (res < 0) throw StateError('udev filter failed ($res)');
        }
        return m;
      });
      final res = lib.enableReceiving(monitor);
      if (res < 0) throw StateError('udev_monitor_enable_receiving ($res)');
      _watch = GlibFdWatch(lib.getFd(monitor), _onReady);
    } catch (_) {
      _release();
      rethrow;
    }
  }

  final void Function() _onEvent;
  late final _Libudev _lib;
  ffi.Pointer<ffi.Void> _udev = ffi.nullptr;
  ffi.Pointer<ffi.Void> _monitor = ffi.nullptr;
  GlibFdWatch? _watch;

  void _onReady(int condition) {
    final monitor = _monitor;
    if (monitor == ffi.nullptr) return;
    // The socket is non-blocking: this returns null once it is empty.
    while (true) {
      final device = _lib.receive(monitor);
      if (device == ffi.nullptr) break;
      _lib.deviceUnref(device);
    }
    if (condition & GlibFdWatch.gIoHup != 0) {
      // A hung-up socket stays "ready" forever; watching it would spin.
      _watch?.dispose();
      _watch = null;
    }
    _onEvent();
  }

  void dispose() => _release();

  void _release() {
    _watch?.dispose();
    _watch = null;
    if (_monitor != ffi.nullptr) {
      _lib.monitorUnref(_monitor);
      _monitor = ffi.nullptr;
    }
    if (_udev != ffi.nullptr) {
      _lib.unref(_udev);
      _udev = ffi.nullptr;
    }
  }
}
