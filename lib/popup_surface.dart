import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/scopes.dart';

/// A popup card's corner rounding, from [ThemeConfig.popupRadius].
///
/// All four corners for a card that floats — a popup sits over a transparent
/// surface with no display corner behind it to cut into, which is why
/// `panelCornerRadius` has a pair to spare and this normally does not.
///
/// [attach] is the panel edge an *attached* bar popup is joined to: the bar's
/// own anchor string, one of `'top'`, `'bottom'`, `'left'` or `'right'`, and
/// null for every popup that floats. The two corners on that edge are squared
/// off, because there is a surface behind them that continues past the card and
/// a rounded corner would cut a wedge out of it — `panelCornerRadius`'s rule for
/// a flush bar, one layer up.
///
/// [ThemeConfig.popupAttachRadius] is deliberately *not* read here. It is not a
/// corner rounding at all but an outward flare, which no [BorderRadius] can
/// express; see [AttachedPopupBorder], which [popupDecoration] uses in this
/// function's place as soon as it is above zero.
///
/// Returns [BorderRadius.zero] when all four corners come out square, which
/// [PopupCard] uses to skip building a clip layer at all.
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
  // Normalised the way the floating case is, and it has to be done here as
  // well: a popup radius of 0 builds a BorderRadius whose corners are all
  // Radius.zero but which is not the const zero, and the clip layer would come
  // back for a card that is square on all four sides.
  return radius == BorderRadius.zero ? BorderRadius.zero : radius;
}

/// The outline of a bar popup that is **attached** to its panel, with the join
/// flaring outward into the bar rather than rounding away from it.
///
/// [ThemeConfig.popupAttachRadius] reads as a corner radius and is the opposite
/// of one. A convex corner curves *away* from the surface behind it, which
/// leaves two transparent wedges where the card meets the bar and reads as a
/// card resting against it. The join wants the inverse: each side sweeps
/// *outward* as it reaches the panel, so the card's edge runs into the bar's
/// the way a branch runs into a trunk. That is a concave fillet, and no
/// [BorderRadius] can express one — hence a [ShapeBorder], and hence
/// [popupDecoration] returning a [Decoration] rather than a [BoxDecoration].
///
/// **The flare paints outside [Rect].** It reaches [attachRadius] past the card
/// on each of the two sides that meet the join, and [collar] past it on the
/// join itself, exactly as a [BoxShadow] paints past its box — so the popup's
/// surface has to be grown by that much or the ears are clipped off at the
/// window edge. [popupAttachInsets] is that amount and `PopupHost.openPopup`
/// folds it into the same padding the shadow uses.
///
/// The far corners keep [radius]; the join carries no rim, for the reason
/// [_popupBorder] gives.
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
  /// [ThemeConfig.panelBorderWidth], and 0 for a bar that carries no rim.
  ///
  /// This is what joins the flare to the bar's own rim rather than hanging the
  /// card off it. A panel's border is drawn along its **inner** edge as well as
  /// its outer one, so with no collar the bar's hairline runs straight across
  /// the mouth of the popup and the card reads as something taped underneath a
  /// line. Reaching one rim-width in does two things at once, both of them
  /// consequences of the flare being *concave*: the card is at its widest
  /// exactly at the join, so its fill covers that hairline across the whole
  /// mouth — the notch that makes the two surfaces one — while the arcs, which
  /// leave their tips tangent to the join line, rise to meet the rim's inner
  /// face at the two ends and let what is left of it taper into the sweep.
  ///
  /// Only meaningful with a flare. A square butt join extended by a collar
  /// would cut a flat-bottomed slot out of the bar's rim instead of growing out
  /// of it, which is why [popupAttachCollar] answers 0 without one and why the
  /// [BoxDecoration] branch of [popupDecoration] — the one a square join takes —
  /// has nowhere to put this.
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
  /// The outline is built once, for a top join, and transformed. Two of the four
  /// maps are reflections rather than rotations, which is harmless: a reflection
  /// reverses the path's winding and flips each arc's handedness together, so
  /// the filled region is the mirror image and nothing about it degenerates.
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
  /// out the segment back along the join, so [paint] has nothing to draw across
  /// it.
  ///
  /// [collar] moves the join line off the card's own edge and into the panel;
  /// everything else is measured from it, so the shape is built at a depth of
  /// `into + collar` and shifted back. A collar of 0 — every theme whose bar
  /// carries no rim — reproduces the outline exactly as it was before the
  /// parameter existed.
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
      // The flare is a quarter circle centred *outside* the card, at (-a, a),
      // so the boundary bows toward the card's own corner instead of away from
      // it: the card is at its widest exactly where it meets the panel. This is
      // the whole difference between a join and a rounded corner.
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

  /// The outline of what the rim encloses: this same shape on the box the rim
  /// leaves behind.
  ///
  /// [ShapeDecoration] never asks for it — it fills and shadows the outer path
  /// and leaves the rim to [paint] — so this exists to satisfy the contract for
  /// anything that clips to a shape's interior.
  ///
  /// Deflating the rect is the approximation Flutter's own shapes make
  /// ([RoundedRectangleBorder.getInnerPath] is a plain `RRect.deflate`), and the
  /// deliberate imprecision is at the ears: the flare is measured from the inner
  /// box, so it is not everywhere one rim-width in from the outer one. An arc
  /// truly concentric with the outer ear would have to start short of its tip,
  /// on the join line, and nothing in the shell reads this path closely enough
  /// to be worth the arithmetic — [paint] draws the rim from the *outer* path.
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
    // Stroked at twice the width and clipped to the card, so only the inner
    // half lands: a rim drawn inside its own outline, the way `Border` draws
    // one, without a second set of radii to keep in step with the first. The
    // path is open, so nothing is drawn across the join.
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
/// Zero unless the card is attached *and* [ThemeConfig.popupAttachRadius] is
/// above zero — the default join is square and reaches nowhere. The two sides
/// that meet the join take the flare; the join itself takes
/// [popupAttachCollar], the reach *into* the panel that lands the flare on the
/// bar's own rim; the far side takes none, because nothing is drawn past it.
///
/// This is [popupShadowInsets]'s job for a different piece of paint, and
/// `PopupHost.openPopup` merges the two: both are margin the popup's own surface
/// has to carry or the compositor clips what should have been drawn there.
/// [popupSurfaceInsets] takes the per-side larger, which on the joined side is
/// the collar outright — the shadow's own inset there has already been clamped
/// to [ThemeConfig.popupGap], and attaching *is* that gap being 0.
EdgeInsets popupAttachInsets(ThemeConfig theme, {String? attachEdge}) {
  if (attachEdge == null || theme.popupAttachRadius <= 0) return EdgeInsets.zero;
  final a = theme.popupAttachRadius;
  final c = popupAttachCollar(theme, attachEdge: attachEdge);
  // The two sides that meet the join take the flare; the join itself takes the
  // collar, and the far side takes nothing. `attachEdge` is the *bar's* anchor,
  // so the joined side of the popup is the one facing it: a top bar's menu is
  // joined along its own top, a left bar's along its own left.
  return switch (attachEdge) {
    'top' => EdgeInsets.only(left: a, right: a, top: c),
    'bottom' => EdgeInsets.only(left: a, right: a, bottom: c),
    'left' => EdgeInsets.only(top: a, bottom: a, left: c),
    'right' => EdgeInsets.only(top: a, bottom: a, right: c),
    _ => EdgeInsets.zero,
  };
}

/// How far an attached card reaches *into* the panel, so that its flare runs
/// into the bar's own rim instead of hanging off it.
///
/// [ThemeConfig.panelBorderWidth], and 0 whenever there is nothing to join to:
/// a card that floats (no [attachEdge] — which already means
/// [ThemeConfig.popupGap] is 0, since that is what attaching *is*), a bar with
/// no rim, or a square butt join, which has no flare to carry the bar's rim
/// into and would cut a flat slot out of it instead. See
/// [AttachedPopupBorder.collar] for what the reach buys.
///
/// The panel's and the popup's rims are read as two independent keys here — the
/// collar is [ThemeConfig.panelBorderWidth] and the flare is stroked at
/// [ThemeConfig.popupBorderWidth] — because nothing makes a theme spell them
/// the same. Equal widths (which is what a theme that wants one continuous
/// outline writes, and what `carbon` ships) put the flare's stroke exactly over
/// the band the bar's rim occupies, so the two read as one line turning the
/// corner; unequal ones still meet at the tip, with a step in the line's
/// thickness there rather than a break in it.
double popupAttachCollar(ThemeConfig theme, {String? attachEdge}) {
  if (attachEdge == null || theme.popupAttachRadius <= 0) return 0.0;
  return math.max(0.0, theme.panelBorderWidth);
}

/// The margin a popup's surface carries, per side: whichever of the shadow's
/// reach and the flare's is larger.
///
/// The larger rather than the sum. Both measure the same thing — how far past
/// the card something paints — and the flare is a solid part of the card's own
/// silhouette, so the shadow around *it* is the shadow the card already casts
/// rather than a second one to make room for. Summing would push every attached
/// popup's window out by a margin nothing draws in, and the shell has no
/// input-region support, so that margin would swallow clicks meant for the
/// desktop.
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
/// Null rather than a zero-width [Border] on purpose, the same nuance
/// `panel_background.dart` documents: a `Border` in the decoration carries a
/// non-zero [BoxDecoration.padding], which a [Container] would silently add to
/// its child's own padding.
///
/// An attached popup drops the side on the join — see [popupCornerRadius] for
/// what [attach] is. A hairline across the seam is the one thing that gives away
/// that the card is a second surface rather than the bar continuing, which is
/// what attaching exists to hide.
///
/// A non-uniform [Border] under a non-zero `borderRadius` is legal here
/// *because the visible sides still share one colour*: `BoxBorder.paint` takes a
/// `paintNonUniformBorder` path — a `drawDRRect` whose inset is 0 on the side
/// left at [BorderStyle.none] — before it reaches the uniformity assert. That
/// path refuses hairline widths, which cannot arise: no border is built at all
/// at or below a width of 0.
///
/// Two consequences the callers inherit. [Border.dimensions], and through it
/// [BoxDecoration.padding], loses [ThemeConfig.popupBorderWidth] on the joined
/// side — which is right, since there is no rim there to hold content off. And
/// the [PopupCard.border] override still replaces all four sides: a rim that
/// carries meaning rather than chrome is not the theme's to strip.
/// The rim as a single side, or [BorderSide.none] at a width of 0.
///
/// [AttachedPopupBorder] takes one of these rather than a [Border], because the
/// shape decides for itself which edge goes without — reading it off a
/// [_popupBorder] would mean reading the very side that had just been dropped.
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
///
/// [attachEdge] is the panel edge a *bar* popup is anchored to, and clamps that
/// one side to [ThemeConfig.popupGap]. A bar popup never paints its shadow over
/// the bar: the surface reaches from the card to the panel edge and no further,
/// so the compositor's own clip cuts the shadow exactly at the join — which is
/// what makes a zero gap read as one continuous surface rather than as a card
/// with a dark band under the bar it is glued to.
///
/// Clamped rather than zeroed, so one rule covers the range. At a gap of 0 the
/// side goes to 0; at a gap under the shadow's reach the shadow fills the gap
/// and stops there rather than crawling under the bar; at a gap of the reach or
/// more this is a no-op, so a floating theme keeps byte-for-byte the geometry it
/// had before attaching existed. Null — every popup that is not a bar popup —
/// is the same no-op.
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
///
/// [attach] names the panel edge an attached bar popup is joined to — see
/// [popupCornerRadius], and [PopupAttachScope], which is what decides it for
/// [PopupCard]. It reshapes the corners and drops the rim on that edge; the
/// shadow needs no attention here, because [popupShadowInsets] has already made
/// the surface flush and a surface clips at its own edge.
Decoration popupDecoration({
  required ThemeConfig theme,
  Border? border,
  bool opaque = false,
  String? attach,
}) {
  final radius = popupCornerRadius(theme, attach: attach);
  final shadow = popupShadow(theme);
  final rim = border ?? _popupBorder(theme, attach);
  if (attach != null && theme.popupAttachRadius > 0) {
    // The flare is not a corner radius and a BoxDecoration cannot draw one, so
    // this is the one card in the shell that is a ShapeDecoration. Everything
    // else about it is the same: the same fill, the same shadow, the same rim
    // colour and width — an explicit `border` contributes its side, since the
    // shape decides for itself that the join carries none.
    return ShapeDecoration(
      color: opaque ? opaquePopupFill(theme) : theme.popupBackground,
      shape: AttachedPopupBorder(
        edge: attach,
        radius: theme.popupRadius,
        attachRadius: theme.popupAttachRadius,
        // The bar's own rim, reached into so the flare continues it rather than
        // hanging beneath it. The margin for this is already in the surface —
        // popupAttachInsets carries it on the joined side.
        collar: popupAttachCollar(theme, attachEdge: attach),
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
/// A square [BoxDecoration] has none, and the layer is skipped entirely for it —
/// the same conditional `main.dart` applies to the panel, so a square card costs
/// exactly the layers it always did. An attached card is a [ShapeDecoration] and
/// always has one: its flare is the part of the silhouette a child would most
/// visibly spill out of.
bool decorationClips(Decoration decoration) => switch (decoration) {
      BoxDecoration(:final borderRadius) => borderRadius != null,
      ShapeDecoration() => true,
      _ => false,
    };

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

/// Marks a popup's content as **attached** to a panel edge, and says which one.
///
/// [OpaquePopupScope]'s pattern with a value: a marker injected at the root of a
/// popup's own view tree, read by [PopupCard] and by anything that builds a
/// [popupDecoration] by hand. [edge] is the panel's anchor string — `'top'`,
/// `'bottom'`, `'left'` or `'right'` — which for an edge-anchored popup is also
/// the popup's own side that touches the bar.
///
/// An inherited widget rather than a parameter threaded through the call sites,
/// for the reason `PopupCard` gives about the theme: a popup's content is built
/// once and captured in a `WindowEntry` builder, in a FlutterView that is a
/// *sibling* of the panel's rather than a descendant, so a card three levels
/// down cannot read the panel's `BarScope` and each of the twelve modules that
/// open bar popups would otherwise have to pass the edge down by hand.
///
/// Presence *is* the attached state: `PopupHost.openPopup` installs one only
/// when the popup is a bar popup, the caller asked to attach, and
/// [ThemeConfig.popupGap] is 0. A floating popup has no scope above it and gets
/// the four-corner card it always did.
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

  // Snapshotted at open and never revised, the discipline the popup's
  // constraints and shadow insets already follow: GTK3 resolves the placement
  // once at map time, so an attached popup cannot become a floating one without
  // being reopened.
  @override
  bool updateShouldNotify(PopupAttachScope oldWidget) => false;
}
