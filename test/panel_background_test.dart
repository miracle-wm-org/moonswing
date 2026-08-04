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

  test('a default bar is square and unbordered', () {
    // The pixel-identity guard for graceful and dracula: this feature must
    // change nothing at all until a theme asks for it.
    for (final gradient in [true, false]) {
      final decoration = panelBackgroundDecoration(
        theme: ThemeConfig(panelGradient: gradient),
      );
      expect(decoration.borderRadius, isNull, reason: 'gradient $gradient');
      expect(decoration.border, isNull, reason: 'gradient $gradient');
    }
  });

  test('a zero-width border is no Border at all', () {
    // Width is the off switch, not alpha — and it has to produce *no* Border,
    // because a Border carries a BoxDecoration.padding that would inset the
    // bar's content the moment anyone wrapped it in a Container.
    final decoration = panelBackgroundDecoration(
      theme: const ThemeConfig(
        panelBorder: Color(0xFFFF0000),
        panelBorderWidth: 0,
      ),
    );
    expect(decoration.border, isNull);
  });

  test('the rim and the rounding reach both shapes', () {
    // The flat branch is the one glassy actually takes, and until now no test
    // looked at anything but the gradient.
    for (final gradient in [true, false]) {
      final theme = ThemeConfig(
        panelGradient: gradient,
        panelMargin: 8,
        panelRadius: 12,
        panelBorder: const Color(0x40FFFFFF),
        panelBorderWidth: 1.5,
      );
      final decoration = panelBackgroundDecoration(theme: theme);
      expect(
        decoration.border,
        Border.all(color: const Color(0x40FFFFFF), width: 1.5),
        reason: 'gradient $gradient',
      );
      expect(decoration.borderRadius, BorderRadius.circular(12),
          reason: 'gradient $gradient');
    }
  });

  test('a floating bar rounds all four corners', () {
    for (final anchor in const ['top', 'bottom', 'left', 'right']) {
      expect(
        panelCornerRadius(
          anchor: anchor,
          theme: const ThemeConfig(panelMargin: 8, panelRadius: 12),
        ),
        BorderRadius.circular(12),
        reason: 'anchor $anchor',
      );
    }
  });

  test('a flush bar rounds only the corners facing the screen', () {
    // Rounding the pair against the screen edge would cut wallpaper wedges out
    // of the display's own corners.
    const r = Radius.circular(12);
    for (final (anchor, expected) in const [
      ('top', BorderRadius.only(bottomLeft: r, bottomRight: r)),
      ('bottom', BorderRadius.only(topLeft: r, topRight: r)),
      ('left', BorderRadius.only(topRight: r, bottomRight: r)),
      ('right', BorderRadius.only(topLeft: r, bottomLeft: r)),
    ]) {
      expect(
        panelCornerRadius(
          anchor: anchor,
          theme: const ThemeConfig(panelMargin: 0, panelRadius: 12),
        ),
        expected,
        reason: 'anchor $anchor',
      );
    }
  });

  test('no radius means no clip layer', () {
    // main.dart keys the ClipRRect off BorderRadius.zero, so this is what keeps
    // an unstyled bar at exactly the layer count it had before.
    expect(
      panelCornerRadius(theme: const ThemeConfig(panelMargin: 8)),
      BorderRadius.zero,
    );
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
