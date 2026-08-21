import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/scopes.dart';

/// A popup card's corner rounding, from [ThemeConfig.popupRadius].
///
/// All four corners, always — unlike `panelCornerRadius`, which spares the pair
/// sitting against the screen edge. A popup is a free-floating card over a
/// transparent surface, so there is no display corner behind it to cut into.
///
/// Returns [BorderRadius.zero] for a radius of 0, which [PopupCard] uses to
/// skip building a clip layer at all.
BorderRadius popupCornerRadius(ThemeConfig theme) => theme.popupRadius <= 0
    ? BorderRadius.zero
    : BorderRadius.circular(theme.popupRadius);

/// The card's rim, or null when [ThemeConfig.popupBorderWidth] is 0.
///
/// Null rather than a zero-width [Border] on purpose, the same nuance
/// `panel_background.dart` documents: a `Border` in the decoration carries a
/// non-zero [BoxDecoration.padding], which a [Container] would silently add to
/// its child's own padding.
Border? _popupBorder(ThemeConfig theme) => theme.popupBorderWidth > 0
    ? Border.all(color: theme.popupBorder, width: theme.popupBorderWidth)
    : null;

/// The surface every popup, menu, flyout and OSD card paints.
///
/// [theme] is required for the same reason `panelBackgroundDecoration`'s is: a
/// defaulted palette here would silently paint the built-in colours over
/// whatever theme is actually active.
///
/// [border] *replaces* the theme's rim rather than adding to it. It exists for
/// the one card whose border carries meaning rather than chrome — the kill
/// confirmation's accent rim, which marks a destructive action.
BoxDecoration popupDecoration({required ThemeConfig theme, Border? border}) {
  final radius = popupCornerRadius(theme);
  return BoxDecoration(
    color: theme.popupBackground,
    // Normalised to null rather than BorderRadius.zero so a square card builds
    // exactly the decoration — and the layers — it did before corners were
    // themable.
    borderRadius: radius == BorderRadius.zero ? null : radius,
    border: border ?? _popupBorder(theme),
  );
}

/// The card every popup, flyout, menu and OSD renders into.
///
/// Reads the palette from the enclosing [ThemeScope] rather than taking a
/// [ThemeConfig] parameter, which is load-bearing: popup content is built once
/// and captured in a `WindowEntry` builder (see `popup.dart`), so a snapshotted
/// theme would freeze an open popup at the palette it opened with. The element
/// is still mounted in that view's tree, so reading from context restyles it in
/// place. See `theme/theme_provider.dart`.
///
/// A [Container], not the [DecoratedBox] the panel uses, and deliberately so:
/// `Container` adds the decoration's own padding — for a bordered box, its rim
/// thickness — to [padding], which is what keeps content from sliding under the
/// rim. The panel avoids `Container` because there the inset would silently
/// change what its own padding keys mean.
class PopupCard extends StatelessWidget {
  const PopupCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.border,
    this.clip = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Overrides [ThemeConfig.popupBorder]/[ThemeConfig.popupBorderWidth].
  final Border? border;

  /// Whether children are clipped to the rounded rect.
  ///
  /// On by default: a `borderRadius` rounds the painted background without
  /// clipping anything, and most cards hold a list, a tab strip or a full-width
  /// hover highlight that paints to their own edge. The layer is skipped
  /// entirely at a radius of 0 — the same conditional `main.dart` applies to the
  /// panel, so a square card costs exactly the layers it always did.
  ///
  /// [Container]'s own `clipBehavior` rather than a wrapping [ClipRRect]: the
  /// clip it builds sits inside its [DecoratedBox] and outside its [Padding],
  /// derived from this same decoration, so the rim paints over the clipped
  /// child. [Clip.antiAlias] rather than `antiAliasWithSaveLayer` — no save
  /// layer.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final decoration = popupDecoration(
      theme: ThemeScope.of(context),
      border: border,
    );
    return Container(
      decoration: decoration,
      clipBehavior: clip && decoration.borderRadius != null
          ? Clip.antiAlias
          : Clip.none,
      padding: padding,
      child: child,
    );
  }
}
