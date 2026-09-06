import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'package:graceful_shell/native/ffi_util.dart';

/// Watches the default GDK display for monitors being plugged in or unplugged and
/// invokes [onChanged] whenever the set changes.
///
/// GDK emits `monitor-added` / `monitor-removed` as the compositor advertises or
/// drops `wl_output`s. This connects both signals to the same handler; callers
/// re-enumerate with `listMonitors()` rather than relying on the (possibly
/// already-invalidated) `GdkMonitor` pointer the signal passes.
class MonitorWatcher {
  MonitorWatcher(this.onChanged) {
    try {
      final display = gdkDisplayGetDefault();
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
        gSignalConnectData(
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
