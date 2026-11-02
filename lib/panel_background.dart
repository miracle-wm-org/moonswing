import 'package:flutter/widgets.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/panel_join.dart';

/// The background drawn behind a panel's modules.
///
/// The bar's colour is [ThemeConfig.panelBackground] and its alpha is honoured as
/// written, so a translucent theme can see through the surface that sits directly
/// on the desktop.
///
/// With [ThemeConfig.panelGradient] the bar fades from `accent` through
/// `surfacePressed` to that colour, with the bright end against the panel's own
/// edge: top → left-aligned, bottom → right, left → top, right → bottom.
///
/// Every stop takes its alpha from `panelBackground`, not from its own colour, so
/// the bar has exactly one opacity and no stop can read as a band across it.
///
/// Both shapes carry the bar's rim and its corner rounding
/// ([panelCornerRadius]); a theme that sets neither gets the decoration it
/// always did.
///
/// The bar's corner rounding, from [ThemeConfig.panelRadius].
///
/// A floating bar rounds all four corners. A flush one rounds only the two facing
/// the screen's interior: rounding the pair against the screen edge would cut
/// wallpaper wedges out of the display's own corners.
///
/// At an end that meets another flush bar ([joins], while the theme has a
/// `panel_join_radius`), the inner corner there is square instead: the two bars
/// are one frame across that corner, and a rounded one would cut a notch out of
/// it — the fillet is what turns it now (`panel_join.dart`).
///
/// Returns [BorderRadius.zero] for a radius of 0, which callers use to skip the
/// clip layer.
BorderRadius panelCornerRadius({
  String anchor = 'top',
  required ThemeConfig theme,
  PanelJoins joins = PanelJoins.none,
}) {
  if (theme.panelRadius <= 0) return BorderRadius.zero;
  final r = Radius.circular(theme.panelRadius);
  if (theme.panelMargin > 0) return BorderRadius.all(r);

  final joined = activePanelJoins(theme, joins);
  final start = joined.start > 0 ? Radius.zero : r;
  final end = joined.end > 0 ? Radius.zero : r;
  final BorderRadius radius;
  switch (anchor) {
    case 'bottom':
      radius = BorderRadius.only(topLeft: start, topRight: end);
    case 'left':
      radius = BorderRadius.only(topRight: start, bottomRight: end);
    case 'right':
      radius = BorderRadius.only(topLeft: start, bottomLeft: end);
    case 'top':
    default:
      radius = BorderRadius.only(bottomLeft: start, bottomRight: end);
  }
  return radius == BorderRadius.zero ? BorderRadius.zero : radius;
}

/// The breathing room between a module's fill and the bar's edge.
const double kPanelModuleGap = 2;

/// How far the modules sit in from each long edge of the bar: the rim's width,
/// then [kPanelModuleGap].
///
/// A module's hover or active fill takes the bar's whole depth (`BarFill`), and
/// laid out across the bar's full box it ran over the rim — both the
/// decoration's `Border` and `PanelRimPainter` stroke *inside* the bar's box —
/// so a highlighted workspace sat flush against, and on top of, the line around
/// it. The panel insets its module area by this across its depth, and anything
/// that sizes itself to `BarScope.thickness` subtracts it twice.
double panelModuleInset(ThemeConfig theme) =>
    (theme.panelBorderWidth > 0 ? theme.panelBorderWidth : 0) +
    kPanelModuleGap;

/// The bar's rim, or null when [ThemeConfig.panelBorderWidth] is 0.
///
/// Width is the off switch rather than alpha, and null rather than a zero-width
/// [Border] on purpose: a `Border` in the decoration carries a non-zero
/// [BoxDecoration.padding], which a [Container] would apply to the bar's content.
Border? _panelBorder(ThemeConfig theme) => theme.panelBorderWidth > 0
    ? Border.all(color: theme.panelBorder, width: theme.panelBorderWidth)
    : null;

/// [theme] is required on purpose: a defaulted palette here would silently
/// paint the built-in colours over whatever theme is actually active.
///
/// [includeRim] false leaves the border out for a bar that paints its own —
/// which is a bar whose theme attaches its popups and carries a rim, because
/// that rim has to be interrupted across the mouth of an open menu and no
/// [Border] can have a gap in it. `panelPaintsOwnRim` (`panel_rim.dart`) is the
/// predicate, [PanelRimPainter] draws what this then leaves out, and the two
/// agree on the outline: `Border.all` strokes it deflated by half its width and
/// so does the painter.
///
/// [joins] squares the corners [panelCornerRadius] squares.
BoxDecoration panelBackgroundDecoration({
  String anchor = 'top',
  required ThemeConfig theme,
  bool includeRim = true,
  PanelJoins joins = PanelJoins.none,
}) {
  final radius = panelCornerRadius(anchor: anchor, theme: theme, joins: joins);
  // Normalised to null rather than BorderRadius.zero so that an untouched
  // theme produces exactly the decoration it did before corners were themable.
  final BorderRadius? borderRadius =
      radius == BorderRadius.zero ? null : radius;
  final border = includeRim ? _panelBorder(theme) : null;

  if (!theme.panelGradient) {
    return BoxDecoration(
      color: theme.panelBackground,
      borderRadius: borderRadius,
      border: border,
    );
  }

  final alpha = theme.panelBackground.a;
  final dark = theme.panelBackground;
  final mid = theme.surfacePressed.withValues(alpha: alpha);
  final light = theme.accent.withValues(alpha: alpha);

  late final Alignment begin;
  late final Alignment end;
  switch (anchor) {
    case 'bottom':
      begin = Alignment.centerRight;
      end = Alignment.centerLeft;
      break;
    case 'left':
      begin = Alignment.topCenter;
      end = Alignment.bottomCenter;
      break;
    case 'right':
      begin = Alignment.bottomCenter;
      end = Alignment.topCenter;
      break;
    case 'top':
    default:
      begin = Alignment.centerLeft;
      end = Alignment.centerRight;
      break;
  }

  return BoxDecoration(
    gradient: LinearGradient(
      begin: begin,
      end: end,
      colors: [light, mid, dark],
      stops: const [0.0, 0.5, 1.0],
    ),
    borderRadius: borderRadius,
    border: border,
  );
}
