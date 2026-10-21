import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/settings/controls.dart' show SettingsTooltip;
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';

/// One of the overview's corner buttons: something done *in* the overview
/// rather than on one of its tabs.
class OverviewAction {
  const OverviewAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final FaIconData icon;

  /// What it does, shown on hover — an icon alone rarely says.
  final String label;
  final VoidCallback onTap;
  final bool enabled;
}

/// How far the action buttons sit in from the output's top-left corner.
const double kOverviewActionInset = 16;

/// One action button's diameter.
const double kOverviewActionSize = 40;

const double _kActionGap = 8;

/// The box [count] action buttons cover, for anything placed around them —
/// a new sticky note is never put under one.
Rect overviewActionBarRect(int count) => Rect.fromLTWH(
  kOverviewActionInset,
  kOverviewActionInset,
  count == 0 ? 0 : count * kOverviewActionSize + (count - 1) * _kActionGap,
  kOverviewActionSize,
);

/// The box of the action button at [index], counting from the left — what a
/// card the button opens is anchored under.
Rect overviewActionRect(int index) => Rect.fromLTWH(
  kOverviewActionInset + index * (kOverviewActionSize + _kActionGap),
  kOverviewActionInset,
  kOverviewActionSize,
  kOverviewActionSize,
);

/// The overview's corner buttons: a row of round actions floating at the
/// output's top-left, on every tab, because they are the window's rather than
/// the panel's — they stay put when the panel is dragged.
class OverviewActionBar extends StatelessWidget {
  const OverviewActionBar({super.key, required this.actions});

  final List<OverviewAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, action) in actions.indexed) ...[
          if (i > 0) const SizedBox(width: _kActionGap),
          _OverviewActionButton(action: action),
        ],
      ],
    );
  }
}

class _OverviewActionButton extends StatelessWidget {
  const _OverviewActionButton({required this.action});

  final OverviewAction action;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Its own layer, so the hover tint repaints a button and not the output.
    return RepaintBoundary(
      child: SettingsTooltip(
        message: action.label,
        child: HoverRegion(
          enabled: action.enabled,
          onTap: action.onTap,
          builder: (context, hovered) => Container(
            width: kOverviewActionSize,
            height: kOverviewActionSize,
            decoration: BoxDecoration(
              // Opaque, like the panel: the button floats over the scrim and
              // whatever the compositor shows through it.
              color: hovered
                  ? Color.alphaBlend(theme.surfaceHover, opaquePopupFill(theme))
                  : opaquePopupFill(theme),
              shape: BoxShape.circle,
              border: Border.all(color: hovered ? theme.accent : theme.divider),
            ),
            child: Center(
              child: FaIcon(
                action.icon,
                size: 16,
                color: !action.enabled
                    ? theme.muted
                    : hovered
                    ? theme.accentText
                    : theme.popupForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A menu over something floating in the overview — a sticky note's, a
/// timer's — or the timer button's composer, drawn in the overview's own
/// window as the todo board's card menu is: a full-screen overlay never opens a
/// native popup, and there is no outside of this window for one to need to
/// reach. A click anywhere off the card closes it.
class OverviewMenuLayer extends StatelessWidget {
  const OverviewMenuLayer({
    super.key,
    required this.at,
    required this.card,
    required this.onDismiss,
  });

  /// Where the card's top-left corner goes, slid back onto the output where
  /// it would hang off it.
  final Offset at;
  final Widget card;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            onSecondaryTapDown: (_) => onDismiss(),
          ),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _AtPointerLayout(at),
            // Absorbs clicks on the card's own chrome, which would otherwise
            // fall through to the barrier.
            child: Listener(behavior: HitTestBehavior.opaque, child: card),
          ),
        ),
      ],
    );
  }
}

/// Puts the menu's top-left corner at the pointer, slid back onto the output
/// where it would hang off its right or bottom edge.
class _AtPointerLayout extends SingleChildLayoutDelegate {
  const _AtPointerLayout(this.at);

  final Offset at;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    at.dx.clamp(0, (size.width - childSize.width).clamp(0, double.infinity)),
    at.dy.clamp(0, (size.height - childSize.height).clamp(0, double.infinity)),
  );

  @override
  bool shouldRelayout(_AtPointerLayout oldDelegate) => oldDelegate.at != at;
}
