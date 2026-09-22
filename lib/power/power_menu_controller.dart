import 'package:flutter/foundation.dart';

import 'package:moonswing/request_controller.dart';

/// The seam between anything that wants the power menu on screen and
/// `_MoonswingRootState`, which owns every window.
///
/// Distinct from [PowerController], which reports the *physical* power key and
/// leaves the root to resolve `[power] key_action` — a press may mean a verb, or
/// nothing at all. This one asks for the menu itself, and is what the bar's
/// power button pokes: a bar module cannot create a window, and a shell with
/// four bars must not be able to open four menus. [KeybindCheatsheetController]'s
/// shape exactly.
class PowerMenuController extends SignalController {
  PowerMenuController._();

  static final PowerMenuController instance = PowerMenuController._();

  @visibleForTesting
  factory PowerMenuController.forTesting() => PowerMenuController._();

  /// Asks the shell to open the menu, or to close it if it is already up. The
  /// root decides which — the controller carries no window state.
  void toggle() => signal();
}
