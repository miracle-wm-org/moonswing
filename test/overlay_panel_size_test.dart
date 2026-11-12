import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/overlay/overlay.dart';
import 'package:moonswing/theme/theme_config.dart';

void main() {
  void expectAspect(Size size, [double aspect = kOverlayPanelAspect]) {
    expect(
      size.width / size.height,
      closeTo(aspect, 0.001),
      reason: 'panel should keep its ratio',
    );
  }

  test('the panel is half again as wide as tall by default', () {
    expect(kOverlayPanelAspect, 1.5);
    expect(const ThemeConfig().overlayAspect, kOverlayPanelAspect);
  });

  test('1080p: the maximum width binds, ratio survives', () {
    final size = overlayPanelSize(const Size(1920, 1080));
    expect(size.width, kOverlayPanelMaxWidth);
    expect(size.height, closeTo(kOverlayPanelMaxWidth / 1.5, 0.001));
    expectAspect(size);
  });

  test('a square panel scales with the display height', () {
    final size = overlayPanelSize(const Size(1920, 1080), aspect: 1.0);
    expect(size.height, closeTo(1080 * kOverlayPanelHeightFraction, 0.001));
    expect(size.width, closeTo(size.height, 0.001));
  });

  test("1080p: a theme's aspect shapes the panel", () {
    final tall = overlayPanelSize(const Size(1920, 1080), aspect: 0.8);
    expect(tall.height, closeTo(1080 * kOverlayPanelHeightFraction, 0.001));
    expectAspect(tall, 0.8);

    // Wide enough that the maximum width binds; the ratio still holds.
    final wide = overlayPanelSize(const Size(1920, 1080), aspect: 1.6);
    expect(wide.width, kOverlayPanelMaxWidth);
    expectAspect(wide, 1.6);
  });

  test('a nonsense aspect falls back to the default', () {
    for (final aspect in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        overlayPanelSize(const Size(1920, 1080), aspect: aspect),
        overlayPanelSize(const Size(1920, 1080)),
        reason: 'aspect $aspect',
      );
    }
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
    final size = overlayPanelSize(const Size(1024, 768), aspect: 1.0);
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
