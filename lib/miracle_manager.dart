import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:miracle/miracle.dart';

/// Owns the shell's single [MiracleConnection] and its lifecycle.
///
/// The shell may start before Miracle WM is up (or without `MIRACLESOCK` set at
/// all), so the connection is allowed to be absent and re-established later.
/// Every panel on every monitor listens to this one notifier, so a retry from
/// any bar restores workspaces on all of them.
///
/// A [MiracleConnection] is single-use — `disconnect()` closes its broadcast
/// event controller — so each attempt builds a fresh one and a dead connection
/// is simply dropped rather than disconnected.
class MiracleManager extends ChangeNotifier {
  MiracleConnection? _connection;
  bool _connecting = false;
  String? _lastError;

  /// The live connection, or null when the shell is not connected to Miracle.
  MiracleConnection? get connection => _connection;

  /// Whether a [connect] attempt is currently in flight.
  bool get connecting => _connecting;

  /// Bumped whenever the set of Wayland outputs changes, so consumers can
  /// re-query state that Miracle silently re-homed.
  ///
  /// Miracle moves a removed output's workspaces onto another output without
  /// emitting a workspace event, so a bar that only refetches on
  /// [EventWorkspace] keeps a stale `workspace -> output` mapping until the next
  /// unrelated workspace event. Its `output` event would say *that* something
  /// changed (never what), but subscribing to [SubscriptionType.output] is not
  /// an option: `miracle.dart`'s `Event.fromJson` throws `UnsupportedError` for
  /// that type, from inside the socket data handler. The shell's own
  /// `OutputTracker` sees the same reconfiguration over `wl_output`, so `main()`
  /// wires it to [notifyTopologyChanged] instead.
  int get outputsRevision => _outputsRevision;
  int _outputsRevision = 0;

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
      await connection.subscribe([SubscriptionType.workspace]);
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

  /// The set of outputs changed; whatever was cached per output is suspect.
  void notifyTopologyChanged() {
    _outputsRevision++;
    notifyListeners();
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
  /// `MiracleConnection.connect` throws a bare [Exception] when `MIRACLESOCK`
  /// is unset, and a [SocketException] — whose `toString()` carries an address
  /// and errno tail no user needs — when the socket won't open.
  String _describe(Object error) {
    if (error is SocketException) {
      final os = error.osError;
      return os == null ? error.message : '${error.message}: ${os.message}';
    }
    final text = error.toString();
    const prefix = 'Exception: ';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }
}
