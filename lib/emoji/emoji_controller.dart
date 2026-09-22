import 'package:flutter/foundation.dart';

import 'package:moonswing/request_controller.dart';

/// The seam between anything that wants the emoji picker open and the shell root.
///
/// The global shortcut (Ctrl+Shift+E) is the one thing that asks for it today,
/// and it cannot create a window, so it pokes this singleton and the root reacts.
/// [LauncherController]'s shape exactly.
class EmojiPickerController extends SignalController {
  EmojiPickerController._();

  static final EmojiPickerController instance = EmojiPickerController._();

  @visibleForTesting
  factory EmojiPickerController.forTesting() => EmojiPickerController._();

  /// Asks the shell to open the picker, or to close it if it is already up.
  /// The root decides which — the controller carries no window state.
  void toggle() => signal();
}
