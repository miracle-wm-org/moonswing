/// The one animation a popup plays, in both directions.
///
/// [PopupTransition] replaced `PopupBounceIn`, which fifteen popup content widgets
/// wrapped themselves in by hand. Three things changed with it:
///
///  * **The effect is the theme's**, not the widget's — `popup_animation`.
///  * **It plays out as well as in.** The exit is the entrance *reversed* on the
///    same controller, so an effect cannot describe an opening it has no closing
///    for. Whoever owns the window flips [closing] and waits for [onClosed].
///  * **`PopupHost` wraps the card itself.** A call site that spelled the
///    animation by hand could forget it, and — worse, once there is an exit —
///    could route its close around it.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import 'package:moonswing/decor/material_textures.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/popup_effect.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';

/// How far a sliding popup travels, in logical pixels.
///
/// Deliberately small. The card is translated *inside* a window sized to its own
/// content plus the shadow's reach, and GTK3 resolves `gdk_window_move_to_rect`
/// once at map time — so a long travel would be clipped at the surface edge on
/// the frames it needed most. The fade makes the residue unobservable rather than
/// merely small: opacity and travel move together, so the half of the journey
/// nearest the clip is drawn at half opacity or less.
const double kPopupSlideDistance = 10.0;

/// The scale a [PopupEffect.scale] card starts from.
const double _kScaleFrom = 0.94;

/// The cross-axis scale a [PopupEffect.grow] card starts from.
const double _kGrowFrom = 0.55;

/// The angle, in radians, a [PopupEffect.flip] card is hinged open through.
const double _kFlipRadians = 1.05; // ~60°.

/// The fraction of its width a [PopupEffect.sprout] card starts out as.
const double _kSproutGirthFrom = 0.3;

/// The sway, in radians, a [PopupEffect.sprout] card settles through.
const double _kSproutSwayRadians = 0.035;

/// The angle, in radians, a [PopupEffect.spin] card turns through.
const double _kSpinRadians = 0.14; // ~8°.

/// Plays [effect] over [child] on mount, and the same effect backwards when
/// [closing] turns true.
///
/// [edge] is the panel anchor the popup is attached to and is what makes the
/// directional effects directional. A popup with no bar behind it — a context
/// menu at the pointer — passes null and is treated as hanging below its anchor,
/// which is where the compositor puts it.
///
/// [effect] and [duration] null mean "whatever the theme says", read from the
/// enclosing [ThemeScope]. `PopupHost` passes both explicitly instead, because
/// it wraps the card from *outside* the `ThemeProvider` the call site built.
class PopupTransition extends StatefulWidget {
  const PopupTransition({
    super.key,
    required this.child,
    this.effect,
    this.duration,
    this.edge,
    this.closing,
    this.onClosed,
  });

  final Widget child;

  /// The effect to play, or null to read `popup_animation` off the theme.
  final PopupEffect? effect;

  /// How long the entrance runs, or null to read `popup_animation_duration` off
  /// the theme. The exit is this shortened by
  /// [ShellDurations.popupExitFraction], never a duration of its own.
  final Duration? duration;

  /// The panel edge the popup is anchored to, for the directional effects.
  final String? edge;

  /// Flipped true by the window's owner to ask for the exit animation.
  final ValueListenable<bool>? closing;

  /// Called once the exit animation has finished and the window may be torn
  /// down. Never called for an entrance.
  final VoidCallback? onClosed;

  @override
  State<PopupTransition> createState() => _PopupTransitionState();
}

class _PopupTransitionState extends State<PopupTransition>
    with SingleTickerProviderStateMixin {
  /// Null until the effect is resolved, and null for good under
  /// [PopupEffect.none] — which is what makes that value a real off switch
  /// rather than a zero-length animation: no controller, no ticker, no
  /// `AnimatedBuilder`, and no save layer over the card.
  AnimationController? _ctrl;

  PopupEffect? _effect;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    widget.closing?.addListener(_onClosingChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The theme cannot be read from initState, and the effect has to be
    // resolved before the first frame is built or the card would flash at full
    // size on the way to being drawn at none of it.
    if (_effect != null) return;
    final theme = ThemeScope.maybeOf(context);
    final effect = widget.effect ?? theme?.popupEffect ?? PopupEffect.slide;
    _effect = effect;
    if (effect.animates) {
      final duration =
          widget.duration ?? theme?.popupInDuration ?? ShellDurations.popupIn;
      _ctrl = AnimationController(
        vsync: this,
        duration: duration,
        // Shorter on the way out, and only on the way out: an entrance is
        // paced to be followed, a dismissal is the user saying they are done.
        // The *shape* is still the entrance reversed, which is the promise
        // this widget makes.
        reverseDuration: duration * ShellDurations.popupExitFraction,
      )..forward();
    }
    // A close requested before this ever built — a popup displaced in the same
    // turn it opened — still has to be answered.
    if (widget.closing?.value ?? false) _onClosingChanged();
  }

  @override
  void didUpdateWidget(PopupTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.closing, widget.closing)) {
      oldWidget.closing?.removeListener(_onClosingChanged);
      widget.closing?.addListener(_onClosingChanged);
      if (widget.closing?.value ?? false) _onClosingChanged();
    }
  }

  @override
  void dispose() {
    widget.closing?.removeListener(_onClosingChanged);
    _ctrl?.dispose();
    super.dispose();
  }

  void _onClosingChanged() {
    if (_exiting || !(widget.closing?.value ?? false)) return;
    // Before the effect is resolved there is nothing to reverse and no frame
    // has been drawn; didChangeDependencies re-asks the moment there is.
    if (_effect == null) return;
    _exiting = true;
    final ctrl = _ctrl;
    if (ctrl == null) {
      widget.onClosed?.call();
      return;
    }
    ctrl.reverse().whenComplete(() {
      // Deliberately not gated on `mounted`: this callback is what destroys
      // the window, and a controller disposed mid-reverse never completes its
      // future at all — which is the case the owner's fallback timer exists
      // for, not this one.
      widget.onClosed?.call();
    });
  }

  /// Which way the card travels or hinges: away from the bar it belongs to.
  ///
  /// A popup below a top bar comes down out of it, one above a bottom bar rises
  /// out of it. Null — a menu at the pointer — reads as the top case.
  Offset get _direction {
    switch (widget.edge) {
      case 'bottom':
        return const Offset(0, 1);
      case 'left':
        return const Offset(-1, 0);
      case 'right':
        return const Offset(1, 0);
      default: // 'top', and every unanchored menu.
        return const Offset(0, -1);
    }
  }

  /// The corner or edge a [PopupEffect.grow] or [PopupEffect.flip] card is
  /// pinned to: the one it shares with the bar.
  Alignment get _joinAlignment {
    switch (widget.edge) {
      case 'bottom':
        return Alignment.bottomCenter;
      case 'left':
        return Alignment.centerLeft;
      case 'right':
        return Alignment.centerRight;
      default:
        return Alignment.topCenter;
    }
  }

  bool get _horizontal => widget.edge == 'left' || widget.edge == 'right';

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null) return widget.child;
    return AnimatedBuilder(
      animation: ctrl,
      // The card is built once and handed through: nothing inside it depends
      // on the animation, and a popup's content is among the most expensive
      // trees in the shell to rebuild — the weather card measures every row it
      // might draw.
      child: widget.child,
      builder: (context, child) => _apply(
        // Eased on the way in, and on the way out by the same token:
        // [Curves.easeOutCubic] read backwards *is* an ease-in, which is the
        // deceleration/acceleration pair a card entering and leaving wants.
        Curves.easeOutCubic.transform(ctrl.value.clamp(0.0, 1.0)),
        child!,
      ),
    );
  }

  Widget _apply(double t, Widget child) {
    switch (_effect ?? PopupEffect.slide) {
      case PopupEffect.none:
        return child;
      case PopupEffect.fade:
        return Opacity(opacity: t, child: child);
      case PopupEffect.slide:
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: _direction * ((1 - t) * kPopupSlideDistance),
            child: child,
          ),
        );
      case PopupEffect.scale:
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: _kScaleFrom + (1 - _kScaleFrom) * t,
            child: child,
          ),
        );
      case PopupEffect.grow:
        final s = _kGrowFrom + (1 - _kGrowFrom) * t;
        return Opacity(
          opacity: t,
          child: Transform.scale(
            // Only across the join: a card unrolling out of a horizontal bar
            // keeps its width, or it reads as a scale that happens to be
            // off-centre rather than as the bar opening.
            scaleX: _horizontal ? s : 1.0,
            scaleY: _horizontal ? 1.0 : s,
            alignment: _joinAlignment,
            child: child,
          ),
        );
      case PopupEffect.flip:
        final angle = (1 - t) * _kFlipRadians;
        final matrix = Matrix4.identity()..setEntry(3, 2, 0.0016);
        // Hinged on the shared edge, so the far side of the card swings and
        // the joined side stays put. A bottom bar and a right-hand one hinge
        // the opposite way round from their counterparts, hence the sign.
        if (_horizontal) {
          matrix.rotateY(widget.edge == 'right' ? -angle : angle);
        } else {
          matrix.rotateX(widget.edge == 'bottom' ? -angle : angle);
        }
        return Opacity(
          opacity: t,
          child: Transform(
            transform: matrix,
            alignment: _joinAlignment,
            child: child,
          ),
        );
      case PopupEffect.sprout:
        // Settled: the card exactly as built, with no clip layer at rest.
        if (t >= 1.0) return child;
        // Length leads and girth follows, which is what makes it a trunk
        // rising rather than a card unrolling: it pushes out of the bar thin,
        // then thickens to its full width as it lengthens.
        final length = t;
        final girth = _kSproutGirthFrom +
            (1 - _kSproutGirthFrom) *
                Curves.easeInOut.transform(((t - 0.12) / 0.88).clamp(0.0, 1.0));
        // And a little sway about its foot as it settles, gone at rest.
        final sway = _kSproutSwayRadians *
            math.sin(t * math.pi * 2.4) *
            (1 - t);
        return Transform.rotate(
          angle: widget.edge == 'bottom' || widget.edge == 'right' ? -sway : sway,
          alignment: _joinAlignment,
          child: Builder(builder: (context) {
            final clipper = SproutClipper(
              edge: widget.edge ?? 'top',
              length: length,
              girth: girth,
            );
            final theme = ThemeScope.maybeOf(context);
            return ClipPath(
              clipper: clipper,
              // The growing trunk wears its bark on the way up, not only once
              // it has arrived: a theme with a material rim strokes the clip's
              // own outline in it.
              child: theme == null || !theme.popupBorderTexture.paints
                  ? child
                  : CustomPaint(
                      foregroundPainter: _SproutBarkPainter(
                        clipper: clipper,
                        theme: theme,
                        devicePixelRatio:
                            MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
                      ),
                      child: child,
                    ),
            );
          }),
        );
      case PopupEffect.spin:
        return Opacity(
          opacity: t,
          child: Transform.rotate(
            angle: (1 - t) * _kSpinRadians,
            child: Transform.scale(
              scale: _kScaleFrom + (1 - _kScaleFrom) * t,
              child: child,
            ),
          ),
        );
    }
  }
}

/// The outline a [PopupEffect.sprout] card is revealed through: a trunk
/// [length] of the way out of the join on [edge], [girth] of the card's width,
/// with a crowned tip and a foot that flares into the bar.
///
/// The crown is carried *past* the card's far edge as [length] reaches 1, so at
/// full length and full girth the clip is the whole card and nothing of its
/// corners is shaved.
class SproutClipper extends CustomClipper<Path> {
  const SproutClipper({
    required this.edge,
    required this.length,
    required this.girth,
  });

  final String edge;
  final double length;
  final double girth;

  @override
  Path getClip(Size size) {
    final horizontal = edge == 'left' || edge == 'right';
    final across = horizontal ? size.height : size.width;
    final along = horizontal ? size.width : size.height;
    final w = across * girth.clamp(0.0, 1.0);
    final crown = w / 2;
    final reach = (along + crown) * length.clamp(0.0, 1.0);
    final c = across / 2;
    // The foot flares into the bar the way a trunk's does.
    final foot = math.min(10.0, across * 0.08) * (1 - girth).clamp(0.0, 1.0) + 2;
    final shoulder = math.max(0.0, reach - crown);
    final path = Path()
      ..moveTo(c - w / 2 - foot, 0)
      ..quadraticBezierTo(c - w / 2, 0, c - w / 2, math.min(foot * 1.4, shoulder))
      ..lineTo(c - w / 2, shoulder)
      ..arcToPoint(Offset(c + w / 2, shoulder),
          radius: Radius.elliptical(w / 2, math.max(0.01, math.min(crown, reach))),
          clockwise: false)
      ..lineTo(c + w / 2, math.min(foot * 1.4, shoulder))
      ..quadraticBezierTo(c + w / 2, 0, c + w / 2 + foot, 0)
      ..close();
    // Built for a join along the top; turned onto the real edge.
    final m = Matrix4.identity();
    switch (edge) {
      case 'bottom':
        m.setEntry(1, 1, -1.0);
        m.setEntry(1, 3, size.height);
      case 'left':
        m.setEntry(0, 0, 0.0);
        m.setEntry(0, 1, 1.0);
        m.setEntry(1, 0, 1.0);
        m.setEntry(1, 1, 0.0);
      case 'right':
        m.setEntry(0, 0, 0.0);
        m.setEntry(0, 1, -1.0);
        m.setEntry(0, 3, size.width);
        m.setEntry(1, 0, 1.0);
        m.setEntry(1, 1, 0.0);
      default:
        break;
    }
    return path.transform(m.storage);
  }

  @override
  bool shouldReclip(SproutClipper old) =>
      old.edge != edge || old.length != length || old.girth != girth;
}

/// The bark on a sprouting card's edge: [SproutClipper]'s outline stroked in
/// the theme's rim material, twice the rim's width so the clip leaves exactly
/// the rim's width inside it.
class _SproutBarkPainter extends CustomPainter {
  _SproutBarkPainter({
    required this.clipper,
    required this.theme,
    required this.devicePixelRatio,
  }) : super(repaint: MaterialTextures.instance);

  final SproutClipper clipper;
  final ThemeConfig theme;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final width = theme.popupBorderWidth;
    if (width <= 0) return;
    final bark = resolveSurfaceImage(
      material: theme.popupBorderTexture,
      tint: theme.popupBorderTextureColor,
      devicePixelRatio: devicePixelRatio,
    );
    final path = clipper.getClip(size);
    final across = clipper.edge != 'left' && clipper.edge != 'right';
    final paint = bark == null
        ? (Paint()..color = theme.popupBorder)
        : materialPaint(bark.image,
            pixelScale: bark.pixelScale * 2,
            across: across,
            opacity: theme.popupBorderTextureColor.a);
    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2,
    );
  }

  @override
  bool shouldRepaint(_SproutBarkPainter old) =>
      old.clipper != clipper ||
      old.theme != theme ||
      old.devicePixelRatio != devicePixelRatio;

  @override
  bool? hitTest(Offset position) => false;
}
