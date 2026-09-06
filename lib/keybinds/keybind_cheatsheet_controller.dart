import 'package:flutter/foundation.dart';

import 'package:graceful_shell/request_controller.dart';

/// The seam between anything that wants the keybind cheat sheet open and the
/// shell root.
///
/// The keyboard bar module is the one thing that asks for it today, and a bar
/// module cannot create a window — `_GracefulShellRootState` owns them all — so
/// it pokes this singleton and the root reacts. [LauncherController]'s shape
/// exactly.
class KeybindCheatsheetController extends SignalController {
  KeybindCheatsheetController._();

  static final KeybindCheatsheetController instance =
      KeybindCheatsheetController._();

  @visibleForTesting
  factory KeybindCheatsheetController.forTesting() =>
      KeybindCheatsheetController._();

  /// Asks the shell to open the sheet, or to close it if it is already up.
  /// The root decides which — the controller carries no window state.
  void toggle() => signal();
}
