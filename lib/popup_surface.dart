import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/scopes.dart';

/// A popup card's corner rounding, from [ThemeConfig.popupRadius].
///
/// All four corners for a card that floats. [attach] is the panel edge an
/// *attached* bar popup is joined to (the bar's own anchor string, null for a
/// floating popup): the two corners on that edge are squared off, because there
/// is a surface behind them that continues past the card and a rounded corner
/// would cut a wedge out of it — `panelCornerRadius`'s rule for a flush bar.
///
/// [ThemeConfig.popupAttachRadius] is deliberately *not* read here: it is an
/// outward flare rather than a corner rounding, which no [BorderRadius] can
/// express. See [AttachedPopupBorder], which [popupDecoration] uses in this
/// function's place above a flare of zero and whenever [popupAttachCollar] is
/// non-zero.
///
/// Returns [BorderRadius.zero] when all four corners come out square, which
/// [PopupCard] uses to skip the clip layer.
BorderRadius popupCornerRadius(ThemeConfig theme, {String? attach}) {
  final r =
      theme.popupRadius <= 0 ? Radius.zero : Radius.circular(theme.popupRadius);
  if (attach == null) {
    return r == Radius.zero ? BorderRadius.zero : BorderRadius.all(r);
  }
  final radius = switch (attach) {
    'top' => BorderRadius.only(bottomLeft: r, bottomRight: r),
    'bottom' => BorderRadius.only(topLeft: r, topRight: r),
    'left' => BorderRadius.only(topRight: r, bottomRight: r),
    'right' => BorderRadius.only(topLeft: r, bottomLeft: r),
    _ => BorderRadius.all(r),
  };
  // Normalised the way the floating case is, and it has to be: a popup radius of
  // 0 builds a BorderRadius whose corners are all Radius.zero but which is not
  // the const zero, and the clip layer would come back for a square card.
  return radius == BorderRadius.zero ? BorderRadius.zero : radius;
}

/// The outline of a bar popup that is **attached** to its panel, with the join
/// flaring outward into the bar rather than rounding away from it.
///
/// [ThemeConfig.popupAttachRadius] reads as a corner radius and is the opposite
/// of one. A convex corner curves *away* from the surface behind it, leaving
/// transparent wedges where the card meets the bar; the join wants each side
/// sweeping *outward* as it reaches the panel. That is a concave fillet, which
/// no [BorderRadius] can express — hence a [ShapeBorder], and hence
/// [popupDecoration] returning a [Decoration] rather than a [BoxDecoration].
///
/// **This shape paints outside [Rect].** It reaches [attachRadius] past the card
/// on the two sides that meet the join, and [collar] past it on the join itself,
/// so the popup's surface has to be grown by that much or the paint is clipped
/// at the window edge. [popupAttachInsets] is that amount.
///
/// That is also why an attached card with **no** flare still comes here whenever
/// [collar] is above zero: at [attachRadius] 0 the outline is the square-cornered
/// card [popupCornerRadius] describes, grown into the panel so its fill covers
/// the bar's inner rim — which no [BoxDecoration] can do.
///
/// The far corners keep [radius]; the join carries no rim, for [_popupBorder]'s
/// reason.
class AttachedPopupBorder extends ShapeBorder {
  const AttachedPopupBorder({
    required this.edge,
    required this.radius,
    required this.attachRadius,
    this.collar = 0.0,
    this.side = BorderSide.none,
  });

  /// The panel edge the card is joined to: `'top'`, `'bottom'`, `'left'` or
  /// `'right'`, the bar's own anchor string.
  final String edge;

  /// [ThemeConfig.popupRadius] — the two corners away from the join.
  final double radius;

  /// [ThemeConfig.popupAttachRadius] — how far the join flares outward.
  final double attachRadius;

  /// How far the card reaches *into* the panel past its own box:
  /// [ThemeConfig.panelBorderWidth], and 0 for a bar with no rim.
  ///
  /// This joins the flare to the bar's own rim rather than hanging the card off
  /// it. A panel's border is drawn along its **inner** edge too, so with no
  /// collar the bar's hairline runs across the mouth of the popup and the card
  /// reads as something taped under a line. Reaching one rim-width in covers
  /// that hairline with the card's own fill, while the arcs — whose tips are
  /// tangent to the join line — pick the line up and carry it down the sides.
  ///
  /// A square butt join ([attachRadius] 0) needs this just as badly: the
  /// hairline is the *bar's* line, so the card has to paint over it. What
  /// changes without a flare is only how the line resumes at either end.
  final double collar;

  /// The rim, drawn on everything but the join.
  final BorderSide side;

  bool get _hasRim => side.style != BorderStyle.none && side.width > 0;

  @override
  EdgeInsetsGeometry get dimensions {
    if (!_hasRim) return EdgeInsets.zero;
    final w = side.width;
    // The join side takes none, because no rim is drawn there and an inset
    // would hold the content off an edge that has nothing on it.
    return switch (edge) {
      'top' => EdgeInsets.only(left: w, right: w, bottom: w),
      'bottom' => EdgeInsets.only(left: w, right: w, top: w),
      'left' => EdgeInsets.only(top: w, right: w, bottom: w),
      _ => EdgeInsets.only(top: w, left: w, bottom: w),
    };
  }

  /// Maps the canonical frame — join along `y = 0`, card below it — onto [rect]
  /// for this [edge].
  ///
  /// The outline is built once for a top join and transformed. Two of the four
  /// maps are reflections rather than rotations, which is harmless: a reflection
  /// reverses the winding and flips each arc's handedness together.
  Matrix4 _frame(Rect rect) {
    final m = Matrix4.identity();
    switch (edge) {
      case 'bottom':
        m.setEntry(0, 0, 1.0);
        m.setEntry(0, 3, rect.left);
        m.setEntry(1, 1, -1.0);
        m.setEntry(1, 3, rect.bottom);
      case 'left':
        m.setEntry(0, 0, 0.0);
        m.setEntry(0, 1, 1.0);
        m.setEntry(0, 3, rect.left);
        m.setEntry(1, 0, 1.0);
        m.setEntry(1, 1, 0.0);
        m.setEntry(1, 3, rect.top);
      case 'right':
        m.setEntry(0, 0, 0.0);
        m.setEntry(0, 1, -1.0);
        m.setEntry(0, 3, rect.right);
        m.setEntry(1, 0, 1.0);
        m.setEntry(1, 1, 0.0);
        m.setEntry(1, 3, rect.top);
      default: // 'top'
        m.setEntry(0, 3, rect.left);
        m.setEntry(1, 3, rect.top);
    }
    return m;
  }

  /// The card's extent *along* the join, and its extent *into* the card.
  (double, double) _extents(Rect rect) => edge == 'left' || edge == 'right'
      ? (rect.height, rect.width)
      : (rect.width, rect.height);

  /// The outline in the canonical frame: the join runs along `y = -collar` from
  /// `-flare` to `along + flare`, and the card occupies `0 <= y <= into`.
  ///
  /// [radius] and [flare] are passed rather than read off the fields, because
  /// [getInnerPath] builds the same outline at a smaller radius. [open] leaves
  /// out the segment back along the join, so [paint] draws nothing across it.
  ///
  /// [collar] moves the join line off the card's edge and into the panel;
  /// everything else is measured from it, so the shape is built at a depth of
  /// `into + collar` and shifted back. A collar of 0 reproduces the outline
  /// exactly as it was before the parameter existed.
  static Path _canonicalPath(
    double along,
    double into, {
    required double radius,
    required double flare,
    double collar = 0,
    bool open = false,
  }) {
    final c = math.max(0.0, collar);
    // Everything below is measured from the join, which the collar has moved.
    final depth = into + c;
    // A radius past half the card would have the two far corners overrun each
    // other, and a flare deeper than what is left below them would run the ears
    // into those corners.
    final r = math.max(0.0, math.min(radius, math.min(along, depth) / 2));
    final a = math.max(0.0, math.min(flare, depth - r));
    final path = Path();
    if (a > 0) {
      // The flare is a quarter circle centred *outside* the card, at (-a, a), so
      // the boundary bows toward the card's own corner instead of away from it:
      // the card is at its widest exactly where it meets the panel. That is the
      // whole difference between a join and a rounded corner.
      path.moveTo(-a, 0);
      path.arcToPoint(Offset(0, a),
          radius: Radius.circular(a), clockwise: true);
    } else {
      // No flare: the join is squared off, which is what popupCornerRadius
      // builds for the BoxDecoration this shape stands in for.
      path.moveTo(0, 0);
    }
    path.lineTo(0, depth - r);
    if (r > 0) {
      path.arcToPoint(Offset(r, depth),
          radius: Radius.circular(r), clockwise: false);
    }
    path.lineTo(along - r, depth);
    if (r > 0) {
      path.arcToPoint(Offset(along, depth - r),
          radius: Radius.circular(r), clockwise: false);
    }
    if (a > 0) {
      path.lineTo(along, a);
      path.arcToPoint(Offset(along + a, 0),
          radius: Radius.circular(a), clockwise: true);
    } else {
      path.lineTo(along, 0);
    }
    if (!open) path.close();
    // Built with the join at y = 0 and dropped back onto the card, so the join
    // sits `c` *above* the card's own edge — inside the panel — and the card's
    // far edge stays exactly where the caller's rect put it.
    return c == 0 ? path : path.shift(Offset(0, -c));
  }

  Path _path(Rect rect, {double? radius, bool open = false}) {
    final (along, into) = _extents(rect);
    return _canonicalPath(along, into,
            radius: radius ?? this.radius,
            flare: attachRadius,
            collar: collar,
            open: open)
        .transform(_frame(rect).storage);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  /// The outline of what the rim encloses: this shape on the box the rim leaves
  /// behind.
  ///
  /// [ShapeDecoration] never asks for it — it fills and shadows the outer path
  /// and leaves the rim to [paint] — so this exists only to satisfy the contract.
  ///
  /// Deflating the rect is the approximation Flutter's own shapes make, and the
  /// imprecision is at the ears: the flare is measured from the inner box, so it
  /// is not everywhere one rim-width in from the outer one. Nothing reads this
  /// path closely enough for the arithmetic to be worth it — [paint] draws the
  /// rim from the *outer* path.
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _hasRim
      ? _path(
          dimensions.resolve(textDirection).deflateRect(rect),
          radius: math.max(0.0, radius - side.width),
        )
      : _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (!_hasRim) return;
    // Stroked at twice the width and clipped to the card, so only the inner half
    // lands: a rim drawn inside its own outline, the way `Border` draws one,
    // without a second set of radii to keep in step. The path is open, so
    // nothing is drawn across the join.
    canvas.save();
    canvas.clipPath(getOuterPath(rect, textDirection: textDirection));
    canvas.drawPath(
      _path(rect, open: true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side.width * 2
        ..color = side.color,
    );
    canvas.restore();
  }

  @override
  ShapeBorder scale(double t) => AttachedPopupBorder(
        edge: edge,
        radius: radius * t,
        attachRadius: attachRadius * t,
        collar: collar * t,
        side: side.scale(t),
      );

  @override
  bool operator ==(Object other) =>
      other is AttachedPopupBorder &&
      other.edge == edge &&
      other.radius == radius &&
      other.attachRadius == attachRadius &&
      other.collar == collar &&
      other.side == side;

  @override
  int get hashCode => Object.hash(edge, radius, attachRadius, collar, side);
}

/// How far an attached card's join reaches past its own box, per side.
///
/// Zero unless the card is attached, and zero then too unless it actually
/// reaches somewhere: the two sides that meet the join take
/// [ThemeConfig.popupAttachRadius], the flare, and the join itself takes
/// [popupAttachCollar], the reach *into* the panel that lays the card's fill
/// over the bar's inner rim. Either may be 0 on its own, and a card that takes
/// neither reaches nowhere at all — which keeps a theme with no panel rim and no
/// flare byte-identical to what it drew before. The far side always takes none.
///
/// This is [popupShadowInsets]'s job for a different piece of paint, and
/// `PopupHost.openPopup` merges the two through [popupSurfaceInsets], which
/// takes the per-side larger — on the joined side, the collar outright, since
/// the shadow's inset there is already clamped to [ThemeConfig.popupGap] and
/// attaching *is* that gap being 0.
EdgeInsets popupAttachInsets(ThemeConfig theme, {String? attachEdge}) {
  if (attachEdge == null) return EdgeInsets.zero;
  final a = math.max(0.0, theme.popupAttachRadius);
  final c = popupAttachCollar(theme, attachEdge: attachEdge);
  if (a == 0 && c == 0) return EdgeInsets.zero;
  // The two sides meeting the join take the flare; the join itself takes the
  // collar, and the far side takes nothing. `attachEdge` is the *bar's* anchor,
  // so the joined side of the popup faces it: a top bar's menu is joined along
  // its own top, a left bar's along its own left.
  return switch (attachEdge) {
    'top' => EdgeInsets.only(left: a, right: a, top: c),
    'bottom' => EdgeInsets.only(left: a, right: a, bottom: c),
    'left' => EdgeInsets.only(top: a, bottom: a, left: c),
    'right' => EdgeInsets.only(top: a, bottom: a, right: c),
    _ => EdgeInsets.zero,
  };
}

/// How far an attached card reaches *into* the panel, so its join runs into the
/// bar's own rim instead of hanging off it.
///
/// [ThemeConfig.panelBorderWidth], and 0 whenever there is nothing to join to: a
/// card that floats, or a bar with no rim. See [AttachedPopupBorder.collar].
///
/// **A square butt join needs this exactly as much as a flared one.** A panel's
/// rim is drawn along its *inner* edge too, so with no collar the bar's hairline
/// runs across the mouth of every menu it opens — the one thing attaching exists
/// to hide. It is the bar's line rather than the card's, so dropping the popup's
/// own rim on the join cannot reach it; only the card's fill painted one
/// rim-width into the panel can. The flare merely changes *how* the line resumes
/// at either end.
///
/// The panel's and the popup's rims are read as two independent keys, because
/// nothing makes a theme spell them the same. Equal widths (what `carbon` ships)
/// lay the card's stroke exactly over the band the bar's rim occupies, so the two
/// read as one line turning the corner; unequal ones still meet, with a step in
/// thickness rather than a break.
double popupAttachCollar(ThemeConfig theme, {String? attachEdge}) {
  if (attachEdge == null) return 0.0;
  return math.max(0.0, theme.panelBorderWidth);
}

/// The margin a popup's surface carries, per side: whichever of the shadow's
/// reach and the flare's is larger.
///
/// The larger rather than the sum. Both measure how far past the card something
/// paints, and the flare is a solid part of the card's own silhouette, so the
/// shadow around it is one the card already casts. Summing would push every
/// attached popup's window out by a margin nothing draws in — and with no
/// input-region support, that margin swallows clicks meant for the desktop.
EdgeInsets popupSurfaceInsets(EdgeInsets shadow, EdgeInsets attach) {
  if (attach == EdgeInsets.zero) return shadow;
  return EdgeInsets.fromLTRB(
    math.max(shadow.left, attach.left),
    math.max(shadow.top, attach.top),
    math.max(shadow.right, attach.right),
    math.max(shadow.bottom, attach.bottom),
  );
}

/// The card's rim, or null when [ThemeConfig.popupBorderWidth] is 0.
///
/// Null rather than a zero-width [Border] on purpose, the nuance
/// `panel_background.dart` documents: a `Border` in the decoration carries a
/// non-zero [BoxDecoration.padding], which a [Container] would silently add to
/// its child's own padding.
///
/// An attached popup drops the side on the join — see [popupCornerRadius] for
/// what [attach] is. A hairline across the seam is what gives away that the card
/// is a second surface rather than the bar continuing.
///
/// A non-uniform [Border] under a non-zero `borderRadius` is legal here *because
/// the visible sides share one colour*: `BoxBorder.paint` takes a
/// `paintNonUniformBorder` path before it reaches the uniformity assert. That
/// path refuses hairline widths, which cannot arise here.
///
/// Two consequences for callers. [Border.dimensions], and through it
/// [BoxDecoration.padding], loses the width on the joined side — right, since
/// there is no rim there to hold content off. And the [PopupCard.border] override
/// still replaces all four sides: a rim that carries meaning rather than chrome
/// is not the theme's to strip.
BorderSide _popupSide(ThemeConfig theme) => theme.popupBorderWidth > 0
    ? BorderSide(color: theme.popupBorder, width: theme.popupBorderWidth)
    : BorderSide.none;

Border? _popupBorder(ThemeConfig theme, String? attach) {
  if (theme.popupBorderWidth <= 0) return null;
  final side = _popupSide(theme);
  return switch (attach) {
    'top' => Border(left: side, right: side, bottom: side),
    'bottom' => Border(left: side, right: side, top: side),
    'left' => Border(top: side, right: side, bottom: side),
    'right' => Border(top: side, left: side, bottom: side),
    _ => Border.all(color: theme.popupBorder, width: theme.popupBorderWidth),
  };
}

/// The rim as a single side, or [BorderSide.none] at a width of 0.
///
/// [AttachedPopupBorder] takes one of these rather than a [Border], because the
/// shape decides for itself which edge goes without — reading it off a
/// [_popupBorder] would mean reading the very side just dropped.
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
/// The amount a popup's compositor surface has to grow by, because a [BoxShadow]
/// paints *outside* its box and the surface clips at its edge — see
/// `PopupHost.openPopup`. The per-side arithmetic is CSS's: the shadow's rect is
/// the card grown by the spread and displaced by the offset, and the blur reaches
/// one blur-radius past that. A side the offset pulls the shadow away from can go
/// to zero but never negative, which keeps a strongly offset shadow from cropping
/// the card itself.
///
/// [BoxShadow.blurRadius] rather than its sigma: [Shadow.convertRadiusToSigma]
/// maps the two the way CSS does, so the falloff dies within one radius.
///
/// [attachEdge] is the panel edge a *bar* popup is anchored to, and clamps that
/// side to [ThemeConfig.popupGap], so the surface reaches from the card to the
/// panel edge and no further and the compositor's clip cuts the shadow at the
/// join. Clamped rather than zeroed so one rule covers the range: at a gap of 0
/// the side goes to 0; at a smaller gap the shadow fills it and stops; at the
/// reach or more this is a no-op. Null is the same no-op.
EdgeInsets popupShadowInsets(ThemeConfig theme, {String? attachEdge}) {
  final shadow = popupShadow(theme);
  if (shadow == null) return EdgeInsets.zero;
  final reach = shadow.blurRadius + shadow.spreadRadius;
  double side(double v) => v < 0 ? 0 : v;
  final insets = EdgeInsets.only(
    left: side(reach - shadow.offset.dx),
    right: side(reach + shadow.offset.dx),
    top: side(reach - shadow.offset.dy),
    bottom: side(reach + shadow.offset.dy),
  );
  if (attachEdge == null) return insets;
  final gap = theme.popupGap;
  return switch (attachEdge) {
    'top' => insets.copyWith(top: math.min(insets.top, gap)),
    'bottom' => insets.copyWith(bottom: math.min(insets.bottom, gap)),
    'left' => insets.copyWith(left: math.min(insets.left, gap)),
    'right' => insets.copyWith(right: math.min(insets.right, gap)),
    _ => insets,
  };
}

/// The surface every popup, menu, flyout and OSD card paints.
///
/// [theme] is required for `panelBackgroundDecoration`'s reason: a defaulted
/// palette would silently paint the built-in colours over the active theme.
///
/// [border] *replaces* the theme's rim rather than adding to it, for the one card
/// whose border carries meaning — the kill confirmation's accent rim.
///
/// [opaque] overrides the fill's alpha and nothing else — see [OpaquePopupScope].
///
/// [attach] names the panel edge an attached bar popup is joined to (see
/// [popupCornerRadius] and [PopupAttachScope]). It reshapes the corners and drops
/// the rim on that edge; the shadow needs no attention, because
/// [popupShadowInsets] has already made the surface flush.
Decoration popupDecoration({
  required ThemeConfig theme,
  Border? border,
  bool opaque = false,
  String? attach,
}) {
  final radius = popupCornerRadius(theme, attach: attach);
  final shadow = popupShadow(theme);
  final rim = border ?? _popupBorder(theme, attach);
  final collar = popupAttachCollar(theme, attachEdge: attach);
  if (attach != null && (theme.popupAttachRadius > 0 || collar > 0)) {
    // Two things a BoxDecoration cannot draw, either of which needs this shape:
    // the flare is not a corner radius, and the collar paints *outside* the
    // card's box. Everything else is the same — same fill, shadow, rim colour and
    // width; an explicit `border` contributes its side, since the shape decides
    // for itself that the join carries none. With no flare the outline is exactly
    // the square-cornered card [popupCornerRadius] describes, grown by the collar
    // on the joined side.
    return ShapeDecoration(
      color: opaque ? opaquePopupFill(theme) : theme.popupBackground,
      shape: AttachedPopupBorder(
        edge: attach,
        radius: theme.popupRadius,
        attachRadius: theme.popupAttachRadius,
        // The bar's own rim, reached into so the card's fill covers it rather
        // than hanging beneath it. The margin for this is already in the
        // surface — popupAttachInsets carries it on the joined side.
        collar: collar,
        // The explicit override's side when there is one — it is a rim that
        // carries meaning rather than chrome — and the theme's otherwise. Not
        // `rim?.top`: that is the side an attached card has just dropped.
        side: border?.top ?? _popupSide(theme),
      ),
      shadows: shadow == null ? null : [shadow],
    );
  }
  return BoxDecoration(
    color: opaque ? opaquePopupFill(theme) : theme.popupBackground,
    // Normalised to null rather than BorderRadius.zero so a square card builds
    // exactly the decoration — and the layers — it did before corners were
    // themable.
    borderRadius: radius == BorderRadius.zero ? null : radius,
    border: rim,
    // Null rather than an empty list, the same normalisation the radius gets:
    // a shadowless theme builds exactly the decoration it did before shadows
    // existed.
    boxShadow: shadow == null ? null : [shadow],
  );
}

/// Whether [decoration] has an outline worth clipping children to.
///
/// A square [BoxDecoration] has none and the layer is skipped for it, so a square
/// card costs exactly the layers it always did. An attached card is a
/// [ShapeDecoration] and always has one: its flare is the part of the silhouette
/// a child would most visibly spill out of.
bool decorationClips(Decoration decoration) => switch (decoration) {
      BoxDecoration(:final borderRadius) => borderRadius != null,
      ShapeDecoration() => true,
      _ => false,
    };

/// The card every popup, flyout, menu and OSD renders into.
///
/// Reads the palette from the enclosing [ThemeScope] rather than taking a
/// [ThemeConfig] parameter, which is load-bearing: popup content is built once
/// and captured in a `WindowEntry` builder, so a snapshotted theme would freeze
/// an open popup at the palette it opened with. The element is still mounted in
/// that view's tree, so reading from context restyles it in place.
///
/// A [Container], not the [DecoratedBox] the panel uses: `Container` adds the
/// decoration's own padding — for a bordered box, its rim thickness — to
/// [padding], which keeps content from sliding under the rim. The panel avoids
/// `Container` because there the inset would change what its padding keys mean.
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
  /// hover highlight that paints to their own edge. The layer is skipped entirely
  /// at a radius of 0.
  ///
  /// [Container]'s own `clipBehavior` rather than a wrapping [ClipRRect]: the
  /// clip it builds sits inside its [DecoratedBox] and outside its [Padding], so
  /// the rim paints over the clipped child. [Clip.antiAlias], so no save layer.
  ///
  /// It is also why the theme's shadow survives: that clip wraps the *child*
  /// subtree, not the background [DecoratedBox]. A hand-rolled [ClipRRect] around
  /// the whole card would cut it off.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final decoration = popupDecoration(
      theme: ThemeScope.of(context),
      border: border,
      opaque: OpaquePopupScope.of(context),
      attach: PopupAttachScope.of(context),
    );
    return Container(
      decoration: decoration,
      clipBehavior: clip && decorationClips(decoration)
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
/// The rule `overlayPanelFill` states for the settings panel, extended to
/// everything that floats over it. A theme's `popup_background` alpha is right
/// for a three-row menu over the desktop and wrong for a card read *over the
/// settings panel* — a dropdown, a colour picker, a confirmation, a file picker
/// — which stack over dense text and form rows. Only the alpha is overridden, so
/// a theme still colours its popups.
///
/// An [InheritedWidget] rather than a flag threaded through every call site,
/// because these cards are built in three places — inline in the pane, in the
/// window's root [Overlay], and in the panel itself. `SettingsOverlay` wraps its
/// `Overlay` in one, which is above all three.
///
/// It cannot span FlutterViews, so a popup opened as its *own* layer-shell window
/// (the root-owned file picker and app chooser) is outside it and keeps the
/// theme's alpha.
class OpaquePopupScope extends InheritedWidget {
  const OpaquePopupScope({super.key, required super.child});

  /// Whether popups in this subtree must paint opaque. False with no scope
  /// above, which is every popup outside the settings page.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OpaquePopupScope>() != null;

  /// [ThemeConfig.popupBackground] as a popup in [context] must paint it.
  ///
  /// The call every hand-rolled popup surface in the settings UI makes in place
  /// of reading `theme.popupBackground` directly; [PopupCard] and
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

/// Marks a popup's content as **attached** to a panel edge, and says which one.
///
/// [OpaquePopupScope]'s pattern with a value. [edge] is the panel's anchor string
/// — `'top'`, `'bottom'`, `'left'` or `'right'` — which for an edge-anchored
/// popup is also the popup's own side touching the bar.
///
/// An inherited widget rather than a parameter, for the reason [PopupCard] gives
/// about the theme: a popup's content is built once in a FlutterView that is a
/// *sibling* of the panel's, so a card three levels down cannot read the panel's
/// `BarScope` and each of the twelve modules opening bar popups would have to
/// pass the edge down by hand.
///
/// Presence *is* the attached state: `PopupHost.openPopup` installs one only when
/// the popup is a bar popup, the caller asked to attach, and
/// [ThemeConfig.popupGap] is 0.
class PopupAttachScope extends InheritedWidget {
  const PopupAttachScope({
    super.key,
    required this.edge,
    required super.child,
  });

  /// The panel edge this popup is joined to.
  final String edge;

  /// The joined edge, or null in a popup that floats — which is every popup
  /// with no scope above it, including every menu anchored to the pointer.
  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PopupAttachScope>()?.edge;

  // Snapshotted at open and never revised, the discipline the popup's constraints
  // and shadow insets already follow: GTK3 resolves the placement once at map
  // time, so an attached popup cannot become a floating one without being
  // reopened.
  @override
  bool updateShouldNotify(PopupAttachScope oldWidget) => false;
}
