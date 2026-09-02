import 'package:flutter/foundation.dart';

import 'package:graceful_shell/request_controller.dart';

/// The seam between anything that wants the emoji picker open and the shell
/// root.
///
/// The global shortcut (Ctrl+Shift+E, through the ext-input-trigger service)
/// is the one thing that asks for it today, and it cannot create a window —
/// `_GracefulShellRootState` owns them all — so it pokes this singleton and
/// the root reacts. [LauncherController]'s shape exactly; see
/// [SignalController] for why this is not a second signal on
/// `InputTriggerStore`.
class EmojiPickerController extends SignalController {
  EmojiPickerController._();

  static final EmojiPickerController instance = EmojiPickerController._();

  @visibleForTesting
  factory EmojiPickerController.forTesting() => EmojiPickerController._();

  /// Asks the shell to open the picker, or to close it if it is already up.
  /// The root decides which — the controller carries no window state.
  void toggle() => signal();
}
