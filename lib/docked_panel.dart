// A column docked against the left or right edge of an output: the shape the
// clipboard history and the notification panel share.
//
// The window is the root's (`_createDockedWindow` in `main.dart`), and its
// shape is what these two panels are:
//
// - **It never takes the keyboard.** Keyboard mode `none`, like a bar: both
//   panels are read beside the window the user is working in, and a surface
//   that took focus on every click would take it off that window. So there is
//   no Escape; everything is a click or the scroll wheel, both of which reach a
//   surface without focus.
// - **It stays until asked to go.** Its own close button, or whatever opened
//   it. The coordinator registration is non-dismissable, so neither a click
//   elsewhere nor another popup opening takes it down.
// - **It reserves its width.** An exclusive zone the width of the panel, so
//   the compositor moves windows out of its way rather than under it — and two
//   panels docked against the same edge sit side by side rather than on top of
//   each other, since each is placed clear of the zones already reserved.
//
// This file is the part of that both panels draw: the slide in and out of the
// docked edge, the opaque fill with its one inner rule, and the header.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// Which edge of the output a docked panel is against.
enum DockSide {
  left,
  right;

  /// The config spelling, for the settings row and the round trip.
  String get configName => name;

  /// [raw] as a side, or [fallback] for anything that is not one — a typo
  /// costs the key, never the table.
  static DockSide parse(String? raw, {DockSide fallback = DockSide.left}) =>
      switch (raw?.trim().toLowerCase()) {
        'left' => DockSide.left,
        'right' => DockSide.right,
        _ => fallback,
      };
}

/// The narrowest a docked panel may be configured: room for a line of text on a
/// card. Shared so the two panels' `width` keys clamp alike.
const int kDockedPanelMinWidth = 240;

/// The widest: a typo must not hand the whole output to a panel.
const int kDockedPanelMaxWidth = 1200;

/// How long a docked panel takes to arrive.
const Duration kDockedPanelEnter = ShellDurations.slow;

/// How long it takes to leave: an exit is the user being done, and does not
/// need the entrance's pace.
const Duration kDockedPanelExit = ShellDurations.base;

/// The panel's frame: it slides out of [side] on creation and back into it once
/// [closingNotifier] flips, then calls [onClosed] — which may tear the window
/// down, so it is called exactly once.
class DockedPanel extends StatefulWidget {
  const DockedPanel({
    super.key,
    required this.side,
    required this.closingNotifier,
    required this.onClosed,
    required this.child,
  });

  /// The edge the window is docked against, which the panel slides in from.
  final DockSide side;

  /// Flipped by whoever wants the panel gone. Starts the exit; [onClosed]
  /// tears the window down after it.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  final Widget child;

  @override
  State<DockedPanel> createState() => _DockedPanelState();
}

class _DockedPanelState extends State<DockedPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  /// Set by the dismissal that started the exit. A second one mid-exit must not
  /// queue a second `onClosed`, which would tear the window down twice.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kDockedPanelEnter,
      reverseDuration: kDockedPanelExit,
    );
    // Out of, and back into, the edge the panel is docked against: anything
    // moving the other way — an overshoot, a centre-pivoted scale — would open
    // a strip between the panel and the screen edge.
    final away = widget.side == DockSide.left ? -1.0 : 1.0;
    _slide = Tween<Offset>(begin: Offset(away, 0), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _controller.forward();
    widget.closingNotifier.addListener(_onClosingRequested);
  }

  @override
  void dispose() {
    widget.closingNotifier.removeListener(_onClosingRequested);
    _controller.dispose();
    super.dispose();
  }

  void _onClosingRequested() {
    if (!widget.closingNotifier.value || _leaving) return;
    _leaving = true;
    // Reversing rather than starting over: a close that lands mid-entrance
    // turns the panel around from wherever it had got to.
    _controller.reverse().then((_) => widget.onClosed());
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // The inner edge, the one that faces the windows, gets the divider line;
    // the outer one is the screen edge and a line there would be drawn on
    // nothing.
    final inner = BorderSide(color: theme.divider);
    return PopupDismissArea(
      // A click in the panel is a click elsewhere as far as any bar popup is
      // concerned. The panel's own registration refuses dismissal, so it is
      // the one thing this leaves open.
      child: Directionality(
        // Its own, for the tests that pump a panel bare; on a real window
        // `ShellTextRoot` has already said the same.
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            color: theme.popupForeground,
          ),
          child: ClipRect(
            child: SlideTransition(
              position: _slide,
              // Deliberately not a PopupCard: a full-height surface against
              // the screen edge, where rounding would cut wallpaper wedges out
              // of the display's corners and a rim would draw a line down the
              // screen edge.
              child: Container(
                // Opaque whatever the theme says: this is read over whatever
                // window would otherwise show through, and the reserved zone
                // means there is never anything under it worth seeing. Only
                // the alpha is overridden, so a palette still tints it.
                decoration: BoxDecoration(
                  color: theme.popupBackground.withValues(alpha: 1.0),
                  border: widget.side == DockSide.left
                      ? Border(right: inner)
                      : Border(left: inner),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The title, a line saying what is in the panel, whatever acts on the whole
/// of it, and the close button.
class DockedPanelHeader extends StatelessWidget {
  const DockedPanelHeader({
    super.key,
    required this.title,
    required this.summary,
    required this.onClose,
    this.actions = const [],
  });

  final String title;
  final String summary;
  final VoidCallback onClose;

  /// Between the title and the close button — a [DockedPanelTextButton] or an
  /// icon. Each is followed by a small gap.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: ShellFontSizes.heading,
                    fontWeight: FontWeight.bold,
                    color: theme.popupForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: theme.popupForeground.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          for (final action in actions) ...[action, const SizedBox(width: 6)],
          SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            box: ShellSizes.iconButton + 6,
            size: ShellFontSizes.title,
            color: theme.popupForeground,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

/// A bordered word in the header — the destructive act on the whole panel
/// ("Clear"), which is why it is a word and not an icon.
///
/// A tint of the accent it is lettered in when hovered, never `surface_hover`
/// at full strength: that key is the accent itself in the shipped palette, so
/// the word would disappear into its own button under the pointer.
class DockedPanelTextButton extends StatelessWidget {
  const DockedPanelTextButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        height: ShellSizes.iconButton + 4,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? theme.accent.withValues(alpha: 0.18) : null,
          border: Border.all(
            color: theme.accent.withValues(alpha: hovered ? 0.9 : 0.5),
          ),
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            color: theme.accentText,
          ),
        ),
      ),
    );
  }
}

/// A card on a docked panel: the control surface, a hover tint, and a hairline
/// border — or [ring], for the one card the panel is drawing attention to.
BoxDecoration dockedPanelCardDecoration(
  BuildContext context, {
  required bool hovered,
  Color? ring,
}) {
  final theme = ThemeScope.of(context);
  return BoxDecoration(
    color: hovered
        ? theme.surfaceHover.atMostAlpha(0.14)
        : theme.controlSurface,
    borderRadius: BorderRadius.circular(ShellRadii.card),
    border: Border.all(color: ring ?? theme.divider),
  );
}

/// The empty state, which is also the panel's instructions.
class DockedPanelEmpty extends StatelessWidget {
  const DockedPanelEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final FaIconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              icon,
              size: 40,
              color: theme.popupForeground.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.label,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                height: 1.4,
                color: theme.popupForeground.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
