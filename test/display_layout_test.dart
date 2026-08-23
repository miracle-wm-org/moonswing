import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/overlay/settings/display_layout.dart';

DisplayBox box(int id, int x, int y, [int w = 1920, int h = 1080]) =>
    (id: id, x: x, y: y, w: w, h: h);

void main() {
  group('logicalSizeOf', () {
    test('divides the mode by the output scale', () {
      expect(logicalSizeOf(3840, 2160, 2.0, 0), const Size(1920, 1080));
    });

    test('swaps the axes for the 90 and 270 degree transforms', () {
      expect(logicalSizeOf(1920, 1080, 1.0, 1), const Size(1080, 1920));
      expect(logicalSizeOf(1920, 1080, 1.0, 3), const Size(1080, 1920));
      expect(logicalSizeOf(1920, 1080, 1.0, 7), const Size(1080, 1920));
      expect(logicalSizeOf(1920, 1080, 1.0, 2), const Size(1920, 1080));
    });

    test('treats a zero or non-finite scale as 1', () {
      expect(logicalSizeOf(1920, 1080, 0, 0), const Size(1920, 1080));
      expect(logicalSizeOf(1920, 1080, double.nan, 0), const Size(1920, 1080));
    });
  });

  group('fitBoxes', () {
    test('centres the arrangement on both axes', () {
      // 2000x1000 of content, 0.1 scale (capped), in a 400x400 viewport:
      // 200x100 drawn, so 100px slack left/right and 150px top/bottom.
      final fit = fitBoxes(
        [box(1, 0, 0, 2000, 1000)],
        const Size(400, 400),
        padding: 0,
        maxScale: 0.1,
      );
      expect(fit.scale, 0.1);
      expect(fit.origin, const Offset(100, 150));
    });

    test('folds a negative origin into the transform', () {
      final fit = fitBoxes(
        [box(1, -2000, 0, 2000, 1000)],
        const Size(400, 400),
        padding: 0,
        maxScale: 0.1,
      );
      expect(diagramRect(box(1, -2000, 0, 2000, 1000), fit),
          const Rect.fromLTWH(100, 150, 200, 100));
    });

    test('never magnifies past maxScale', () {
      final fit = fitBoxes(
        [box(1, 0, 0, 100, 100)],
        const Size(400, 400),
        padding: 0,
        maxScale: 0.12,
      );
      expect(fit.scale, 0.12);
    });

    test('shrinks to fit the tighter axis', () {
      final fit = fitBoxes(
        [box(1, 0, 0, 4000, 1000)],
        const Size(400, 400),
        padding: 0,
        maxScale: 1.0,
      );
      expect(fit.scale, 0.1);
    });

    test('survives an empty list', () {
      final fit = fitBoxes([], const Size(400, 400));
      expect(fit.scale, greaterThan(0));
      expect(fit.origin, const Offset(200, 200));
    });
  });

  group('snapPosition', () {
    final anchor = box(1, 0, 0);

    test('leaves a lone display where it was dropped', () {
      expect(
        snapPosition(
            moving: anchor, others: const [], desiredX: 731, desiredY: -12),
        (x: 731, y: -12),
      );
    });

    test('abuts the nearest edge', () {
      // Dropped just right of the anchor, roughly level with it.
      expect(
        snapPosition(
          moving: box(2, 0, 0),
          others: [anchor],
          desiredX: 1850,
          desiredY: 40,
        ),
        (x: 1920, y: 40),
      );
      // Dropped below.
      expect(
        snapPosition(
          moving: box(2, 0, 0),
          others: [anchor],
          desiredX: 30,
          desiredY: 1000,
        ),
        (x: 30, y: 1080),
      );
      // Dropped left.
      expect(
        snapPosition(
          moving: box(2, 0, 0),
          others: [anchor],
          desiredX: -1800,
          desiredY: 0,
        ),
        (x: -1920, y: 0),
      );
    });

    test('keeps at least kMinEdgeOverlap along the shared edge', () {
      // Dragged far past the anchor's bottom-right corner: whichever edge
      // wins, the shared extent along it is exactly kMinEdgeOverlap.
      final snapped = snapPosition(
        moving: box(2, 0, 0),
        others: [anchor],
        desiredX: 1920,
        desiredY: 99999,
      );
      final placed = box(2, snapped.x, snapped.y);
      expect(areConnected(anchor, placed), isTrue);
      final sharedX = (anchor.x + anchor.w).clamp(placed.x, placed.x + placed.w) -
          anchor.x.clamp(placed.x, placed.x + placed.w);
      final sharedY = (anchor.y + anchor.h).clamp(placed.y, placed.y + placed.h) -
          anchor.y.clamp(placed.y, placed.y + placed.h);
      expect(sharedX == kMinEdgeOverlap || sharedY == kMinEdgeOverlap, isTrue,
          reason: 'shared extent was ($sharedX, $sharedY)');
    });

    test('never lands corner-to-corner', () {
      final snapped = snapPosition(
        moving: box(2, 0, 0),
        others: [anchor],
        desiredX: 1920,
        desiredY: 1080,
      );
      expect(areConnected(anchor, box(2, snapped.x, snapped.y)), isTrue);
    });

    test('refuses a placement that would overlap a third display', () {
      // Anchor at origin, a second display already occupying the slot on its
      // right; a drop aimed there must go elsewhere rather than stack.
      final right = box(3, 1920, 0);
      final snapped = snapPosition(
        moving: box(2, 0, 0),
        others: [anchor, right],
        desiredX: 1930,
        desiredY: 10,
      );
      final placed = box(2, snapped.x, snapped.y);
      for (final other in [anchor, right]) {
        expect(
          Rect.fromLTWH(placed.x.toDouble(), placed.y.toDouble(), 1920, 1080)
              .overlaps(Rect.fromLTWH(
                  other.x.toDouble(), other.y.toDouble(), 1920, 1080)),
          isFalse,
        );
      }
      expect(
        areConnected(placed, anchor) || areConnected(placed, right),
        isTrue,
      );
    });

    test('snaps against displays of different sizes', () {
      final small = box(1, 0, 0, 1280, 720);
      final snapped = snapPosition(
        moving: box(2, 0, 0, 3840, 2160),
        others: [small],
        desiredX: 1200,
        desiredY: 30,
      );
      expect(snapped.x, 1280);
    });
  });

  group('areConnected', () {
    test('is true for abutting displays with shared extent', () {
      expect(areConnected(box(1, 0, 0), box(2, 1920, 0)), isTrue);
      expect(areConnected(box(1, 0, 0), box(2, 0, 1080)), isTrue);
    });

    test('is false for a corner touch', () {
      expect(areConnected(box(1, 0, 0), box(2, 1920, 1080)), isFalse);
    });

    test('is false across a gap', () {
      expect(areConnected(box(1, 0, 0), box(2, 1921, 0)), isFalse);
    });

    test('is true when they overlap in area', () {
      expect(areConnected(box(1, 0, 0), box(2, 100, 100)), isTrue);
    });
  });

  group('relinkDisconnected', () {
    test('leaves a contiguous arrangement alone', () {
      final boxes = [box(1, 0, 0), box(2, 1920, 0), box(3, 3840, 0)];
      expect(relinkDisconnected(boxes), boxes);
    });

    test('reattaches a display stranded by a moved bridge', () {
      // A-B-C in a row, then B is dragged above A: C is now orphaned.
      final boxes = [box(1, 0, 0), box(2, 0, -1080), box(3, 3840, 0)];
      final fixed = relinkDisconnected(boxes);
      expect(fixed[0], boxes[0]);
      expect(fixed[1], boxes[1]);
      for (var i = 0; i < fixed.length; i++) {
        expect(
          fixed.asMap().entries.any((e) => e.key != i && areConnected(e.value, fixed[i])),
          isTrue,
          reason: 'display ${fixed[i].id} is unreachable',
        );
      }
    });

    test('is a no-op for zero or one display', () {
      expect(relinkDisconnected([]), isEmpty);
      expect(relinkDisconnected([box(1, 500, 500)]), [box(1, 500, 500)]);
    });
  });

  group('rebaseToOrigin', () {
    test('translates the arrangement to (0, 0)', () {
      expect(
        rebaseToOrigin([box(1, -1920, 40), box(2, 0, 40)]),
        [box(1, 0, 0), box(2, 1920, 0)],
      );
    });

    test('leaves an already-based arrangement alone', () {
      final boxes = [box(1, 0, 0), box(2, 1920, 0)];
      expect(rebaseToOrigin(boxes), boxes);
    });
  });
}
