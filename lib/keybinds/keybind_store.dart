// The compositor's effective key bindings, for the whole shell.
//
// `KeyboardStore`'s singleton-with-leases shape and `WeatherStore.error`'s
// failure shape: one `GET_KEYBINDS` round trip for the machine however many
// bars carry the cheat sheet's icon, and a failure that is a *visible* state
// with a retry rather than an empty sheet.
//
// The read is deliberately **not** cached across opens. Miracle re-reads its
// configuration on `reload_config`, and the sheet exists to answer what a key
// does *now*; a stale list is the one thing it must not show. So every first
// lease refreshes, and the last good answer stays on screen while it does.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_manager.dart';

/// How far along the store's view of the compositor's bindings is.
///
/// Not a `ShellService`/`ServiceStatus`: that pair answers "should I show a
/// spinner", for which a decline and a success are the same answer, and this
/// has to tell "miracle is not running" apart from "miracle has no bindings".
/// [KeyboardStatus]'s split.
enum KeybindStatus {
  /// Nothing holds a lease; nothing has been read.
  idle,

  /// The first read is in flight and there is nothing to show yet.
  loading,

  /// Miracle answered.
  ready,

  /// Miracle could not be asked, or refused. [KeybindStore.error] says why and
  /// [KeybindStore.retry] is offered.
  unavailable,
}

/// Where the bindings come from.
///
/// An interface for `Locale1Client`'s reason: the real one needs an IPC socket,
/// and a widget test needs neither a compositor nor a socket to render a sheet.
abstract class KeybindSource {
  /// The effective bindings, or a throw carrying a one-line reason.
  Future<KeybindsResult> read();
}

/// Why the bindings could not be read, in one line a person can act on.
class KeybindUnavailable implements Exception {
  const KeybindUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The real source: miracle's IPC socket, through the shell's one connection.
class MiracleKeybindSource implements KeybindSource {
  const MiracleKeybindSource(this._manager);

  final MiracleManager _manager;

  @override
  Future<KeybindsResult> read() async {
    var connection = _manager.connection;
    if (connection == null) {
      // The shell is allowed to start before miracle does, and the manager
      // drops a connection whose socket died. One attempt here is what makes
      // the cheat sheet's Retry button also a *connect* button.
      await _manager.connect();
      connection = _manager.connection;
    }
    if (connection == null) {
      throw KeybindUnavailable(
        _manager.lastError ?? 'The shell is not connected to Miracle.',
      );
    }
    return connection.getKeybinds();
  }
}

/// The effective key bindings, leased by whatever is showing them.
class KeybindStore extends ChangeNotifier {
  KeybindStore._({KeybindSource? source}) : _source = source;

  static final KeybindStore instance = KeybindStore._();

  /// A detached store over an injected source, so a widget test can take a real
  /// lease with no compositor behind it.
  @visibleForTesting
  factory KeybindStore.forTesting({KeybindSource? source}) =>
      KeybindStore._(source: source);

  KeybindSource? _source;

  /// Points the store at its source. Called once from `main()`; the shell's
  /// [MiracleManager] is built there and nothing below can reach it.
  void bind(KeybindSource source) => _source = source;

  KeybindsResult? _result;

  /// What miracle last answered, or null before the first successful read.
  ///
  /// Kept across a [release] and across a later failure: a sheet reopened while
  /// the compositor is restarting shows the bindings it knew, over the reason
  /// the refresh did not land, rather than an empty card.
  KeybindsResult? get result => _result;

  KeybindStatus _status = KeybindStatus.idle;
  KeybindStatus get status => _status;

  bool _refreshing = false;

  /// Whether a read is in flight. Distinct from [KeybindStatus.loading], which
  /// is the *first* read — a refresh over a list already on screen is a quiet
  /// spinner in the header, not a card that empties itself.
  bool get refreshing => _refreshing;

  String _error = '';

  /// Why the last read did not land, or empty.
  ///
  /// Cleared only by a read that succeeds. Every failure here recovers without
  /// restarting the shell and the shell cannot see it happen, so the retry is
  /// the user's to trigger.
  String get error => _error;

  int _leases = 0;

  @visibleForTesting
  int get leaseCount => _leases;

  /// Take a lease, and refresh on the first one.
  ///
  /// Notifies nothing synchronously — this runs inside the acquiring widget's
  /// `initState`, where a `notifyListeners` is a `setState` during a build on
  /// every other surface holding a lease.
  void acquire() {
    _leases++;
    if (_leases > 1) return;
    if (_result == null) _status = KeybindStatus.loading;
    unawaited(_load(notifyStart: false));
  }

  void release() {
    if (_leases > 0) _leases--;
    // `_result`, `_status` and `_error` are deliberately kept: closing the
    // sheet must not throw away a failure the user has not read yet, and the
    // next open paints the last good list while its own refresh is in flight.
  }

  /// Ask again. The user's affordance after a failure, and safe to call while
  /// one is already in flight.
  Future<void> retry() => _load();

  Future<void> _load({bool notifyStart = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (notifyStart) notifyListeners();

    final source = _source;
    if (source == null) {
      // No `bind` — a module built alone in a widget test, with no `main()`
      // behind it. A visible reason, not a silent empty sheet.
      _finish(
        error: 'The shell is not connected to Miracle.',
        status: KeybindStatus.unavailable,
      );
      return;
    }

    try {
      final result = await source.read();
      _result = result;
      _finish(error: '', status: KeybindStatus.ready);
    } on KeybindUnavailable catch (e) {
      _finish(error: e.message, status: KeybindStatus.unavailable);
    } catch (e) {
      debugPrint('keybinds: $e');
      _finish(
        error: 'Miracle did not answer the request for its key bindings.',
        status: KeybindStatus.unavailable,
      );
    }
  }

  void _finish({required String error, required KeybindStatus status}) {
    _refreshing = false;
    _error = error;
    _status = status;
    notifyListeners();
  }
}

/// Points the shared store at the shell's miracle connection.
///
/// Called from `main()` beside the other store seeds. Not a `ShellService`:
/// there is nothing to start — the first lease is what reads — and a shell with
/// no compositor must not settle a start-up task `failed` over a cheat sheet.
void startKeybindService(MiracleManager miracle) =>
    KeybindStore.instance.bind(MiracleKeybindSource(miracle));
