import 'dart:math' as math;

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
        // The inset runs along the bar: a side bar is as narrow as a top bar
        // is short, so the generous half goes down it rather than across.
        padding: BarScope.isVerticalOf(context)
            ? const EdgeInsets.symmetric(horizontal: 2, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    final vertical = BarScope.isVerticalOf(context);
    return Align(
      widthFactor: anchor != null && vertical ? null : 1,
      heightFactor: anchor != null && !vertical ? null : 1,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Laying a module out along the bar
// ---------------------------------------------------------------------------
//
// A side bar is a column `height` pixels wide, so whatever a module puts beside
// its glyph on a top bar has to go somewhere else there. Three answers, and
// every module uses these rather than reading the anchor itself:
//
// - [BarFlex]: what sits *beside* on a top bar sits *below* on a side one — the
//   glyph and its reading, a row of workspaces, the transport buttons.
// - [BarText]: a short reading under a glyph (`42%`, `21°`, `US`), set no
//   larger than the bar's secondary size there and scaled down to the bar's
//   depth if it still does not fit, rather than wrapping a digit per line.
// - [BarRotated]: running text (the clock, a track title, a network name) is
//   turned on its side to read along the bar instead.

/// A [Row] on a top or bottom bar and a [Column] on a side one.
///
/// Both shrink-wrap along the bar and centre across it, so a module built from
/// one is as long as its content and sits in the middle of the bar's depth
/// whichever way the bar runs.
class BarFlex extends StatelessWidget {
  const BarFlex({
    super.key,
    this.spacing = 0,
    this.verticalSpacing,
    required this.children,
  });

  /// The gap between children on a top or bottom bar.
  final double spacing;

  /// The gap on a side bar, where it is between a glyph and the line under it
  /// rather than two things side by side. Defaults to [spacing].
  final double? verticalSpacing;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (BarScope.isVerticalOf(context)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        spacing: verticalSpacing ?? spacing,
        children: children,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: spacing,
      children: children,
    );
  }
}

/// Turns [child] on its side on a side bar, so text runs along the bar and
/// reads; passes it through untouched anywhere else.
///
/// The tops of the letters face the screen's edge on either side — a left bar
/// reads bottom to top and a right bar top to bottom — so the two mirror each
/// other the way the bars themselves do.
///
/// Goes *inside* a [BarFill], never around one: the fill measures the bar's
/// depth across its own box, and inside a [RotatedBox] that box is turned too.
class BarRotated extends StatelessWidget {
  const BarRotated({super.key, required this.child});

  final Widget child;

  /// Quarter turns clockwise for a bar on [anchor].
  static int quarterTurnsFor(String? anchor) => switch (anchor) {
        'left' => 3,
        'right' => 1,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final turns = quarterTurnsFor(BarScope.maybeOf(context));
    if (turns == 0) return child;
    return RotatedBox(quarterTurns: turns, child: child);
  }
}

/// A short reading set beside a module's glyph on a top or bottom bar and
/// under it on a side one: a percentage, a temperature, a count.
///
/// On a side bar it is one line, no larger than [ShellFontSizes.secondary], and
/// scaled down to fit the bar's depth if even that is too wide — a `100%` that
/// wrapped would be a digit per line down the bar, and one that overflowed
/// would paint into the next module.
class BarText extends StatelessWidget {
  const BarText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (!BarScope.isVerticalOf(context)) return Text(text, style: style);
    final size = style.fontSize;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: style.copyWith(
          fontSize: size == null
              ? ShellFontSizes.secondary
              : math.min(size, ShellFontSizes.secondary),
        ),
      ),
    );
  }
}

/// A thin rule between two groups in one module: upright on a top or bottom
/// bar, flat on a side one.
class BarDivider extends StatelessWidget {
  const BarDivider({
    super.key,
    required this.length,
    required this.color,
    this.margin = 4,
  });

  /// How far the rule reaches across the bar.
  final double length;
  final Color color;

  /// The gap either side of it, along the bar.
  final double margin;

  @override
  Widget build(BuildContext context) {
    final vertical = BarScope.isVerticalOf(context);
    return Container(
      width: vertical ? length : 1,
      height: vertical ? 1 : length,
      margin: vertical
          ? EdgeInsets.symmetric(vertical: margin)
          : EdgeInsets.symmetric(horizontal: margin),
      color: color,
    );
  }
}
