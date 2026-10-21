/// Everything a bar paints besides its colour: its material, its end caps, the
/// carve of its edges, the roots of an open popup — and the foliage hanging off
/// it.
///
/// Two layers, and which side of the modules each sits on is the design:
///
///  * [PanelSurfaceDecor] paints **under** the modules — wood, stone, bevel,
///    roots. Text and icons sit on the material the way a carved sign sits on
///    its board.
///  * [PanelFoliage] paints **over** everything — the leaves are in front of
///    the bar and in front of the windows below it. It reaches onto the bar
///    only as a fringe on the inner edge (`foliage.dart` keeps it to a third of
///    the bar), so a module is overhung, never hidden.
///
/// Both are hit-test transparent: a painter that answered hits would swallow
/// every click on the modules under or over it (the rule `panel_rim.dart`
/// learned the hard way).
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:moonswing/decor/foliage.dart';
import 'package:moonswing/decor/material_textures.dart';
import 'package:moonswing/decor/material_tiles.dart' show shade;
import 'package:moonswing/decor/seeded_random.dart';
import 'package:moonswing/panel_rim.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';

/// Maps the *bar frame* — x along the bar, y from its inner edge (0) into the
/// bar towards the screen edge ([Size] across) — onto a box of [size] for a bar
/// on [anchor].
///
/// The frame every bar-side painter draws in, so roots, caps and bevels are
/// written once for a horizontal bar and are right on all four edges.
Matrix4 barFrame(String anchor, Size size) {
  final m = Matrix4.identity();
  switch (anchor) {
    case 'bottom':
      break; // Inner edge on top, screen edge below: already the frame.
    case 'left':
      m.setEntry(0, 0, 0.0);
      m.setEntry(0, 1, -1.0);
      m.setEntry(0, 3, size.width);
      m.setEntry(1, 0, 1.0);
      m.setEntry(1, 1, 0.0);
    case 'right':
      m.setEntry(0, 0, 0.0);
      m.setEntry(0, 1, 1.0);
      m.setEntry(1, 0, 1.0);
      m.setEntry(1, 1, 0.0);
    default: // 'top': the inner edge is the bottom of the box.
      m.setEntry(1, 1, -1.0);
      m.setEntry(1, 3, size.height);
  }
  return m;
}

/// The bar's length and depth in the bar frame.
(double, double) barExtents(String anchor, Size size) =>
    anchor == 'left' || anchor == 'right'
        ? (size.height, size.width)
        : (size.width, size.height);

/// Whether roots grow off an open popup on [theme]'s bars.
bool themeGrowsRoots(ThemeConfig theme) =>
    theme.popupRoots > 0 && theme.popupGap <= 0;

/// Paints the bar's material, caps, bevel and roots, under its modules.
class PanelDecorPainter extends CustomPainter {
  PanelDecorPainter({
    required this.theme,
    required this.anchor,
    required this.radius,
    required this.devicePixelRatio,
    this.mouth,
    this.roots = 0.0,
    super.repaint,
  });

  final ThemeConfig theme;
  final String anchor;
  final BorderRadius radius;
  final double devicePixelRatio;

  /// The open popup's mouth on this bar, or null.
  final PanelRimBreak? mouth;

  /// How far the roots have grown, 0…1.
  final double roots;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.save();
    if (radius != BorderRadius.zero) {
      canvas.clipRRect(radius.toRRect(rect));
    } else {
      canvas.clipRect(rect);
    }
    canvas.transform(barFrame(anchor, size).storage);
    final (length, depth) = barExtents(anchor, size);
    final frame = Rect.fromLTWH(0, 0, length, depth);

    _paintBody(canvas, frame);
    _paintCaps(canvas, frame);
    _paintBevel(canvas, frame);
    final m = mouth;
    if (m != null && roots > 0 && themeGrowsRoots(theme)) {
      paintRoots(canvas, theme, m, depth, roots, devicePixelRatio);
    }
    canvas.restore();
  }

  void _paintBody(Canvas canvas, Rect frame) {
    if (!theme.panelTexture.paints && theme.panelImage.isEmpty) return;
    final source = resolveSurfaceImage(
      material: theme.panelTexture,
      tint: theme.panelTextureColor,
      devicePixelRatio: devicePixelRatio,
      path: theme.panelImage,
    );
    if (source == null) return;
    canvas.drawRect(
      frame,
      materialPaint(source.image,
          pixelScale: source.pixelScale,
          opacity: theme.panelTextureColor.a),
    );
  }

  void _paintCaps(Canvas canvas, Rect frame) {
    final length = theme.panelEndLength;
    if (!theme.panelEndTexture.paints || length <= 0) return;
    final cap = math.min(length, frame.width / 2);
    final source = resolveSurfaceImage(
      material: theme.panelEndTexture,
      tint: theme.panelEndColor,
      devicePixelRatio: devicePixelRatio,
    );
    if (source == null) return;
    final depth = frame.height;
    for (final end in [0, 1]) {
      // The cap's inner boundary is a stone edge, not a saw cut: a wander of
      // a few pixels, the same at both ends of the same bar.
      final edge = _capEdge(cap, depth, seed: end);
      final path = end == 0 ? edge : _mirror(edge, frame.width);
      // The cap casts a shadow onto the beam it sits over.
      canvas.save();
      canvas.clipPath(path, doAntiAlias: true);
      canvas.drawRect(
        frame,
        materialPaint(source.image,
            pixelScale: source.pixelScale,
            // Offset so the two ends are not the same stones mirrored.
            origin: Offset(end * 61.0, 0),
            opacity: theme.panelEndColor.a),
      );
      // Rounded off towards the bar's end, as a capstone is.
      final outer = end == 0 ? 0.0 : frame.width;
      canvas.drawRect(
        frame,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(outer, 0),
            Offset(end == 0 ? cap : frame.width - cap, 0),
            const [Color(0x40000000), Color(0x00000000), Color(0x14FFFFFF)],
            const [0.0, 0.6, 1.0],
          ),
      );
      canvas.restore();
      final seam = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xAA000000);
      canvas.drawPath(path, seam);
      // Its shadow on the wood, falling away from the cap.
      final from = end == 0 ? cap : frame.width - cap;
      final to = end == 0 ? cap + 7 : frame.width - cap - 7;
      canvas.save();
      canvas.clipPath(
          Path.combine(PathOperation.difference, Path()..addRect(frame), path));
      canvas.drawRect(
        Rect.fromLTRB(math.min(from, to) - 4, 0, math.max(from, to) + 4, depth),
        Paint()
          ..shader = ui.Gradient.linear(Offset(from, 0), Offset(to, 0),
              const [Color(0x55000000), Color(0x00000000)]),
      );
      canvas.restore();
    }
  }

  /// The left cap's outline in the bar frame: from the bar's end to a
  /// wandering edge about [cap] along.
  Path _capEdge(double cap, double depth, {required int seed}) {
    final rng = SeededRandom(mixSeed([0xCA9, seed]));
    final path = Path()..moveTo(-1, -1);
    path.lineTo(cap + rng.jitter(2.5), -1);
    const steps = 5;
    for (var i = 1; i <= steps; i++) {
      final y = depth * i / steps;
      final x = cap + rng.jitter(3.5);
      path.lineTo(x, y);
    }
    path
      ..lineTo(cap + rng.jitter(2), depth + 1)
      ..lineTo(-1, depth + 1)
      ..close();
    return path;
  }

  Path _mirror(Path path, double width) {
    final m = Matrix4.identity()
      ..setEntry(0, 0, -1.0)
      ..setEntry(0, 3, width);
    return path.transform(m.storage);
  }

  void _paintBevel(Canvas canvas, Rect frame) {
    final b = theme.panelBevel;
    if (b <= 0) return;
    final depth = frame.height;
    final band = math.max(2.0, depth * 0.32);
    // Which of the two long edges faces the light (the top of the screen, or
    // its left for a side bar) depends on the anchor, because the frame puts
    // the inner edge at y = 0 on every bar.
    final innerLit = anchor == 'bottom' || anchor == 'right';
    final lit = innerLit ? 0.0 : depth;
    final dark = innerLit ? depth : 0.0;
    double toward(double from, double by) => from == 0 ? by : depth - by;
    canvas.drawRect(
      frame,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, lit),
          Offset(0, toward(lit, band)),
          [Color.fromRGBO(255, 245, 225, 0.28 * b), const Color(0x00FFFFFF)],
        ),
    );
    canvas.drawRect(
      frame,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, dark),
          Offset(0, toward(dark, band * 1.2)),
          [Color.fromRGBO(0, 0, 0, 0.5 * b), const Color(0x00000000)],
        ),
    );
    // A crisp lit lip right on the edge, which is what reads as a carve.
    canvas.drawLine(
      Offset(0, toward(lit, 0.75)),
      Offset(frame.width, toward(lit, 0.75)),
      Paint()
        ..strokeWidth = 1
        ..color = Color.fromRGBO(255, 240, 210, 0.35 * b),
    );
  }

  @override
  bool shouldRepaint(PanelDecorPainter old) =>
      old.theme != theme ||
      old.anchor != anchor ||
      old.radius != radius ||
      old.devicePixelRatio != devicePixelRatio ||
      old.mouth != mouth ||
      old.roots != roots;

  // Never a hit: the modules above this answer their own pointer, and the bar
  // between them must stay as hit-transparent as a DecoratedBox is.
  @override
  bool? hitTest(Offset position) => false;
}

/// Roots spreading along a bar from both sides of an open popup's [mouth], in
/// the bar frame (y from the inner edge into a bar [depth] deep), grown to
/// [progress].
///
/// Three to a side — a buttress hugging the edge, a second climbing higher
/// into the bar, a rootlet off the first — plus the collar where the trunk
/// leaves the bar between them. Drawn in the theme's popup rim material, so
/// they are visibly the same wood as the card growing out of them.
void paintRoots(Canvas canvas, ThemeConfig theme, PanelRimBreak mouth,
    double depth, double progress, double devicePixelRatio) {
  final reach = theme.popupRoots * Curves.easeOutCubic.transform(progress);
  if (reach <= 0.5) return;
  final (start, end) = mouth;
  final source = resolveSurfaceImage(
    material: theme.popupBorderTexture,
    tint: theme.popupBorderTextureColor,
    devicePixelRatio: devicePixelRatio,
  );
  final fill = source == null
      ? (Paint()..color = theme.popupBorderTextureColor)
      : materialPaint(source.image, pixelScale: source.pixelScale * 2);
  final base = theme.popupBorderTextureColor;
  final rng = SeededRandom(mixSeed([start.round(), end.round(), 0x2007]));

  final shapes = <Path>[];
  // The collar: the trunk's foot, flaring into the bar across the mouth.
  final collarH = math.min(depth * 0.3, 9.0) * math.min(1.0, progress * 2);
  shapes.add(Path()
    ..moveTo(start - 2, -0.5)
    ..cubicTo(start + 2, collarH * 0.2, start + 4, collarH, start + 10, collarH)
    ..lineTo(end - 10, collarH)
    ..cubicTo(end - 4, collarH, end - 2, collarH * 0.2, end + 2, -0.5)
    ..close());

  for (final side in [-1.0, 1.0]) {
    final x0 = side < 0 ? start + 3 : end - 3;
    final specs = [
      // (length share, rise into the bar, base half-width)
      (1.0, depth * rng.range(0.2, 0.28), rng.range(5.5, 6.5)),
      (rng.range(0.6, 0.8), depth * rng.range(0.45, 0.58), rng.range(4.0, 4.8)),
      (rng.range(0.35, 0.5), depth * rng.range(0.05, 0.09), rng.range(3.0, 3.6)),
    ];
    for (final (share, rise, halfW) in specs) {
      shapes.add(_root(
        from: Offset(x0, 0),
        side: side,
        length: reach * share + 6,
        rise: rise,
        halfWidth: halfW * math.min(1.0, 0.4 + progress),
        rng: rng,
      ));
    }
  }

  // One outline for the foot and every root, so the bark runs on from the
  // trunk into its roots without a seam between them.
  final whole = shapes.reduce((a, b) => Path.combine(PathOperation.union, a, b));
  canvas.drawPath(
    whole.shift(const Offset(0.8, 1.0)),
    Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
  );
  canvas.drawPath(whole, fill);
  // Rounded: dark where it meets the bar's edge, lit along its far flank.
  final b = whole.getBounds();
  canvas.drawPath(
    whole,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, b.top),
        Offset(0, b.bottom),
        const [Color(0x55000000), Color(0x18000000), Color(0x40FFF0D8)],
        const [0.0, 0.5, 1.0],
      ),
  );
  canvas.drawPath(
    whole,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = shade(base, -0.3).withValues(alpha: 0.95),
  );
}

/// One tapering root from [from], running [side]ways along the bar for
/// [length] while climbing [rise] into it.
Path _root({
  required Offset from,
  required double side,
  required double length,
  required double rise,
  required double halfWidth,
  required SeededRandom rng,
}) {
  const steps = 16;
  final top = <Offset>[];
  final bottom = <Offset>[];
  final wobble = rng.range(0, 10);
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final x = from.dx + side * length * t;
    // Out of the mouth along the edge, lifting into the bar and settling.
    final y = rise * math.pow(math.sin(t * math.pi / 2), 0.8) * (1 - 0.25 * t) +
        math.sin(wobble + t * 7) * 0.8 * t;
    // Thick at the foot and thinning all the way out, the way a buttress
    // root runs into the ground.
    final hw = halfWidth * math.pow(1 - t, 1.1) + 0.4;
    top.add(Offset(x, y + hw));
    bottom.add(Offset(x, math.max(-0.5, y - hw)));
  }
  final path = Path()..moveTo(bottom.first.dx, bottom.first.dy);
  for (final p in bottom.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (final p in top.reversed) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}

/// The bar's under-module decor: material, caps, bevel and the roots of an
/// open popup, which grow in as the popup opens.
///
/// Builds **no painter at all** for a theme with none of it, and no ticker
/// until a theme with roots has a popup to grow them for: an idle bar on a
/// plain theme is the [child] and nothing else. The [child] is handed through
/// unrebuilt and behind a repaint boundary of its own, so a root growing
/// repaints this layer without rebuilding a single module, and a module
/// repainting re-records none of this.
class PanelSurfaceDecor extends StatefulWidget {
  const PanelSurfaceDecor({
    super.key,
    required this.theme,
    required this.anchor,
    required this.radius,
    required this.panel,
    required this.child,
  });

  final ThemeConfig theme;
  final String anchor;
  final BorderRadius radius;

  /// The panel's own `FlutterView`, which [PanelRimBreaks] is keyed on.
  final Object? panel;

  final Widget child;

  @override
  State<PanelSurfaceDecor> createState() => _PanelSurfaceDecorState();
}

class _PanelSurfaceDecorState extends State<PanelSurfaceDecor>
    with SingleTickerProviderStateMixin {
  AnimationController? _roots;
  PanelRimBreak? _mouth;

  /// What the painter repaints on: a picture landing, and the roots growing.
  /// Built once, not per build — a `Listenable.merge` minted in `build`
  /// re-subscribes every rebuild.
  late final Listenable _repaint;
  final ValueNotifier<int> _rootsTick = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge([MaterialTextures.instance, _rootsTick]);
    PanelRimBreaks.instance.addListener(_onBreak);
    // A popup already open when this bar was built (a theme switch rebuilds
    // it under one) has its roots at once, without the growth.
    if (themeGrowsRoots(widget.theme)) {
      _mouth = PanelRimBreaks.instance.of(widget.panel);
      if (_mouth != null) _rootsController().value = 1.0;
    }
  }

  AnimationController _rootsController() => _roots ??= AnimationController(
        vsync: this,
        // Paced to the card it grows from: the roots spread as the trunk rises.
        duration: widget.theme.popupInDuration * 1.6 + ShellDurations.popupIn,
        reverseDuration: widget.theme.popupOutDuration,
      )..addListener(() => _rootsTick.value++);

  @override
  void didUpdateWidget(PanelSurfaceDecor old) {
    super.didUpdateWidget(old);
    if (old.panel != widget.panel || old.theme != widget.theme) _onBreak();
  }

  @override
  void dispose() {
    PanelRimBreaks.instance.removeListener(_onBreak);
    _roots?.dispose();
    _rootsTick.dispose();
    super.dispose();
  }

  void _onBreak() {
    if (!themeGrowsRoots(widget.theme)) {
      if (_mouth != null || _roots != null) {
        _roots?.dispose();
        _roots = null;
        _mouth = null;
        if (mounted) setState(() {});
      }
      return;
    }
    final next = PanelRimBreaks.instance.of(widget.panel);
    if (next != null) {
      final ctrl = _rootsController();
      final moved = _mouth != null && _mouth != next;
      _mouth = next;
      if (moved) {
        ctrl.value = 0.55;
      }
      ctrl.forward();
      setState(() {});
    } else if (_mouth != null) {
      final ctrl = _roots;
      if (ctrl == null) {
        setState(() => _mouth = null);
        return;
      }
      ctrl.reverse().whenComplete(() {
        if (!mounted || PanelRimBreaks.instance.of(widget.panel) != null) {
          return;
        }
        // Nothing left to grow: the ticker goes with the roots.
        _roots?.dispose();
        _roots = null;
        setState(() => _mouth = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final grows = themeGrowsRoots(theme);
    final decor = theme.panelHasDecor;
    return CustomPaint(
      painter: decor || grows
          ? _LivePanelDecorPainter(
              state: this,
              theme: theme,
              anchor: widget.anchor,
              radius: widget.radius,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              repaint: _repaint,
            )
          : null,
      // The modules repaint on their own layer — a clock's second, a hover —
      // without re-recording the wood, stones and carve under them, which
      // repaint only when a tile lands or a root grows. Present on every
      // theme, so switching one never moves the modules to a new depth.
      child: RepaintBoundary(child: widget.child),
    );
  }
}

/// [PanelDecorPainter] reading the roots' progress at paint time rather than
/// build time, so a root growing repaints without a rebuild.
class _LivePanelDecorPainter extends PanelDecorPainter {
  _LivePanelDecorPainter({
    required this.state,
    required super.theme,
    required super.anchor,
    required super.radius,
    required super.devicePixelRatio,
    super.repaint,
  });

  final _PanelSurfaceDecorState state;

  @override
  PanelRimBreak? get mouth => state._mouth;

  @override
  double get roots => state._roots?.value ?? 0.0;

  @override
  bool shouldRepaint(PanelDecorPainter old) =>
      super.shouldRepaint(old) || old is! _LivePanelDecorPainter;
}

// ---------------------------------------------------------------------------
// Foliage
// ---------------------------------------------------------------------------

/// The leaves, over the bar and over the overhang below it, with a rustle when
/// the pointer arrives on the bar or a popup opens out of it.
///
/// The plan is grown when the bar's size, the theme, the anchor or the pixel
/// ratio changes, never per frame. Each plant is then **rasterized once** into
/// an image of its own, laid on the device-pixel grid where it rests, and every
/// frame after that — at rest or rustling — is a blit per plant. A plant's
/// vector picture is thousands of operations a canopy over (every leaf a
/// gradient, a clip, a blurred shadow and its veins), and the GTK embedder
/// rasters the whole surface again for any change anywhere on it — a clock
/// tick, a hover, a root growing — so replaying those pictures was the bar's
/// cost on every frame it drew, and sixty of them a second through a rustle.
/// The pictures stay only as the stand-in for the frame or two before the
/// images land: `toImage`, never `toImageSync` (see [MaterialTextures]).
///
/// There is no ticker at rest: a rustle creates one and disposes it when the
/// last leaf is still.
class PanelFoliage extends StatefulWidget {
  const PanelFoliage({
    super.key,
    required this.theme,
    required this.anchor,
    required this.thickness,
    required this.panel,
    this.rustle,
  });

  final ThemeConfig theme;
  final String anchor;

  /// The bar's own depth; the rest of the surface is overhang.
  final double thickness;

  /// The panel's own `FlutterView`: a popup opening out of it rustles the
  /// leaves around its mouth.
  final Object? panel;

  /// Fires when the pointer arrives on the bar.
  final Listenable? rustle;

  @override
  State<PanelFoliage> createState() => _PanelFoliageState();

  /// How many plants [state] draws from rasterized images, or null while it
  /// still draws their pictures.
  @visibleForTesting
  static int? debugRasterized(State<PanelFoliage> state) =>
      (state as _PanelFoliageState)._images?.length;
}

/// One plant rasterized where it rests: [rect] is in the surface's logical
/// pixels and lies on its device-pixel grid, so drawing [image] into it at rest
/// resamples nothing.
class _SprigImage {
  _SprigImage(this.image, this.rect);

  final ui.Image image;
  final Rect rect;

  late final Rect source =
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
}

class _PanelFoliageState extends State<PanelFoliage>
    with SingleTickerProviderStateMixin {
  FoliagePlan _plan = FoliagePlan.empty;
  List<ui.Picture> _pictures = const [];
  List<_SprigImage>? _images;
  Object? _planKey;

  /// Bumped with every plan, so images rasterized for one that has since been
  /// replaced are dropped when they land.
  int _generation = 0;

  AnimationController? _sway;

  /// Where along the bar the current rustle started, or null for everywhere.
  double? _epicentre;
  PanelRimBreak? _lastBreak;
  final ValueNotifier<int> _tick = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    widget.rustle?.addListener(_onPointer);
    PanelRimBreaks.instance.addListener(_onBreak);
  }

  @override
  void didUpdateWidget(PanelFoliage old) {
    super.didUpdateWidget(old);
    if (!identical(old.rustle, widget.rustle)) {
      old.rustle?.removeListener(_onPointer);
      widget.rustle?.addListener(_onPointer);
    }
  }

  @override
  void dispose() {
    widget.rustle?.removeListener(_onPointer);
    PanelRimBreaks.instance.removeListener(_onBreak);
    _sway?.dispose();
    _tick.dispose();
    _dropPlan();
    super.dispose();
  }

  void _dropPlan() {
    _generation++;
    for (final p in _pictures) {
      p.dispose();
    }
    _pictures = const [];
    for (final i in _images ?? const <_SprigImage>[]) {
      i.image.dispose();
    }
    _images = null;
  }

  void _onPointer() => _rustle(null, strength: 0.7);

  void _onBreak() {
    final b = PanelRimBreaks.instance.of(widget.panel);
    if (b != null && b != _lastBreak) _rustle((b.$1 + b.$2) / 2, strength: 1.0);
    _lastBreak = b;
  }

  double _strength = 1.0;

  void _rustle(double? at, {required double strength}) {
    if (!mounted || _plan.sprigs.isEmpty) return;
    final ctrl = _sway ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )
      ..addListener(() => _tick.value++)
      ..addStatusListener((s) {
        if (s != AnimationStatus.completed) return;
        // Still again: the ticker goes. After this notification rather than
        // inside it — a controller disposed from its own status callback is
        // still mid-dispatch.
        final done = _sway;
        _sway = null;
        _tick.value++;
        scheduleMicrotask(() => done?.dispose());
      });
    // A pass of the pointer over a bar already swaying does not restart it.
    if (ctrl.isAnimating && ctrl.value < 0.4 && at == null) return;
    _epicentre = at;
    _strength = strength;
    ctrl.forward(from: 0);
  }

  void _ensurePlan(Size surface, Matrix4 frame, double devicePixelRatio) {
    final theme = widget.theme;
    final vertical = widget.anchor == 'left' || widget.anchor == 'right';
    final length = vertical ? surface.height : surface.width;
    final reach = (vertical ? surface.width : surface.height) - widget.thickness;
    final key = (
      theme.panelFoliage,
      theme.foliageColor,
      theme.foliageBloom,
      theme.foliageDensity,
      theme.panelEndLength,
      widget.anchor,
      surface,
      widget.thickness,
      devicePixelRatio,
    );
    if (key == _planKey) return;
    _planKey = key;
    _dropPlan();
    _plan = growFoliage(
      style: theme.panelFoliage,
      length: length,
      thickness: widget.thickness,
      reach: reach,
      anchor: widget.anchor,
      leaf: theme.foliageColor,
      bloom: theme.foliageBloom,
      density: theme.foliageDensity,
      endCaps: theme.panelEndTexture.paints ? theme.panelEndLength : 0,
    );
    _pictures = [for (final s in _plan.sprigs) recordSprig(s)];
    if (_pictures.isNotEmpty) {
      _rasterize(_generation, frame, devicePixelRatio);
    }
  }

  /// Rasterizes every plant of the current plan onto the device-pixel grid of
  /// a surface mapped by [frame], and swaps the images in once all have landed
  /// — one repaint, not one per plant.
  Future<void> _rasterize(int generation, Matrix4 frame, double dpr) async {
    final plan = _plan;
    final pictures = _pictures;
    final pending = <Future<_SprigImage>>[];
    for (var i = 0; i < plan.sprigs.length; i++) {
      final s = plan.sprigs[i];
      // The plant's reach, plus the shadow every leaf casts: offset by under
      // two pixels and blurred by a sigma of 1.3, so six is ample.
      final canonical = s.bounds.inflate(6).shift(s.root);
      final r = MatrixUtils.transformRect(frame, canonical);
      final rect = Rect.fromLTRB(
        (r.left * dpr).floorToDouble() / dpr,
        (r.top * dpr).floorToDouble() / dpr,
        (r.right * dpr).ceilToDouble() / dpr,
        (r.bottom * dpr).ceilToDouble() / dpr,
      );
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..scale(dpr)
        ..translate(-rect.left, -rect.top)
        ..transform(frame.storage)
        ..translate(s.root.dx, s.root.dy)
        ..drawPicture(pictures[i]);
      final placed = recorder.endRecording();
      pending.add(placed
          .toImage(
            math.max(1, (rect.width * dpr).round()),
            math.max(1, (rect.height * dpr).round()),
          )
          .then((image) => _SprigImage(image, rect))
          .whenComplete(placed.dispose));
    }
    final List<_SprigImage> images;
    try {
      images = await Future.wait(pending);
    } catch (_) {
      // The pictures stay, which paint the same canopy at their old cost.
      return;
    }
    if (!mounted || generation != _generation) {
      for (final i in images) {
        i.image.dispose();
      }
      return;
    }
    _images = images;
    // Nothing paints the vector pictures again until the plan changes.
    for (final p in _pictures) {
      p.dispose();
    }
    _pictures = const [];
    _tick.value++;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.theme.panelReach <= 0 || !widget.theme.panelFoliage.grows) {
      return const SizedBox.shrink();
    }
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(builder: (context, constraints) {
          final size = constraints.biggest;
          if (size.isEmpty || !size.isFinite) return const SizedBox.shrink();
          final frame = foliageFrame(
            anchor: widget.anchor,
            surface: size,
            thickness: widget.thickness,
          );
          _ensurePlan(size, frame, dpr);
          return CustomPaint(
            size: size,
            isComplex: true,
            painter: _FoliagePainter(
              state: this,
              frame: frame,
              repaint: _tick,
            ),
          );
        }),
      ),
    );
  }
}

class _FoliagePainter extends CustomPainter {
  _FoliagePainter({required this.state, required this.frame, super.repaint});

  final _PanelFoliageState state;
  final Matrix4 frame;

  @override
  void paint(Canvas canvas, Size size) {
    final plan = state._plan;
    if (plan.sprigs.isEmpty) return;
    final images = state._images;
    final pictures = state._pictures;
    final sway = state._sway;
    final t = sway == null ? 1.0 : sway.value;
    // Seconds into the rustle, and how much of it is left: a quick shiver that
    // dies away, each plant at its own pace.
    final seconds = t * 2.4;
    final decay = math.exp(-seconds * 1.7) * (1 - t);
    final swaying = sway != null && decay > 0.001;
    // A rotation in the canonical frame turns the other way on the surface
    // wherever the frame reflects.
    final m = frame.storage;
    final handed = m[0] * m[5] - m[4] * m[1] < 0 ? -1.0 : 1.0;
    final blit = Paint()..filterQuality = FilterQuality.low;
    for (var i = 0; i < plan.sprigs.length; i++) {
      final s = plan.sprigs[i];
      var angle = 0.0;
      if (swaying) {
        final at = state._epicentre;
        final near = at == null ? 1.0 : math.exp(-(s.root.dx - at).abs() / 160);
        final omega = 7.5 + (s.phase % 1.0) * 3;
        angle = s.kind.sway *
            state._strength *
            near *
            decay *
            math.sin(omega * seconds + s.phase);
      }
      if (images != null) {
        final image = images[i];
        if (angle == 0) {
          canvas.drawImageRect(image.image, image.source, image.rect, blit);
          continue;
        }
        final root = MatrixUtils.transformPoint(frame, s.root);
        canvas
          ..save()
          ..translate(root.dx, root.dy)
          ..rotate(angle * handed)
          ..translate(-root.dx, -root.dy)
          ..drawImageRect(image.image, image.source, image.rect, blit)
          ..restore();
        continue;
      }
      // Before the images land: the plant's own picture, about its root.
      canvas
        ..save()
        ..transform(frame.storage)
        ..translate(s.root.dx, s.root.dy)
        ..rotate(angle)
        ..drawPicture(pictures[i])
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_FoliagePainter old) => old.frame != frame;

  @override
  bool? hitTest(Offset position) => false;
}
