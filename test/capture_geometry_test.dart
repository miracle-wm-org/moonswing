import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/capture/capture_targets.dart';

/// The coordinate layer of the screenshot and recording feature: a selection
/// is made in logical pixels and a capture arrives in physical ones, and every
/// crop in the feature is that conversion.
void main() {
  group('CaptureRect', () {
    test('fromCorners spans a drag made in any direction', () {
      const forward = CaptureRect.fromCorners(10, 20, 110, 220);
      const backward = CaptureRect.fromCorners(110, 220, 10, 20);
      const mixed = CaptureRect.fromCorners(110, 20, 10, 220);
      expect(forward, const CaptureRect(10, 20, 100, 200));
      expect(backward, forward);
      expect(mixed, forward);
    });

    test('contains is half-open, so touching rectangles do not overlap', () {
      const rect = CaptureRect(0, 0, 10, 10);
      expect(rect.contains(0, 0), isTrue);
      expect(rect.contains(9, 9), isTrue);
      expect(rect.contains(10, 5), isFalse);
      expect(rect.contains(5, 10), isFalse);
    });

    test('intersect answers empty rather than a negative rectangle', () {
      const a = CaptureRect(0, 0, 10, 10);
      const b = CaptureRect(50, 50, 10, 10);
      expect(a.intersect(b).isEmpty, isTrue);
      expect(a.intersect(const CaptureRect(5, 5, 100, 100)),
          const CaptureRect(5, 5, 5, 5));
    });
  });

  group('scaledInto', () {
    test('is the identity at scale 1', () {
      const rect = CaptureRect(100, 50, 400, 300);
      expect(rect.scaledInto(const CaptureSize(1920, 1080), 1920, 1080), rect);
    });

    test('scales by the buffer, not by an advertised scale factor', () {
      // A 1.5x fractional-scaled 1920x1080 output: the logical space is 1280x720
      // and the buffer the compositor hands back is the full 1920x1080.
      const rect = CaptureRect(100, 100, 200, 100);
      final scaled = rect.scaledInto(const CaptureSize(1280, 720), 1920, 1080);
      expect(scaled, const CaptureRect(150, 150, 300, 150));
    });

    test('maps edges rather than sizes, so a crop cannot creep', () {
      // Rounding the origin and the *size* independently lets adjacent crops
      // overlap or leave a seam; both edges are rounded and the width is their
      // difference.
      const rect = CaptureRect(1, 1, 3, 3);
      final scaled = rect.scaledInto(const CaptureSize(10, 10), 15, 15);
      expect(scaled!.x, 2); // 1 * 1.5 rounds to 2
      expect(scaled.right, 6); // 4 * 1.5 == 6
      expect(scaled.width, 4);
    });

    test('clips to the buffer', () {
      const rect = CaptureRect(1900, 1000, 400, 400);
      final scaled = rect.scaledInto(const CaptureSize(1920, 1080), 1920, 1080);
      expect(scaled, const CaptureRect(1900, 1000, 20, 80));
    });

    test('answers null for a degenerate space rather than guessing', () {
      const rect = CaptureRect(0, 0, 10, 10);
      expect(rect.scaledInto(const CaptureSize(0, 0), 100, 100), isNull);
      expect(rect.scaledInto(const CaptureSize(100, 100), 0, 100), isNull);
      // Entirely outside the buffer is not a crop of nothing, it is no crop.
      expect(
        const CaptureRect(500, 500, 10, 10)
            .scaledInto(const CaptureSize(100, 100), 100, 100),
        isNull,
      );
    });
  });

  group('CaptureTarget', () {
    test('a whole output has no crop', () {
      const target =
          OutputCapture(connector: 'DP-1', outputSize: CaptureSize(1920, 1080));
      expect(target.crop, isNull);
      expect(target.toplevelIdentifier, isNull);
      expect(target.label, 'DP-1');
    });

    test('a window carries both routes to the pixels', () {
      const window = WindowCapture(
        connector: 'DP-1',
        outputSize: CaptureSize(1920, 1080),
        crop: CaptureRect(10, 10, 800, 600),
        title: 'Notes',
        appId: 'org.example.notes',
      );
      // With no handle it is a fixed rectangle on its output...
      expect(window.followsWindow, isFalse);
      expect(window.crop, const CaptureRect(10, 10, 800, 600));
      // ...and joining one on is what makes it follow the window.
      final joined = window.withToplevelIdentifier('toplevel-7');
      expect(joined.followsWindow, isTrue);
      expect(joined.toplevelIdentifier, 'toplevel-7');
      expect(joined.crop, window.crop, reason: 'the fallback survives the join');
      expect(joined.title, 'Notes');
    });

    test('a window with neither a title nor an app id still has a label', () {
      const window = WindowCapture(
        connector: 'DP-1',
        outputSize: CaptureSize(1920, 1080),
        crop: CaptureRect(0, 0, 10, 10),
        title: '',
        appId: '',
      );
      expect(window.label, isNotEmpty);
    });

    test('an area labels itself by its size', () {
      const area = AreaCapture(
        connector: 'DP-1',
        outputSize: CaptureSize(1920, 1080),
        crop: CaptureRect(4, 4, 640, 480),
      );
      expect(area.label, '640 x 480');
    });
  });
}
