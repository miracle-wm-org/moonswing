import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:miracle/miracle.dart';

/// Owns the shell's single [MiracleConnection] and its lifecycle.
///
/// The shell may start before Miracle WM is up (or with no socket in the
/// environment at all), so the connection is allowed to be absent and
/// re-established later. Every panel on every monitor listens to this one
/// notifier, so a retry from any bar restores workspaces on all of them.
///
/// A dead connection is dropped rather than disconnected: nothing here needs
/// `disconnect()`, and dropping it is what makes the identity comparison in
/// each consumer ([WorkspacesState], [WorkspaceAppsStore]) a reliable "this is
/// a different connection now".
class MiracleManager extends ChangeNotifier {
  MiracleConnection? _connection;
  bool _connecting = false;
  String? _lastError;

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
    if (_connecting || _connection != null) return;
    _connecting = true;
    _lastError = null;
    notifyListeners();

    try {
      final connection = MiracleConnection();
      await connection.connect(
        onSocketError: (error, _) =>
            _onSocketLost(connection, _describe(error)),
        onSocketDone: () => _onSocketLost(connection, 'the socket closed'),
      );
      // All three of these feed the workspace row. `window` is what replaced
      // its window-tree poll, and `output` is what replaced the `wl_output`
      // proxy the shell used to keep for it: miracle re-homes a removed
      // output's workspaces onto another one and emits no workspace event
      // saying so, but it does emit this. Before miracle.dart 2.0 neither
      // could be decoded — `Event.fromJson` threw from inside the socket's
      // data handler — which is why this was `workspace` alone.
      await connection.subscribe([
        SubscriptionType.workspace,
        SubscriptionType.window,
        SubscriptionType.output,
      ]);
      _connection = connection;
    } catch (e, stack) {
      _connection = null;
      _lastError = _describe(e);
      debugPrint('Miracle connect failed: $e');
      debugPrintStack(stackTrace: stack, label: 'MiracleManager.connect');
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Drops [connection] when its socket dies, so the bars fall back to the
  /// retry affordance instead of silently showing a stale, empty workspace row.
  ///
  /// The socket both errors and closes on some failures, so this may fire twice
  /// for one drop; the identity check makes the second call a no-op, keeping the
  /// first (more specific) [reason].
  ///
  /// Also ignores callbacks from a connection we have already replaced.
  void _onSocketLost(MiracleConnection connection, String reason) {
    if (!identical(_connection, connection)) return;
    _connection = null;
    _lastError = 'Connection to Miracle was lost: $reason';
    debugPrint('Miracle connection lost: $reason');
    notifyListeners();
  }

  /// Renders a connect failure as one human-readable line.
  ///
  /// `MiracleConnection.connect` throws a [MiracleConnectionException] when
  /// none of `MIRACLESOCK`/`SWAYSOCK`/`I3SOCK` names a socket, and a
  /// [SocketException] — whose `toString()` carries an address and errno tail
  /// no user needs — when the socket won't open. Both of those reach the user
  /// in the retry button's tooltip, so both are unwrapped to their message.
  String _describe(Object error) {
    if (error is SocketException) {
      final os = error.osError;
      return os == null ? error.message : '${error.message}: ${os.message}';
    }
    if (error is MiracleConnectionException) return error.message;
    final text = error.toString();
    const prefix = 'Exception: ';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }
}
