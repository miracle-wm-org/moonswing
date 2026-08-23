import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';

/// Pumps [card] under a [ThemeScope] carrying [theme].
Future<void> pumpCard(
  WidgetTester tester,
  ThemeConfig theme,
  Widget card,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: theme,
        child: Center(child: card),
      ),
    ),
  );
}

BoxDecoration decorationOf(WidgetTester tester) =>
    tester.widget<Container>(find.byType(Container)).decoration
        as BoxDecoration;

void main() {
  group('the decoration', () {
    test('the default palette gives a rounded, rimmed card', () {
      const theme = ThemeConfig();
      final decoration = popupDecoration(theme: theme);
      expect(decoration.color, theme.popupBackground);
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect(
        decoration.border,
        Border.all(color: theme.popupBorder, width: 1.0),
      );
    });

    test('a card rounds all four corners', () {
      // Unlike the bar, which spares the pair against the screen edge. There
      // is no anchor to vary here, and that is the point.
      const theme = ThemeConfig(popupRadius: 12.0);
      expect(popupCornerRadius(theme), BorderRadius.circular(12.0));
    });

    test('a zero-width rim is no Border at all', () {
      // Not a zero-width Border: a Border in the decoration carries a non-zero
      // BoxDecoration.padding, which a Container would silently add to the
      // card's own padding and shift its content.
      const theme = ThemeConfig(popupBorderWidth: 0.0);
      expect(popupDecoration(theme: theme).border, isNull);
    });

    test('no radius means no borderRadius to build a clip from', () {
      const theme = ThemeConfig(popupRadius: 0.0);
      expect(popupCornerRadius(theme), BorderRadius.zero);
      expect(popupDecoration(theme: theme).borderRadius, isNull);
    });

    test(
      'the border override replaces the theme rim rather than adding to it',
      () {
        const theme = ThemeConfig(popupBorderWidth: 1.0);
        final override = Border.all(color: const Color(0xFFFF0000), width: 1.5);
        final decoration = popupDecoration(theme: theme, border: override);
        expect(decoration.border, override);
        // The rounding still comes from the theme — only the rim is overridden.
        expect(
          decoration.borderRadius,
          BorderRadius.circular(theme.popupRadius),
        );
      },
    );
  });

  group('the card', () {
    testWidgets('a rounded card clips its children exactly once', (
      tester,
    ) async {
      // A borderRadius rounds the painted background without clipping
      // anything, so a list or a chart would paint square corners over it.
      await pumpCard(
        tester,
        const ThemeConfig(popupRadius: 8.0),
        const PopupCard(child: SizedBox(width: 100, height: 100)),
      );
      expect(find.byType(ClipPath), findsOneWidget);
    });

    testWidgets('a square card builds no clip layer', (tester) async {
      await pumpCard(
        tester,
        const ThemeConfig(popupRadius: 0.0),
        const PopupCard(child: SizedBox(width: 100, height: 100)),
      );
      expect(find.byType(ClipPath), findsNothing);
    });

    testWidgets('clip: false opts out', (tester) async {
      await pumpCard(
        tester,
        const ThemeConfig(popupRadius: 8.0),
        const PopupCard(clip: false, child: SizedBox(width: 100, height: 100)),
      );
      expect(find.byType(ClipPath), findsNothing);
    });

    testWidgets('a rim fits inside a pinned width', (tester) async {
      // The sound popup pins minWidth == maxWidth == 240 and popup.dart
      // measures the laid-out content to hand GTK a size before the window
      // maps. The rim has to eat inward: if it grew the card instead, the
      // measured width would change and the edge-centred anchor placement
      // would put the popup half the error away from its button.
      await pumpCard(
        tester,
        const ThemeConfig(popupBorderWidth: 1.0),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 240),
          child: const PopupCard(
            child: SizedBox(height: 40, key: Key('content')),
          ),
        ),
      );
      expect(tester.getSize(find.byType(PopupCard)).width, 240.0);
      expect(tester.getSize(find.byKey(const Key('content'))).width, 238.0);
    });

    testWidgets('a card follows a live theme change', (tester) async {
      // Popup content is built once and captured in a WindowEntry builder, so
      // PopupCard must read the palette from context rather than take it as a
      // parameter — otherwise an open popup freezes at the theme it opened
      // with, which is the bug ThemeProvider exists to prevent.
      const child = SizedBox(width: 100, height: 100);
      await pumpCard(
        tester,
        const ThemeConfig(popupRadius: 8.0),
        const PopupCard(child: child),
      );
      expect(decorationOf(tester).borderRadius, BorderRadius.circular(8.0));

      await pumpCard(
        tester,
        const ThemeConfig(popupRadius: 20.0),
        const PopupCard(child: child),
      );
      expect(decorationOf(tester).borderRadius, BorderRadius.circular(20.0));
    });

    testWidgets('the shadow reaches the decoration the card paints',
        (tester) async {
      const child = SizedBox(width: 100, height: 100);
      await pumpCard(
        tester,
        const ThemeConfig(popupShadowBlur: 12.0, popupShadowOffsetY: 4.0),
        const PopupCard(child: child),
      );
      final shadows = decorationOf(tester).boxShadow!;
      expect(shadows, hasLength(1));
      expect(shadows.single.blurRadius, 12.0);
      expect(shadows.single.offset, const Offset(0, 4));
    });
  });

  group('the shadow', () {
    test('the default palette casts one', () {
      const theme = ThemeConfig();
      final shadow = popupShadow(theme)!;
      expect(shadow.color, theme.popupShadowColor);
      expect(shadow.blurRadius, 16.0);
      expect(shadow.spreadRadius, 0.0);
      expect(shadow.offset, const Offset(0, 6));
    });

    test('a transparent colour is the off switch', () {
      // Alpha, not a width, unlike the rim: a shadow carries no
      // BoxDecoration.padding for a Container to silently apply, so there is
      // nothing a zero-alpha shadow could shift.
      const theme = ThemeConfig(popupShadowColor: Color(0x00000000));
      expect(popupShadow(theme), isNull);
      expect(popupShadowInsets(theme), EdgeInsets.zero);
      expect(popupDecoration(theme: theme).boxShadow, isNull);
    });

    test('no geometry is no shadow', () {
      // Nothing to draw the card does not already cover, and a BoxShadow would
      // still cost a layer — and, worse, still grow every popup window.
      const theme = ThemeConfig(
        popupShadowBlur: 0.0,
        popupShadowSpread: 0.0,
        popupShadowOffsetX: 0.0,
        popupShadowOffsetY: 0.0,
      );
      expect(popupShadow(theme), isNull);
      expect(popupShadowInsets(theme), EdgeInsets.zero);
    });

    test('a null boxShadow rather than an empty list', () {
      // The same normalisation the radius gets, so a shadowless theme builds
      // exactly the decoration it did before shadows existed.
      const theme = ThemeConfig(popupShadowColor: Color(0x00000000));
      expect(popupDecoration(theme: theme).boxShadow, isNull);
    });

    test('a centred shadow reaches equally on every side', () {
      const theme = ThemeConfig(
        popupShadowBlur: 16.0,
        popupShadowSpread: 0.0,
        popupShadowOffsetX: 0.0,
        popupShadowOffsetY: 0.0,
      );
      expect(popupShadowInsets(theme), const EdgeInsets.all(16.0));
    });

    test('an offset shifts the reach without shrinking the total', () {
      const theme = ThemeConfig(
        popupShadowBlur: 16.0,
        popupShadowOffsetX: 4.0,
        popupShadowOffsetY: 6.0,
      );
      expect(
        popupShadowInsets(theme),
        const EdgeInsets.only(left: 12, right: 20, top: 10, bottom: 22),
      );
    });

    test('spread adds to the reach and a negative one takes it back', () {
      const grown = ThemeConfig(
        popupShadowBlur: 10.0,
        popupShadowSpread: 4.0,
        popupShadowOffsetY: 0.0,
      );
      expect(popupShadowInsets(grown), const EdgeInsets.all(14.0));

      const pulled = ThemeConfig(
        popupShadowBlur: 10.0,
        popupShadowSpread: -4.0,
        popupShadowOffsetY: 0.0,
      );
      expect(popupShadowInsets(pulled), const EdgeInsets.all(6.0));
    });

    test('a side the shadow leaves behind floors at zero', () {
      // Never negative: a strongly offset shadow must not crop the card itself
      // out of the window that was grown for it.
      const theme = ThemeConfig(
        popupShadowBlur: 4.0,
        popupShadowOffsetY: 30.0,
      );
      final insets = popupShadowInsets(theme);
      expect(insets.top, 0.0);
      expect(insets.bottom, 34.0);
    });
  });
}
