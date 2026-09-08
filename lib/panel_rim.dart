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

import 'package:flutter/widgets.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/panel_background.dart';

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
/// Only a bar that carries a rim *and* attaches its popups has a seam to
/// remove, and only that case takes the painter — so every other theme keeps
/// byte-for-byte the decoration, the layers and the paint it always had.
bool panelPaintsOwnRim(ThemeConfig theme) =>
    theme.panelBorderWidth > 0 && theme.popupGap <= 0;

/// The bar's rim, with the stretch an attached popup's mouth covers left out.
///
/// It draws exactly what `Border.all` would — the same deflated outline stroked
/// at the same width, so a bar with no popup open is pixel-identical to one
/// whose rim is still in its `BoxDecoration` — and then clips that one band away
/// with [ClipOp.difference]. Clipping rather than drawing the line in two
/// segments is what keeps [radius] free: the corner arcs are part of the same
/// stroked outline and are never near the break, which is bounded by the
/// module's own popup.
class PanelRimPainter extends CustomPainter {
  const PanelRimPainter({
    required this.color,
    required this.width,
    required this.radius,
    required this.anchor,
    this.gap,
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
    final rect = Offset.zero & size;
    final cut = breakRect(size);
    canvas.save();
    if (cut != null) canvas.clipRect(cut, clipOp: ClipOp.difference);
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
      old.gap != gap;
}

/// The rim layer a panel stacks over its background, or null when the theme
/// does not want one painted separately.
///
/// Listens to [PanelRimBreaks] rather than having the panel do it, so a popup
/// opening repaints one `CustomPaint` instead of rebuilding a bar full of
/// modules.
Widget? panelRimLayer({
  required ThemeConfig theme,
  required String anchor,
  required Object? panel,
}) {
  if (!panelPaintsOwnRim(theme)) return null;
  final radius = panelCornerRadius(anchor: anchor, theme: theme);
  return ListenableBuilder(
    listenable: PanelRimBreaks.instance,
    builder: (context, _) => CustomPaint(
      painter: PanelRimPainter(
        color: theme.panelBorder,
        width: theme.panelBorderWidth,
        radius: radius,
        anchor: anchor,
        gap: PanelRimBreaks.instance.of(panel),
      ),
    ),
  );
}
