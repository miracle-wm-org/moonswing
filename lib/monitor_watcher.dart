import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

// Raw GLib/GDK symbols. GTK is already linked into the process (Flutter's Linux
// embedder pulls it in and gtk-layer-shell links against it), so the symbols
// resolve from the running process rather than a separately-opened library —
// the same approach `layer_shell`'s `GdkMonitor.getConnector` uses.
final ffi.DynamicLibrary _process = ffi.DynamicLibrary.process();

typedef _GdkDisplayGetDefaultC = ffi.Pointer<ffi.Void> Function();
typedef _GdkDisplayGetDefaultDart = ffi.Pointer<ffi.Void> Function();

final _gdkDisplayGetDefault =
    _process.lookupFunction<_GdkDisplayGetDefaultC, _GdkDisplayGetDefaultDart>(
        'gdk_display_get_default');

// gulong g_signal_connect_data(gpointer instance, const gchar *detailed_signal,
//     GCallback c_handler, gpointer data, GClosureNotify destroy_data,
//     GConnectFlags connect_flags);
typedef _GSignalConnectDataC = ffi.Uint64 Function(
  ffi.Pointer<ffi.Void> instance,
  ffi.Pointer<Utf8> detailedSignal,
  ffi.Pointer<ffi.Void> handler,
  ffi.Pointer<ffi.Void> data,
  ffi.Pointer<ffi.Void> destroyData,
  ffi.Uint32 connectFlags,
);
typedef _GSignalConnectDataDart = int Function(
  ffi.Pointer<ffi.Void> instance,
  ffi.Pointer<Utf8> detailedSignal,
  ffi.Pointer<ffi.Void> handler,
  ffi.Pointer<ffi.Void> data,
  ffi.Pointer<ffi.Void> destroyData,
  int connectFlags,
);

final _gSignalConnectData =
    _process.lookupFunction<_GSignalConnectDataC, _GSignalConnectDataDart>(
        'g_signal_connect_data');

/// Watches the default GDK display for monitors being plugged in or unplugged
/// and invokes [onChanged] whenever the set of monitors changes.
///
/// GDK emits `monitor-added` / `monitor-removed` on the default display as the
/// compositor advertises or drops `wl_output`s. This class connects both
/// signals to the same handler; callers re-enumerate with `listMonitors()` in
/// response rather than relying on the (possibly already-invalidated)
/// `GdkMonitor` pointer passed to the signal.
class MonitorWatcher {
  MonitorWatcher(this.onChanged) {
    try {
      final display = _gdkDisplayGetDefault();
      if (display.address == 0) return;

      // The GDK signal signature is
      //   void handler(GdkDisplay*, GdkMonitor*, gpointer user_data)
      // We ignore all three arguments and just re-sync.
      _callback = ffi.NativeCallable<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>)>.isolateLocal(_onSignal);

      for (final signal in const ['monitor-added', 'monitor-removed']) {
        final namePtr = signal.toNativeUtf8();
        _signalNames.add(namePtr);
        _gSignalConnectData(
          display,
          namePtr,
          _callback!.nativeFunction.cast(),
          ffi.nullptr,
          ffi.nullptr,
          0,
        );
      }
    } catch (_) {
      // Missing symbols (e.g. an unexpected GDK build) just mean no hotplug
      // support — the shell still runs with whatever monitors it started with.
      dispose();
    }
  }

  /// Invoked on the platform thread whenever a monitor is added or removed.
  final void Function() onChanged;

  ffi.NativeCallable<
      ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>)>? _callback;
  final List<ffi.Pointer<Utf8>> _signalNames = [];

  void _onSignal(ffi.Pointer<ffi.Void> display, ffi.Pointer<ffi.Void> monitor,
      ffi.Pointer<ffi.Void> userData) {
    onChanged();
  }

  /// Releases the native callback and the interned signal-name strings. The
  /// signal handlers themselves live as long as the display, which is the whole
  /// process lifetime, so there is nothing else to disconnect.
  void dispose() {
    _callback?.close();
    _callback = null;
    for (final name in _signalNames) {
      malloc.free(name);
    }
    _signalNames.clear();
  }
}
