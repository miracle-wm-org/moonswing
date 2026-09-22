import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';

/// A bar popup's card is built once and captured in a `WindowEntry` builder, in a
/// FlutterView that is a *sibling* of the panel's, so it cannot read the panel's
/// `BarScope`. [PopupAttachScope] is how the joined edge reaches it, and these pin
/// what a card does with it — the only half of the attached mode observable
/// without a compositor.

/// A square join: the default, and the shape `moonswing` and `dracula` ship.
const _square = ThemeConfig(popupRadius: 12.0, popupBorderWidth: 1.0);

/// A flared join, which is a different kind of decoration entirely.
const _flared = ThemeConfig(
  popupRadius: 12.0,
  popupAttachRadius: 8.0,
  popupBorderWidth: 1.0,
);

/// A square join against a bar that carries a rim of its own — the shape a user
/// gets by taking the default theme and switching `panel_border_width` on.
const _rimmedBar = ThemeConfig(
  popupRadius: 12.0,
  popupBorderWidth: 1.0,
  panelBorderWidth: 1.0,
);

Widget _host(Widget card, {String? attach, ThemeConfig theme = _square}) {
  final tree = ThemeScope(theme: theme, child: Center(child: card));
  return Directionality(
    textDirection: TextDirection.ltr,
    child: attach == null
        ? tree
        // Keyed so a test that pumps several edges in a row gets a fresh
        // element each time: the scope deliberately does not notify on a
        // change, because a popup's attachment is snapshotted at open and
        // GTK3 resolves the placement once at map time.
        : PopupAttachScope(
            key: ValueKey(attach), edge: attach, child: tree),
  );
}

Decoration _cardDecoration(WidgetTester tester) =>
    tester.widget<Container>(find.byType(Container).first).decoration!;

const _card = PopupCard(child: SizedBox(width: 60, height: 30));

void main() {
  testWidgets('a card outside any scope floats', (tester) async {
    // Every popup anchored to the pointer, and every card pumped bare in a
    // test, keeps the shape it always had.
    await tester.pumpWidget(_host(_card));
    final decoration = _cardDecoration(tester) as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(12.0));
    expect(decoration.border,
        Border.all(color: _square.popupBorder, width: 1.0));
  });

  testWidgets('a card under a scope squares the join and drops its rim',
      (tester) async {
    await tester.pumpWidget(_host(_card, attach: 'top'));
    final decoration = _cardDecoration(tester) as BoxDecoration;
    expect(
      decoration.borderRadius,
      const BorderRadius.only(
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
    );
    final border = decoration.border! as Border;
    expect(border.top.style, BorderStyle.none);
    expect(border.bottom.width, 1.0);
  });

  testWidgets('the edge the scope names is the edge that joins', (tester) async {
    for (final edge in ['top', 'bottom', 'left', 'right']) {
      await tester.pumpWidget(_host(_card, attach: edge));
      final border = (_cardDecoration(tester) as BoxDecoration).border! as Border;
      final joined = switch (edge) {
        'top' => border.top,
        'bottom' => border.bottom,
        'left' => border.left,
        _ => border.right,
      };
      expect(joined.style, BorderStyle.none, reason: edge);
      // And exactly one side is missing — a card with two open sides would be
      // a rim that reads as a mistake rather than as a join.
      final missing = [border.top, border.bottom, border.left, border.right]
          .where((s) => s.style == BorderStyle.none);
      expect(missing, hasLength(1), reason: edge);
    }
  });

  testWidgets('a flared join reaches the card as a shape', (tester) async {
    for (final edge in ['top', 'bottom', 'left', 'right']) {
      await tester.pumpWidget(_host(_card, attach: edge, theme: _flared));
      final shape =
          (_cardDecoration(tester) as ShapeDecoration).shape
              as AttachedPopupBorder;
      expect(shape.edge, edge);
      expect(shape.attachRadius, 8.0);
      expect(tester.takeException(), isNull, reason: edge);
    }
  });

  testWidgets('a rimmed bar changes nothing about the card', (tester) async {
    // A panel's rim is drawn along its *inner* edge too, so a bar that carries
    // one puts a hairline straight across the mouth of every menu it opens. The
    // card cannot cover it — the compositor places the popup below the bar — so
    // the panel leaves that stretch of its own rim unpainted instead, which is
    // `panel_rim.dart`'s job and `test/panel_rim_test.dart`'s to pin. What this
    // pins is the other half: the decoration is the plain square-joined box it
    // is against an unrimmed bar, because the card paints nothing outside its
    // own box for the bar's sake.
    for (final edge in ['top', 'bottom', 'left', 'right']) {
      await tester.pumpWidget(_host(_card, attach: edge, theme: _rimmedBar));
      expect(_cardDecoration(tester), isA<BoxDecoration>(), reason: edge);
      expect(tester.takeException(), isNull, reason: edge);
    }
  });

  testWidgets('an unrimmed bar leaves the square card exactly as it was',
      (tester) async {
    // Nothing paints outside the card, so the decoration is the plain box it has
    // always been. This is what keeps `moonswing` and `dracula` — both attached,
    // both square — byte-identical.
    await tester.pumpWidget(_host(_card, attach: 'top'));
    expect(_cardDecoration(tester), isA<BoxDecoration>());
  });

  testWidgets('a rimmed bar still floats where nothing is attached',
      (tester) async {
    // The reach into the panel is the join's, and a popup anchored to the
    // pointer has none.
    await tester.pumpWidget(_host(_card, theme: _rimmedBar));
    final decoration = _cardDecoration(tester) as BoxDecoration;
    expect(decoration.border,
        Border.all(color: _rimmedBar.popupBorder, width: 1.0));
  });

  testWidgets('a flared theme still floats where nothing is attached',
      (tester) async {
    // popup_attach_radius is read only at a join. A popup anchored to the
    // pointer under the same theme is the card it always was.
    await tester.pumpWidget(_host(_card, theme: _flared));
    expect(_cardDecoration(tester), isA<BoxDecoration>());
  });

  testWidgets('an explicit border survives the scope', (tester) async {
    // PopupCard.border is the rim that carries meaning rather than chrome —
    // the kill confirmation's accent rim — and attaching is not its business.
    const accent =
        Border.fromBorderSide(BorderSide(color: Color(0xFFFF0000), width: 2));
    await tester.pumpWidget(_host(
      const PopupCard(border: accent, child: SizedBox(width: 60, height: 30)),
      attach: 'top',
    ));
    expect((_cardDecoration(tester) as BoxDecoration).border, accent);
  });

  testWidgets('a fully square attached card builds no clip layer',
      (tester) async {
    // The normalisation popupCornerRadius carries: a card with nothing to clip
    // must cost exactly the layers it did before corners were themable.
    await tester.pumpWidget(_host(
      _card,
      attach: 'top',
      theme: const ThemeConfig(popupRadius: 0.0),
    ));
    final card = tester.widget<Container>(find.byType(Container).first);
    expect((card.decoration! as BoxDecoration).borderRadius, isNull);
    expect(card.clipBehavior, Clip.none);
  });

  testWidgets('a flared card always clips, because its flare is its silhouette',
      (tester) async {
    await tester.pumpWidget(_host(_card, attach: 'top', theme: _flared));
    expect(tester.widget<Container>(find.byType(Container).first).clipBehavior,
        Clip.antiAlias);
  });
}
