import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Tab and Shift+Tab move the keyboard focus to the next and previous field.
///
/// The shell boots without a `WidgetsApp`, and that is where both halves of
/// this live: the shortcuts binding Tab to [NextFocusIntent], and the
/// [NextFocusAction] that answers it. Without them Tab reached nothing — and
/// `DefaultTextEditingShortcuts`, which every window with a text field already
/// supplies, binds no Tab on Linux, so a settings page with twenty fields could
/// only be walked with the mouse.
///
/// The order is the enclosing `FocusTraversalGroup`'s — reading order, from the
/// `View` — and stays inside the nearest `FocusScope`, so a pane behind a nested
/// `Navigator` cycles through its own fields. A single-line `EditableText`
/// selects its text when focus lands on it this way (`selectAllOnFocus`, on by
/// default on desktop), so a number tabbed into is replaced by typing.
///
/// A `Focus` that only listens for keys around a field is a stop of its own
/// and has to say `skipTraversal: true`, or Tab pauses on it with nothing drawn
/// as focused.
class TabFocusTraversal extends StatelessWidget {
  const TabFocusTraversal({super.key, required this.child});

  final Widget child;

  static const Map<ShortcutActivator, Intent> _shortcuts = {
    SingleActivator(LogicalKeyboardKey.tab): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.tab, shift: true): PreviousFocusIntent(),
  };

  // Shared, as `WidgetsApp.defaultActions` shares its own: an action carries no
  // per-widget state, only the listeners each `Actions` adds and removes.
  static final Map<Type, Action<Intent>> _actions = {
    NextFocusIntent: NextFocusAction(),
    PreviousFocusIntent: PreviousFocusAction(),
  };

  @override
  Widget build(BuildContext context) => Shortcuts(
    debugLabel: 'Tab focus traversal',
    shortcuts: _shortcuts,
    child: Actions(actions: _actions, child: child),
  );
}
