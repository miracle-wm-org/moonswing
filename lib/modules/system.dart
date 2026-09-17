// The bar's power button. It creates no window of its own: it pokes
// [PowerMenuController], exactly as `keybinds.dart` and `launcher.dart` poke
// theirs — the root owns every window, and that is what keeps a shell with four
// bars from opening four menus.
//
// It used to open a popup of its own: a column of the same five verbs, each of
// the four destructive ones behind a full-screen confirmation of its own. Two
// surfaces describing one list of verbs, one of which had to grow a Restart row
// after the other already had one. The button now opens the power menu the
// physical power key opens, so there is one power surface in the shell and the
// menu *is* the confirmation.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/power/power_menu_controller.dart';
import 'package:graceful_shell/scopes.dart';

/// The bar's power icon.
class System extends StatelessWidget {
  const System({super.key, this.controller});

  /// The controller this pokes. Defaults to the singleton the root listens to;
  /// a widget test passes its own.
  final PowerMenuController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return BarButton(
      // Tap-*down*, like every other button in the bar that opens a surface:
      // `PopupDismissArea`'s ancestor `Listener` fires before any descendant
      // recognizer, and the coordinator's reopen guard is armed and consumed
      // inside that one pointer-down — so a menu opened from `onTap` would be
      // dismissed by the very press that opened it.
      onTapDown: (_) => (controller ?? PowerMenuController.instance).toggle(),
      child: FaIcon(
        FontAwesomeIcons.powerOff,
        size: 12,
        color: theme.foreground,
      ),
    );
  }
}

final Module systemModule = Module.plain(
  configKey: 'system',
  builder: (_) => const System(),
);
