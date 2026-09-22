import 'package:flutter/foundation.dart';

import 'package:moonswing/request_controller.dart';

/// The seam between anything that wants the launcher open and the shell root.
///
/// Two things ask for it: the global shortcut and the magnifier bar module.
/// Neither can create a window — `_MoonswingRootState` owns them all — so
/// both poke this singleton and the root reacts. (Why not `InputTriggerStore`:
/// see [SignalController].)
class LauncherController extends SignalController {
  LauncherController._();

  static final LauncherController instance = LauncherController._();

  @visibleForTesting
  factory LauncherController.forTesting() => LauncherController._();

  /// Asks the shell to open the launcher, or to close it if it is already up.
  /// The root decides which — the controller carries no window state.
  void toggle() => signal();
}
