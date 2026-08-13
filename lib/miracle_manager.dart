import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:miracle/miracle.dart';

/// Owns the shell's single [MiracleConnection] and its lifecycle.
///
/// The shell may start before Miracle WM is up (or not under Miracle at all),
/// so the connection is allowed to be absent and re-established later. Every
/// panel on every monitor listens to this one notifier, so a retry from any bar
/// restores workspaces on all of them.
///
/// A [MiracleConnection] is single-use — `disconnect()` closes its broadcast
/// event controller — so each attempt builds a fresh one and a dead connection
/// is simply dropped rather than disconnected.
class MiracleManager extends ChangeNotifier {
  /// [socketPath] is the IPC socket to connect to, defaulting to the
  /// `MIRACLESOCK` the shell was launched with. Injectable for tests, which
  /// must be able to exercise both halves of [unavailable] without forking a
  /// process to change their own environment.
  MiracleManager({String? socketPath})
      : _socketPath = socketPath ?? Platform.environment['MIRACLESOCK'];

  final String? _socketPath;

  MiracleConnection? _connection;
  bool _connecting = false;
  String? _lastError;

  /// Guards the [unavailable] notice, which would otherwise print again on
  /// every [connect] — the workspaces module calls it from a retry button, and
  /// a future service restart would call it too.
  bool _reportedUnavailable = false;

  /// Whether the shell is running somewhere Miracle IPC does not exist at all,
  /// rather than somewhere it exists and is not answering.
  ///
  /// `MIRACLESOCK` is inherited from the environment the shell was launched
  /// with, and [Platform.environment] is a snapshot taken at process start —
  /// so an unset variable can never become set while this process lives.
  /// Starting Miracle afterwards would not help either: it exports the path to
  /// the sessions *it* starts. There is therefore nothing to retry and nothing
  /// has failed; this is a feature the machine does not have, in the same
  /// register as a compositor without `ext-image-copy-capture`, and the
  /// workspaces module renders nothing at all rather than an error affordance.
  bool get unavailable => _socketPath?.isEmpty ?? true;

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
    // Not an error, and not something a retry could change — say so once, in
    // the same register as the other absent-feature notices, and stop. A stack
    // trace here is what made a shell running fine without Miracle look like a
    // shell that had crashed.
    if (unavailable) {
      if (!_reportedUnavailable) {
        _reportedUnavailable = true;
        debugPrint('miracle: MIRACLESOCK is not set; the shell is not running '
            'under miracle-wm and the workspaces module is unavailable');
      }
      return;
    }

    if (_connecting || _connection != null) return;
    _connecting = true;
    _lastError = null;
    notifyListeners();

    try {
      final connection = MiracleConnection();
      await connection.connect(
        socketPath: _socketPath,
        onSocketError: (error, _) =>
            _onSocketLost(connection, _describe(error)),
        onSocketDone: () => _onSocketLost(connection, 'the socket closed'),
      );
      await connection.subscribe([SubscriptionType.workspace]);
      _connection = connection;
    } catch (e) {
      _connection = null;
      _lastError = _describe(e);
      // One line, no stack: every failure here is a socket the shell is
      // designed to live without, and the reason is already in the message.
      debugPrint('miracle: connect failed: $_lastError');
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
    debugPrint('miracle: connection lost: $reason');
    notifyListeners();
  }

  /// Renders a connect failure as one human-readable line.
  ///
  /// `MiracleConnection.connect` throws a [SocketException] — whose
  /// `toString()` carries an address and errno tail no user needs — when the
  /// socket won't open, and a bare [Exception] for everything else.
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
