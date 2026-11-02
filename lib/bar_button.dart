import 'package:flutter/widgets.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The chrome around a bar module's clickable area.
///
/// Seven modules used to hand-roll these fifteen lines each, all with a
/// hard-coded `0x28FFFFFF` hover fill — which made bar-button hover the one hover
/// in the shell that ignored `theme.surfaceHover`. The fill now comes from the
/// theme, at the alpha the old constant had.
class BarButton extends StatelessWidget {
  const BarButton({
    super.key,
    this.active = false,
    this.onTapDown,
    this.onSecondaryTapDown,
    required this.child,
  });

  /// Keeps the fill on independent of the pointer — the module's popup is
  /// open, so the button should read as pressed.
  final bool active;

  final GestureTapDownCallback? onTapDown;
  final GestureTapDownCallback? onSecondaryTapDown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      // Tap-*down*, not tap: every popup toggle in the shell opens inside the
      // pointer-down that arms the coordinator's reopen guard.
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      builder: (context, hovered) => Container(
        decoration: BoxDecoration(
          color: (hovered || active)
              ? theme.surfaceHover.atMostAlpha(0.16)
              : null,
          borderRadius: BorderRadius.circular(ShellRadii.barButton),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: BarFill(child: child),
      ),
    );
  }
}

/// Stretches a bar module's hover fill across the bar's whole depth, keeping
/// the module's own length.
///
/// The bar hands every module the full depth as a *loose* constraint — the
/// sections are `Row`s and `Column`s centred in a `Stack` — so a fill sized by
/// its content came out as tall as its glyph plus padding: the camera's was a
/// sliver around the icon while the clock's, set in larger type, was most of
/// the bar. Every module's fill goes on the outside of one of these, so all of
/// them read as one height on hover.
///
/// An [Align] with the factor along the bar's length pinned to 1: it shrink-
/// wraps that way (a `Row` lays its children out unbounded there anyway, but a
/// module that bounds one must not have its button swallow the room) and takes
/// whatever the bar's depth allows the other way, centring [child] in it.
/// Outside a bar — no [BarScope] — both factors are pinned, so it is sized
/// to [child] and only centres it in whatever minimum it is given.
class BarFill extends StatelessWidget {
  const BarFill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final anchor = BarScope.maybeOf(context);
    final vertical = anchor == 'left' || anchor == 'right';
    return Align(
      widthFactor: anchor != null && vertical ? null : 1,
      heightFactor: anchor != null && !vertical ? null : 1,
      child: child,
    );
  }
}
