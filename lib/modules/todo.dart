// The bar's todo button: opens the board on the output it was clicked on.
//
// Like `keybinds.dart` it creates no window of its own — it pokes
// [TodoController] and the root owns the overlay, which is what keeps a shell
// with four bars from opening four boards.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/todo/todo_controller.dart';
import 'package:moonswing/todo/todo_store.dart';

/// The bar's checklist icon, with a count of what is due today or overdue.
class TodoButton extends StatelessWidget {
  const TodoButton({super.key, this.controller, this.store});

  /// Defaults to the singletons the root listens to; a widget test passes its
  /// own.
  final TodoController? controller;
  final TodoStore? store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = this.store ?? TodoStore.instance;
    return BarButton(
      // Tap-*down*, for the reason `KeybindsButton` gives: the coordinator's
      // reopen guard is armed and consumed inside the one pointer-down.
      onTapDown: (_) => (controller ?? TodoController.instance).toggle(
        // The connector, which is also the root's key for this output's
        // surfaces. Null while outputs are still being enumerated, and the
        // root then lets the compositor pick — the focused output, which is
        // where a click just happened.
        output: DisplayScope.of(context)?.name,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            FontAwesomeIcons.listCheck,
            size: ShellFontSizes.label,
            color: theme.foreground,
          ),
          // The store notifies on every drag on the board; the bar redraws
          // only when the number it shows moves.
          StoreSelector<int>(
            listenable: store,
            selector: () => store.dueCount,
            builder: (context, due) => due == 0
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Text(
                      '$due',
                      style: TextStyle(
                        fontSize: ShellFontSizes.secondary,
                        color: theme.foreground,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

final Module todoModule = Module.plain(
  configKey: 'todo',
  builder: (context) => const TodoButton(),
);
