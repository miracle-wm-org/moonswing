import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/overlay/sticky_notes/sticky_layout.dart';
import 'package:moonswing/todo/todo_model.dart';

void main() {
  // A 1080p output with a panel centred on it: 360px of margin either side,
  // room for three medium notes down each, and none above or below.
  const surface = Size(1920, 1080);
  final card = Rect.fromCenter(
    center: const Offset(960, 540),
    width: 1200,
    height: 750,
  );

  Rect rectOf(({double dx, double dy}) place) =>
      stickyRect(surface, card, NotePlacement(dx: place.dx, dy: place.dy));

  test('the first note goes at the top of the panel\'s left side', () {
    final place = placeNewSticky(surface, card, const []);
    final rect = rectOf(place);
    expect(rect, Rect.fromLTWH(124, card.top, 220, 220));
    // Stored from the panel's centre, so it follows the panel.
    expect(place.dx, rect.center.dx - card.center.dx);
    expect(place.dy, rect.center.dy - card.center.dy);
  });

  test('down the left, then down the right, never overlapping', () {
    final taken = <Rect>[];
    for (var i = 0; i < 6; i++) {
      final rect = rectOf(placeNewSticky(surface, card, taken));
      expect(rect.overlaps(card), isFalse, reason: 'note $i is on the panel');
      for (final other in taken) {
        expect(rect.overlaps(other), isFalse, reason: 'note $i overlaps');
      }
      expect(
        (Offset.zero & surface).deflate(kStickyGap).contains(rect.topLeft),
        isTrue,
      );
      taken.add(rect);
    }
    expect(
      [for (final r in taken) r.left < card.left],
      [
        true, true, true, false, false, false, //
      ],
    );
    expect(taken[1].top, greaterThan(taken[0].top));
  });

  test('anything reserved is kept clear', () {
    final buttons = const Rect.fromLTWH(16, 16, 40, 40);
    final blocking = Rect.fromLTWH(100, card.top, 40, 40);
    final rect = rectOf(placeNewSticky(surface, card, [buttons, blocking]));
    expect(rect.overlaps(blocking), isFalse);
    expect(rect.left, 124);
    expect(rect.top, greaterThan(card.top));
  });

  test('with nowhere free, a note is set off the newest one', () {
    final taken = <Rect>[];
    for (var i = 0; i < 6; i++) {
      taken.add(rectOf(placeNewSticky(surface, card, taken)));
    }
    final rect = rectOf(placeNewSticky(surface, card, taken));
    expect(rect.topLeft, taken.last.topLeft + const Offset(24, 24));
  });

  test('a note that fits nowhere starts on the panel', () {
    // 210px either side: too little for a note and its gaps.
    final wide = Rect.fromCenter(
      center: const Offset(960, 540),
      width: 1500,
      height: 750,
    );
    final place = placeNewSticky(surface, wide, const []);
    final rect = stickyRect(
      surface,
      wide,
      NotePlacement(dx: place.dx, dy: place.dy),
    );
    expect(rect.center, wide.center);
  });

  test('a note is clamped onto the output and keeps its place', () {
    const far = NotePlacement(dx: -5000, dy: 5000);
    final rect = stickyRect(surface, card, far);
    expect(rect, const Rect.fromLTWH(0, 1080 - 220.0, 220, 220));
    // With the panel moved towards it, it comes back into view.
    final unplaced = stickyRect(surface, card, const NotePlacement());
    expect(unplaced.center, card.center);
    final dragged = stickyRect(
      surface,
      card,
      const NotePlacement(),
      drag: const Offset(30, -10),
    );
    expect(dragged.center, card.center + const Offset(30, -10));
  });

  test('a note\'s size is its writing, never its paper', () {
    const place = NotePlacement(dx: -600, dy: -100);
    final rects = {
      for (final size in StickySize.values)
        stickyRect(surface, card, place.copyWith(size: size)),
    };
    expect(rects, hasLength(1));
    expect(rects.single.size, const Size(kStickySide, kStickySide));
  });
}
