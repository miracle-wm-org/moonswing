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

/// Watches a file descriptor on the GLib main loop and invokes [onReady] on the
/// Dart thread whenever it becomes readable (or errors/hangs up).
///
/// The Dart UI isolate runs on the GLib main thread in the Flutter Linux embedder,
/// so `NativeCallable.isolateLocal` is safe — the callback is only ever invoked
/// from GLib main-loop dispatch. This is what lets the screencast code drive both
/// the capture `wl_display` and the PipeWire `pw_loop` without extra threads.
class GlibFdWatch {
  static const int gIoIn = 1;
  static const int gIoErr = 8;
  static const int gIoHup = 16;

  GlibFdWatch(int fd, this.onReady) {
    // Resolved first: with no GLib in the process (`flutter_tester`) this
    // throws, and must do so before a callable exists to keep the isolate alive.
    final add = _gUnixFdAdd;
    _callback = ffi.NativeCallable<_FdSourceFuncC>.isolateLocal(
      _onFdReady,
      exceptionalReturn: 1,
    );
    _tag = add(
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

// guint g_idle_add_full(gint priority, GSourceFunc function, gpointer data,
//     GDestroyNotify notify);
typedef _GIdleAddFullC = ffi.Uint32 Function(
  ffi.Int32 priority,
  ffi.Pointer<ffi.Void> function,
  ffi.Pointer<ffi.Void> data,
  ffi.Pointer<ffi.Void> notify,
);
typedef _GIdleAddFullDart = int Function(
  int priority,
  ffi.Pointer<ffi.Void> function,
  ffi.Pointer<ffi.Void> data,
  ffi.Pointer<ffi.Void> notify,
);
final _gIdleAddFull = _process
    .lookupFunction<_GIdleAddFullC, _GIdleAddFullDart>('g_idle_add_full');

typedef _SourceFuncC = ffi.Int32 Function(ffi.Pointer<ffi.Void> userData);

/// `G_PRIORITY_DEFAULT`: ahead of GDK's redraw (`GDK_PRIORITY_REDRAW`, 120),
/// so a continuously animating surface cannot starve the queue.
const int _gPriorityDefault = 0;

/// Runs [callback] from its own GLib main-loop dispatch, never from inside
/// whatever is running now.
///
/// What this buys is *not* being inside a GTK signal handler. The embedder's
/// draw handler (`wait_for_frame` in `fl_view_renderer_*.cc`) drops its frame
/// mutex and runs engine tasks — Dart, since the UI and platform threads are
/// one — for up to 100ms while it waits for a frame of the window's new size,
/// then goes on using the `GdkWindow` and renderer it started with. Anything
/// that destroys or unmaps that window from Dart in the meantime leaves the
/// draw holding freed memory: a SIGSEGV in `gdk_window_get_width`, or a hang
/// locking a freed mutex. That wait only runs engine tasks, never GLib sources,
/// so an idle source is guaranteed to land after the draw has returned.
///
/// With no GLib in the process (`flutter_tester`) [callback] runs at once.
void runOnGlibIdle(void Function() callback) {
  _GlibIdleQueue.instance.add(callback);
}

class _GlibIdleQueue {
  _GlibIdleQueue._();

  static final _GlibIdleQueue instance = _GlibIdleQueue._();

  final List<void Function()> _pending = [];
  ffi.NativeCallable<_SourceFuncC>? _callback;
  _GIdleAddFullDart? _idleAdd;
  bool _scheduled = false;
  bool? _available;

  void add(void Function() callback) {
    if (!_ensureCallable()) {
      callback();
      return;
    }
    _pending.add(callback);
    if (_scheduled) return;
    _scheduled = true;
    _idleAdd!(
      _gPriorityDefault,
      _callback!.nativeFunction.cast(),
      ffi.nullptr,
      ffi.nullptr,
    );
  }

  bool _ensureCallable() {
    if (_available != null) return _available!;
    try {
      // Resolved first: with no GLib this throws before a callable exists to
      // keep the isolate alive.
      _idleAdd = _gIdleAddFull;
      _callback = ffi.NativeCallable<_SourceFuncC>.isolateLocal(
        _drain,
        exceptionalReturn: 0,
      );
      _available = true;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  int _drain(ffi.Pointer<ffi.Void> _) {
    _scheduled = false;
    final batch = List.of(_pending);
    _pending.clear();
    for (final callback in batch) {
      try {
        callback();
      } catch (error, stack) {
        // One failing callback must not strand the rest of the batch.
        // ignore: avoid_print
        print('runOnGlibIdle: $error\n$stack');
      }
    }
    return 0; // G_SOURCE_REMOVE — rescheduled by the next add.
  }
}
