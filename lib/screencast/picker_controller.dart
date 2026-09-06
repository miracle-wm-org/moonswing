import 'package:flutter/foundation.dart';

import 'package:graceful_shell/request_controller.dart';

import 'pick_types.dart';

export 'pick_types.dart';

/// The seam between the portal backend (which awaits a choice inside a D-Bus
/// `Start` call) and `_GracefulShellRootState`, which owns every window.
///
/// All of the behaviour is [RequestController]'s: decline-when-unheard (screen
/// sharing must never start without a visible consent surface), supersede on a new
/// portal request, and an answer on teardown so `Start` cannot hang forever.
class ScreencastPickerController extends RequestController<PickRequest, PickResult>
    implements SourcePicker {
  ScreencastPickerController._();

  static final ScreencastPickerController instance =
      ScreencastPickerController._();

  @visibleForTesting
  factory ScreencastPickerController.forTesting() =>
      ScreencastPickerController._();

  /// Called by the picker UI on dismissal, or by the portal on
  /// `Request.Close`. A dismissal is a *denial* — it resolves the pick with
  /// null, which becomes portal response 1.
  @override
  void cancel() => complete(null);
}
