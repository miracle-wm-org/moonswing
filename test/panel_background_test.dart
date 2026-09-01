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
        // Floating popups, so the bar is a boundary on all four sides; see the
        // attached case below.
        popupGap: 6,
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

  group('the rim and the edge the menus come out of', () {
    // `popup_gap = 0` is the attached mode: a bar popup is flush with the
    // panel's inner edge and made of the same material, so the two are meant to
    // read as one surface. A rim along that edge is the seam attaching exists
    // to remove, and it has to be the *panel* that leaves it off — the line is
    // on the panel's own surface, and a popup is a separate compositor surface
    // the compositor places, so painting over it would need the two to align to
    // the pixel and would only ever work where card and bar are one colour.
    const attached = ThemeConfig(
      panelBorder: Color(0xFF525252),
      panelBorderWidth: 1.0,
    );

    /// The side of [anchor]'s bar that faces the screen's interior.
    BorderSide inner(Border border, String anchor) => switch (anchor) {
          'top' => border.bottom,
          'bottom' => border.top,
          'left' => border.right,
          _ => border.left,
        };

    test('an attached theme leaves the inner edge open, and only that', () {
      for (final anchor in const ['top', 'bottom', 'left', 'right']) {
        final border =
            panelBackgroundDecoration(anchor: anchor, theme: attached).border!
                as Border;
        expect(inner(border, anchor).style, BorderStyle.none, reason: anchor);
        // Exactly one side: the other three are against the screen edge on a
        // flush bar and are the rim the user asked for on a floating one.
        expect(
            [border.top, border.bottom, border.left, border.right]
                .where((s) => s.style == BorderStyle.none),
            hasLength(1),
            reason: anchor);
        final drawn =
            [border.top, border.bottom, border.left, border.right]
                .where((s) => s.style != BorderStyle.none);
        for (final side in drawn) {
          expect(side.color, attached.panelBorder, reason: anchor);
          expect(side.width, attached.panelBorderWidth, reason: anchor);
        }
      }
    });

    test('a gap gives the bar all four sides back', () {
      // With a gap the cards genuinely float, so the bar's inner edge is a
      // boundary again and the rim runs the whole way round.
      for (final anchor in const ['top', 'bottom', 'left', 'right']) {
        final border = panelBackgroundDecoration(
          anchor: anchor,
          theme: const ThemeConfig(
            panelBorder: Color(0xFF525252),
            panelBorderWidth: 1.0,
            popupGap: 6.0,
          ),
        ).border! as Border;
        expect(border.isUniform, isTrue, reason: anchor);
        expect(inner(border, anchor).style, BorderStyle.solid, reason: anchor);
      }
    });

    test('an unrimmed bar is untouched by any of it', () {
      // Width is still the off switch, and it still has to produce no Border at
      // all — which is every shipped theme but carbon.
      expect(panelBackgroundDecoration(theme: const ThemeConfig()).border,
          isNull);
    });

    test('the rounding survives the open edge', () {
      // A rounded bar keeps both: the rounding on the two corners facing the
      // screen's interior, and the open edge between them. A non-uniform Border
      // under a borderRadius is legal only because the visible sides share one
      // colour — BoxBorder.paint takes its paintNonUniformBorder path before it
      // reaches the uniformity assert — which is what the widget test below
      // pins, since painting is what would throw.
      const rounded = ThemeConfig(
        panelBorder: Color(0xFF525252),
        panelBorderWidth: 1.0,
        panelMargin: 8,
        panelRadius: 12,
      );
      final decoration = panelBackgroundDecoration(theme: rounded);
      expect(decoration.borderRadius, BorderRadius.circular(12));
      expect((decoration.border! as Border).isUniform, isFalse);
    });

    testWidgets('an open-edged rim paints without complaint', (tester) async {
      for (final anchor in const ['top', 'bottom', 'left', 'right']) {
        await tester.pumpWidget(DecoratedBox(
          decoration: panelBackgroundDecoration(
            anchor: anchor,
            theme: const ThemeConfig(
              panelBorder: Color(0xFF525252),
              panelBorderWidth: 1.0,
              panelMargin: 8,
              panelRadius: 12,
            ),
          ),
          child: const SizedBox(width: 200, height: 32),
        ));
        expect(tester.takeException(), isNull, reason: anchor);
      }
    });
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
