import 'dart:ffi' as ffi;

/// Raw GLib symbols resolved from the running process — the Flutter Linux
/// embedder links GTK, which pulls in GLib, so the symbols are already
/// present. Same approach as `MonitorWatcher` (`lib/monitor_watcher.dart`).
final ffi.DynamicLibrary _process = ffi.DynamicLibrary.process();

// guint g_unix_fd_add(gint fd, GIOCondition condition,
//     GUnixFDSourceFunc function, gpointer user_data);
typedef _GUnixFdAddC = ffi.Uint32 Function(
  ffi.Int32 fd,
  ffi.Uint32 condition,
  ffi.Pointer<ffi.Void> function,
  ffi.Pointer<ffi.Void> userData,
);
typedef _GUnixFdAddDart = int Function(
  int fd,
  int condition,
  ffi.Pointer<ffi.Void> function,
  ffi.Pointer<ffi.Void> userData,
);
final _gUnixFdAdd =
    _process.lookupFunction<_GUnixFdAddC, _GUnixFdAddDart>('g_unix_fd_add');

// gboolean g_source_remove(guint tag);
typedef _GSourceRemoveC = ffi.Int32 Function(ffi.Uint32 tag);
typedef _GSourceRemoveDart = int Function(int tag);
final _gSourceRemove = _process
    .lookupFunction<_GSourceRemoveC, _GSourceRemoveDart>('g_source_remove');

typedef _FdSourceFuncC = ffi.Int32 Function(
    ffi.Int32 fd, ffi.Uint32 condition, ffi.Pointer<ffi.Void> userData);

/// Watches a file descriptor on the GLib main loop and invokes [onReady] on
/// the Dart thread whenever it becomes readable (or errors/hangs up).
///
/// The Dart UI isolate runs on the GLib main thread in the Flutter Linux
/// embedder, so `NativeCallable.isolateLocal` is safe here — the callback is
/// only ever invoked from GLib main-loop dispatch, which is this thread. This
/// is the integration point that lets the screencast code drive both the
/// capture `wl_display` and the PipeWire `pw_loop` without extra threads.
class GlibFdWatch {
  static const int gIoIn = 1;
  static const int gIoErr = 8;
  static const int gIoHup = 16;

  GlibFdWatch(int fd, this.onReady) {
    _callback = ffi.NativeCallable<_FdSourceFuncC>.isolateLocal(
      _onFdReady,
      exceptionalReturn: 1,
    );
    _tag = _gUnixFdAdd(
      fd,
      gIoIn | gIoErr | gIoHup,
      _callback!.nativeFunction.cast(),
      ffi.nullptr,
    );
  }

  /// Invoked with the `GIOCondition` bitfield that fired.
  final void Function(int condition) onReady;

  ffi.NativeCallable<_FdSourceFuncC>? _callback;
  int _tag = 0;

  int _onFdReady(int fd, int condition, ffi.Pointer<ffi.Void> userData) {
    onReady(condition);
    return 1; // G_SOURCE_CONTINUE — the watch stays until disposed.
  }

  void dispose() {
    if (_tag != 0) {
      _gSourceRemove(_tag);
      _tag = 0;
    }
    _callback?.close();
    _callback = null;
  }
}
