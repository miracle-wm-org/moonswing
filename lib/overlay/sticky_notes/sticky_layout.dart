// Where the overview's sticky notes and floating timers go: the arithmetic,
// apart from the widgets, for `test/sticky_layout_test.dart`.
//
// A note's place is stored as its centre measured from the panel's centre
// (`NotePlacement.dx`/`dy`), and a timer's the same way, so either follows the
// panel when it is dragged. Everything here turns that into a rectangle on the
// output and back; the `float` functions take any size, and the `sticky` ones
// are them at a note's.

import 'dart:math' as math;
import 'dart:ui';

import 'package:moonswing/todo/todo_model.dart';

/// The gap kept between a new note and the panel, the output's edge and
/// another note.
const double kStickyGap = 16;

/// How far a note that finds no free spot is set off the last one.
const double kStickyCascade = 24;

/// A note's side, in logical pixels: they are square.
double stickySide(StickySize size) => switch (size) {
  StickySize.small => 160,
  StickySize.medium => 220,
  StickySize.large => 300,
};

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
  final side = stickySide(placement.size);
  return floatRect(
    surface,
    card,
    placement.isPlaced ? Offset(placement.dx!, placement.dy!) : null,
    Size(side, side),
    drag: drag,
  );
}

/// The rectangle of something of [size] whose centre is [place] from the
/// centre of the panel at [card], moved [drag] further — [stickyRect] for any
/// size, clamped onto the [surface] on the same terms. A null [place] is the
/// panel's centre.
Rect floatRect(
  Size surface,
  Rect card,
  Offset? place,
  Size size, {
  Offset drag = Offset.zero,
}) {
  final centre = card.center + (place ?? Offset.zero) + drag;
  final maxX = math.max(0.0, surface.width - size.width);
  final maxY = math.max(0.0, surface.height - size.height);
  return Rect.fromLTWH(
    (centre.dx - size.width / 2).clamp(0.0, maxX),
    (centre.dy - size.height / 2).clamp(0.0, maxY),
    size.width,
    size.height,
  );
}

/// Where [rect] is, as a note's stored place: its centre from [card]'s.
({double dx, double dy}) stickyPlaceOf(Rect rect, Rect card) {
  final offset = rect.center - card.center;
  return (dx: offset.dx, dy: offset.dy);
}

/// The place for a new note of [size]: the first free spot around the panel at
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
  StickySize size,
) {
  final side = stickySide(size);
  return placeNewFloat(surface, card, taken, Size(side, side));
}

/// [placeNewSticky] for anything of [size]: the same search, in the same order,
/// with the same fallback.
({double dx, double dy}) placeNewFloat(
  Size surface,
  Rect card,
  List<Rect> taken,
  Size size,
) {
  final width = size.width;
  final height = size.height;
  final room = (Offset.zero & surface).deflate(kStickyGap);

  bool free(Rect r) =>
      _contains(room, r) &&
      !r.overlaps(card.inflate(kStickyGap - 0.5)) &&
      !taken.any((t) => r.overlaps(t.inflate(kStickyGap - 0.5)));

  Iterable<Rect> candidates() sync* {
    // Down a side: from the panel's top to the bottom of the room.
    for (final left in [
      card.left - kStickyGap - width,
      card.right + kStickyGap,
    ]) {
      for (
        var top = card.top;
        top + height <= room.bottom;
        top += height + kStickyGap
      ) {
        yield Rect.fromLTWH(left, top, width, height);
      }
    }
    // Along an edge: across the panel's width.
    for (final top in [
      card.top - kStickyGap - height,
      card.bottom + kStickyGap,
    ]) {
      for (
        var left = card.left;
        left + width <= card.right;
        left += width + kStickyGap
      ) {
        yield Rect.fromLTWH(left, top, width, height);
      }
    }
  }

  for (final candidate in candidates()) {
    if (free(candidate)) return stickyPlaceOf(candidate, card);
  }

  final anchor = taken.isEmpty
      ? Rect.fromCenter(center: card.center, width: width, height: height)
      : Rect.fromLTWH(
          taken.last.left + kStickyCascade,
          taken.last.top + kStickyCascade,
          width,
          height,
        );
  final maxX = math.max(0.0, surface.width - width);
  final maxY = math.max(0.0, surface.height - height);
  final cascaded = Rect.fromLTWH(
    anchor.left.clamp(0.0, maxX),
    anchor.top.clamp(0.0, maxY),
    width,
    height,
  );
  return stickyPlaceOf(cascaded, card);
}

bool _contains(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;
