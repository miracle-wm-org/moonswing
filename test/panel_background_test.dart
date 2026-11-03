import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/panel_background.dart';
import 'package:moonswing/theme/panel_gradient.dart';

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
      panelGradient: PanelGradient.none,
      panelBackground: Color(0x40121722),
    );
    final decoration = panelBackgroundDecoration(theme: theme);
    expect(decoration.gradient, isNull);
    expect(decoration.color, const Color(0x40121722));
  });

  test('a default bar is square and unbordered', () {
    // The pixel-identity guard for moonswing and dracula: this feature must
    // change nothing at all until a theme asks for it.
    for (final gradient in PanelGradient.values) {
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
    for (final gradient in PanelGradient.values) {
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

  test('modules stop short of the rim, and a gap past it', () {
    // A highlighted workspace used to fill the bar to its edges, over the rim.
    expect(panelModuleInset(const ThemeConfig()), kPanelModuleGap);
    expect(
      panelModuleInset(const ThemeConfig(panelBorderWidth: 1.5)),
      1.5 + kPanelModuleGap,
    );
  });
  group('four corners', () {
    const red = Color(0xFFFF0000);
    const green = Color(0xFF00FF00);
    const blue = Color(0xFF0000FF);
    const white = Color(0xFFFFFFFF);
    const theme = ThemeConfig(
      panelGradient: PanelGradient.corners,
      panelGradientTopLeft: red,
      panelGradientTopRight: green,
      panelGradientBottomRight: blue,
      panelGradientBottomLeft: white,
    );

    test('the shape is a corner decoration carrying the theme\'s four', () {
      final decoration = panelBackgroundDecoration(theme: theme);
      expect(decoration, isA<PanelCornerDecoration>());
      expect(
        (decoration as PanelCornerDecoration).corners,
        PanelCorners.of(theme),
      );
      expect(decoration.color, isNull);
      expect(decoration.gradient, isNull);
    });

    test('the corners are the screen\'s, whichever edge the bar is on', () {
      // Unlike the accent fade, which turns with the anchor: a theme lit from
      // the top-left of the display is lit from there on every bar.
      for (final anchor in const ['top', 'bottom', 'left', 'right']) {
        final decoration =
            panelBackgroundDecoration(anchor: anchor, theme: theme)
                as PanelCornerDecoration;
        expect(decoration.corners.topLeft, red, reason: 'anchor $anchor');
        expect(decoration.corners.bottomRight, blue, reason: 'anchor $anchor');
      }
    });

    test('each corner keeps its own alpha', () {
      const translucent = ThemeConfig(
        panelGradient: PanelGradient.corners,
        panelBackground: Color(0xFF000000),
        panelGradientTopLeft: Color(0x40FF0000),
      );
      final decoration =
          panelBackgroundDecoration(theme: translucent)
              as PanelCornerDecoration;
      expect(decoration.corners.topLeft, const Color(0x40FF0000));
    });

    test(
      'the blend is bilinear: each edge is the fade between its corners',
      () {
        final corners = PanelCorners.of(theme);
        expect(corners.at(0, 0), red);
        expect(corners.at(1, 0), green);
        expect(corners.at(1, 1), blue);
        expect(corners.at(0, 1), white);
        expect(corners.at(0.5, 0), Color.lerp(red, green, 0.5));
        expect(corners.at(0, 0.5), Color.lerp(red, white, 0.5));
        expect(
          corners.at(0.5, 0.5),
          Color.lerp(
            Color.lerp(red, green, 0.5),
            Color.lerp(white, blue, 0.5),
            0.5,
          ),
        );
      },
    );

    test('the rim and the rounding come with it', () {
      final decoration = panelBackgroundDecoration(
        theme: const ThemeConfig(
          panelGradient: PanelGradient.corners,
          panelMargin: 8,
          panelRadius: 12,
          panelBorder: Color(0x40FFFFFF),
          panelBorderWidth: 1.5,
        ),
      );
      expect(
        decoration.border,
        Border.all(color: const Color(0x40FFFFFF), width: 1.5),
      );
      expect(decoration.borderRadius, BorderRadius.circular(12));
      expect(
        panelBackgroundDecoration(
          theme: const ThemeConfig(panelGradient: PanelGradient.corners),
          includeRim: false,
        ).border,
        isNull,
      );
    });

    test(
      'equal corners are an equal decoration, and different ones are not',
      () {
        expect(
          panelBackgroundDecoration(theme: theme),
          panelBackgroundDecoration(theme: theme),
        );
        expect(
          panelBackgroundDecoration(theme: theme),
          isNot(
            panelBackgroundDecoration(
              theme: const ThemeConfig(panelGradient: PanelGradient.corners),
            ),
          ),
        );
      },
    );

    testWidgets('the painted bar is each corner\'s colour at that corner', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 240,
                height: 32,
                child: DecoratedBox(
                  decoration: panelBackgroundDecoration(theme: theme),
                ),
              ),
            ),
          ),
        ),
      );

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final (bytes, width) =
          await tester.runAsync(() async {
                final image = await boundary.toImage();
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                );
                final width = image.width;
                image.dispose();
                return (data!, width);
              })
              as (ByteData, int);

      Color pixel(int x, int y) {
        final i = (y * width + x) * 4;
        return Color.fromARGB(
          bytes.getUint8(i + 3),
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
        );
      }

      void near(Color actual, Color expected, String where) {
        for (final (a, e) in [
          (actual.r, expected.r),
          (actual.g, expected.g),
          (actual.b, expected.b),
          (actual.a, expected.a),
        ]) {
          expect(a, closeTo(e, 3 / 255), reason: '$where: $actual');
        }
      }

      final corners = PanelCorners.of(theme);
      // A pixel's centre, not its edge, so each is a hair in from the corner.
      Color expectedAt(int x, int y) =>
          corners.at((x + 0.5) / 240, (y + 0.5) / 32);
      for (final (x, y, where) in const [
        (0, 0, 'top-left'),
        (239, 0, 'top-right'),
        (239, 31, 'bottom-right'),
        (0, 31, 'bottom-left'),
        (120, 16, 'middle'),
        (60, 8, 'a quarter in'),
      ]) {
        near(pixel(x, y), expectedAt(x, y), where);
      }
    });
  });
}
