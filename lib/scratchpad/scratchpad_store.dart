// The window manager's scratchpad, as the shell drives it: stash the focused
// window there, and show or hide what is stashed.
//
// Both halves are miracle's IPC commands and nothing else — `move scratchpad`
// and `scratchpad show` — so there is no state here to keep in step with the
// compositor. That is deliberate rather than an omission: miracle keeps a
// stashed window out of its tree altogether (no workspace, no parent), so
// `GET_TREE` cannot say how many windows are on the scratchpad or whether they
// are showing, and a count or an "open" state the shell kept for itself would
// be wrong the first time the user pressed one of miracle's own bindings.
//
// One store for the machine, [KeybindStore]'s shape: the bar button on every
// monitor and the two global shortcuts all go through it, and the shortcuts
// have no widget tree above them to read `MiracleScope` from. What it does
// hold is the last failure, because a command that went nowhere is otherwise
// indistinguishable from a scratchpad with nothing on it.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_manager.dart';

/// Sends one command to the window manager, throwing on any failure.
typedef ScratchpadCommandRunner = Future<void> Function(MiracleCommand command);

/// The scratchpad's two actions, and why the last one did not work.
class ScratchpadStore extends ChangeNotifier {
  ScratchpadStore._();

  static final ScratchpadStore instance = ScratchpadStore._();

  /// A detached store over [run], so a test can drive both actions with no
  /// compositor behind them.
  @visibleForTesting
  factory ScratchpadStore.forTesting(ScratchpadCommandRunner run) =>
      ScratchpadStore._()..bind(run);

  ScratchpadCommandRunner? _run;

  String? _error;

  /// Why the last action failed, or null when it worked (or none has run).
  /// Short enough for a tooltip.
  String? get error => _error;

  /// Points the store at whatever sends its commands. Called once from
  /// `main()` through [startScratchpadService].
  void bind(ScratchpadCommandRunner run) => _run = run;

  /// Shows what is on the scratchpad, or hides it if it is showing.
  ///
  /// miracle toggles *every* stashed window together — `scratchpad show` takes
  /// criteria on the wire, but the compositor does not yet honour them — so
  /// this is one toggle for the whole scratchpad, not a cycle through it.
  Future<void> toggle() => _send(MiracleCommand.scratchpadShow());

  /// Moves the window miracle has focused onto the scratchpad.
  ///
  /// No criteria, so miracle resolves its own selection. That is the window
  /// the user was in even when this came from a click on the bar: panels take
  /// no keyboard focus, which is what keeps the selection where it was.
  Future<void> moveFocusedWindow() => _send(MiracleCommand.moveToScratchpad());

  /// Never throws: every way this can fail is recorded in [error] instead,
  /// because a global shortcut's callback has nobody to throw to.
  Future<void> _send(MiracleCommand command) async {
    final run = _run;
    String? error;
    if (run == null) {
      error = 'The shell is not connected to Miracle.';
    } else {
      try {
        await run(command);
      } catch (e) {
        error = _describe(e);
        debugPrint('scratchpad: "$command" failed: $e');
      }
    }
    // Only a change notifies: every bar on every monitor listens, and a
    // toggle that worked twice in a row has nothing new to say.
    if (error == _error) return;
    _error = error;
    notifyListeners();
  }

  static String _describe(Object error) => switch (error) {
    MiracleCommandException(:final failures) =>
      failures.map((f) => f.error).nonNulls.firstOrNull ??
          'Miracle refused the command.',
    MiracleConnectionException(:final message) => message,
    TimeoutException() => 'Miracle did not answer in time.',
    _ => '$error',
  };
}

/// The real runner: the shell's one miracle connection.
///
/// A missing connection is given one [MiracleManager.connect] first, the
/// cheat sheet's rule — the manager drops a connection whose socket died, and
/// a scratchpad key pressed after miracle restarted should just work.
ScratchpadCommandRunner miracleScratchpadRunner(MiracleManager manager) =>
    (command) async {
      var connection = manager.connection;
      if (connection == null) {
        await manager.connect();
        connection = manager.connection;
      }
      if (connection == null) {
        throw MiracleConnectionException(
          manager.lastError ?? 'The shell is not connected to Miracle.',
        );
      }
      await connection.runOrThrow(command);
    };

/// Points the shared store at the shell's miracle connection.
///
/// Not a `ShellService`, [startKeybindService]'s reason: there is nothing to
/// start, and a machine with no compositor must not settle a start-up task
/// `failed` over a scratchpad nobody has touched.
void startScratchpadService(MiracleManager miracle) =>
    ScratchpadStore.instance.bind(miracleScratchpadRunner(miracle));
