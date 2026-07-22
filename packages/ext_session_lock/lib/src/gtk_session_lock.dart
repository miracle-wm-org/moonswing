import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

/// Raw FFI bindings for `libgtk-session-lock`, the GTK3 helper library that
/// implements the `ext-session-lock-v1` Wayland protocol.
///
/// This mirrors how `package:layer_shell` binds `libgtk-layer-shell`: the
/// library is opened at runtime rather than linked. Unlike that package,
/// however, loading is *tolerated to fail* — a machine without
/// `libgtk-session-lock0` installed must still run the shell, so
/// [GtkSessionLockBindings.instance] returns null and the lock screen reports
/// itself unsupported rather than taking the whole shell down at startup.
///
/// C declarations (from `gtk-session-lock.h`):
/// ```c
/// gboolean gtk_session_lock_is_supported();
/// guint    gtk_session_lock_get_protocol_version();
/// GtkSessionLockLock *gtk_session_lock_prepare_lock(void);
/// void gtk_session_lock_lock_lock(GtkSessionLockLock *lock);
/// void gtk_session_lock_lock_destroy(GtkSessionLockLock *lock);
/// void gtk_session_lock_lock_unlock_and_destroy(GtkSessionLockLock *lock);
/// void gtk_session_lock_lock_new_surface(
///     GtkSessionLockLock *lock, GtkWindow *gtk_window, GdkMonitor *monitor);
/// gboolean gtk_session_lock_is_lock_window(GtkWindow *window);
/// ```
///
/// Note `gboolean` is a `gint` (32-bit), not a C `bool`, so it is bound as
/// [ffi.Int32] and compared against zero.
class GtkSessionLockBindings {
  GtkSessionLockBindings._(ffi.DynamicLibrary lib)
      : _isSupported = lib.lookupFunction<ffi.Int32 Function(),
            int Function()>('gtk_session_lock_is_supported'),
        _getProtocolVersion = lib.lookupFunction<ffi.Uint32 Function(),
            int Function()>('gtk_session_lock_get_protocol_version'),
        _prepareLock = lib.lookupFunction<
            ffi.Pointer<ffi.Void> Function(),
            ffi.Pointer<ffi.Void> Function()>('gtk_session_lock_prepare_lock'),
        _lockLock = lib.lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)>('gtk_session_lock_lock_lock'),
        _lockDestroy = lib.lookupFunction<
                ffi.Void Function(ffi.Pointer<ffi.Void>),
                void Function(ffi.Pointer<ffi.Void>)>(
            'gtk_session_lock_lock_destroy'),
        _lockUnlockAndDestroy = lib.lookupFunction<
                ffi.Void Function(ffi.Pointer<ffi.Void>),
                void Function(ffi.Pointer<ffi.Void>)>(
            'gtk_session_lock_lock_unlock_and_destroy'),
        _lockNewSurface = lib.lookupFunction<
                ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
                    ffi.Pointer<ffi.Void>),
                void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
                    ffi.Pointer<ffi.Void>)>('gtk_session_lock_lock_new_surface'),
        _isLockWindow = lib.lookupFunction<
                ffi.Int32 Function(ffi.Pointer<ffi.Void>),
                int Function(ffi.Pointer<ffi.Void>)>(
            'gtk_session_lock_is_lock_window');

  final int Function() _isSupported;
  final int Function() _getProtocolVersion;
  final ffi.Pointer<ffi.Void> Function() _prepareLock;
  final void Function(ffi.Pointer<ffi.Void>) _lockLock;
  final void Function(ffi.Pointer<ffi.Void>) _lockDestroy;
  final void Function(ffi.Pointer<ffi.Void>) _lockUnlockAndDestroy;
  final void Function(
          ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)
      _lockNewSurface;
  final int Function(ffi.Pointer<ffi.Void>) _isLockWindow;

  static bool _attempted = false;
  static GtkSessionLockBindings? _instance;

  /// The loaded bindings, or null when `libgtk-session-lock` is unavailable.
  ///
  /// Loading is attempted once and the result cached, including failure.
  static GtkSessionLockBindings? get instance {
    if (_attempted) return _instance;
    _attempted = true;
    for (final name in const [
      'libgtk-session-lock.so.0',
      'libgtk-session-lock.so',
    ]) {
      try {
        _instance = GtkSessionLockBindings._(ffi.DynamicLibrary.open(name));
        return _instance;
      } catch (_) {
        // Try the next candidate.
      }
    }
    return _instance;
  }

  /// True when the compositor advertises `ext_session_lock_manager_v1`.
  bool isSupported() => _isSupported() != 0;

  /// The `ext-session-lock-v1` protocol version the compositor offers.
  int getProtocolVersion() => _getProtocolVersion();

  /// Creates a lock object. Connect its signals, then call [lockLock].
  ffi.Pointer<ffi.Void> prepareLock() => _prepareLock();

  /// Requests that the compositor lock the session.
  void lockLock(ffi.Pointer<ffi.Void> lock) => _lockLock(lock);

  /// Drops the lock object *without* unlocking the session.
  void lockDestroy(ffi.Pointer<ffi.Void> lock) => _lockDestroy(lock);

  /// Unlocks the session and destroys the lock object.
  void lockUnlockAndDestroy(ffi.Pointer<ffi.Void> lock) =>
      _lockUnlockAndDestroy(lock);

  /// Turns [window] into the lock surface for [monitor].
  ///
  /// Must be called *before* the window is realized.
  void lockNewSurface(
    ffi.Pointer<ffi.Void> lock,
    ffi.Pointer<ffi.Void> window,
    ffi.Pointer<ffi.Void> monitor,
  ) =>
      _lockNewSurface(lock, window, monitor);

  /// True when [window] has been made a lock surface.
  bool isLockWindow(ffi.Pointer<ffi.Void> window) => _isLockWindow(window) != 0;
}

// GLib signal plumbing. GObject is already in the process (Flutter's Linux
// embedder pulls GTK in), so these resolve from the running process — the same
// approach `graceful_shell`'s `MonitorWatcher` and `layer_shell`'s
// `GdkMonitor.getConnector` take.
final ffi.DynamicLibrary _process = ffi.DynamicLibrary.process();

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

final _gdkDisplayGetDefault = _process.lookupFunction<
    ffi.Pointer<ffi.Void> Function(),
    ffi.Pointer<ffi.Void> Function()>('gdk_display_get_default');

final _gdkDisplaySync = _process.lookupFunction<
    ffi.Void Function(ffi.Pointer<ffi.Void>),
    void Function(ffi.Pointer<ffi.Void>)>('gdk_display_sync');

/// Blocks until the compositor has processed every request sent so far.
///
/// `ext-session-lock-v1` requires this after `unlock_and_destroy`: without it
/// "the server might terminate the client with a protocol error before it
/// processes the unlock_and_destroy request". gtk-session-lock's own example
/// calls `gdk_display_sync()` in exactly this spot.
void gdkDisplaySync() {
  try {
    final display = _gdkDisplayGetDefault();
    if (display.address != 0) _gdkDisplaySync(display);
  } catch (_) {
    // Nothing useful to do if GDK is already gone.
  }
}

/// Connects [handler] to [signal] on the GObject at [instance].
///
/// The signals used here (`locked`, `finished`) carry no payload beyond the
/// emitting object, so the callback signature is
/// `void handler(GObject *self, gpointer user_data)`.
int gSignalConnect(
  ffi.Pointer<ffi.Void> instance,
  String signal,
  ffi.Pointer<ffi.Void> handler,
) {
  final namePtr = signal.toNativeUtf8();
  try {
    return _gSignalConnectData(
      instance,
      namePtr,
      handler,
      ffi.nullptr,
      ffi.nullptr,
      0,
    );
  } finally {
    calloc.free(namePtr);
  }
}
