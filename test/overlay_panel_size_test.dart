import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/overlay/overlay.dart';

void main() {
  void expectAspect(Size size) {
    expect(
      size.width / size.height,
      closeTo(kOverlayPanelAspect, 0.001),
      reason: 'panel should keep its 16:10 ratio',
    );
  }

  test('1080p: scales with the display width', () {
    final size = overlayPanelSize(const Size(1920, 1080));
    expect(size.width, closeTo(1920 * kOverlayPanelWidthFraction, 0.001));
    expectAspect(size);
  });

  test('1440p and above: clamped to the maximum', () {
    expect(overlayPanelSize(const Size(2560, 1440)), kOverlayPanelMaxSize);
    expect(overlayPanelSize(const Size(3840, 2160)), kOverlayPanelMaxSize);
  });

  test('short and wide: the height fraction binds, ratio survives', () {
    final size = overlayPanelSize(const Size(2560, 900));
    expect(size.height, closeTo(900 * kOverlayPanelHeightFraction, 0.001));
    expectAspect(size);
  });

  test('small display: floors at the minimum', () {
    final size = overlayPanelSize(const Size(1024, 768));
    expect(size, kOverlayPanelMinSize);
  });

  test('display smaller than the minimum: fits on screen anyway', () {
    const available = Size(640, 480);
    final size = overlayPanelSize(available);
    expect(size.width, lessThanOrEqualTo(available.width));
    expect(size.height, lessThanOrEqualTo(available.height));
  });
}
