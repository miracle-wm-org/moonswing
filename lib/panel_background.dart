import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';

/// The background drawn behind a panel's modules.
///
/// The bar's colour is [ThemeConfig.panelBackground] and its alpha is honoured
/// as written, so a translucent theme can see through the surface that sits
/// directly on the desktop. Before this the panel was painted from
/// `workspaceBackground` at a hardcoded 93%, which made it the one thing in the
/// shell no theme could open up.
///
/// With [ThemeConfig.panelGradient] the bar fades from `accent` through
/// `surfacePressed` to that colour, "aligned" to the panel's own edge — the
/// bright end sits against that edge:
///   top    -> left-aligned    bottom -> right-aligned
///   left   -> top-aligned     right  -> bottom-aligned
///
/// Every stop takes its alpha from `panelBackground`, not from its own colour.
/// The bar therefore has exactly one opacity: an author sets how see-through it
/// is in one place, and a stop cannot be more opaque than the rest of the bar
/// and read as a band across it.
///
/// Both shapes carry the bar's rim ([ThemeConfig.panelBorderWidth]) and its
/// corner rounding ([panelCornerRadius]); a theme that sets neither gets the
/// same decoration it always did.
///
/// The bar's corner rounding, from [ThemeConfig.panelRadius].
///
/// A floating bar ([ThemeConfig.panelMargin] > 0) rounds all four corners. A
/// flush one rounds only the two facing the screen's interior: rounding the
/// pair that sits against the screen edge would cut wallpaper wedges out of the
/// display's own corners and make the bar read as a misaligned card.
///
/// Returns [BorderRadius.zero] for a radius of 0, which callers use to skip
/// building a clip layer at all.
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
/// Width is the off switch rather than alpha, and null rather than a
/// zero-width [Border] on purpose: a `Border` in the decoration carries a
/// non-zero [BoxDecoration.padding], which a [Container] would silently apply
/// to the bar's content.
///
/// **A bar whose theme attaches its popups carries no rim on its inner edge**
/// — the edge every menu grows out of. `popup_gap = 0` is the attached mode
/// (see [ThemeConfig.popupGap]), and it says the card is flush with the bar and
/// made of the same material: the two are meant to read as one surface, and a
/// hairline along the join is the one thing that gives away that they are two.
///
/// It has to be the *panel* that declines to draw it, because the line is on
/// the panel's own surface. A popup is a separate compositor surface placed by
/// the compositor, so painting over the line is a trick that needs the two
/// surfaces to align to the pixel and needs `popup_background` to equal
/// `panel_background` — neither of which the shell can promise. Not drawing it
/// needs neither, and it is a decision the panel can make on its own: attaching
/// is a property of the *theme*, so the bar knows statically that its inner
/// edge is a join rather than a boundary, without knowing that any popup is
/// open or where its mouth is.
///
/// The other three sides are untouched. On a flush bar they sit against the
/// screen edges; on a floating one ([ThemeConfig.panelMargin] > 0) they are the
/// rim the user asked for, and only the joined edge is spared.
///
/// A non-uniform [Border] under a non-zero `borderRadius` is legal *because the
/// visible sides still share one colour*: `BoxBorder.paint` takes a
/// `paintNonUniformBorder` path — a `drawDRRect` whose inset is 0 on the side
/// left at [BorderStyle.none] — before it reaches the uniformity assert. That
/// path refuses hairline widths, which cannot arise here: no border is built at
/// all at or below a width of 0. This is `_popupBorder`'s note
/// (`popup_surface.dart`), which drops the card's own rim on the same join.
Border? _panelBorder(ThemeConfig theme, String anchor) {
  if (theme.panelBorderWidth <= 0) return null;
  final side =
      BorderSide(color: theme.panelBorder, width: theme.panelBorderWidth);
  if (theme.popupGap > 0) return Border.fromBorderSide(side);
  // [anchor] is the screen edge the bar is against, so the inner edge — the one
  // its menus are anchored to — is the opposite one.
  return switch (anchor) {
    'bottom' => Border(left: side, right: side, bottom: side),
    'left' => Border(top: side, bottom: side, left: side),
    'right' => Border(top: side, bottom: side, right: side),
    _ => Border(left: side, right: side, top: side), // 'top'
  };
}

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
  final border = _panelBorder(theme, anchor);

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
