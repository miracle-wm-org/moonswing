/// The wallpaper window's change from one wallpaper to the next: the geometry
/// of every [WallpaperTransition] (pure, in [wallpaperFrame]) and the switcher
/// that plays it ([WallpaperSwitcher]).
///
/// `AnimatedSwitcher` did this when the only effect was a crossfade, and it
/// cannot do the rest: it wraps every child in the same transition, played
/// forwards on the incoming one and *backwards* on the outgoing one, so a
/// circle opening over the old wallpaper is also the old wallpaper's own circle
/// closing — with nothing at all painted outside it. Here an effect describes
/// both layers at once, so the outgoing wallpaper stays whole beneath a reveal
/// and only moves when the effect says it does (the flip).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:moonswing/decor/seeded_random.dart';
import 'package:moonswing/wallpaper_transition.dart';

export 'package:moonswing/wallpaper_transition.dart';

/// What one of the two wallpapers looks like on one frame of a change.
///
/// Three properties, always all three, because the switcher renders every layer
/// through the same three widgets whatever the effect: a layer whose *shape* of
/// subtree changed from one frame to the next would remount the wallpaper under
/// it, which for a video is a new player starting from the beginning.
class WallpaperLayer {
  const WallpaperLayer({this.opacity = 1.0, this.transform, this.clip});

  /// Fully visible, untouched.
  static const WallpaperLayer shown = WallpaperLayer();

  /// Not painted at all.
  static const WallpaperLayer hidden = WallpaperLayer(opacity: 0.0);

  /// 0 to 1. At 1 no layer is composited; at 0 nothing is painted.
  final double opacity;

  /// In the layer's own pixels; null is the identity.
  final Matrix4? transform;

  /// What of the layer is painted, in its own pixels; null is all of it.
  final Path? clip;
}

/// Both layers of one frame, and whether the dark fill shows behind them —
/// which it has to for an effect that moves the outgoing wallpaper off part of
/// the screen without the incoming one covering it.
class WallpaperFrame {
  const WallpaperFrame({
    required this.outgoing,
    required this.incoming,
    this.backdrop = false,
  });

  final WallpaperLayer outgoing;
  final WallpaperLayer incoming;
  final bool backdrop;

  /// The change finished: the new wallpaper alone.
  static const WallpaperFrame done = WallpaperFrame(
    outgoing: WallpaperLayer.hidden,
    incoming: WallpaperLayer.shown,
  );
}

/// The fill behind a flip — the same as the window's own empty state.
const Color kWallpaperBackdrop = Color(0xFF1A1A1A);

/// How many squares the [WallpaperTransition.checkerboard] lays across the
/// screen; rows follow from the screen's aspect, so the squares are square.
const int _kCheckerColumns = 8;

/// The slats of a [WallpaperTransition.blinds].
const int _kBlindSlats = 10;

/// The tiles across the screen in a [WallpaperTransition.dissolve].
const int _kDissolveColumns = 32;

/// The progress by which every dissolve tile has landed, leaving the rest of
/// the change for the last ones to be seen to land rather than arriving on the
/// final frame.
const double _kDissolveLatest = 0.85;

/// How far a flip draws the card back at its edge-on moment.
const double _kFlipRecede = 0.15;

/// How much larger than the screen a zoom starts.
const double _kZoomFrom = 0.12;

/// One frame of [plan] at linear progress [t] (0 to 1) over a window of
/// [size]. Each effect applies its own easing, since what reads as natural
/// differs — a slide wants to arrive quickly and settle, a flip to be fastest
/// edge-on.
@visibleForTesting
WallpaperFrame wallpaperFrame(
  WallpaperTransitionPlan plan,
  double t,
  Size size,
) {
  if (t >= 1.0) return WallpaperFrame.done;
  final p = t <= 0.0 ? 0.0 : t;
  final w = size.width;
  final h = size.height;

  switch (plan.effect) {
    case WallpaperTransition.none:
      return WallpaperFrame.done;

    case WallpaperTransition.random:
    case WallpaperTransition.fade:
      return WallpaperFrame(
        outgoing: WallpaperLayer.shown,
        incoming: WallpaperLayer(opacity: Curves.easeInOut.transform(p)),
      );

    case WallpaperTransition.checkerboard:
      // Every other square runs half a square behind, so the whole sweep is
      // one and a half squares' worth of travel.
      final e = Curves.easeInOut.transform(p) * 1.5;
      final cell = w / _kCheckerColumns;
      final rows = cell <= 0 ? 0 : (h / cell).ceil();
      final path = Path();
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < _kCheckerColumns; c++) {
          final local = (e - ((r + c).isOdd ? 0.5 : 0.0)).clamp(0.0, 1.0);
          if (local <= 0) continue;
          path.addRect(Rect.fromLTWH(c * cell, r * cell, cell * local, cell));
        }
      }
      return WallpaperFrame(
        outgoing: WallpaperLayer.shown,
        incoming: WallpaperLayer(clip: path),
      );

    case WallpaperTransition.circle:
      final e = Curves.easeInOutCubic.transform(p);
      // From the centre the farthest point is a corner.
      final radius = e * math.sqrt(w * w + h * h) / 2;
      return WallpaperFrame(
        outgoing: WallpaperLayer.shown,
        incoming: WallpaperLayer(
          clip: Path()
            ..addOval(
              Rect.fromCircle(center: Offset(w / 2, h / 2), radius: radius),
            ),
        ),
      );

    case WallpaperTransition.flip:
      final e = Curves.easeInOut.transform(p);
      final recede = 1.0 - _kFlipRecede * math.sin(math.pi * e);
      if (e < 0.5) {
        return WallpaperFrame(
          backdrop: true,
          outgoing: WallpaperLayer(
            transform: _flip(size, e * math.pi, recede),
          ),
          incoming: WallpaperLayer.hidden,
        );
      }
      return WallpaperFrame(
        backdrop: true,
        outgoing: WallpaperLayer.hidden,
        incoming: WallpaperLayer(
          transform: _flip(size, (e - 1.0) * math.pi, recede),
        ),
      );

    case WallpaperTransition.slide:
      final away = 1.0 - Curves.easeOutCubic.transform(p);
      final (dx, dy) = switch (plan.edge) {
        WallpaperEdge.left => (-w * away, 0.0),
        WallpaperEdge.right => (w * away, 0.0),
        WallpaperEdge.top => (0.0, -h * away),
        WallpaperEdge.bottom => (0.0, h * away),
      };
      return WallpaperFrame(
        outgoing: WallpaperLayer.shown,
        incoming: WallpaperLayer(
          transform: Matrix4.translationValues(dx, dy, 0),
        ),
      );

    case WallpaperTransition.wipe:
      final e = Curves.easeInOutCubic.transform(p);
      final rect = switch (plan.edge) {
        WallpaperEdge.left => Rect.fromLTWH(0, 0, w * e, h),
        WallpaperEdge.right => Rect.fromLTWH(w * (1 - e), 0, w * e, h),
        WallpaperEdge.top => Rect.fromLTWH(0, 0, w, h * e),
        WallpaperEdge.bottom => Rect.fromLTWH(0, h * (1 - e), w, h * e),
      };
      return WallpaperFrame(
        outgoing: WallpaperLayer.shown,
        incoming: WallpaperLayer(clip: Path()..addRect(rect)),
      );

    case WallpaperTransition.blinds:
      final e = Curves.easeInOutCubic.transform(p);
      final slat = h / _kBlindSlats;
      final path = Path();
      if (e > 0) {
        for (var i = 0; i < _kBlindSlats; i++) {
          path.addRect(Rect.fromLTWH(0, i * slat, w, slat * e));
        }
      }
      return WallpaperFrame(
        outgoing: WallpaperLayer.shown,
        incoming: WallpaperLayer(clip: path),
      );

    case WallpaperTransition.zoom:
      final e = Curves.easeOutCubic.transform(p);
      final scale = 1.0 + _kZoomFrom * (1.0 - e);
      return WallpaperFrame(
        outgoing: WallpaperLayer.shown,
        incoming: WallpaperLayer(
          opacity: Curves.easeOut.transform(p),
          transform: _aboutCentre(
            size,
            Matrix4.diagonal3Values(scale, scale, 1),
          ),
        ),
      );

    case WallpaperTransition.dissolve:
      final cell = w / _kDissolveColumns;
      final rows = cell <= 0 ? 0 : (h / cell).ceil();
      // Re-drawn from the seed every frame rather than kept: a frame is a pure
      // function of the plan and the progress, and a few hundred draws from
      // mulberry32 are nothing beside the clip they decide.
      final random = SeededRandom(plan.seed);
      final path = Path();
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < _kDissolveColumns; c++) {
          final lands = random.nextDouble() * _kDissolveLatest;
          if (p > lands) {
            path.addRect(Rect.fromLTWH(c * cell, r * cell, cell, cell));
          }
        }
      }
      return WallpaperFrame(
        outgoing: WallpaperLayer.shown,
        incoming: WallpaperLayer(clip: path),
      );
  }
}

/// [m] applied about the centre of a window of [size] rather than its origin.
Matrix4 _aboutCentre(Size size, Matrix4 m) =>
    Matrix4.translationValues(size.width / 2, size.height / 2, 0)
      ..multiply(m)
      ..multiply(
        Matrix4.translationValues(-size.width / 2, -size.height / 2, 0),
      );

/// A turn of [angle] about the vertical middle, in perspective, drawn back to
/// [scale].
///
/// The perspective is relative to the width, so a 4K output and a laptop flip
/// alike: the near edge of the turning card swells by at most a quarter.
Matrix4 _flip(Size size, double angle, double scale) {
  final depth = size.width <= 0 ? 0.0 : 0.5 / size.width;
  return _aboutCentre(
    size,
    Matrix4.identity()
      ..setEntry(3, 2, depth)
      ..scaleByDouble(scale, scale, 1, 1)
      ..rotateY(angle),
  );
}

/// Shows [child], and when it is replaced by one with a different key, plays
/// [transition] from the one to the other over [duration].
///
/// [transition] and [duration] are read when a change starts, so editing them
/// never touches a change already playing and never plays one by itself.
///
/// A change arriving while one is playing cuts the playing one short: the
/// wallpaper that was arriving becomes the one that leaves. Wallpapers change
/// minutes apart; a second change mid-flight is an edit in Settings, and the
/// edit is what the user is watching.
class WallpaperSwitcher extends StatefulWidget {
  const WallpaperSwitcher({
    super.key,
    required this.child,
    this.transition = WallpaperTransition.fallback,
    this.duration = const Duration(milliseconds: 1500),
    this.random,
  });

  /// The wallpaper. Keyed: a change is a child with a different key.
  final Widget child;

  final WallpaperTransition transition;
  final Duration duration;

  /// The source of `random`'s picks and of each change's edge and seed.
  /// Injectable for tests.
  final math.Random? random;

  @override
  State<WallpaperSwitcher> createState() => _WallpaperSwitcherState();
}

class _WallpaperSwitcherState extends State<WallpaperSwitcher>
    with SingleTickerProviderStateMixin {
  late Widget _current = widget.child;
  Widget? _previous;
  WallpaperTransitionPlan? _plan;

  /// The last effect played, so `random` never plays the same one twice.
  WallpaperTransition? _lastEffect;

  /// Created on the first change rather than up front: a desktop that never
  /// rotates never needs one.
  AnimationController? _controller;

  late final math.Random _random = widget.random ?? math.Random();

  @override
  void didUpdateWidget(WallpaperSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Widget.canUpdate(_current, widget.child)) {
      _current = widget.child;
      return;
    }
    _change(widget.child);
  }

  void _change(Widget next) {
    final transition = widget.transition;
    if (!transition.animates || widget.duration <= Duration.zero) {
      _controller?.stop();
      _previous = null;
      _plan = null;
      _current = next;
      return;
    }
    final plan = WallpaperTransitionPlan.choose(
      transition,
      _random,
      previous: _lastEffect,
    );
    _lastEffect = plan.effect;
    _previous = _current;
    _current = next;
    _plan = plan;
    final controller = _controller ??= AnimationController(vsync: this)
      ..addStatusListener(_onStatus);
    controller
      ..duration = widget.duration
      ..forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _previous = null;
      _plan = null;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The same subtree at rest as mid-change — one `LayoutBuilder`, one
    // `AnimatedBuilder`, one `Stack` with a keyed slot per wallpaper — so the
    // wallpaper that is staying is never remounted when a change starts or
    // ends: the `Stack` re-parents it through its key, and nothing above it
    // changes type. At rest the builder listens to an animation that never
    // ticks.
    final Animation<double> animation =
        _controller ?? kAlwaysCompleteAnimation;
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final previous = _previous;
          final plan = _plan;
          final frame = previous == null || plan == null
              ? WallpaperFrame.done
              : wallpaperFrame(plan, animation.value, constraints.biggest);
          return _frame(frame, previous);
        },
      ),
    );
  }

  Widget _frame(WallpaperFrame frame, Widget? previous) {
    return Stack(
      fit: StackFit.expand,
      // Not the directional default, which needs a `Directionality` above:
      // every child is expanded, so the alignment never places anything.
      alignment: Alignment.topLeft,
      children: [
        if (frame.backdrop)
          const IgnorePointer(
            key: ValueKey('__wallpaper_backdrop__'),
            child: ColoredBox(color: kWallpaperBackdrop),
          ),
        if (previous != null)
          _LayerView(
            key: _slotKey(previous),
            layer: frame.outgoing,
            child: previous,
          ),
        _LayerView(
          key: _slotKey(_current),
          layer: frame.incoming,
          child: _current,
        ),
      ],
    );
  }

  static Key _slotKey(Widget child) => _SlotKey(child.key);
}

/// A slot keyed by the wallpaper it holds.
class _SlotKey extends LocalKey {
  const _SlotKey(this.inner);
  final Key? inner;

  @override
  bool operator ==(Object other) => other is _SlotKey && other.inner == inner;

  @override
  int get hashCode => Object.hash(_SlotKey, inner);
}

class _LayerView extends StatelessWidget {
  const _LayerView({super.key, required this.layer, required this.child});

  final WallpaperLayer layer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clip = layer.clip;
    return Opacity(
      opacity: layer.opacity.clamp(0.0, 1.0),
      child: Transform(
        transform: layer.transform ?? Matrix4.identity(),
        child: ClipPath(
          clipper: clip == null ? null : _PathClipper(clip),
          clipBehavior: clip == null ? Clip.none : Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class _PathClipper extends CustomClipper<Path> {
  const _PathClipper(this.path);
  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PathClipper oldClipper) => oldClipper.path != path;
}
