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

/// The card's shadow, or null when the theme asks for none.
///
/// Null in two cases, and both matter: a fully transparent [ThemeConfig.popupShadowColor]
/// is the feature's off switch, and a shadow with no blur, no spread and no
/// offset has nothing to draw that the card does not already cover. Either way
/// a `BoxShadow` would still cost a layer, and — because [popupShadowInsets] is
/// derived from this same predicate — would still grow every popup's window.
BoxShadow? popupShadow(ThemeConfig theme) {
  if (theme.popupShadowColor.a <= 0) return null;
  final offset = theme.popupShadowOffset;
  if (theme.popupShadowBlur == 0 &&
      theme.popupShadowSpread == 0 &&
      offset == Offset.zero) {
    return null;
  }
  return BoxShadow(
    color: theme.popupShadowColor,
    blurRadius: theme.popupShadowBlur,
    spreadRadius: theme.popupShadowSpread,
    offset: offset,
  );
}

/// How far [popupShadow] bleeds past the card on each side.
///
/// This is the amount a popup's own compositor surface has to grow by, because
/// a [BoxShadow] paints *outside* its box and the surface clips at its edge —
/// see `PopupHost.openPopup`. The per-side arithmetic is CSS's: the shadow's
/// rect is the card grown by the spread and displaced by the offset, and the
/// blur reaches one blur-radius past that. A side the offset pulls the shadow
/// away from can go to zero but never negative, which is what keeps a strongly
/// offset shadow from cropping the card itself.
///
/// [BoxShadow.blurRadius] rather than its sigma: [Shadow.convertRadiusToSigma]
/// maps the two the way CSS does, so the visible falloff dies within one radius.
EdgeInsets popupShadowInsets(ThemeConfig theme) {
  final shadow = popupShadow(theme);
  if (shadow == null) return EdgeInsets.zero;
  final reach = shadow.blurRadius + shadow.spreadRadius;
  double side(double v) => v < 0 ? 0 : v;
  return EdgeInsets.only(
    left: side(reach - shadow.offset.dx),
    right: side(reach + shadow.offset.dx),
    top: side(reach - shadow.offset.dy),
    bottom: side(reach + shadow.offset.dy),
  );
}

/// The surface every popup, menu, flyout and OSD card paints.
///
/// [theme] is required for the same reason `panelBackgroundDecoration`'s is: a
/// defaulted palette here would silently paint the built-in colours over
/// whatever theme is actually active.
///
/// [border] *replaces* the theme's rim rather than adding to it. It exists for
/// the one card whose border carries meaning rather than chrome — the kill
/// confirmation's accent rim, which marks a destructive action.
///
/// [opaque] overrides the fill's alpha and nothing else — see
/// [OpaquePopupScope], which is what decides it for [PopupCard].
BoxDecoration popupDecoration({
  required ThemeConfig theme,
  Border? border,
  bool opaque = false,
}) {
  final radius = popupCornerRadius(theme);
  final shadow = popupShadow(theme);
  return BoxDecoration(
    color: opaque ? opaquePopupFill(theme) : theme.popupBackground,
    // Normalised to null rather than BorderRadius.zero so a square card builds
    // exactly the decoration — and the layers — it did before corners were
    // themable.
    borderRadius: radius == BorderRadius.zero ? null : radius,
    border: border ?? _popupBorder(theme),
    // Null rather than an empty list, the same normalisation the radius gets:
    // a shadowless theme builds exactly the decoration it did before shadows
    // existed.
    boxShadow: shadow == null ? null : [shadow],
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
  ///
  /// It is also why the theme's shadow survives: that clip wraps the *child*
  /// subtree, not the background [DecoratedBox], so a [popupShadow] still
  /// paints outside the card. A hand-rolled [ClipRRect] around the whole card
  /// would cut it off.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final decoration = popupDecoration(
      theme: ThemeScope.of(context),
      border: border,
      opaque: OpaquePopupScope.of(context),
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

/// Marks a subtree whose popups paint **opaque**, whatever alpha the theme's
/// `popup_background` carries.
///
/// The rule `overlayPanelFill` (`overlay/overlay.dart`) states for the settings
/// panel itself, extended to everything that floats over it. A theme's
/// `popup_background` alpha — `glassy` ships it at `0xB0` — is right for a
/// three-row menu sitting over the desktop and wrong for a card the user is
/// reading *over the settings panel*: a dropdown list, a colour picker, a
/// confirmation, a file picker. Those stack over dense small text and form
/// rows, so a translucent card shows the page it is covering straight through
/// itself and neither layer stays readable. The hue stays the theme's and only
/// the alpha is overridden, so a theme still colours its popups — it just
/// cannot make the ones inside the settings page see-through.
///
/// An [InheritedWidget] rather than a flag threaded through every call site,
/// because these cards are built in three different places — inline in the
/// pane, in the window's root [Overlay] (`showRootModal`, and every
/// `AnchoredSearchDropdown`), and in the panel itself — and a flag would have
/// to be passed down each of those paths by hand. `SettingsOverlay` wraps its
/// `Overlay` in one of these, which is above all three.
///
/// It cannot span FlutterViews, so a popup the settings page opens as its *own*
/// layer-shell window (the root-owned file picker and app chooser, which the
/// desktop surface uses) is outside it and keeps the theme's alpha.
class OpaquePopupScope extends InheritedWidget {
  const OpaquePopupScope({super.key, required super.child});

  /// Whether popups in this subtree must paint opaque. False with no scope
  /// above, which is every popup outside the settings page.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OpaquePopupScope>() != null;

  /// [ThemeConfig.popupBackground] as a popup in [context] must paint it.
  ///
  /// The one call every hand-rolled popup surface in the settings UI makes in
  /// place of reading `theme.popupBackground` directly; [PopupCard] and
  /// [popupDecoration] make it for the cards built on those.
  static Color fill(BuildContext context, ThemeConfig theme) =>
      of(context) ? opaquePopupFill(theme) : theme.popupBackground;

  // The scope's presence is what is read, and it never changes for the life of
  // a window's tree — the settings overlay wraps its Overlay in one and every
  // other window has none.
  @override
  bool updateShouldNotify(OpaquePopupScope oldWidget) => false;
}

/// [ThemeConfig.popupBackground] with its alpha overridden, hue intact.
///
/// The one expression behind [OpaquePopupScope.fill] and `overlayPanelFill`.
Color opaquePopupFill(ThemeConfig theme) =>
    theme.popupBackground.withValues(alpha: 1.0);
