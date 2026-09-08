/// The geometry half of a full-screen overlay's entrance: one [OverlayEffect]
/// applied to the card, played forward to open and backward to close.
///
/// `FadeOverlayScaffold` owns the controller, the scrim and the closing
/// handshake; this owns what the *card* does, and nothing else. The split is the
/// rule that scaffold documents: an overlay window spans the whole output, so
/// anything wrapping the scaffold in an opacity or a transform is a full-output
/// offscreen every frame. Everything here is bounded by the card.
library;

import 'package:flutter/widgets.dart';

import 'package:graceful_shell/theme/overlay_effect.dart';

/// How far a travelling card moves, in logical pixels.
///
/// Small on purpose. The card is centred in a surface that spans the output, so
/// there is room for far more — but an overlay is a thing being *presented*, not
/// thrown, and the fade is doing the arriving. Big enough to read as a
/// direction, short enough that a 160ms default has time to cover it.
const double kOverlayTravel = 28.0;

/// The scale an [OverlayEffect.scale] card starts from.
///
/// The value every overlay played before the key existed, so a theme that says
/// nothing about `overlay_animation` is the shell as it was.
const double kOverlayScaleFrom = 0.96;

/// The scale an [OverlayEffect.zoom] card starts from — the mirror of
/// [kOverlayScaleFrom], a touch further out because a card shrinking into place
/// reads as smaller motion than one growing.
const double _kZoomFrom = 1.08;

/// The cross-axis scale an [OverlayEffect.unfold] card starts from.
const double _kUnfoldFrom = 0.62;

/// The angle, in radians, an [OverlayEffect.flip] or [OverlayEffect.swing] card
/// is hinged open through. ~40°: enough to read as a hinge, short of the angle
/// where a wide card's far edge leaves the output.
const double _kHingeRadians = 0.7;

/// The angle, in radians, an [OverlayEffect.spin] card turns through. ~5°.
const double _kSpinRadians = 0.09;

/// The perspective entry for the hinged effects.
///
/// An order of magnitude gentler than a popup's, and for a reason the popup does
/// not have: these cards are large — the settings panel is most of the output —
/// and perspective divides by distance, so the foreshortening a menu-sized card
/// wants would fold a panel-sized one in half.
const double _kPerspective = 0.0006;

/// Applies [effect]'s movement to [child] and fades it, both driven by
/// animations the scaffold owns.
///
/// [geometry] is the configured curve, which may leave the unit interval — that
/// is what an overshoot *is*. [opacity] is the same curve clamped into it,
/// because `FadeTransition` asserts, and a card that flickered out of existence
/// at the top of a bounce would be a bug rather than a flourish.
class OverlayTransition extends StatelessWidget {
  const OverlayTransition({
    super.key,
    required this.effect,
    required this.geometry,
    required this.opacity,
    required this.child,
  });

  final OverlayEffect effect;

  /// The configured curve, in the effect's own units. Unclamped.
  final Animation<double> geometry;

  /// The same progress clamped to `0..1`, for anything reading as an alpha.
  final Animation<double> opacity;

  /// The centred card.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // No wrapping at all under `none`: the scaffold builds no controller for it,
    // so there is nothing to listen to and nothing to skip.
    if (!effect.animates) return child;
    Widget card = child;
    if (effect != OverlayEffect.fade) {
      card = AnimatedBuilder(
        animation: geometry,
        // Built once and handed through: nothing inside an overlay card depends
        // on the animation, and these are the most expensive trees in the shell
        // — the settings panel lays out a whole page, the launcher a grid of
        // measured labels.
        child: card,
        builder: (context, built) => _apply(geometry.value, built!),
      );
    }
    // The one real layer, and it is the card's size rather than the output's.
    // See `FadeOverlayScaffold` for why that distinction is worth a paragraph.
    return FadeTransition(opacity: opacity, child: card);
  }

  Widget _apply(double t, Widget child) {
    switch (effect) {
      // Both handled by the caller; spelled out rather than defaulted so a new
      // effect cannot be added without deciding what it draws.
      case OverlayEffect.none:
      case OverlayEffect.fade:
        return child;
      case OverlayEffect.scale:
        return Transform.scale(
          scale: kOverlayScaleFrom + (1 - kOverlayScaleFrom) * t,
          child: child,
        );
      case OverlayEffect.zoom:
        return Transform.scale(
          scale: _kZoomFrom + (1 - _kZoomFrom) * t,
          child: child,
        );
      case OverlayEffect.rise:
        return Transform.translate(
          offset: Offset(0, (1 - t) * kOverlayTravel),
          child: child,
        );
      case OverlayEffect.drop:
        return Transform.translate(
          offset: Offset(0, -(1 - t) * kOverlayTravel),
          child: child,
        );
      case OverlayEffect.unfold:
        return Transform.scale(
          // Across one axis only, about the card's middle: a card that kept its
          // width while its height opened reads as unfolding, where scaling both
          // is [OverlayEffect.scale] with a longer journey.
          scaleY: _kUnfoldFrom + (1 - _kUnfoldFrom) * t,
          child: child,
        );
      case OverlayEffect.flip:
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, _kPerspective)
            ..rotateX((1 - t) * _kHingeRadians),
          alignment: Alignment.center,
          child: child,
        );
      case OverlayEffect.swing:
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, _kPerspective)
            ..rotateY((1 - t) * _kHingeRadians),
          alignment: Alignment.center,
          child: child,
        );
      case OverlayEffect.spin:
        return Transform.rotate(
          angle: (1 - t) * _kSpinRadians,
          child: Transform.scale(
            scale: kOverlayScaleFrom + (1 - kOverlayScaleFrom) * t,
            child: child,
          ),
        );
    }
  }
}

/// [curve]'s pacing, held inside `0..1`.
///
/// The overshooting curves are the point of offering curves at all, and they are
/// also unusable as an alpha: `Opacity` asserts its argument is in the unit
/// interval, so an elastic fade would abort the shell on the first frame past
/// its peak. Clamping rather than substituting a second curve keeps the fade in
/// step with the movement it belongs to — the card is fully opaque for the whole
/// of the overshoot, which is exactly what a card settling into place should be.
class ClampedCurve extends Curve {
  const ClampedCurve(this.curve);

  final Curve curve;

  @override
  double transformInternal(double t) => curve.transform(t).clamp(0.0, 1.0);

  @override
  String toString() => 'ClampedCurve($curve)';
}

/// The Flutter curve an [OverlayCurve] names.
///
/// The one place the table meets `dart:ui`, kept out of `theme/overlay_effect.dart`
/// so that table stays a plain unit test.
Curve flutterCurve(OverlayCurve curve) {
  switch (curve) {
    case OverlayCurve.linear:
      return Curves.linear;
    case OverlayCurve.easeIn:
      return Curves.easeInCubic;
    case OverlayCurve.easeOut:
      // The shell's standard entrance ease, and what popups play — so the
      // default overlay entrance is the default popup entrance's pacing.
      return Curves.easeOutCubic;
    case OverlayCurve.easeInOut:
      return Curves.easeInOutCubic;
    case OverlayCurve.emphasized:
      return Curves.fastOutSlowIn;
    case OverlayCurve.overshoot:
      return Curves.easeOutBack;
    case OverlayCurve.bounce:
      return Curves.bounceOut;
    case OverlayCurve.elastic:
      return Curves.elasticOut;
  }
}
