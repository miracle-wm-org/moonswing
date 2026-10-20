import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:moonswing/overlay_transition.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/overlay_effect.dart';

/// The entrance every full-screen overlay plays: scrim, a centred card that
/// arrives on the theme's `overlay_animation`, and the closing-notifier
/// handshake.
///
/// The handshake is the load-bearing part: nothing tears the window down
/// directly. The root flips [closing]; this scaffold plays the reverse animation
/// and only then calls [onClosed], which unregisters and destroys the native
/// window.
///
/// **The shape and the pace are the theme's, not a call site's.** This used to
/// take a `duration` and a `beginScale`, and two overlays set them — which meant
/// the same shell answered a keystroke two different ways for no reason the user
/// could see or change. What is left of that is [durationScale], a *proportion*
/// of whatever the theme asks for rather than a duration of its own, so an
/// overlay that wants to arrive more deliberately still moves when the theme
/// does. See `lib/theme/overlay_effect.dart` for the tables and `CONFIG.md` for
/// the four keys.
class FadeOverlayScaffold extends StatefulWidget {
  const FadeOverlayScaffold({
    super.key,
    required this.closing,
    required this.onClosed,
    this.durationScale = 1.0,
    this.onBackdropTap,
    this.offset,
    this.foreground,
    required this.child,
  });

  /// Flipped true by the owner to request the fade-out.
  final ValueListenable<bool> closing;

  /// Called once the fade-out has finished — the cue to tear the window down.
  final VoidCallback onClosed;

  /// This overlay's pace as a multiple of the theme's, for the one surface that
  /// is not a card the pointer is chasing.
  ///
  /// A ratio rather than a duration so `overlay_animation_duration` still moves
  /// every overlay together, and so an overlay cannot quietly opt out of a
  /// user's choice. Unread under [OverlayEffect.none], which builds no
  /// controller at all.
  final double durationScale;

  /// Tap on the scrim. The shell has no input-region support, so a
  /// full-screen surface swallows every click on the monitor — without
  /// dismiss-on-backdrop a mouse-only user has no way out. Null for overlays
  /// that handle (or refuse) backdrop clicks themselves.
  final VoidCallback? onBackdropTap;

  /// How far the card sits from the centre of the surface, for a card the
  /// user has moved. Null is the centre for good.
  ///
  /// Applied as the card's *position* — never a transform over it, and never
  /// inside the [OverlayTransition], whose render objects hit-test against
  /// their own untranslated box and would drop every click on a card dragged
  /// off it. Clamped at layout, so whatever is asked for, the card stays on
  /// the surface; a move costs a relayout of this one box, which re-lays its
  /// child out only if the constraints changed, and they do not.
  final ValueListenable<Offset>? offset;

  /// The centred card.
  final Widget child;

  /// What floats on the window *around* the card, and over it: built across
  /// the whole surface above the card, and given the scaffold's [opacity] so
  /// it can arrive and leave with the card.
  ///
  /// Never an `Opacity` over the whole of it, for the reason the scrim fades
  /// by its own alpha (see [build]): the foreground is the size of the output.
  /// Each thing in it fades on its own, and anything it lays out answers hits
  /// only where it draws, so the card stays reachable around it.
  final Widget Function(BuildContext context, Animation<double> opacity)?
  foreground;

  @override
  State<FadeOverlayScaffold> createState() => _FadeOverlayScaffoldState();
}

class _FadeOverlayScaffoldState extends State<FadeOverlayScaffold>
    with SingleTickerProviderStateMixin {
  /// Null until the theme is resolved, and null for good under
  /// [OverlayEffect.none] — which is what makes that value a real off switch
  /// rather than a zero-length animation: no controller, no ticker, and no
  /// layer over the card.
  AnimationController? _controller;

  /// The configured curve in its own units, which the overshooting curves take
  /// outside `0..1`.
  Animation<double>? _geometry;

  /// The same progress as an alpha: [_geometry]'s curve, clamped.
  Animation<double>? _opacity;

  OverlayEffect? _effect;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    widget.closing.addListener(_onClosingChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The theme cannot be read from initState, and the effect has to be
    // resolved before the first frame is built or the card would flash at full
    // size on its way to being drawn at none of it.
    if (_effect != null) return;
    final theme = ThemeScope.of(context);
    final effect = theme.overlayEffect;
    _effect = effect;
    if (effect.animates) {
      final duration = theme.overlayInDuration * widget.durationScale;
      _controller = AnimationController(
        vsync: this,
        duration: duration,
        // The exit is the entrance reversed and scaled by
        // `overlay_animation_exit_ratio` — one number rather than a second
        // duration, so lengthening the entrance lengthens the exit with it and
        // the ratio says only how the two relate.
        reverseDuration: duration * theme.overlayExitRatio,
      );
      final curve = flutterCurve(theme.overlayCurve);
      _geometry = CurvedAnimation(
        parent: _controller!,
        curve: curve,
        // Read backwards, so an ease-out entrance leaves on an ease-in and an
        // overshoot becomes the anticipation dip that answers it.
        reverseCurve: curve.flipped,
      );
      final clamped = ClampedCurve(curve);
      _opacity = CurvedAnimation(
        parent: _controller!,
        curve: clamped,
        reverseCurve: clamped.flipped,
      );
      _controller!.forward();
    }
    // A close requested before this ever built — an overlay superseded in the
    // same turn it opened — still has to be answered.
    //
    // Under `none` that answer is immediate, and immediate here means *inside
    // the build this is part of*: `onClosed` unregisters a window and calls
    // setState on the root, which during a build is an assertion in debug and a
    // scheduling anomaly in release. So it waits for the end of the frame. An
    // animated effect is already asynchronous — the reverse has to play — and
    // needs no such care.
    if (widget.closing.value) {
      if (effect.animates) {
        _onClosingChanged();
      } else {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _onClosingChanged());
      }
    }
  }

  @override
  void didUpdateWidget(FadeOverlayScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.closing, widget.closing)) {
      oldWidget.closing.removeListener(_onClosingChanged);
      widget.closing.addListener(_onClosingChanged);
      if (widget.closing.value) _onClosingChanged();
    }
  }

  @override
  void dispose() {
    widget.closing.removeListener(_onClosingChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _onClosingChanged() {
    if (_exiting || !widget.closing.value) return;
    // Before the effect is resolved there is nothing to reverse and no frame
    // has been drawn; didChangeDependencies re-asks the moment there is.
    if (_effect == null) return;
    _exiting = true;
    final controller = _controller;
    if (controller == null) {
      // `none`: the window may be torn down on the frame it was closed.
      widget.onClosed();
      return;
    }
    controller.reverse().then((_) => widget.onClosed());
  }

  @override
  Widget build(BuildContext context) {
    final scrim = ThemeScope.of(context).scrim;
    final opacity = _opacity;

    // No BackdropFilter here, deliberately. A filter reaches only what Flutter
    // has already painted beneath it, and this scaffold *is* the first thing
    // painted into its window: the scrim is this widget's own child, and under
    // that is a transparent layer-shell surface whose contents belong to the
    // compositor. So the backdrop is empty, the filter resolves to nothing, and
    // every animated frame paid for a full-output Gaussian that changed no pixel.
    //
    // **And no `Opacity` across the whole of it either, for the same
    // arithmetic.** Every overlay window calls `spanFullOutput`, so an opacity
    // layer here is bounded by the output: `RenderOpacity` skips the layer at
    // exactly 1.0, so it cost nothing at rest and then allocated and blended a
    // full-output offscreen on every frame in and out — thirty-odd megabytes a
    // frame at 4K. The scrim is a flat fill and fades by its own alpha instead;
    // only the card keeps a real layer, because a card is a stack of overlapping
    // pieces and fading them one at a time shows it through itself.
    //
    // This is also why no [OverlayEffect] moves the scrim: it is the size of the
    // output, so anything transforming it is that same full-output layer under
    // another name. The wash arrives by alpha, whatever the card is doing.
    Widget backdrop = Stack(
      // Non-directional, so this does not depend on an ambient
      // `Directionality` for a stack whose one unpositioned child is centred.
      alignment: Alignment.center,
      // `Positioned.fill` and the default loose fit, never `StackFit.expand`:
      // that tightens *every* child, which would stretch the card to the
      // output instead of centring it.
      children: [
        Positioned.fill(
          child: opacity == null
              // `none`, and the one case that needs no listener at all.
              ? ColoredBox(color: scrim)
              : AnimatedBuilder(
                  animation: opacity,
                  builder: (context, _) => ColoredBox(
                    color: scrim.withValues(alpha: scrim.a * opacity.value),
                  ),
                ),
        ),
        // Built outside the scrim's builder, and driven by transition widgets
        // rather than by a rebuild of this scaffold: the card, the `Center` and
        // the transform stop being rebuilt on every frame of the animation.
        _placeCard(
          OverlayTransition(
            effect: _effect ?? OverlayEffect.scale,
            geometry: _geometry ?? kAlwaysCompleteAnimation,
            opacity: opacity ?? kAlwaysCompleteAnimation,
            child: widget.child,
          ),
        ),
        if (widget.foreground case final foreground?)
          Positioned.fill(
            child: foreground(context, opacity ?? kAlwaysCompleteAnimation),
          ),
      ],
    );
    if (widget.onBackdropTap != null) {
      // An ancestor of both, as it has always been: the card's own opaque
      // detector is deeper in the tree, so it enters the arena first and
      // wins, and a tap on the card still does not dismiss through this one.
      backdrop = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onBackdropTap,
        child: backdrop,
      );
    }
    return backdrop;
  }

  Widget _placeCard(Widget card) {
    final offset = widget.offset;
    if (offset == null) return Center(child: card);
    // Fills the stack, so the delegate is handed the whole surface to place
    // the card in — and so a click anywhere on it reaches the card wherever it
    // has been moved to.
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _CardPlacement(offset),
        child: card,
      ),
    );
  }
}

/// Centres the card, moves it by [offset], and keeps it on the surface.
class _CardPlacement extends SingleChildLayoutDelegate {
  // The listenable is the relayout trigger, so a drag never rebuilds anything.
  _CardPlacement(this.offset) : super(relayout: offset);

  final ValueListenable<Offset> offset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      placeOverlayCard(size, childSize, offset.value);

  @override
  bool shouldRelayout(_CardPlacement oldDelegate) =>
      oldDelegate.offset != offset;
}

/// Where a card of [card] size sits on a surface of [surface] size when it has
/// been moved [offset] from the centre: the centre plus the offset, clamped so
/// no edge of the card leaves the surface. A card larger than the surface is
/// pinned to its top left rather than pushed off it.
///
/// Also what places anything kept relative to the card, such as the
/// overview's sticky notes.
Offset placeOverlayCard(Size surface, Size card, Offset offset) {
  final maxX = math.max(0.0, surface.width - card.width);
  final maxY = math.max(0.0, surface.height - card.height);
  return Offset(
    (maxX / 2 + offset.dx).clamp(0.0, maxX),
    (maxY / 2 + offset.dy).clamp(0.0, maxY),
  );
}

/// The card a full-screen overlay centres on its scrim: [color], rounded to the
/// theme's `overlay_radius` and rimmed in the accent, with [child] clipped to
/// the inside of that rim.
///
/// The clip is what lets the radius be the user's. A card's content is laid out
/// in its box, not its outline, so at the 12 every overlay used to hard-code a
/// header's divider or a highlighted row in a corner fell inside the curve by
/// luck — and at a larger radius would be drawn out past it onto the scrim.
class OverlayCard extends StatelessWidget {
  const OverlayCard({
    super.key,
    required this.color,
    this.padding = EdgeInsets.zero,
    required this.child,
  });

  /// The fill. Each overlay picks its own: the workspaces force it opaque, the
  /// search cards keep the theme's alpha.
  final Color color;

  /// Inside the clip, so content kept off the edge by it is still cut by the
  /// curve rather than poking past it.
  final EdgeInsetsGeometry padding;

  final Widget child;

  /// The accent rim's thickness.
  static const double borderWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final radius = theme.overlayRadius;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: theme.accent, width: borderWidth),
      ),
      child: Padding(
        padding: const EdgeInsets.all(borderWidth),
        // Concentric with the rim's inner edge. On a square card the clip is
        // switched off rather than left out: a zero-radius clip is still a clip
        // layer, for nothing, but dropping the widget would change the depth of
        // everything under it — and the settings panel is one of these cards,
        // so typing a radius into it would remount the pane being typed in.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            math.max(0.0, radius - borderWidth),
          ),
          clipBehavior: radius > borderWidth ? Clip.antiAlias : Clip.none,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
