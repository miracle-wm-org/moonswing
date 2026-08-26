// The power menu the physical power button opens: a row of large targets over
// a full-screen layer-shell backdrop, one per [PowerAction].
//
// The actions are injected (`onAction`), so a widget test drives the whole
// surface without suspending the machine it runs on.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/overlay_fade_scaffold.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/power/power_actions.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// Width and height of one action tile. Large because the surface this opens
/// on is the whole output and the gesture that opened it was a *physical
/// button*: whatever the user does next, they are not aiming carefully yet.
const double kPowerTileSize = 112;

/// The full-screen power menu.
///
/// Unlike the bar's power popup this asks for no confirmation. The two are
/// reached differently and that is the whole difference: the popup is one
/// small target among a row of bar icons, where a mis-click lands on a verb
/// nobody aimed at, while this menu *is* the confirmation: it appears
/// because the power button was pressed, and answering "shut down" to a
/// dialog that opened for exactly that reason is a second deliberate act.
class PowerMenuOverlay extends StatefulWidget {
  const PowerMenuOverlay({
    super.key,
    required this.closingNotifier,
    required this.onClosed,
    required this.onAction,
    this.actions = kPowerMenuActions,
    this.initialAction = PowerAction.shutdown,
  });

  /// Flipped by the owner to start the exit animation; [onClosed] follows.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// Perform this verb. The overlay animates itself out either way — it does
  /// not wait for the machine to go down, because on `lock` and `logout` it
  /// never does.
  final void Function(PowerAction action) onAction;

  final List<PowerAction> actions;

  /// What Enter answers with before the user has moved. Shut Down, because
  /// this dialog is what a power-button press opens and powering off is what
  /// that press asked for — so the fast path is press, glance, Enter. The two
  /// ways out are Escape and a click outside, and the card says so under the
  /// tiles rather than spending a sixth tile on Cancel.
  final PowerAction initialAction;

  @override
  State<PowerMenuOverlay> createState() => _PowerMenuOverlayState();
}

class _PowerMenuOverlayState extends State<PowerMenuOverlay> {
  late int _selected = _initialIndex;
  bool _answered = false;

  int get _initialIndex {
    final index = widget.actions.indexOf(widget.initialAction);
    return index < 0 ? 0 : index;
  }

  void _move(int delta) {
    if (widget.actions.isEmpty) return;
    setState(() {
      _selected = (_selected + delta) % widget.actions.length;
      if (_selected < 0) _selected += widget.actions.length;
    });
  }

  /// Runs [action] and dismisses. Latched: `lock` and `logout` leave the shell
  /// running, so a second press on a tile that is still fading out would run
  /// the verb twice.
  void _activate(PowerAction action) {
    if (_answered) return;
    _answered = true;
    widget.onAction(action);
    widget.closingNotifier.value = true;
  }

  void _cancel() {
    if (_answered) return;
    _answered = true;
    widget.closingNotifier.value = true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _cancel();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.tab:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.space:
        if (widget.actions.isNotEmpty) _activate(widget.actions[_selected]);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Its own text root, like the launcher and settings overlays: the window
    // chrome supplies one, but a widget test pumping this on its own must not
    // have to, and every `Text` below needs a `Directionality` in release as
    // well as in debug.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: theme.fontFamily,
          fontSize: ShellFontSizes.body,
          color: theme.popupForeground,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.normal,
        ),
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: FadeOverlayScaffold(
            closing: widget.closingNotifier,
            onClosed: widget.onClosed,
            // The shell has no input-region support, so this surface swallows
            // every click on the monitor: without dismiss-on-backdrop a
            // mouse-only user would have no way out of a menu they opened by
            // brushing the case.
            onBackdropTap: _cancel,
            // Never flush against the edges of a small output; what is
            // outside this is backdrop, so a click there still dismisses.
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: GestureDetector(
                // The card is not the backdrop; a click that lands between
                // two tiles must not answer the dialog.
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: PopupCard(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Power',
                        style: TextStyle(
                          fontSize: ShellFontSizes.title,
                          fontWeight: FontWeight.w600,
                          color: theme.popupForeground,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // A [Wrap] rather than a [Row]: five tiles are 600px
                      // across and the surface is one output wide, which on a
                      // small or rotated display is not enough — and a row
                      // that overflows reports it every frame on a surface
                      // whose console nobody is reading.
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final (index, action)
                              in widget.actions.indexed)
                            _PowerTile(
                              action: action,
                              selected: index == _selected,
                              onTap: () => _activate(action),
                              onHover: () => setState(() => _selected = index),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Esc or a click outside cancels',
                        style: TextStyle(
                          fontSize: ShellFontSizes.secondary,
                          color: theme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One action: its glyph over its label, in a square big enough to hit
/// without looking.
class _PowerTile extends StatelessWidget {
  const _PowerTile({
    required this.action,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final PowerAction action;

  /// Whether the keyboard is on this tile. Hover moves it, so the pointer and
  /// the arrow keys cannot disagree about what Enter would do.
  final bool selected;

  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      onEnter: onHover,
      builder: (context, hovered) {
        final highlighted = hovered || selected;
        return AnimatedContainer(
          duration: ShellDurations.fast,
          width: kPowerTileSize,
          height: kPowerTileSize,
          // Selection and hover are one state on purpose: entering a tile
          // moves the selection to it, so a rim that marked "the keyboard is
          // here" separately from the fill would only ever mark the tile the
          // fill already marks. The unselected rim is what keeps the tiles
          // legible under a theme whose `surface_hover` is nearly clear.
          decoration: BoxDecoration(
            color: highlighted ? theme.accent : theme.surfaceHover,
            borderRadius: BorderRadius.circular(ShellRadii.card),
            border: Border.all(
              color: highlighted ? theme.accent : theme.divider,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(
                action.icon,
                size: 26,
                color: highlighted ? kOnAccent : theme.popupForeground,
              ),
              const SizedBox(height: 12),
              Text(
                action.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ShellFontSizes.body,
                  color: highlighted ? kOnAccent : theme.popupForeground,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
