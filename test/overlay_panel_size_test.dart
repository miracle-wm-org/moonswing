import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/overlay/overlay.dart';

void main() {
  void expectAspect(Size size) {
    expect(
      size.width / size.height,
      closeTo(kOverlayPanelAspect, 0.001),
      reason: 'panel should keep its ratio',
    );
  }

  test('the panel is a little taller than it is wide', () {
    expect(kOverlayPanelAspect, lessThan(1));
    expect(kOverlayPanelAspect, greaterThan(0.85));
  });

  test('1080p: scales with the display height', () {
    final size = overlayPanelSize(const Size(1920, 1080));
    expect(size.height, closeTo(1080 * kOverlayPanelHeightFraction, 0.001));
    expect(size.height, greaterThan(size.width));
    expectAspect(size);
  });

  test('4K at scale 1: clamped to the maximum', () {
    expect(overlayPanelSize(const Size(3840, 2160)), kOverlayPanelMaxSize);
  });

  test('portrait: the width fraction binds, ratio survives', () {
    final size = overlayPanelSize(const Size(1080, 1920));
    expect(size.width, closeTo(1080 * kOverlayPanelWidthFraction, 0.001));
    expectAspect(size);
  });

  test('short display: the minimum width stands, the height still fits', () {
    final size = overlayPanelSize(const Size(1024, 768));
    expect(size.width, kOverlayPanelMinSize.width);
    expect(size.height, closeTo(768 * kOverlayPanelHeightFraction, 0.001));
  });

  test('display smaller than the minimum: fits on screen anyway', () {
    const available = Size(640, 480);
    final size = overlayPanelSize(available);
    expect(size.width, lessThanOrEqualTo(available.width));
    expect(size.height, lessThanOrEqualTo(available.height));
  });
}
