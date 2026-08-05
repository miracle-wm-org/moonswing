import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pick_types.dart';

export 'pick_types.dart';

/// The seam between the portal backend (which awaits a choice inside a D-Bus
/// `Start` call) and `_GracefulShellRootState` (which owns every window and
/// shows the picker overlay). Same singleton shape as `LauncherController`,
/// but carrying a request/response pair instead of a toggle.
class ScreencastPickerController extends ChangeNotifier implements SourcePicker {
  ScreencastPickerController._();

  static final ScreencastPickerController instance =
      ScreencastPickerController._();

  @visibleForTesting
  factory ScreencastPickerController.forTesting() =>
      ScreencastPickerController._();

  PickRequest? _pending;
  Completer<PickResult?>? _completer;

  /// The request the root should currently show a picker for, or null.
  PickRequest? get pending => _pending;

  /// Asks the user to pick. Resolves with null on cancel (backdrop, Escape,
  /// `Request.Close`, or a superseding request). If no UI is listening the
  /// answer is an immediate decline: screen sharing must never start without
  /// a visible consent surface.
  @override
  Future<PickResult?> pick(PickRequest request) {
    if (!hasListeners) return Future.value(null);
    cancel(); // a new portal request supersedes a stale pick
    _pending = request;
    final completer = Completer<PickResult?>();
    _completer = completer;
    notifyListeners();
    return completer.future;
  }

  /// Called by the picker UI when the user confirms a selection.
  void complete(PickResult result) => _finish(result);

  /// Called by the picker UI on dismissal, or by the portal on
  /// `Request.Close`.
  @override
  void cancel() => _finish(null);

  void _finish(PickResult? result) {
    final completer = _completer;
    if (completer == null) return;
    _pending = null;
    _completer = null;
    completer.complete(result);
    notifyListeners();
  }
}
