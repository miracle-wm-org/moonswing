/// The stretch of a panel's inner rim that an attached popup's mouth covers,
/// and the painter that leaves it out.
///
/// A bar popup is placed on the *far* side of the panel's inner edge — the
/// compositor never puts it over the bar, which is what makes an attached card
/// read as growing out of one — so a rimmed bar draws its own hairline straight
/// across the mouth of every menu it opens, and **nothing the card paints can
/// reach that line**. Two attempts to make it reach are recorded elsewhere for
/// the next person who has the idea: a *collar* on the card's shape asking the
/// compositor for a negative `WindowPositioner.offset` (`popup_surface.dart`),
/// and an inset on the anchor rect (`popup.dart`). Both are the wrong end of
/// the problem. The line belongs to the panel's surface, so the panel is what
/// has to leave it off — but only across the mouth, because on a flush bar the
/// inner edge is the only side of the rim anybody can see and dropping it
/// outright takes the bar's one visible edge with it.
///
/// The two surfaces are separate FlutterViews but one isolate, so this is a
/// plain store: the popup publishes the range its mouth covers and the panel
/// paints around it, the way `OsdStore` and `PopupCoordinator` already carry
/// state between views.
library;

import 'dart:math' as math;
// ClipOp is not among the dart:ui symbols `package:flutter/painting.dart`
// re-exports, unlike Canvas, Paint and PaintingStyle beside it.
import 'dart:ui' show ClipOp;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/panel_background.dart';
import 'package:moonswing/panel_join.dart';

/// The stretch of a panel's main axis an attached popup's mouth covers, in the
/// panel's own logical coordinates.
///
/// A record rather than a class so the store can compare two of them for
/// equality without spelling one out; Dart records have value equality.
typedef PanelRimBreak = (double start, double end);

/// Where each panel's inner rim is currently interrupted.
///
/// Keyed on the panel's own `FlutterView`, which is the object both ends resolve
/// to: the panel's tree is in it, and `PopupHost.openPopup` runs from a module's
/// context inside that same tree. `View.maybeOf` rather than the `WindowScope`
/// the popup is parented through, because the view is public API and is present
/// in any tree a panel can be pumped in. One entry per panel, because a panel
/// hosts at most one open bar popup — `PopupCoordinator` guarantees that much,
/// and a second one would be a menu nested inside the first, which is attached
/// to nothing.
///
/// The singleton `ChangeNotifier` shape of `OsdStore`/`TrayStore`, with their
/// rule about not notifying for a value that did not move: every panel on every
/// monitor listens to this, and a popup that resizes while open (the sound
/// slider swaps its label on every drag) would otherwise re-lay every bar in
/// the shell.
class PanelRimBreaks extends ChangeNotifier {
  PanelRimBreaks._();

  static final PanelRimBreaks instance = PanelRimBreaks._();

  final Map<Object, PanelRimBreak> _breaks = <Object, PanelRimBreak>{};

  /// The break on [panel]'s inner rim, or null while nothing is attached to it.
  PanelRimBreak? of(Object? panel) => panel == null ? null : _breaks[panel];

  /// Records that [panel] has an attached popup whose mouth covers [range].
  void set(Object panel, PanelRimBreak range) {
    if (_breaks[panel] == range) return;
    _breaks[panel] = range;
    notifyListeners();
  }

  /// Forgets [panel]'s break, if it had one.
  ///
  /// Called synchronously from `PopupHost.closePopup` rather than at the end of
  /// the exit animation, and the ordering is the reason: several call sites
  /// close one popup and open another in the same gesture (the dock's tooltip
  /// giving way to its menu), so a deferred clear would land *after* the new
  /// popup had published its own range and take it away again.
  void clear(Object panel) {
    if (_breaks.remove(panel) != null) notifyListeners();
  }

  @visibleForTesting
  void clearAll() {
    if (_breaks.isEmpty) return;
    _breaks.clear();
    notifyListeners();
  }
}

/// The stretch of the panel's main axis an attached popup's mouth covers.
///
/// Everything here is in the panel's own logical coordinates, along the axis the
/// bar runs in: [anchorCentre] is the centre of the anchor rect (which is the
/// module's own extent — see `barAnchorRect`), [windowExtent] is the popup
/// window's size along that axis, [leadingInset] is the popup's surface margin
/// on the near side, and [cardExtent] is the card inside it.
///
/// Two things it has to get right.
///
/// **The mouth is the card plus its flare**, not the card alone:
/// `popup_attach_radius` bows the card outward exactly where it meets the bar,
/// so that is the width the join actually occupies. Breaking only the card's
/// width would leave two short stubs of the bar's rim under the ears — and the
/// ears' own outline is tangent to the join at its tips, so what continues the
/// line there is the card's rim, which is the whole point of the flare.
///
/// **The window is clamped the way the compositor clamps it.** A bar popup is
/// centred on its module and slid back onto the output when that would hang it
/// over an edge (`kPopupSlide`), which is the common case for the modules at
/// either end of a bar. The break has to move with it or it opens under empty
/// bar. This is a prediction rather than a report — nothing tells the shell
/// where the compositor actually put the window — so it replicates
/// `xdg_positioner`'s own slide: shift the window back onto the output, no
/// further than its own start.
PanelRimBreak attachedMouthRange({
  required double anchorCentre,
  required double windowExtent,
  required double leadingInset,
  required double cardExtent,
  required double flare,
  required double panelExtent,
}) {
  final slack = math.max(0.0, panelExtent - windowExtent);
  final windowStart =
      (anchorCentre - windowExtent / 2).clamp(0.0, slack).toDouble();
  final start = windowStart + leadingInset - flare;
  return (start, start + cardExtent + 2 * flare);
}

/// Whether [theme] wants its bar's rim painted by [PanelRimPainter] rather than
/// by the `Border` in `panelBackgroundDecoration`.
///
/// Only a bar that carries a rim *and* has something to leave out of it takes
/// the painter: one that attaches its popups, one that meets another bar under
/// the theme ([joins], filtered by [activePanelJoins] here), where the rim
/// between the two is left out ([panelJoinSeams]), or one lying flush against
/// a screen edge, which draws no rim along it ([panelFlushEdges]). A rimmed bar
/// floating clear of every edge, with its menus floating clear of it, keeps
/// byte-for-byte the decoration, the layers and the paint it always had.
bool panelPaintsOwnRim(
  ThemeConfig theme, {
  String anchor = 'top',
  PanelJoins joins = PanelJoins.none,
}) =>
    theme.panelBorderWidth > 0 &&
    (theme.popupGap <= 0 ||
        !activePanelJoins(theme, joins, anchor: anchor).isEmpty ||
        panelFlushEdges(anchor: anchor, theme: theme, joins: joins)
            .isNotEmpty);

/// The bands of a bar's rim to leave out where it meets another bar, for a bar
/// of [size] anchored to [anchor] with a rim [width] wide, meeting [joins]
/// (already filtered by the theme — [activePanelJoins]).
///
/// Joined bars have one outline between them, not two lines butted together.
/// At a corner one bar runs across it and the other stops against its inner
/// edge ([panelCrossesCorners]), and each leaves out its half of the seam:
///
/// - the bar that **stops** leaves out the rim across its end, but not the
///   long sides' lines, which run on to the end of its box and meet the other
///   bar's rim there;
/// - the bar that **runs across** leaves out its inner rim where the other's
///   end lies against it — the other bar's depth, which starts at this bar's
///   end because their margins off that side are one — less a rim's width at
///   either side, so its own end line still turns the outer corner and its
///   inner line still meets the other bar's inner one.
///
/// Every band is exactly the rim's own thickness deep, so the clip takes the
/// line and none of the fill under it.
List<Rect> panelJoinSeams({
  required String anchor,
  required Size size,
  required double width,
  required PanelJoins joins,
}) {
  if (width <= 0 || joins.isEmpty) return const [];
  final vertical = isVerticalAnchor(anchor);
  final length = vertical ? size.height : size.width;
  final depth = vertical ? size.width : size.height;
  // Bands in the bar's own (along, across) coordinates, turned onto the box.
  Rect band(double a0, double a1, double c0, double c1) => vertical
      ? Rect.fromLTRB(c0, a0, c1, a1)
      : Rect.fromLTRB(a0, c0, a1, c1);
  final edge = screenEdgeOf(anchor);
  // The inner rim's band across the depth: the side facing the screen's middle.
  final (innerFrom, innerTo) = switch (edge) {
    'bottom' || 'right' => (0.0, width),
    _ => (depth - width, depth),
  };
  final crosses = panelCrossesCorners(anchor);
  final seams = <Rect>[];
  for (final (start, neighbour) in [(true, joins.start), (false, joins.end)]) {
    if (neighbour <= 0) continue;
    if (!crosses) {
      final (a0, a1) = start ? (0.0, width) : (length - width, length);
      if (depth > 2 * width) seams.add(band(a0, a1, width, depth - width));
      continue;
    }
    final reach = math.min(neighbour, length / 2);
    if (reach <= 2 * width) continue;
    final (a0, a1) = start
        ? (width, reach - width)
        : (length - reach + width, length - width);
    seams.add(band(a0, a1, innerFrom, innerTo));
  }
  return seams;
}

/// The bar's rim, with the stretch an attached popup's mouth covers left out,
/// and no line at all along a side flush against the screen.
///
/// It draws exactly what `Border.all` would — the same deflated outline stroked
/// at the same width, so a bar with no popup open is pixel-identical to one
/// whose rim is still in its `BoxDecoration` — and then clips that one band away
/// with [ClipOp.difference]. Clipping rather than drawing the line in two
/// segments is what keeps [radius] free: the corner arcs are part of the same
/// stroked outline and are never near the break, which is bounded by the
/// module's own popup.
///
/// A [flush] side is not clipped away but pushed out of the box: the outline is
/// stroked a rim's width past that edge, so the line lies outside the bar and
/// the two sides that meet it run on to the screen's edge. Clipping a band
/// there instead would also take the last rim's width of those two lines and
/// leave a notch of fill showing at the screen edge beside each.
class PanelRimPainter extends CustomPainter {
  const PanelRimPainter({
    required this.color,
    required this.width,
    required this.radius,
    required this.anchor,
    this.gap,
    this.joins = PanelJoins.none,
    this.flush = const <String>{},
  });

  /// [ThemeConfig.panelBorder].
  final Color color;

  /// [ThemeConfig.panelBorderWidth]. Nothing is drawn at or below 0.
  final double width;

  /// The bar's corner rounding, from `panelCornerRadius`.
  final BorderRadius radius;

  /// The screen edge the bar is anchored to, which decides which of its four
  /// sides is the inner one.
  final String anchor;

  /// The stretch of the inner edge to leave unpainted, or null for none.
  final PanelRimBreak? gap;

  /// The bars this one meets as the theme draws them ([activePanelJoins]),
  /// whose seams are left unpainted ([panelJoinSeams]).
  final PanelJoins joins;

  /// The screen edges the bar lies flush against ([panelFlushEdges]), along
  /// which no rim is drawn.
  final Set<String> flush;

  /// The outline the rim is stroked along, before `Border.all`'s deflation:
  /// the bar's box, pushed out by the rim's width past each [flush] edge so the
  /// line there falls outside it.
  Rect outlineRect(Size size) {
    double out(String edge) => flush.contains(edge) ? width : 0;
    return Rect.fromLTRB(
      -out('left'),
      -out('top'),
      size.width + out('right'),
      size.height + out('bottom'),
    );
  }

  /// The band of [size] the break occupies: the inner edge's rim, over the
  /// range the mouth covers.
  ///
  /// Exactly the rim's own thickness, so the clip takes the line and nothing
  /// else — a taller band would eat into the bar's fill, which is drawn by the
  /// decoration underneath and would show the desktop through.
  Rect? breakRect(Size size) {
    final range = gap;
    if (range == null || width <= 0) return null;
    final (start, end) = range;
    if (!(end > start)) return null;
    return switch (anchor) {
      'bottom' => Rect.fromLTRB(start, 0, end, width),
      'left' => Rect.fromLTRB(size.width - width, start, size.width, end),
      'right' => Rect.fromLTRB(0, start, width, end),
      _ => Rect.fromLTRB(start, size.height - width, end, size.height),
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (width <= 0) return;
    final rect = outlineRect(size);
    final cut = breakRect(size);
    canvas.save();
    // The line pushed past a flush edge must not land on whatever the surface
    // holds beyond the bar: the overhang a theme's foliage or fillet grows.
    if (flush.isNotEmpty) canvas.clipRect(Offset.zero & size);
    if (cut != null) canvas.clipRect(cut, clipOp: ClipOp.difference);
    for (final seam in panelJoinSeams(
      anchor: anchor,
      size: size,
      width: width,
      joins: joins,
    )) {
      canvas.clipRect(seam, clipOp: ClipOp.difference);
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    // `Border.all` strokes the outline deflated by half its width, so the band
    // lands inside the box; both of Flutter's uniform-border paths do exactly
    // this and this has to match them or switching a theme's `popup_gap` off
    // would visibly move the bar's rim.
    if (radius == BorderRadius.zero) {
      canvas.drawRect(rect.deflate(width / 2), paint);
    } else {
      canvas.drawRRect(radius.toRRect(rect).deflate(width / 2), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PanelRimPainter old) =>
      old.color != color ||
      old.width != width ||
      old.radius != radius ||
      old.anchor != anchor ||
      old.gap != gap ||
      old.joins != joins ||
      !setEquals(old.flush, flush);
}

/// [content] with the bar's rim painted over it, or [content] unchanged when
/// the theme's rim is still the decoration's.
///
/// **A [CustomPaint] foreground painter, never a layer stacked over the bar.**
/// A background `painter:` is *opaque to hits by default* — the documented
/// default of [CustomPainter.hitTest] is that every point is a hit for a
/// background painter and no point is for a foreground one, and
/// `RenderCustomPaint.hitTestSelf` spells it `hitTest(position) ?? true`. A
/// rim stacked over the bar therefore swallowed every click on every module in
/// it, which is what a full-width painter laid over a panel does. Painting it
/// as this content's foreground puts the line over the modules — where it
/// belongs, since a module laid out flush to the bar's edge would otherwise
/// paint across it — and leaves the pointer alone.
///
/// Listens to [PanelRimBreaks] here rather than having the panel do it, and
/// hands [content] through unrebuilt, so a popup opening repaints the rim
/// instead of rebuilding a bar full of modules.
Widget panelWithRim({
  required ThemeConfig theme,
  required String anchor,
  required Object? panel,
  required Widget content,
  PanelJoins joins = PanelJoins.none,
}) {
  if (!panelPaintsOwnRim(theme, anchor: anchor, joins: joins)) return content;
  final radius = panelCornerRadius(anchor: anchor, theme: theme, joins: joins);
  final seams = activePanelJoins(theme, joins, anchor: anchor);
  final flush = panelFlushEdges(anchor: anchor, theme: theme, joins: joins);
  return ListenableBuilder(
    listenable: PanelRimBreaks.instance,
    builder: (context, child) => CustomPaint(
      foregroundPainter: PanelRimPainter(
        color: theme.panelBorder,
        width: theme.panelBorderWidth,
        radius: radius,
        anchor: anchor,
        // Only a theme that attaches its popups has a mouth to break; one
        // here for its joins alone would otherwise open a gap no menu covers.
        gap: theme.popupGap <= 0
            ? _rimGap(theme, PanelRimBreaks.instance.of(panel))
            : null,
        joins: seams,
        flush: flush,
      ),
      child: child,
    ),
    child: content,
  );
}

/// The stretch of rim to leave out for [mouth]: the mouth itself, and on a
/// theme that grows roots off its popups (`popup_roots`), the roots either side
/// of it too — a root breaks *through* the bar's rim rather than being crossed
/// by it. The roots are `lib/decor/panel_decor.dart`'s.
PanelRimBreak? _rimGap(ThemeConfig theme, PanelRimBreak? mouth) {
  if (mouth == null) return null;
  if (theme.popupRoots <= 0 || theme.popupGap > 0) return mouth;
  return (mouth.$1 - theme.popupRoots, mouth.$2 + theme.popupRoots);
}

/// A bar's modules, inside whatever the theme wraps them in, kept mounted
/// across a theme switch.
///
/// The theme decides how many widgets stand between the bar's decoration and
/// its modules: a [ClipRRect] only while `panel_radius` is non-zero (so a square
/// bar adds no clip layer), and [panelWithRim]'s painter only for a rimmed bar
/// that attaches its popups. Either one coming or going moves [content] to a
/// different depth, and an unkeyed subtree that moves is *rebuilt*, not moved —
/// every module in the bar was disposed and created again. That is not just
/// lost state: a module's `dispose` closes what it has open, and the clock
/// hosts the settings overlay, so picking Dracula over Glassy (12 → 0) in a
/// settings panel opened from the clock took the panel down under the pointer.
///
/// [GlobalKey] on [content] is what makes it a move: the framework reparents a
/// globally-keyed subtree to wherever its key turns up in the same frame, state
/// and render objects included. The wrappers stay conditional, so every theme
/// keeps exactly the layers it had.
class PanelContentFrame extends StatefulWidget {
  const PanelContentFrame({
    super.key,
    required this.theme,
    required this.anchor,
    required this.panel,
    required this.content,
    this.joins = PanelJoins.none,
  });

  final ThemeConfig theme;
  final String anchor;

  /// The bars this one meets, whose corners [panelCornerRadius] squares.
  final PanelJoins joins;

  /// The panel's own `FlutterView`, which [PanelRimBreaks] is keyed on.
  final Object? panel;

  /// The modules.
  final Widget content;

  @override
  State<PanelContentFrame> createState() => _PanelContentFrameState();
}

class _PanelContentFrameState extends State<PanelContentFrame> {
  final GlobalKey _content = GlobalKey(debugLabel: 'panel content');

  @override
  Widget build(BuildContext context) {
    final radius = panelCornerRadius(
      anchor: widget.anchor,
      theme: widget.theme,
      joins: widget.joins,
    );
    final Widget content = KeyedSubtree(key: _content, child: widget.content);
    return panelWithRim(
      theme: widget.theme,
      anchor: widget.anchor,
      panel: widget.panel,
      joins: widget.joins,
      content: radius == BorderRadius.zero
          ? content
          : ClipRRect(borderRadius: radius, child: content),
    );
  }
}
