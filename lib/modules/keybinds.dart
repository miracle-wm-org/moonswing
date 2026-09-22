// The keyboard button that opens the miracle keybind cheat sheet.
//
// It creates no window of its own: it pokes [KeybindCheatsheetController],
// exactly as `launcher.dart` pokes its own — the root owns every window, and
// that is what keeps a shell with four bars from opening four sheets.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/keybinds/keybind_cheatsheet_controller.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The bar's keyboard icon.
class KeybindsButton extends StatelessWidget {
  const KeybindsButton({super.key, this.controller});

  /// The controller this pokes. Defaults to the singleton the root listens to;
  /// a widget test passes its own.
  final KeybindCheatsheetController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return BarButton(
      // Tap-*down*, like every other button in the bar that opens a surface:
      // `PopupDismissArea`'s ancestor `Listener` fires before any descendant
      // recognizer, and the coordinator's reopen guard is armed and consumed
      // inside that one pointer-down — so a sheet opened from `onTap` would be
      // dismissed by the very press that opened it.
      onTapDown: (_) =>
          (controller ?? KeybindCheatsheetController.instance).toggle(),
      child: FaIcon(
        FontAwesomeIcons.keyboard,
        size: ShellFontSizes.label,
        color: theme.foreground,
      ),
    );
  }
}

final Module keybindsModule = Module.plain(
  configKey: 'keybinds',
  builder: (context) => const KeybindsButton(),
);
