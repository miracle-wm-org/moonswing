import 'dart:ffi' as ffi;

import 'package:ext_session_lock/ext_session_lock.dart';
import 'package:flutter/widgets.dart';

import 'package:graceful_shell/lock/lock_controller.dart';
import 'package:graceful_shell/popup.dart';

/// Owns the `ext-session-lock-v1` lifecycle on behalf of the shell root: the
/// [SessionLock] object, one [SessionLockWindowController] per monitor,
/// monitors hotplugged mid-lock, and the teardown ordering that keeps the
/// compositor connection alive.
///
/// The root keeps three duties: reacting to [LockController] by calling
/// [lock], building a `SessionLockWindow` per controller in [windows], and
/// calling [dispose] from its own — which abandons rather than unlocks,
/// because a shell dying while the session is locked must leave it locked.
class SessionLockHost {
  SessionLockHost({required this.onChanged});

  /// Called whenever [windows] changed, so the owner rebuilds its tree.
  /// The rebuild is what detaches a dying window's view; the native side is
  /// destroyed one frame later (see [_destroyAfterFrame]).
  final VoidCallback onChanged;

  SessionLock? _lock;
  final Map<String, SessionLockWindowController> _windows = {};
  bool _disposed = false;

  /// True from a successful [lock] until the unlock (ours or the
  /// compositor's) has been processed.
  bool get isLocked => _lock != null;

  /// The lock surfaces, one per covered monitor. Outputs without one are
  /// blanked by the compositor, so a missing entry is safe, never a leak.
  Iterable<SessionLockWindowController> get windows => _windows.values;

  /// Locks the session and puts a lock surface on every monitor in
  /// [monitors] (key → `GdkMonitor`).
  ///
  /// Ordering matters and mirrors gtk-session-lock's own example: prepare the
  /// lock, ask the compositor to lock, *then* create the surfaces. Each
  /// [SessionLockWindowController] claims its GTK window's surface before the
  /// window is realized.
  void lock(Map<String, ffi.Pointer<ffi.NativeType>> monitors) {
    if (_lock != null || _disposed) return;

    if (!SessionLock.isSupported) {
      final reason = SessionLock.isAvailable
          ? 'the compositor does not implement ext-session-lock-v1'
          : 'libgtk-session-lock is not installed';
      debugPrint('lock: cannot lock the session — $reason');
      LockController.instance.markFailed(reason);
      return;
    }

    debugPrint('lock: available=${SessionLock.isAvailable} '
        'supported=${SessionLock.isSupported} '
        'protocol=${SessionLock.protocolVersion}');

    final lock = SessionLock(
      onLocked: () =>
          debugPrint('lock: compositor confirmed the session is locked'),
      onFinished: _onFinished,
    );
    try {
      lock.prepare();
      debugPrint(
          'lock: prepared, handle=0x${lock.handle.address.toRadixString(16)}');
      lock.lock();
      debugPrint('lock: lock request sent');
    } catch (error) {
      debugPrint('lock: failed to lock the session: $error');
      lock.release();
      LockController.instance.markFailed('$error');
      return;
    }

    _lock = lock;
    for (final entry in monitors.entries) {
      _createWindow(entry.key, entry.value, lock);
    }

    LockController.instance.markActive();
    onChanged();

    // Re-check once the windows have been presented: `attached` at creation
    // only proves the handlers were connected, this proves the role survived
    // realize + map.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final entry in _windows.entries) {
        debugPrint('lock: ${entry.key} isLockWindow after map='
            '${entry.value.isLockWindow}');
      }
    });
  }

  void _createWindow(
      String key, ffi.Pointer<ffi.NativeType> monitor, SessionLock lock) {
    try {
      final controller = SessionLockWindowController(
        sessionLock: lock,
        monitor: monitor,
      );
      _windows[key] = controller;
      // Sampled before the window is realized: false means the lock surface
      // was never registered, so GDK will map an ordinary toplevel — a
      // floating window instead of a lock surface. Otherwise silent apart
      // from a g_critical on stderr.
      debugPrint('lock: $key attached=${controller.attachedAsLockSurface}');
    } catch (error) {
      // A monitor we could not build a surface for is blanked by the
      // compositor, so the session stays covered either way.
      debugPrint('lock: no lock surface for $key: $error');
    }
  }

  /// A monitor was plugged in while locked: without a lock surface the
  /// compositor would just blank it. No-op when not locked.
  void addMonitor(String key, ffi.Pointer<ffi.NativeType> monitor) {
    final lock = _lock;
    if (lock == null || _windows.containsKey(key)) return;
    _createWindow(key, monitor, lock);
  }

  /// A monitor went away. Returns its controller — still alive, because the
  /// caller must detach its view (rebuild) before destroying the native side.
  SessionLockWindowController? removeMonitor(String key) =>
      _windows.remove(key);

  /// PAM accepted the password: release the lock and restore the session.
  void unlock() => _teardown(unlock: true);

  /// The compositor ended the lock without us asking (it refused the lock, or
  /// took it away). The session may well still be locked, so drop our lock
  /// object without sending an unlock.
  void _onFinished() => _teardown(unlock: false);

  void _teardown({required bool unlock}) {
    final lock = _lock;
    if (lock == null || _disposed) return;
    _lock = null;

    final removed = _windows.values.toList();
    _windows.clear();
    LockController.instance.clear();

    // Detach the views this frame, then tear down the native side once that
    // frame has rendered — destroying a window Flutter is still rendering
    // into would use a freed FlView.
    //
    // The lock is released *before* the windows are destroyed: the protocol
    // says lock surfaces should be destroyed after the unlock request, and
    // unlockAndDestroy() syncs with the compositor, without which the server
    // may kill the connection with a protocol error mid-teardown.
    onChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (unlock) {
        lock.unlockAndDestroy();
      } else {
        lock.release();
      }
      for (final controller in removed) {
        // No hide: unmapping a lock surface before it is destroyed shows the
        // desktop it is there to cover. The wait itself still applies — the
        // abort [WindowTeardown] documents is not particular to popups.
        destroyWindowWhenDetached(controller, hide: false);
      }
    });
  }

  /// Drops the lock windows, but never sends an unlock on the way out: if the
  /// shell is going away while the session is locked, the session must stay
  /// locked. abandon() sends no Wayland request at all — after `locked` the
  /// only legal destructor is unlock_and_destroy, which would do the opposite
  /// of what we want; disconnecting instead leaves the session locked.
  void dispose() {
    _disposed = true;
    for (final controller in _windows.values) {
      controller.destroy();
    }
    _windows.clear();
    _lock?.abandon();
    _lock = null;
  }
}
