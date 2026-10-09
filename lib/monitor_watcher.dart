import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'package:moonswing/native/ffi_util.dart';

typedef _GdkDisplayGetNMonitorsC = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _GdkDisplayGetNMonitorsDart = int Function(ffi.Pointer<ffi.Void>);
typedef _GdkDisplayGetMonitorC = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _GdkDisplayGetMonitorDart = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>, int);

/// Every signal watched here has the shape `void (gpointer, gpointer, gpointer)`.
typedef _SignalC = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>);

/// Watches the default GDK display for monitors being plugged in, unplugged or
/// moved, and invokes [onChanged] whenever any of that happens.
///
/// GDK emits `monitor-added` / `monitor-removed` as the compositor advertises or
/// drops `wl_output`s. Callers re-enumerate with `listMonitors()` rather than
/// relying on the (possibly already-invalidated) `GdkMonitor` pointer the signal
/// passes.
///
/// A *move* is `notify::geometry` on the monitor itself, and is watched too,
/// because which monitors get surfaces depends on where they are: mirrored
/// displays share an origin and only one of them is given any (see
/// `distinctMonitors`). Cloning or un-cloning a display adds and removes no
/// monitor, and the shell's own `wl_output` listener is a different Wayland
/// connection from GDK's, so it can fire before GDK has heard of the move —
/// leaving an un-mirrored display with no bar until the next reconfigure.
class MonitorWatcher {
  MonitorWatcher(this.onChanged) {
    try {
      final display = gdkDisplayGetDefault();
      if (display.address == 0) return;

      // Looked up before anything is connected: a handler left behind by a
      // throw would outlive the callable [dispose] closes under it.
      final nMonitors = processLibrary.lookupFunction<_GdkDisplayGetNMonitorsC,
          _GdkDisplayGetNMonitorsDart>('gdk_display_get_n_monitors');
      final getMonitor = processLibrary.lookupFunction<_GdkDisplayGetMonitorC,
          _GdkDisplayGetMonitorDart>('gdk_display_get_monitor');

      // Every argument is ignored but `monitor-added`'s monitor, which is
      // watched for moves; callers just re-sync.
      _removedCallback = ffi.NativeCallable<_SignalC>.isolateLocal(_onRemoved);
      _addedCallback = ffi.NativeCallable<_SignalC>.isolateLocal(_onAdded);
      _geometryCallback =
          ffi.NativeCallable<_SignalC>.isolateLocal(_onGeometry);

      _connect(display, 'monitor-added', _addedCallback!);
      _connect(display, 'monitor-removed', _removedCallback!);
      for (var i = 0; i < nMonitors(display); i++) {
        final monitor = getMonitor(display, i);
        if (monitor.address != 0) _watchGeometry(monitor);
      }
    } catch (_) {
      // Missing symbols (e.g. an unexpected GDK build) just mean no hotplug
      // support — the shell still runs with whatever monitors it started with.
      dispose();
    }
  }

  /// Invoked on the platform thread whenever a monitor is added, removed or
  /// moved.
  final void Function() onChanged;

  ffi.NativeCallable<_SignalC>? _removedCallback;
  ffi.NativeCallable<_SignalC>? _addedCallback;
  ffi.NativeCallable<_SignalC>? _geometryCallback;

  /// Interned once per name rather than per connection, since a monitor's
  /// `notify::geometry` is connected again for every hotplug.
  final Map<String, ffi.Pointer<Utf8>> _signalNames = {};

  void _connect(ffi.Pointer<ffi.Void> instance, String signal,
      ffi.NativeCallable<_SignalC> callback) {
    gSignalConnectData(
      instance,
      _signalNames.putIfAbsent(signal, () => signal.toNativeUtf8()),
      callback.nativeFunction.cast(),
      ffi.nullptr,
      ffi.nullptr,
      0,
    );
  }

  /// The handler goes when the monitor is finalized, so an unplugged one needs
  /// no disconnecting.
  void _watchGeometry(ffi.Pointer<ffi.Void> monitor) {
    if (_geometryCallback case final callback?) {
      _connect(monitor, 'notify::geometry', callback);
    }
  }

  void _onRemoved(ffi.Pointer<ffi.Void> display, ffi.Pointer<ffi.Void> monitor,
      ffi.Pointer<ffi.Void> userData) {
    onChanged();
  }

  /// `monitor-added`: the second argument is the new `GdkMonitor`, live for the
  /// length of the emission, which is all connecting to it needs.
  void _onAdded(ffi.Pointer<ffi.Void> display, ffi.Pointer<ffi.Void> monitor,
      ffi.Pointer<ffi.Void> userData) {
    if (monitor.address != 0) _watchGeometry(monitor);
    onChanged();
  }

  /// `notify::geometry`: `(GdkMonitor*, GParamSpec*, gpointer)`.
  void _onGeometry(ffi.Pointer<ffi.Void> monitor, ffi.Pointer<ffi.Void> pspec,
      ffi.Pointer<ffi.Void> userData) {
    onChanged();
  }

  /// Releases the native callbacks and the interned signal-name strings. The
  /// signal handlers themselves live as long as the display and its monitors,
  /// which is the whole process lifetime, so there is nothing else to
  /// disconnect.
  void dispose() {
    _removedCallback?.close();
    _removedCallback = null;
    _addedCallback?.close();
    _addedCallback = null;
    _geometryCallback?.close();
    _geometryCallback = null;
    for (final name in _signalNames.values) {
      malloc.free(name);
    }
    _signalNames.clear();
  }
}
