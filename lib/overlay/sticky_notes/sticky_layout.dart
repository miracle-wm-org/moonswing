// Where the overview's sticky notes go: the arithmetic, apart from the widgets,
// for `test/sticky_layout_test.dart`.
//
// A note's place is stored as its centre measured from the panel's centre
// (`NotePlacement.dx`/`dy`), so a note follows the panel when it is dragged.
// Everything here turns that into a rectangle on the output and back.

import 'dart:math' as math;
import 'dart:ui';

import 'package:moonswing/todo/todo_model.dart';

/// The gap kept between a new note and the panel, the output's edge and
/// another note.
const double kStickyGap = 16;

/// How far a note that finds no free spot is set off the last one.
const double kStickyCascade = 24;

/// A note's side, in logical pixels: they are square, and all one size — a
/// note's `StickySize` is the size of its writing, not of its paper.
const double kStickySide = 220;

/// The note's rectangle on a [surface] holding the panel at [card], moved
/// [drag] further while the user drags it.
///
/// Clamped onto the surface, the way the panel is: a note whose place is past
/// the edge — the panel was dragged towards it, or the output is smaller than
/// the one it was placed on — sits against the edge, and goes back to its place
/// when there is room again, because the place itself is never rewritten. A
/// note never placed sits on the panel's centre.
Rect stickyRect(
  Size surface,
  Rect card,
  NotePlacement placement, {
  Offset drag = Offset.zero,
}) {
  const side = kStickySide;
  final centre =
      card.center +
      (placement.isPlaced
          ? Offset(placement.dx!, placement.dy!)
          : Offset.zero) +
      drag;
  final maxX = math.max(0.0, surface.width - side);
  final maxY = math.max(0.0, surface.height - side);
  return Rect.fromLTWH(
    (centre.dx - side / 2).clamp(0.0, maxX),
    (centre.dy - side / 2).clamp(0.0, maxY),
    side,
    side,
  );
}

/// Where [rect] is, as a note's stored place: its centre from [card]'s.
({double dx, double dy}) stickyPlaceOf(Rect rect, Rect card) {
  final offset = rect.center - card.center;
  return (dx: offset.dx, dy: offset.dy);
}

/// The place for a new note: the first free spot around the panel at
/// [card] that is on the [surface] and overlaps nothing in [taken], returned as
/// [stickyPlaceOf] spells it.
///
/// Looked for down the panel's left side from its top, then down its right,
/// then along its top and along its bottom — the reading order of the panel's
/// margins, so the first note is where the eye starts. [taken] is every other
/// note, newest last, and anything else that must stay clear (the overview's
/// action buttons). When nothing is free the note is set [kStickyCascade] off
/// the newest one, over whatever is there, rather than not appearing: a
/// covered note can be dragged away, a missing one cannot.
({double dx, double dy}) placeNewSticky(
  Size surface,
  Rect card,
  List<Rect> taken,
) {
  const side = kStickySide;
  final step = side + kStickyGap;
  final room = (Offset.zero & surface).deflate(kStickyGap);

  bool free(Rect r) =>
      _contains(room, r) &&
      !r.overlaps(card.inflate(kStickyGap - 0.5)) &&
      !taken.any((t) => r.overlaps(t.inflate(kStickyGap - 0.5)));

  Iterable<Rect> candidates() sync* {
    // Down a side: from the panel's top to the bottom of the room.
    for (final left in [
      card.left - kStickyGap - side,
      card.right + kStickyGap,
    ]) {
      for (var top = card.top; top + side <= room.bottom; top += step) {
        yield Rect.fromLTWH(left, top, side, side);
      }
    }
    // Along an edge: across the panel's width.
    for (final top in [
      card.top - kStickyGap - side,
      card.bottom + kStickyGap,
    ]) {
      for (var left = card.left; left + side <= card.right; left += step) {
        yield Rect.fromLTWH(left, top, side, side);
      }
    }
  }

  for (final candidate in candidates()) {
    if (free(candidate)) return stickyPlaceOf(candidate, card);
  }

  final anchor = taken.isEmpty
      ? Rect.fromCenter(center: card.center, width: side, height: side)
      : Rect.fromLTWH(
          taken.last.left + kStickyCascade,
          taken.last.top + kStickyCascade,
          side,
          side,
        );
  final maxX = math.max(0.0, surface.width - side);
  final maxY = math.max(0.0, surface.height - side);
  final cascaded = Rect.fromLTWH(
    anchor.left.clamp(0.0, maxX),
    anchor.top.clamp(0.0, maxY),
    side,
    side,
  );
  return stickyPlaceOf(cascaded, card);
}

bool _contains(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;
