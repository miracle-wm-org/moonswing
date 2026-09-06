// Pure geometry for the display arrangement diagram (`_DisplayDiagram` in
// `display.dart`).
//
// Everything here is a function of its arguments: no BuildContext, no Wayland
// objects, no disk — so `test/display_layout_test.dart` can point at it, where
// the drag interaction in `display.dart` is hard to test. Same discipline as
// `lib/desktop/desktop_layout.dart`.
//
// All coordinates here are *logical* (compositor) pixels — what
// wlr-output-management's `position` event reports and what `set_position`
// takes. Mode pixels are converted once, by [logicalSizeOf].

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// One display in logical coordinate space, keyed by its head id.
typedef DisplayBox = ({int id, int x, int y, int w, int h});

/// Viewport mapping: logical coordinates -> diagram pixels. [origin] already
/// folds in the bounding-box offset and the centring slack, so a box is drawn
/// at `box.x * scale + origin.dx`.
typedef DiagramFit = ({double scale, Offset origin});

/// Minimum shared extent, in logical pixels, along the edge two displays meet
/// on. Two displays that met at a corner only would leave each unreachable
/// from the other, so a snap never produces less than this.
const int kMinEdgeOverlap = 64;

/// The logical size a head occupies, given its mode, output scale and
/// `wl_output` transform.
///
/// Positions are logical, so a 2x HiDPI head occupies half its mode; and
/// transforms 1/3/5/7 are the 90/270-degree cases, which swap width and height.
Size logicalSizeOf(int modeW, int modeH, double outputScale, int transform) {
  final s = (outputScale.isFinite && outputScale > 0) ? outputScale : 1.0;
  final w = modeW / s;
  final h = modeH / s;
  final rotated = transform == 1 || transform == 3 || transform == 5 || transform == 7;
  return rotated ? Size(h, w) : Size(w, h);
}

/// Fits [boxes] into [viewport], centred on both axes.
///
/// The scale is capped at [maxScale] so a single small output is not blown up
/// to fill the strip. Callers freeze the result for the duration of a drag —
/// recomputing it per pointer move is what made the view zoom continuously.
DiagramFit fitBoxes(
  List<DisplayBox> boxes,
  Size viewport, {
  double padding = 16,
  double maxScale = 0.12,
}) {
  if (boxes.isEmpty) {
    return (
      scale: maxScale,
      origin: Offset(viewport.width / 2, viewport.height / 2),
    );
  }

  var minX = boxes.first.x;
  var minY = boxes.first.y;
  var maxX = boxes.first.x + boxes.first.w;
  var maxY = boxes.first.y + boxes.first.h;
  for (final b in boxes.skip(1)) {
    minX = math.min(minX, b.x);
    minY = math.min(minY, b.y);
    maxX = math.max(maxX, b.x + b.w);
    maxY = math.max(maxY, b.y + b.h);
  }

  final totalW = math.max(1, maxX - minX).toDouble();
  final totalH = math.max(1, maxY - minY).toDouble();
  final availW = math.max(1.0, viewport.width - padding * 2);
  final availH = math.max(1.0, viewport.height - padding * 2);

  var scale = math.min(availW / totalW, availH / totalH);
  if (!scale.isFinite || scale <= 0) scale = maxScale;
  scale = math.min(scale, maxScale);

  final dx = (viewport.width - totalW * scale) / 2 - minX * scale;
  final dy = (viewport.height - totalH * scale) / 2 - minY * scale;
  return (scale: scale, origin: Offset(dx, dy));
}

/// Where [box] lands on the diagram under [fit].
Rect diagramRect(DisplayBox box, DiagramFit fit) => Rect.fromLTWH(
      box.x * fit.scale + fit.origin.dx,
      box.y * fit.scale + fit.origin.dy,
      box.w * fit.scale,
      box.h * fit.scale,
    );

/// Resolves a free-dragged position to one that abuts a neighbour.
///
/// Four candidate placements are generated per box in [others] — one per edge —
/// each with the perpendicular axis clamped so the two share at least
/// [kMinEdgeOverlap], or the whole of the shorter side when that is less.
/// Candidates that would overlap *area* are dropped; touching edges are not an
/// overlap. The winner is the candidate nearest the requested position, so the
/// rect follows the cursor between snaps.
///
/// With no [others] the requested position is returned unchanged.
({int x, int y}) snapPosition({
  required DisplayBox moving,
  required List<DisplayBox> others,
  required int desiredX,
  required int desiredY,
}) {
  if (others.isEmpty) return (x: desiredX, y: desiredY);

  ({int x, int y})? best;
  var bestScore = double.infinity;
  ({int x, int y})? bestClear;
  var bestClearScore = double.infinity;

  void consider(int x, int y) {
    final dx = (x - desiredX).toDouble();
    final dy = (y - desiredY).toDouble();
    final score = dx * dx + dy * dy;
    if (score < bestScore) {
      bestScore = score;
      best = (x: x, y: y);
    }
    if (score < bestClearScore) {
      final candidate = (id: moving.id, x: x, y: y, w: moving.w, h: moving.h);
      for (final o in others) {
        if (_overlapsArea(candidate, o)) return;
      }
      bestClearScore = score;
      bestClear = (x: x, y: y);
    }
  }

  for (final o in others) {
    final overlapY = math.min(kMinEdgeOverlap, math.min(moving.h, o.h));
    final overlapX = math.min(kMinEdgeOverlap, math.min(moving.w, o.w));
    final y = _clampTolerant(desiredY, o.y - moving.h + overlapY, o.y + o.h - overlapY);
    final x = _clampTolerant(desiredX, o.x - moving.w + overlapX, o.x + o.w - overlapX);

    consider(o.x + o.w, y); // right of o
    consider(o.x - moving.w, y); // left of o
    consider(x, o.y + o.h); // below o
    consider(x, o.y - moving.h); // above o
  }

  return bestClear ?? best ?? (x: desiredX, y: desiredY);
}

/// True when a pointer can cross between [a] and [b]: they share area, or they
/// abut along an edge with non-zero shared extent. A corner-only touch is not
/// enough — neither display is reachable from the other.
bool areConnected(DisplayBox a, DisplayBox b) {
  final ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x);
  final oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y);
  if (ox < 0 || oy < 0) return false;
  return ox > 0 || oy > 0;
}

/// Pulls any display that is not reachable from the rest back onto the
/// arrangement.
///
/// Live snapping keeps the *dragged* display attached but cannot keep the others
/// attached to each other: dragging the middle of an `A-B-C` chain away strands
/// `C`. A BFS from the first box finds the main component; every box outside it
/// is re-placed with [snapPosition] against the component, nearest first.
List<DisplayBox> relinkDisconnected(List<DisplayBox> boxes) {
  if (boxes.length < 2) return List.of(boxes);

  final result = List.of(boxes);
  final reached = <int>{0};
  final queue = <int>[0];
  while (queue.isNotEmpty) {
    final i = queue.removeLast();
    for (var j = 0; j < result.length; j++) {
      if (reached.contains(j)) continue;
      if (areConnected(result[i], result[j])) {
        reached.add(j);
        queue.add(j);
      }
    }
  }

  while (reached.length < result.length) {
    // Nearest orphan first, so the closest one defines the edge the next one
    // may then attach to.
    var pick = -1;
    var pickScore = double.infinity;
    for (var j = 0; j < result.length; j++) {
      if (reached.contains(j)) continue;
      for (final i in reached) {
        final score = _centerDistanceSquared(result[i], result[j]);
        if (score < pickScore) {
          pickScore = score;
          pick = j;
        }
      }
    }
    if (pick < 0) break;

    final orphan = result[pick];
    final anchors = [for (final i in reached) result[i]];
    final snapped = snapPosition(
      moving: orphan,
      others: anchors,
      desiredX: orphan.x,
      desiredY: orphan.y,
    );
    result[pick] = (
      id: orphan.id,
      x: snapped.x,
      y: snapped.y,
      w: orphan.w,
      h: orphan.h,
    );
    reached.add(pick);
  }

  return result;
}

/// Translates [boxes] so the arrangement starts at (0, 0).
List<DisplayBox> rebaseToOrigin(List<DisplayBox> boxes) {
  if (boxes.isEmpty) return List.of(boxes);
  var minX = boxes.first.x;
  var minY = boxes.first.y;
  for (final b in boxes.skip(1)) {
    minX = math.min(minX, b.x);
    minY = math.min(minY, b.y);
  }
  if (minX == 0 && minY == 0) return List.of(boxes);
  return [
    for (final b in boxes)
      (id: b.id, x: b.x - minX, y: b.y - minY, w: b.w, h: b.h),
  ];
}

bool _overlapsArea(DisplayBox a, DisplayBox b) =>
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

double _centerDistanceSquared(DisplayBox a, DisplayBox b) {
  final dx = (a.x + a.w / 2) - (b.x + b.w / 2);
  final dy = (a.y + a.h / 2) - (b.y + b.h / 2);
  return dx * dx + dy * dy;
}

/// `clamp` that tolerates an inverted range, the way `moveItemsBy`'s clamp in
/// `desktop_layout.dart` does — a degenerate pair must not throw.
int _clampTolerant(int value, int lower, int upper) {
  if (lower > upper) return (lower + upper) ~/ 2;
  return value < lower ? lower : (value > upper ? upper : value);
}
