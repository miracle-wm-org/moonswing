import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/theme/builtin_themes.dart';
import 'package:toml/toml.dart';
import 'package:moonswing/scopes.dart';

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

/// [popupDecoration] answers a plain [Decoration] because an attached card that
/// paints outside its own box — a flared join — is a [ShapeDecoration]; every
/// case that is not is still a [BoxDecoration], and these read its fields.
BoxDecoration boxOf(Decoration decoration) => decoration as BoxDecoration;

BoxDecoration decorationOf(WidgetTester tester) =>
    tester.widget<Container>(find.byType(Container)).decoration
        as BoxDecoration;

void main() {
  group('the decoration', () {
    test('the default palette gives a rounded, rimmed card', () {
      const theme = ThemeConfig();
      final decoration = popupDecoration(theme: theme) as BoxDecoration;
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
      expect(boxOf(popupDecoration(theme: theme)).border, isNull);
    });

    group('attaching to a bar edge', () {
      // The join is squared off, for panelCornerRadius's reason one layer up:
      // there *is* a surface behind those two corners, and rounding them would
      // cut a wedge out of it. popup_attach_radius is not read here at all —
      // it is an outward flare, which no BorderRadius can express.
      const theme = ThemeConfig(popupRadius: 12.0);
      const far = Radius.circular(12.0);

      test('top', () {
        expect(popupCornerRadius(theme, attach: 'top'),
            const BorderRadius.only(bottomLeft: far, bottomRight: far));
      });

      test('bottom', () {
        expect(popupCornerRadius(theme, attach: 'bottom'),
            const BorderRadius.only(topLeft: far, topRight: far));
      });

      test('left', () {
        expect(popupCornerRadius(theme, attach: 'left'),
            const BorderRadius.only(topRight: far, bottomRight: far));
      });

      test('right', () {
        expect(popupCornerRadius(theme, attach: 'right'),
            const BorderRadius.only(topLeft: far, bottomLeft: far));
      });

      test('the join radius is not a corner radius', () {
        // Squared off whatever it says, because the flare is drawn by
        // AttachedPopupBorder instead.
        const flared = ThemeConfig(popupRadius: 12.0, popupAttachRadius: 8.0);
        expect(popupCornerRadius(flared, attach: 'top'),
            popupCornerRadius(theme, attach: 'top'));
      });

      test('square on all four sides normalises to zero', () {
        // Or the clip layer comes back for a card that has nothing to clip.
        const square = ThemeConfig(popupRadius: 0.0);
        expect(popupCornerRadius(square, attach: 'top'), BorderRadius.zero);
        expect(boxOf(popupDecoration(theme: square, attach: 'top')).borderRadius,
            isNull);
      });

      test('the rim on the join is dropped, and only that side', () {
        const rimmed = ThemeConfig(popupBorderWidth: 2.0);
        final side = BorderSide(color: rimmed.popupBorder, width: 2.0);
        expect(boxOf(popupDecoration(theme: rimmed, attach: 'top')).border,
            Border(left: side, right: side, bottom: side));
        expect(boxOf(popupDecoration(theme: rimmed, attach: 'left')).border,
            Border(top: side, right: side, bottom: side));
        // A hairline across the seam is the one thing that gives away that the
        // card is a second surface, so the joined side carries no rim at all.
        final border =
            boxOf(popupDecoration(theme: rimmed, attach: 'bottom')).border
                as Border;
        expect(border.bottom.style, BorderStyle.none);
        expect(border.top.width, 2.0);
      });

      test('a zero-width rim is still no Border at all', () {
        const none = ThemeConfig(popupBorderWidth: 0.0);
        expect(boxOf(popupDecoration(theme: none, attach: 'top')).border, isNull);
      });

      test('an explicit border still replaces all four sides', () {
        // PopupCard.border is the rim that carries meaning rather than chrome —
        // the kill confirmation's accent rim — and is not the theme's to strip.
        const accent = Border.fromBorderSide(
            BorderSide(color: Color(0xFFFF0000), width: 2));
        expect(
            boxOf(popupDecoration(
                    theme: const ThemeConfig(), border: accent, attach: 'top'))
                .border,
            accent);
      });

      testWidgets('a non-uniform rim under an asymmetric radius still paints',
          (tester) async {
        // BoxBorder.paint asserts that a borderRadius needs a uniform border, but
        // takes a paintNonUniformBorder path first when the *visible* sides share
        // one colour. That path is what the square-join card rests on, and it
        // refuses hairlines — which cannot arise, since no border is built below
        // a width of 0.
        for (final edge in ['top', 'bottom', 'left', 'right']) {
          await pumpCard(
            tester,
            const ThemeConfig(popupRadius: 12.0, popupBorderWidth: 1.0),
            PopupAttachScope(
              key: ValueKey(edge),
              edge: edge,
              child: const PopupCard(child: SizedBox(width: 80, height: 40)),
            ),
          );
          expect(tester.takeException(), isNull, reason: edge);
        }
      });
    });

    group('the flared join', () {
      // popup_attach_radius reads as a corner radius and is the opposite of one:
      // each side sweeps *outward* as it reaches the panel, so the card runs into
      // the bar rather than resting against it. That cannot be a BorderRadius,
      // hence the one ShapeDecoration in the shell.
      const flared = ThemeConfig(popupRadius: 12.0, popupAttachRadius: 10.0);
      const card = Rect.fromLTWH(100, 50, 200, 120);

      Path outlineFor(String edge, {double attachRadius = 10.0}) =>
          AttachedPopupBorder(
            edge: edge,
            radius: 12.0,
            attachRadius: attachRadius,
          ).getOuterPath(card);

      test('a flare makes the decoration a shape rather than a box', () {
        expect(popupDecoration(theme: flared, attach: 'top'),
            isA<ShapeDecoration>());
        // And only when there is something to draw outside the card's own box:
        // a square join against an unrimmed bar must cost exactly the
        // decoration it always did.
        expect(popupDecoration(theme: flared), isA<BoxDecoration>());
        expect(
            popupDecoration(
                theme: const ThemeConfig(popupRadius: 12.0), attach: 'top'),
            isA<BoxDecoration>());
      });

      test('the bar\'s rim never reaches the decoration', () {
        // The bar's inner rim is dealt with by the bar (see panel_rim.dart),
        // so nothing about the card's decoration changes when it is there. A
        // square join stays the plain box it is against an unrimmed bar, and a
        // flared one carries the flare and nothing else.
        const square = ThemeConfig(popupRadius: 12.0, panelBorderWidth: 1.0);
        expect(popupDecoration(theme: square, attach: 'top'),
            isA<BoxDecoration>());
        expect(popupDecoration(theme: square), isA<BoxDecoration>());

        const rimmedAndFlared = ThemeConfig(
          popupRadius: 12.0,
          popupAttachRadius: 10.0,
          panelBorderWidth: 1.0,
        );
        final shape =
            (popupDecoration(theme: rimmedAndFlared, attach: 'top')
                    as ShapeDecoration)
                .shape as AttachedPopupBorder;
        expect(
          shape,
          AttachedPopupBorder(
            edge: 'top',
            radius: 12.0,
            attachRadius: 10.0,
            side: BorderSide(
              color: rimmedAndFlared.popupBorder,
              width: rimmedAndFlared.popupBorderWidth,
            ),
          ),
          reason: 'the flare alone, with nothing added for the bar\'s rim',
        );
      });

      testWidgets('a square join against a rimmed bar paints without complaint',
          (tester) async {
        for (final edge in ['top', 'bottom', 'left', 'right']) {
          await pumpCard(
            tester,
            const ThemeConfig(
              popupRadius: 12.0,
              popupBorderWidth: 1.0,
              panelBorderWidth: 1.0,
            ),
            PopupAttachScope(
              key: ValueKey(edge),
              edge: edge,
              child: const PopupCard(child: SizedBox(width: 80, height: 40)),
            ),
          );
          expect(tester.takeException(), isNull, reason: edge);
        }
      });

      test('the shape carries the fill, the shadow and the rim', () {
        const rimmed = ThemeConfig(
          popupRadius: 12.0,
          popupAttachRadius: 10.0,
          popupBorderWidth: 2.0,
        );
        final decoration =
            popupDecoration(theme: rimmed, attach: 'top') as ShapeDecoration;
        expect(decoration.color, rimmed.popupBackground);
        expect(decoration.shadows, hasLength(1));
        final shape = decoration.shape as AttachedPopupBorder;
        expect(shape.edge, 'top');
        expect(shape.side.width, 2.0);
        // The join takes no rim inset, because no rim is drawn there.
        expect(shape.dimensions,
            const EdgeInsets.only(left: 2, right: 2, bottom: 2));
      });

      test('the flare bows outward, into the panel', () {
        // Right at the join the outline reaches a full attachRadius past the card
        // on both sides; a fraction of the way in it has already pulled back to
        // the card's own edge. The first is what makes the card meet the bar
        // wider than it is, the second is what keeps it from being a trapezoid.
        final top = outlineFor('top');
        expect(top.contains(const Offset(100 - 5, 50 + 0.2)), isTrue,
            reason: 'left ear at the join line');
        expect(top.contains(const Offset(300 + 5, 50 + 0.2)), isTrue,
            reason: 'right ear at the join line');
        expect(top.contains(const Offset(100 - 5, 50 + 9)), isFalse,
            reason: 'the flare has pulled back by nine tenths of its depth');
        expect(top.contains(const Offset(100 - 5, 50 - 1)), isFalse,
            reason: 'nothing is drawn past the join line');
      });

      test('the flare is on the joined edge, and only there', () {
        expect(outlineFor('bottom').contains(const Offset(100 - 5, 170 - 0.2)),
            isTrue);
        expect(outlineFor('bottom').contains(const Offset(100 - 5, 50 + 0.2)),
            isFalse);
        expect(outlineFor('left').contains(const Offset(100 + 0.2, 50 - 5)),
            isTrue);
        expect(outlineFor('right').contains(const Offset(300 - 0.2, 50 - 5)),
            isTrue);
        expect(outlineFor('right').contains(const Offset(100 + 0.2, 50 - 5)),
            isFalse);
      });

      test('the card itself is still inside its own outline', () {
        for (final edge in ['top', 'bottom', 'left', 'right']) {
          expect(outlineFor(edge).contains(card.center), isTrue, reason: edge);
          expect(outlineFor(edge).contains(card.topLeft + const Offset(20, 20)),
              isTrue,
              reason: edge);
        }
      });

      test('no flare falls back to the squared-off rounded rect', () {
        final none = outlineFor('top', attachRadius: 0);
        expect(none.contains(const Offset(100 - 1, 50 + 0.2)), isFalse);
        // The join corners are square, so the very corner is inside — which a
        // rounded one would not be.
        expect(none.contains(const Offset(100 + 0.5, 50 + 0.5)), isTrue);
        expect(none.contains(const Offset(100 + 0.5, 170 - 0.5)), isFalse,
            reason: 'the far corners are still rounded');
      });

      test('the rim encloses nothing the outline does not', () {
        // getInnerPath is contract-only — ShapeDecoration fills the outer path
        // and paint draws the rim from it — but an inner path that escaped its
        // own outline is exactly what a later ShapeBorderClipper would trip on.
        const border = AttachedPopupBorder(
          edge: 'top',
          radius: 12.0,
          attachRadius: 10.0,
          side: BorderSide(width: 2.0),
        );
        final outer = border.getOuterPath(card);
        final inner = border.getInnerPath(card);
        expect(inner.getBounds().width, lessThan(outer.getBounds().width));
        // Walked around the inner outline rather than sampled at a few
        // corners, so a single arc going the wrong way cannot slip through.
        for (final metric in inner.computeMetrics()) {
          for (var t = 0.0; t <= 1.0; t += 1 / 64) {
            final at = metric.getTangentForOffset(metric.length * t)!.position;
            expect(outer.contains(at), isTrue, reason: '$at is outside');
          }
        }
      });

      test('nothing is drawn past the join line, on any edge', () {
        // The bar's rim is the bar's to leave out — the compositor places the
        // card below the panel, so there is nothing for the outline to reach
        // for. An outline that went further would be a band of the card's
        // colour laid over the bar's *body*, a seam of its own wherever the two
        // fills differ, and it would need surface margin that, with no
        // input-region support, swallows clicks.
        //
        // card is LTWH(100, 50, 200, 120): left 100, top 50, right 300,
        // bottom 170.
        Path joined(String edge) => AttachedPopupBorder(
              edge: edge,
              radius: 12.0,
              attachRadius: 10.0,
            ).getOuterPath(card);
        expect(joined('top').getBounds().top, 50.0);
        expect(joined('bottom').getBounds().bottom, 170.0);
        expect(joined('left').getBounds().left, 100.0);
        expect(joined('right').getBounds().right, 300.0);
        expect(joined('top').contains(const Offset(200, 49)), isFalse);
        expect(joined('bottom').contains(const Offset(200, 171)), isFalse);
        expect(joined('left').contains(const Offset(99, 110)), isFalse);
        expect(joined('right').contains(const Offset(301, 110)), isFalse);
      });

      test('the flare is clamped to what the card can carry', () {
        // A flare deeper than what is left below the far corners would run the
        // ears into them; a radius past half the card would have the far
        // corners overrun each other. Neither may throw or self-intersect.
        const tiny = Rect.fromLTWH(0, 0, 40, 20);
        const border = AttachedPopupBorder(
            edge: 'top', radius: 60.0, attachRadius: 90.0);
        final path = border.getOuterPath(tiny);
        expect(path.contains(const Offset(20, 10)), isTrue);
        expect(path.getBounds().height, lessThanOrEqualTo(20.0));
      });
    });

    group('the surface margin', () {
      test('a flare reaches past the card on the two sides that meet the join',
          () {
        const flared = ThemeConfig(popupAttachRadius: 10.0);
        expect(popupAttachInsets(flared, attachEdge: 'top'),
            const EdgeInsets.symmetric(horizontal: 10));
        expect(popupAttachInsets(flared, attachEdge: 'bottom'),
            const EdgeInsets.symmetric(horizontal: 10));
        expect(popupAttachInsets(flared, attachEdge: 'left'),
            const EdgeInsets.symmetric(vertical: 10));
        expect(popupAttachInsets(flared, attachEdge: 'right'),
            const EdgeInsets.symmetric(vertical: 10));
      });

      test('a floating card reaches nowhere, and neither does a bare join', () {
        const flared = ThemeConfig(popupAttachRadius: 10.0);
        expect(popupAttachInsets(flared), EdgeInsets.zero);
        // A square butt join: no flare to reach out with and nothing drawn past
        // the join, so the surface is exactly the card.
        expect(popupAttachInsets(const ThemeConfig(), attachEdge: 'top'),
            EdgeInsets.zero);
      });

      test('a rimmed bar asks for no surface margin at all', () {
        // The bar's rim is nothing the card can reach — the compositor places
        // the popup below the panel — so it is the panel that leaves that line
        // out across the mouth, and a rimmed bar leaves an attached popup's
        // surface exactly where an unrimmed one does. Margin nothing draws in is
        // margin that swallows clicks, with no input-region support to stop it.
        const square = ThemeConfig(panelBorderWidth: 2.0);
        for (final edge in ['top', 'bottom', 'left', 'right']) {
          expect(popupAttachInsets(square, attachEdge: edge), EdgeInsets.zero,
              reason: edge);
        }

        const flared =
            ThemeConfig(popupAttachRadius: 10.0, panelBorderWidth: 2.0);
        expect(popupAttachInsets(flared, attachEdge: 'top'),
            const EdgeInsets.symmetric(horizontal: 10));
        expect(popupAttachInsets(flared, attachEdge: 'bottom'),
            const EdgeInsets.symmetric(horizontal: 10));
        expect(popupAttachInsets(flared, attachEdge: 'left'),
            const EdgeInsets.symmetric(vertical: 10));
        expect(popupAttachInsets(flared, attachEdge: 'right'),
            const EdgeInsets.symmetric(vertical: 10));
      });

      test('the joined side takes no margin from either source', () {
        // popupSurfaceInsets takes the per-side larger of the shadow's reach and
        // the flare's, and on the joined side both are 0: the shadow has been
        // clamped to popup_gap, which attaching means is 0, and the flare
        // reaches only sideways. That is what leaves an attached surface flush
        // with the bar, so the compositor's own clip cuts it exactly at the
        // join.
        const flared = ThemeConfig(
          popupAttachRadius: 10.0,
          panelBorderWidth: 2.0,
          popupShadowBlur: 16.0,
        );
        final shadow = popupShadowInsets(flared, attachEdge: 'top');
        final surface = popupSurfaceInsets(
          shadow,
          popupAttachInsets(flared, attachEdge: 'top'),
        );
        expect(shadow.top, 0.0,
            reason: 'the shadow is cut at the join, so it contests nothing');
        expect(surface.top, 0.0);
        expect(surface.left, 16.0, reason: 'the flare loses to a wider shadow');
        expect(surface.bottom, shadow.bottom,
            reason: 'and the shadow still owns every side the join does not');
        expect(surface.bottom, greaterThan(0));
      });

      test('the surface takes the larger of the two, never the sum', () {
        // Both measure the same thing — how far past the card something paints —
        // and the flare is part of the card's own silhouette, so the shadow around
        // it is one the card already casts. Summing would push every attached
        // window out by a margin nothing draws in, which then swallows clicks.
        const shadow = EdgeInsets.only(left: 16, right: 16, top: 0, bottom: 22);
        const flare = EdgeInsets.symmetric(horizontal: 10);
        expect(popupSurfaceInsets(shadow, flare), shadow);
        expect(
            popupSurfaceInsets(shadow, const EdgeInsets.symmetric(horizontal: 30)),
            const EdgeInsets.only(left: 30, right: 30, top: 0, bottom: 22));
      });

      test('no flare hands the shadow straight back', () {
        const shadow = EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 22);
        expect(popupSurfaceInsets(shadow, EdgeInsets.zero), same(shadow));
      });
    });

    test('no radius means no borderRadius to build a clip from', () {
      const theme = ThemeConfig(popupRadius: 0.0);
      expect(popupCornerRadius(theme), BorderRadius.zero);
      expect(boxOf(popupDecoration(theme: theme)).borderRadius, isNull);
    });

    test(
      'the border override replaces the theme rim rather than adding to it',
      () {
        const theme = ThemeConfig(popupBorderWidth: 1.0);
        final override = Border.all(color: const Color(0xFFFF0000), width: 1.5);
        final decoration =
            boxOf(popupDecoration(theme: theme, border: override));
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
      // The sound popup pins minWidth == maxWidth == 240 and popup.dart measures
      // the laid-out content to hand GTK a size before the window maps. The rim
      // has to eat inward: growing the card instead would change the measured
      // width and put the popup half the error away from its button.
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
      expect(boxOf(popupDecoration(theme: theme)).boxShadow, isNull);
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
      expect(boxOf(popupDecoration(theme: theme)).boxShadow, isNull);
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

    group('an attached bar popup', () {
      // The joined side is clamped to the gap, so the surface reaches from the
      // card to the panel edge and no further and the compositor's own clip
      // cuts the shadow at the join.
      const theme = ThemeConfig(
        popupShadowBlur: 16.0,
        popupShadowOffsetY: 6.0,
      );

      test('a zero gap zeroes the joined side and nothing else', () {
        final floating = popupShadowInsets(theme);
        expect(floating, const EdgeInsets.only(
            left: 16, right: 16, top: 10, bottom: 22));

        expect(popupShadowInsets(theme, attachEdge: 'top'),
            floating.copyWith(top: 0));
        expect(popupShadowInsets(theme, attachEdge: 'bottom'),
            floating.copyWith(bottom: 0));
        expect(popupShadowInsets(theme, attachEdge: 'left'),
            floating.copyWith(left: 0));
        expect(popupShadowInsets(theme, attachEdge: 'right'),
            floating.copyWith(right: 0));
      });

      test('a gap under the reach lets the shadow fill it and stop', () {
        const gapped = ThemeConfig(
          popupShadowBlur: 16.0,
          popupShadowOffsetY: 6.0,
          popupGap: 4.0,
        );
        // top reaches 10, so it is clamped; bottom reaches 22 and is too.
        expect(popupShadowInsets(gapped, attachEdge: 'top').top, 4.0);
        expect(popupShadowInsets(gapped, attachEdge: 'bottom').bottom, 4.0);
        // The other sides are untouched either way.
        expect(popupShadowInsets(gapped, attachEdge: 'top').bottom, 22.0);
      });

      test('a gap past the reach is a no-op', () {
        const floaty = ThemeConfig(
          popupShadowBlur: 16.0,
          popupShadowOffsetY: 6.0,
          popupGap: 40.0,
        );
        for (final edge in ['top', 'bottom', 'left', 'right']) {
          expect(popupShadowInsets(floaty, attachEdge: edge),
              popupShadowInsets(floaty),
              reason: edge);
        }
      });

      test('no attach edge is byte-for-byte what it always was', () {
        // Every popup that is not a bar popup — the desktop's context menu, the
        // dock's unpin menu, the app-directory flyout, the OSD — goes through
        // the one-argument call, and must not have moved.
        for (final name in kBuiltInThemes.keys) {
          final t = ThemeConfig.fromMap(
              TomlDocument.parse(kBuiltInThemes[name]!).toMap());
          expect(popupShadowInsets(t, attachEdge: null), popupShadowInsets(t),
              reason: name);
        }
      });

      test('a shadowless theme stays shadowless', () {
        const none = ThemeConfig(popupShadowColor: Color(0x00000000));
        expect(popupShadowInsets(none, attachEdge: 'top'), EdgeInsets.zero);
      });
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
