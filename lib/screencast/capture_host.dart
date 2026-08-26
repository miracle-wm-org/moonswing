// The one Wayland capture connection in the process.
//
// `CaptureConnection` used to be created by, and belong to,
// `startScreencastService` — which was right while the portal backend was the
// only thing capturing. It is not the only one any more: the shell's own
// screenshot and recording features (`lib/capture/`) bind the same globals,
// create sessions on the same sources, and would otherwise each open a second
// connection with a second registry, a second `wl_shm` and a second copy of
// the foreign-toplevel list, on a compositor that already advertises one of
// each.
//
// So the connection is hoisted here and both features borrow it. Two rules
// come out of the sharing, and neither is optional:
//
// - **A failed connect is remembered, not retried per caller.** The two
//   reasons this returns null — no display to reach, no libwayland to load —
//   do not resolve while the shell is running, and a screenshot module that
//   re-attempted the dlopen on every click would pay for it on every click.
// - **`onDied` fans out, and drops the connection.** `CaptureConnection`
//   carries one callback and there are now two interested parties; worse, the
//   old arrangement left the dead connection in place, so every capture after
//   a compositor restart would have been made against a socket nobody was
//   listening on. Clearing it here is what lets the next caller reconnect.
//
// Deliberately Flutter-free, like everything else below the screencast UI:
// `tool/screencast_spike.dart` compiles this whole layer with `dart compile
// exe`.

import 'capture_connection.dart';
import 'screencast_log.dart';

/// Process-wide owner of the shared [CaptureConnection].
class CaptureHost {
  CaptureHost._();

  static CaptureConnection? _connection;
  static bool _attempted = false;
  static final List<void Function()> _diedListeners = [];

  /// The live connection, or null when there is none *right now* — this never
  /// connects. For "give me one", use [connect].
  static CaptureConnection? get current => _connection;

  /// Whether a connect has been tried and failed. The screenshot and recorder
  /// modules render this as an unavailable state rather than as an empty one.
  static bool get unavailable => _attempted && _connection == null;

  /// The shared connection, connecting on the first call.
  ///
  /// [attachToGlibLoop] is honoured on the connect that actually happens; the
  /// shell always wants it (the Dart UI isolate runs on the GLib main thread),
  /// and only `tool/screencast_spike.dart`, which has no GLib loop, passes
  /// false and pumps by hand.
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
    _connection = connection;
    return connection;
  }

  /// Registers [listener] for the connection dying. Idempotent per callback.
  static void addDiedListener(void Function() listener) {
    if (!_diedListeners.contains(listener)) _diedListeners.add(listener);
  }

  static void removeDiedListener(void Function() listener) =>
      _diedListeners.remove(listener);

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
    final connection = _connection;
    _connection = null;
    _attempted = false;
    connection?.dispose();
  }

  /// Drops the memoised state without touching a live connection, for tests
  /// that need a clean slate.
  static void resetForTesting() {
    _diedListeners.clear();
    _connection = null;
    _attempted = false;
  }
}
