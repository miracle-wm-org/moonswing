// The one Wayland capture connection in the process.
//
// `CaptureConnection` used to belong to `startScreencastService`, which was right
// while the portal backend was the only thing capturing. The shell's own
// screenshot and recording features bind the same globals and create sessions on
// the same sources, and would otherwise each open a second connection with a
// second registry, a second `wl_shm` and a second copy of the foreign-toplevel
// list, on a compositor that advertises one of each.
//
// So the connection is hoisted here and both features borrow it. Two rules come
// out of the sharing:
//
// - **A failed connect is remembered, not retried per caller.** The two reasons
//   this returns null — no display to reach, no libwayland to load — do not
//   resolve while the shell is running.
// - **`onDied` fans out, and drops the connection.** `CaptureConnection` carries
//   one callback and there are two interested parties; and the old arrangement
//   left the dead connection in place, so every capture after a compositor
//   restart was made against a socket nobody was listening on.
// - **`onToplevelsChanged` fans out too**, for the same reason and a third
//   party: the window switcher's list lives for the whole session, while the
//   screencast picker only wants the list while it is on screen.
//
// Deliberately Flutter-free, like everything else below the screencast UI.

import 'capture_connection.dart';
import 'screencast_log.dart';

/// Process-wide owner of the shared [CaptureConnection].
class CaptureHost {
  CaptureHost._();

  static CaptureConnection? _connection;
  static bool _attempted = false;
  static final List<void Function()> _diedListeners = [];
  static final List<void Function()> _toplevelListeners = [];

  /// The live connection, or null when there is none *right now* — this never
  /// connects. For "give me one", use [connect].
  static CaptureConnection? get current => _connection;

  /// Whether a connect has been tried and failed. The screenshot and recorder
  /// modules render this as an unavailable state rather than as an empty one.
  static bool get unavailable => _attempted && _connection == null;

  /// The shared connection, connecting on the first call.
  ///
  /// [attachToGlibLoop] is honoured on the connect that actually happens; the
  /// shell always wants it, and only `tool/screencast_spike.dart`, which has no
  /// GLib loop, passes false and pumps by hand.
  static CaptureConnection? connect({bool attachToGlibLoop = true}) {
    final existing = _connection;
    if (existing != null) return existing;
    if (_attempted) return null;
    _attempted = true;

    final connection =
        CaptureConnection.connect(attachToGlibLoop: attachToGlibLoop);
    if (connection == null) {
      screencastLog('capture connection unavailable: cannot reach the display');
      return null;
    }
    connection.onDied = _onDied;
    connection.onToplevelsChanged = _onToplevelsChanged;
    _connection = connection;
    return connection;
  }

  /// Registers [listener] for the connection dying. Idempotent per callback.
  static void addDiedListener(void Function() listener) {
    if (!_diedListeners.contains(listener)) _diedListeners.add(listener);
  }

  static void removeDiedListener(void Function() listener) =>
      _diedListeners.remove(listener);

  /// Registers [listener] for a toplevel opening, closing or being retitled.
  /// Idempotent per callback.
  ///
  /// `onDied`'s reason, a second time: [CaptureConnection] carries one callback
  /// and there is now more than one interested party — the screencast picker
  /// while it is on screen, and the window switcher's list for the whole life
  /// of the session. Whoever set the field last would otherwise be the only one
  /// told.
  static void addToplevelsChangedListener(void Function() listener) {
    if (!_toplevelListeners.contains(listener)) {
      _toplevelListeners.add(listener);
    }
  }

  static void removeToplevelsChangedListener(void Function() listener) =>
      _toplevelListeners.remove(listener);

  static void _onToplevelsChanged() {
    for (final listener in List.of(_toplevelListeners)) {
      listener();
    }
  }

  static void _onDied() {
    screencastLog('capture connection lost');
    _connection = null;
    // Cleared, so the *next* caller reconnects rather than inheriting the
    // corpse — a compositor restart should cost one failed capture, not every
    // capture for the rest of the session.
    _attempted = false;
    for (final listener in List.of(_diedListeners)) {
      listener();
    }
  }

  /// Shell teardown. The connection outlives every session on it, so nothing
  /// smaller than the process is allowed to close it.
  static void dispose() {
    _diedListeners.clear();
    _toplevelListeners.clear();
    final connection = _connection;
    _connection = null;
    _attempted = false;
    connection?.dispose();
  }

  /// Drops the memoised state without touching a live connection, for tests
  /// that need a clean slate.
  static void resetForTesting() {
    _diedListeners.clear();
    _toplevelListeners.clear();
    _connection = null;
    _attempted = false;
  }
}
