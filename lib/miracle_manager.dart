import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:miracle/miracle.dart';

/// What the environment says about whether the shell is running under Miracle
/// WM, before any socket is opened.
enum MiracleSession {
  /// `MIRACLESOCK` is set, or `XDG_CURRENT_DESKTOP` names miracle-wm.
  miracle,

  /// Some other compositor: sway, Miriway, anything that is not miracle. The
  /// shell runs on it without the features that need Miracle's IPC.
  other,

  /// Only an i3-compatible socket (`SWAYSOCK`/`I3SOCK`) and no desktop name.
  /// miracle sets both of those too, and its session script exports them to
  /// systemd without `MIRACLESOCK`, so this is settled by asking the socket.
  undetermined,
}

/// The message a Miracle-only feature shows on any other compositor.
const String kNotMiracleMessage = 'Moonswing is not running under Miracle WM.';

/// Reads [environment] for which compositor the shell is running inside.
///
/// The sway and i3 socket variables are *not* evidence of miracle on their
/// own: sway sets `SWAYSOCK` too, and its IPC answers the i3 half of the
/// protocol while ignoring miracle's extensions outright — a `GET_KEYBINDS`
/// sent to sway is logged and never answered.
MiracleSession detectMiracleSession(Map<String, String> environment) {
  String? value(String key) {
    final v = environment[key];
    return v == null || v.isEmpty ? null : v;
  }

  if (value('MIRACLESOCK') != null) return MiracleSession.miracle;
  final desktop = value('XDG_CURRENT_DESKTOP');
  if (desktop != null) {
    // miracle's session script exports `mir:miracle-wm`, the snap's portal
    // half `miracle-wm:mir`; either order, any case.
    final names = desktop.toLowerCase().split(':');
    return names.contains('miracle-wm') || names.contains('miracle')
        ? MiracleSession.miracle
        : MiracleSession.other;
  }
  if (value('SWAYSOCK') == null && value('I3SOCK') == null) {
    return MiracleSession.other;
  }
  return MiracleSession.undetermined;
}

/// Owns the shell's single [MiracleConnection] and its lifecycle.
///
/// The shell may start before Miracle WM is up, or with no socket in the
/// environment at all, so the connection is allowed to be absent and
/// re-established later. Every panel on every monitor listens to this one
/// notifier, so a retry from any bar restores workspaces on all of them.
///
/// It may also be running under a different compositor altogether — sway,
/// Miriway — where nothing of miracle's will ever answer. That is [unsupported]:
/// settled once, never retried, and the cue for every Miracle-only surface to
/// render nothing (or say why) rather than offer a retry that cannot work.
///
/// A dead connection is dropped rather than disconnected, which is what makes the
/// identity comparison in each consumer a reliable "this is a different
/// connection now".
class MiracleManager extends ChangeNotifier {
  MiracleManager({
    Map<String, String>? environment,
    this.requestTimeout = const Duration(seconds: 10),
    this.probeTimeout = const Duration(seconds: 2),
  }) : _environment = environment ?? Platform.environment,
       session = detectMiracleSession(environment ?? Platform.environment) {
    if (session == MiracleSession.other) {
      _unsupported = true;
      _lastError = kNotMiracleMessage;
    }
  }

  final Map<String, String> _environment;

  /// What the environment said at start-up. [unsupported] is the live answer.
  final MiracleSession session;

  /// How long any one request may wait for its reply. Without it, a request
  /// the compositor ignores — miracle's own extensions, on anything else — is a
  /// spinner that never ends.
  final Duration requestTimeout;

  /// How long [MiracleSession.undetermined]'s identity check may take before
  /// the socket is judged not to be miracle's.
  final Duration probeTimeout;

  MiracleConnection? _connection;
  bool _connecting = false;
  String? _lastError;
  bool _unsupported = false;

  /// Whether the compositor is known not to be Miracle WM.
  ///
  /// True from construction when the environment says so, or after the first
  /// [connect] when the only socket on offer turned out to be somebody else's.
  /// Never goes back to false: the compositor does not change under a running
  /// shell. While it is true [connection] is null and [connect] does nothing.
  bool get unsupported => _unsupported;

  /// The live connection, or null when the shell is not connected to Miracle.
  MiracleConnection? get connection => _connection;

  /// Whether a [connect] attempt is currently in flight.
  bool get connecting => _connecting;

  /// Why the shell is not connected — the last [connect] failure, or the reason
  /// a live connection dropped. Null while connected or before the first
  /// attempt. Short enough to show the user in a tooltip.
  String? get lastError => _lastError;

  /// Opens the IPC socket and subscribes to workspace events.
  ///
  /// Never throws: a failure just leaves [connection] null and records
  /// [lastError], which is what the UI renders the retry affordance from.
  Future<void> connect() async {
    if (_unsupported || _connecting || _connection != null) return;
    _connecting = true;
    _lastError = null;
    notifyListeners();

    final connection = MiracleConnection();
    try {
      await connection.connect(
        // Named explicitly rather than left to the package's own search, which
        // is the same list in the same order: the point is that it is this
        // socket the identity check below is about.
        socketPath: MiracleConnection.resolveSocketPath(_environment),
        requestTimeout: requestTimeout,
        onSocketError: (error, _) =>
            _onSocketLost(connection, _describe(error)),
        onSocketDone: () => _onSocketLost(connection, 'the socket closed'),
      );
      if (session == MiracleSession.undetermined &&
          !await _speaksMiracle(connection)) {
        unawaited(_discard(connection));
        _unsupported = true;
        _lastError = kNotMiracleMessage;
        debugPrint('Miracle: the i3-compatible socket is not miracle\'s; '
            'Miracle-only features are off');
        return;
      }
      // All three feed the workspace row. `window` replaced its window-tree poll,
      // and `output` replaced the `wl_output` proxy the shell used to keep for it:
      // miracle re-homes a removed output's workspaces onto another one and emits
      // no workspace event saying so, but it does emit this. Before miracle.dart
      // 2.0 neither could be decoded.
      await connection.subscribe([
        SubscriptionType.workspace,
        SubscriptionType.window,
        SubscriptionType.output,
      ]);
      _connection = connection;
    } catch (e, stack) {
      _connection = null;
      unawaited(_discard(connection));
      _lastError = _describe(e);
      debugPrint('Miracle connect failed: $e');
      debugPrintStack(stackTrace: stack, label: 'MiracleManager.connect');
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Whether the socket behind [connection] answers a request only miracle
  /// implements.
  ///
  /// `GET_KEYBINDS` is miracle's own message type. miracle answers it; sway
  /// logs it and sends nothing back, and i3 does the same, so silence within
  /// [probeTimeout] — or the socket closing on us — is the answer "no".
  Future<bool> _speaksMiracle(MiracleConnection connection) async {
    try {
      await connection.getKeybinds().timeout(probeTimeout);
      return true;
    } on TimeoutException {
      return false;
    } on MiracleConnectionException {
      return false;
    }
  }

  /// Closes a connection that never became [connection]. Best effort: it may
  /// never have opened.
  static Future<void> _discard(MiracleConnection connection) async {
    try {
      await connection.disconnect();
    } catch (_) {}
  }

  /// Drops [connection] when its socket dies, so the bars fall back to the retry
  /// affordance instead of silently showing a stale, empty workspace row.
  ///
  /// The socket both errors and closes on some failures, so this may fire twice
  /// for one drop; the identity check makes the second call a no-op, keeping the
  /// first and more specific [reason]. Callbacks from an already-replaced
  /// connection are ignored too.
  void _onSocketLost(MiracleConnection connection, String reason) {
    if (!identical(_connection, connection)) return;
    _connection = null;
    _lastError = 'Connection to Miracle was lost: $reason';
    debugPrint('Miracle connection lost: $reason');
    notifyListeners();
  }

  /// Renders a connect failure as one human-readable line.
  ///
  /// `MiracleConnection.connect` throws a [MiracleConnectionException] when none
  /// of `MIRACLESOCK`/`SWAYSOCK`/`I3SOCK` names a socket, and a [SocketException]
  /// — whose `toString()` carries an address and errno tail no user needs — when
  /// the socket will not open. Both reach the user in the retry button's tooltip,
  /// as does a request that outlived [requestTimeout].
  String _describe(Object error) {
    if (error is SocketException) {
      final os = error.osError;
      return os == null ? error.message : '${error.message}: ${os.message}';
    }
    if (error is MiracleConnectionException) return error.message;
    if (error is TimeoutException) return 'Miracle did not answer in time.';
    final text = error.toString();
    const prefix = 'Exception: ';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }
}
