import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/panel_background.dart';

List<Color> stopsOf(ThemeConfig theme) =>
    (panelBackgroundDecoration(theme: theme).gradient as LinearGradient).colors;

void main() {
  test('the default palette keeps the bar at its long-standing 93%', () {
    final stops = stopsOf(const ThemeConfig());
    for (final c in stops) {
      expect(c.a, closeTo(0xEE / 0xFF, 0.001));
    }
    // ...and the hues are the theme's, untouched.
    expect(stops.last, const ThemeConfig().panelBackground);
  });

  test("a translucent panel_background reaches the desktop", () {
    // The regression this guards: the bar used to be painted from
    // workspaceBackground at a hardcoded 93%, so it was the one surface a
    // glass theme could not see through — while its own popups obeyed.
    const theme = ThemeConfig(panelBackground: Color(0x40121722));
    for (final c in stopsOf(theme)) {
      expect(c.a, closeTo(0x40 / 0xFF, 0.001));
    }
  });

  test('every stop shares one opacity, so the bar cannot band', () {
    // accent and surfacePressed are opaque here; the bar is not.
    const theme = ThemeConfig(
      panelBackground: Color(0x40121722),
      accent: Color(0xFF7FB6FF),
      surfacePressed: Color(0xFFFFFFFF),
    );
    final alphas = stopsOf(theme).map((c) => c.a).toSet();
    expect(alphas, hasLength(1));
  });

  test('panel_gradient off paints a flat panel_background', () {
    const theme = ThemeConfig(
      panelGradient: false,
      panelBackground: Color(0x40121722),
    );
    final decoration = panelBackgroundDecoration(theme: theme);
    expect(decoration.gradient, isNull);
    expect(decoration.color, const Color(0x40121722));
  });

  test('the gradient is aligned to the panel edge', () {
    for (final (anchor, begin) in const [
      ('top', Alignment.centerLeft),
      ('bottom', Alignment.centerRight),
      ('left', Alignment.topCenter),
      ('right', Alignment.bottomCenter),
    ]) {
      final gradient = panelBackgroundDecoration(
        anchor: anchor,
        theme: const ThemeConfig(),
      ).gradient as LinearGradient;
      expect(gradient.begin, begin, reason: 'anchor $anchor');
    }
  });
}
