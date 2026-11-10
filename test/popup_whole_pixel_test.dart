import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/popup.dart';

/// A popup is a sized-to-content view, and the engine's Linux renderer stops
/// drawing one whose frame is not exactly its GTK allocation times the scale:
/// `redraw_cb` asks GTK for `frame_width / scale_factor`, integer division, and
/// returns without drawing. A card a fraction of a pixel wide at scale 2 is an
/// odd number of physical pixels, which no allocation can match — so the popup
/// froze on whatever GTK last painted, a frame from early in its fade (#236).
///
/// These pin the rounding that keeps every popup surface whole.
void main() {
  const unbounded = BoxConstraints();

  test('a fractional card is rounded up, never down', () {
    // Rounding down would cut the card's last row or rim off at the surface.
    expect(
      wholePixelPopupSize(const Size(150.7, 88.25), unbounded),
      const Size(151, 89),
    );
  });

  test('a whole size is left alone, float noise included', () {
    expect(
      wholePixelPopupSize(const Size(150, 88), unbounded),
      const Size(150, 88),
    );
    expect(
      wholePixelPopupSize(const Size(150.0000000001, 88), unbounded),
      const Size(150, 88),
    );
  });

  test('every size it answers is even in physical pixels at scale 2', () {
    for (var w = 100.0; w < 102; w += 0.13) {
      final size = wholePixelPopupSize(Size(w, w / 2), unbounded);
      expect((size.width * 2) % 2, 0, reason: 'width for $w');
      expect((size.height * 2) % 2, 0, reason: 'height for $w');
    }
  });

  test('never past the maximum GTK hint, which the backend truncates', () {
    // A card at its own maximum plus a fractional shadow: 320 + 12.5. The hint
    // GTK is given is 332, so 333 would be clamped and mismatch all over again.
    const window = BoxConstraints(maxWidth: 332.5, maxHeight: 572.5);
    expect(
      wholePixelPopupSize(const Size(332.5, 572.5), window),
      const Size(332, 572),
    );
  });

  test('never under the minimum GTK hint, nor under one pixel', () {
    const window = BoxConstraints(minWidth: 80.6, minHeight: 0);
    expect(
      wholePixelPopupSize(const Size(70.2, 0), window),
      const Size(80, 1),
    );
  });

  testWidgets('the box takes the whole size and keeps its child as laid out',
      (tester) async {
    final child = GlobalKey();
    await tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: PopupWholePixelBox(
          window: unbounded,
          child: SizedBox(key: child, width: 120.3, height: 40.6),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PopupWholePixelBox)), const Size(121, 41));
    // The child is not stretched into the fraction: the card keeps the size it
    // asked for, and the surface's sliver past it is transparent.
    expect(tester.getSize(find.byKey(child)), const Size(120.3, 40.6));
    expect(tester.getTopLeft(find.byKey(child)), Offset.zero);
  });
}
