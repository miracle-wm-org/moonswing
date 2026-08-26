import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';

/// `glassy`'s own `popup_background`: the alpha this whole mechanism is about.
const _translucent = ThemeConfig(popupBackground: Color(0xB0141821));

Widget _host(Widget child, {required bool opaque}) {
  final tree = ThemeScope(theme: _translucent, child: Center(child: child));
  return Directionality(
    textDirection: TextDirection.ltr,
    child: opaque ? OpaquePopupScope(child: tree) : tree,
  );
}

BoxDecoration _cardDecoration(WidgetTester tester) =>
    tester.widget<Container>(find.byType(Container).first).decoration
        as BoxDecoration;

void main() {
  group('the fill', () {
    test('a translucent palette keeps its hue and loses its alpha', () {
      expect(opaquePopupFill(_translucent), const Color(0xFF141821));
    });

    test('an opaque palette is passed through unchanged', () {
      const theme = ThemeConfig(popupBackground: Color(0xFF2C2C2C));
      expect(opaquePopupFill(theme), const Color(0xFF2C2C2C));
    });

    test('a fully transparent palette still fills', () {
      const theme = ThemeConfig(popupBackground: Color(0x00141821));
      expect(opaquePopupFill(theme).a, 1.0);
    });

    test('the decoration overrides the alpha and nothing else', () {
      // A popup that floats is still a BoxDecoration; only an attached card
      // with a flared join is a ShapeDecoration.
      final plain = popupDecoration(theme: _translucent) as BoxDecoration;
      final opaque =
          popupDecoration(theme: _translucent, opaque: true) as BoxDecoration;
      expect(plain.color, _translucent.popupBackground);
      expect(opaque.color, const Color(0xFF141821));
      // The rim, the rounding and the shadow are the theme's either way.
      expect(opaque.border, plain.border);
      expect(opaque.borderRadius, plain.borderRadius);
      expect(opaque.boxShadow, plain.boxShadow);
    });
  });

  group('the scope', () {
    testWidgets('no scope leaves a popup the theme\'s alpha', (tester) async {
      await tester.pumpWidget(
        _host(const PopupCard(child: SizedBox(width: 20, height: 20)),
            opaque: false),
      );
      expect(_cardDecoration(tester).color, _translucent.popupBackground);
    });

    testWidgets('a card inside the scope paints opaque', (tester) async {
      await tester.pumpWidget(
        _host(const PopupCard(child: SizedBox(width: 20, height: 20)),
            opaque: true),
      );
      expect(_cardDecoration(tester).color, const Color(0xFF141821));
    });

    testWidgets('the scope reaches an OverlayEntry built under it',
        (tester) async {
      // The path every settings popup actually takes: `showRootModal` and
      // `AnchoredSearchDropdown` insert into the window's root Overlay, which
      // `SettingsOverlay` wraps in the scope. A scope placed *inside* the
      // panel instead would leave every one of those cards translucent.
      await tester.pumpWidget(
        _host(
          Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => const Center(
                  child: PopupCard(child: SizedBox(width: 20, height: 20)),
                ),
              ),
            ],
          ),
          opaque: true,
        ),
      );
      expect(
        tester
            .widget<Container>(find.ancestor(
              of: find.byType(SizedBox).last,
              matching: find.byType(Container),
            ))
            .decoration,
        isA<BoxDecoration>()
            .having((d) => d.color, 'color', const Color(0xFF141821)),
      );
    });

    testWidgets('fill answers for a hand-rolled surface', (tester) async {
      late Color plain;
      late Color opaque;
      await tester.pumpWidget(_host(
        Builder(builder: (context) {
          opaque = OpaquePopupScope.fill(context, _translucent);
          return const SizedBox.shrink();
        }),
        opaque: true,
      ));
      await tester.pumpWidget(_host(
        Builder(builder: (context) {
          plain = OpaquePopupScope.fill(context, _translucent);
          return const SizedBox.shrink();
        }),
        opaque: false,
      ));
      expect(opaque, const Color(0xFF141821));
      expect(plain, _translucent.popupBackground);
    });
  });
}
