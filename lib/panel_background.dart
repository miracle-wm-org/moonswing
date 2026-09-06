import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';

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
/// Returns [BorderRadius.zero] for a radius of 0, which callers use to skip the
/// clip layer.
BorderRadius panelCornerRadius({
  String anchor = 'top',
  required ThemeConfig theme,
}) {
  if (theme.panelRadius <= 0) return BorderRadius.zero;
  final r = Radius.circular(theme.panelRadius);
  if (theme.panelMargin > 0) return BorderRadius.all(r);

  switch (anchor) {
    case 'bottom':
      return BorderRadius.only(topLeft: r, topRight: r);
    case 'left':
      return BorderRadius.only(topRight: r, bottomRight: r);
    case 'right':
      return BorderRadius.only(topLeft: r, bottomLeft: r);
    case 'top':
    default:
      return BorderRadius.only(bottomLeft: r, bottomRight: r);
  }
}

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
BoxDecoration panelBackgroundDecoration({
  String anchor = 'top',
  required ThemeConfig theme,
}) {
  final radius = panelCornerRadius(anchor: anchor, theme: theme);
  // Normalised to null rather than BorderRadius.zero so that an untouched
  // theme produces exactly the decoration it did before corners were themable.
  final BorderRadius? borderRadius =
      radius == BorderRadius.zero ? null : radius;
  final border = _panelBorder(theme);

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
