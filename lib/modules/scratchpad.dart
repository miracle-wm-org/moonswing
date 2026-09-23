// The scratchpad button: one click shows what the window manager has stashed
// on its scratchpad, or hides it again.
//
// The module owns nothing. The commands go through [ScratchpadStore], which the
// two `[shortcuts]` keys share, so a toggle from the keyboard and one from any
// bar on any monitor are the same toggle. What is left here is the button and
// its hover label — and the label is where the keys are told, because this is
// the one feature whose most common half (stashing a window) the button cannot
// do for you: a click on the bar is a click away from the window you meant.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/input_trigger/keysym.dart';
import 'package:moonswing/keybinds/shell_keybind_store.dart';
import 'package:moonswing/keybinds/shell_keybinds.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_coordinator.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/scratchpad/scratchpad_store.dart';
import 'package:moonswing/theme/popup_effect.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/tokens.dart';

/// What the hover label says, a line at a time.
///
/// [shortcuts] is what the shell *registered* at start-up, not what the config
/// says now: the label describes what the keys on the keyboard do, and an edit
/// on the cheat sheet does nothing until a restart.
String scratchpadTooltip(ShortcutsConfig shortcuts, {String? error}) {
  String keys(ShortcutSpec? spec) =>
      spec == null ? kShellShortcutDisabled : shortcutLabel(spec);
  return [
    'Scratchpad — click to show or hide',
    '${keys(shortcuts.toggleScratchpad)}  show or hide',
    '${keys(shortcuts.moveToScratchpad)}  move the focused window here',
    ?error,
  ].join('\n');
}

class ScratchpadButton extends StatefulWidget {
  const ScratchpadButton({super.key, this.store, this.shortcuts});

  /// The store this drives. Defaults to the singleton; a widget test passes
  /// its own, which is what keeps this testable with no compositor behind it.
  final ScratchpadStore? store;

  /// The keys the label names. Defaults to what the shell registered.
  final ShortcutsConfig? shortcuts;

  @override
  State<ScratchpadButton> createState() => _ScratchpadButtonState();
}

class _ScratchpadButtonState extends State<ScratchpadButton>
    with PopupHost<ScratchpadButton> {
  ScratchpadStore get _store => widget.store ?? ScratchpadStore.instance;

  /// Whether the pointer is over the button. A field, not state: nothing is
  /// drawn from it — `BarButton` does its own hover fill — and a `setState`
  /// per crossing would rebuild the button for nothing.
  bool _hovered = false;

  @override
  void dispose() {
    closePopup();
    super.dispose();
  }

  void _openTooltip(BuildContext context) {
    if (isPopupOpen) return;
    final store = _store;
    final shortcuts =
        widget.shortcuts ?? ShellKeybindStore.instance.registered;
    openBarPopup(
      context,
      child: ThemeProvider(
        // Listening, so a click that fails while the label is up says so on
        // the label rather than on the next hover.
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => TooltipLabel(
            text: scratchpadTooltip(shortcuts, error: store.error),
          ),
        ),
      ),
      preferredConstraints: const BoxConstraints(maxWidth: 320, maxHeight: 96),
      // A hover label displaces nothing, and never attaches to the bar — see
      // the dock's tooltip.
      policy: TransientPolicy.tooltip,
      attach: false,
      effect: PopupEffect.none,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _hovered) _openTooltip(context);
        });
      },
      onExit: (_) {
        _hovered = false;
        closePopup();
      },
      child: ListenableBuilder(
        listenable: _store,
        builder: (context, child) => BarButton(
          // Tap-down, like every bar button: the press that toggles is also
          // the one `PopupDismissArea` reads, and it takes the label down.
          onTapDown: (_) => _store.toggle(),
          child: FaIcon(
            FontAwesomeIcons.noteSticky,
            size: ShellFontSizes.secondary,
            // Muted after a failure, which is the button's half of saying so;
            // the label says why, and the next click is the retry.
            color: _store.error == null ? theme.foreground : theme.muted,
          ),
        ),
      ),
    );
  }
}

final Module scratchpadModule = Module.plain(
  configKey: 'scratchpad',
  builder: (context) => const ScratchpadButton(),
);
