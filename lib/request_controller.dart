/// The two shapes of "seam" controller between something deep in a surface's
/// widget tree and `_MoonswingRootState`, which owns every window.
///
/// A widget that needs a root-owned window cannot create one, so it pokes a
/// process-wide singleton and the root — the only listener — reacts.
/// [RequestController] carries a request/response pair and hands the asker a
/// future; [SignalController] carries a bare signal with optional payload state
/// in the subclass.
///
/// Both are deliberately not `InputTriggerStore`: that store reports *compositor*
/// triggers and its listener toggles on any notification, so a second signal
/// there would trip the wrong handler.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// A controller whose ask is answered: `pick()` resolves once the root (or a
/// teardown) supplies a result.
///
/// Three rules every subclass inherits, none optional:
///
/// - **No listener means an immediate decline.** A headless run or a unit test
///   must never await a window that will not appear — and for the screencast
///   picker this is a security posture: a backend that could answer without a
///   visible consent surface could silently record the screen.
/// - **A second request supersedes the first**, which resolves as declined, so no
///   caller is left awaiting a window that has been replaced.
/// - **Teardown still owes every awaiting caller an answer.** [dispose] declines
///   the pending request rather than stranding its future.
abstract class RequestController<Req, Res> extends ChangeNotifier {
  Req? _pending;
  Completer<Res?>? _completer;

  /// The request awaiting an answer, or null.
  Req? get pending => _pending;

  /// Asks the root to answer [request], resolving to the answer or null when
  /// declined (dismissed, superseded, or nothing listening).
  Future<Res?> pick(Req request) {
    if (!hasListeners) return Future<Res?>.value(null);
    _resolve(null);
    final completer = Completer<Res?>();
    _pending = request;
    _completer = completer;
    notifyListeners();
    return completer.future;
  }

  /// Called by the owning UI once the user answers, with null for a
  /// dismissal. Idempotent — answering an already-answered request is a
  /// no-op, not a second notification.
  void complete(Res? result) {
    if (_pending == null && _completer == null) return;
    _resolve(result);
    notifyListeners();
  }

  void _resolve(Res? result) {
    final completer = _completer;
    _completer = null;
    _pending = null;
    if (completer != null && !completer.isCompleted) completer.complete(result);
  }

  @override
  void dispose() {
    _resolve(null);
    super.dispose();
  }
}

/// A controller whose ask is fire-and-forget: the root reacts to
/// [notifyListeners] and nothing resolves back to the caller.
abstract class SignalController extends ChangeNotifier {
  int _count = 0;

  /// Monotonic count of signals. Exposed for tests; the root reacts to
  /// [notifyListeners], not to this value.
  @visibleForTesting
  int get signalCount => _count;

  /// Notifies the root. Subclasses expose this under their domain verb
  /// (`toggle()`, `open()`), setting any payload state first.
  @protected
  void signal() {
    _count++;
    notifyListeners();
  }
}
