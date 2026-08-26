// The Tux desktop widget: the three arrangements, the lease, the tap, and the
// promise that nothing on the card animates by itself.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/desktop/widgets/tux_widget.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/tux/tux_art.dart';
import 'package:graceful_shell/tux/tux_greetings.dart';
import 'package:graceful_shell/tux/tux_store.dart';

/// 1x1 on the default grid, which is the size this widget is *for*.
const Size _oneByOne = Size(96, 96);

/// 3x2 on the default grid — `3*96 + 2*12` by `2*96 + 12`.
const Size _threeByTwo = Size(312, 204);

final DateTime _today = DateTime(2026, 8, 26, 9);

TuxStore _store({DateTime? day, String name = ''}) {
  final on = day ?? _today;
  final store = TuxStore.forTesting(now: () => on, name: name);
  addTearDown(store.dispose);
  return store;
}

Future<void> pumpTux(
  WidgetTester tester,
  Widget child, {
  Size size = _threeByTwo,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Widget _widget(TuxStore store, {(int, int) span = (3, 2)}) =>
    TuxWidget(span: (columns: span.$1, rows: span.$2), store: store);

/// The greeting the store is showing, as the wide layouts set it: salutation
/// and line as two separate `Text`s.
Finder _text(String value) => find.text(value);

void main() {
  group('the layout it takes', () {
    test('is chosen by span, not by pixels', () {
      expect(TuxLayout.forSpan((columns: 1, rows: 1)), TuxLayout.portrait);
      expect(TuxLayout.forSpan((columns: 1, rows: 3)), TuxLayout.portrait);
      expect(TuxLayout.forSpan((columns: 2, rows: 1)), TuxLayout.beside);
      expect(TuxLayout.forSpan((columns: 4, rows: 1)), TuxLayout.beside);
      expect(TuxLayout.forSpan((columns: 2, rows: 2)), TuxLayout.stacked);
      expect(TuxLayout.forSpan((columns: 4, rows: 3)), TuxLayout.stacked);
    });
  });

  group('the card', () {
    testWidgets('draws Tux at every span the registry allows', (tester) async {
      for (final span in const [(1, 1), (2, 1), (2, 2), (4, 3)]) {
        await pumpTux(tester, _widget(_store(), span: span));
        expect(find.byType(TuxArt), findsOneWidget, reason: 'span $span');
        // Scaling properly is the whole reason he is a vector: one drawing,
        // fitted to whatever box the grid hands over.
        final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
        expect(picture.fit, BoxFit.contain, reason: 'span $span');
      }
    });

    testWidgets('says the nice thing beside him at two cells', (tester) async {
      final store = _store(name: 'Sam');
      await pumpTux(tester, _widget(store, span: (2, 1)),
          size: const Size(204, 96));

      final greeting = store.greeting;
      expect(_text(greeting.salutation), findsOneWidget);
      expect(_text(greeting.line), findsOneWidget);
      expect(greeting.salutation, endsWith(', Sam'));
    });

    testWidgets('says it under him at two cells by two', (tester) async {
      final store = _store();
      await pumpTux(tester, _widget(store, span: (3, 2)));

      expect(_text(store.greeting.salutation), findsOneWidget);
      expect(_text(store.greeting.line), findsOneWidget);

      // Under, not beside: the drawing's box starts above the greeting's.
      final tux = tester.getRect(find.byType(TuxArt));
      final line = tester.getRect(_text(store.greeting.line));
      expect(tux.bottom, lessThanOrEqualTo(line.top));
    });

    testWidgets('holds the greeting back until hovered at 1x1',
        (tester) async {
      // A 96px square holds a picture or a sentence and not both. The line is
      // *built* either way — this is an opacity, so a test that looked for the
      // widget would pass with it invisible — so assert on what is painted.
      final store = _store();
      await pumpTux(tester, _widget(store, span: (1, 1)), size: _oneByOne);

      expect(find.byType(TuxArt), findsOneWidget);
      expect(_text(store.greeting.combined), findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(find.ancestor(
          of: _text(store.greeting.combined),
          matching: find.byType(AnimatedOpacity),
        )).opacity,
        0,
      );
    });

    testWidgets('reveals it on hover at 1x1', (tester) async {
      final store = _store();
      await pumpTux(tester, _widget(store, span: (1, 1)), size: _oneByOne);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(tester.getCenter(find.byType(TuxArt)));
      await tester.pumpAndSettle();

      expect(
        tester.widget<AnimatedOpacity>(find.ancestor(
          of: _text(store.greeting.combined),
          matching: find.byType(AnimatedOpacity),
        )).opacity,
        1,
      );
    });
  });

  group('the lease', () {
    testWidgets('is taken and released with the widget lifetime',
        (tester) async {
      final store = _store();
      await pumpTux(tester, _widget(store));
      expect(store.leaseCount, 1);
      expect(store.waitingForRollover, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(store.leaseCount, 0);
      // The card is gone, so nothing is left waiting for midnight.
      expect(store.waitingForRollover, isFalse);
    });

    testWidgets('moves when the store does', (tester) async {
      final first = _store();
      final second = _store();

      await pumpTux(tester, _widget(first));
      expect(first.leaseCount, 1);

      await pumpTux(tester, _widget(second));
      expect(first.leaseCount, 0);
      expect(second.leaseCount, 1);
    });
  });

  group('tapping him', () {
    testWidgets('asks for another line', (tester) async {
      final store = _store();
      await pumpTux(tester, _widget(store));
      final first = store.greeting.line;

      await tester.tap(find.byType(TuxArt));
      await tester.pump();

      expect(store.offset, 1);
      expect(store.greeting.line, isNot(first));
      expect(_text(store.greeting.line), findsOneWidget);
    });

    testWidgets('works at 1x1, where he is the whole card', (tester) async {
      final store = _store();
      await pumpTux(tester, _widget(store, span: (1, 1)), size: _oneByOne);

      await tester.tapAt(const Offset(48, 48));
      await tester.pump();
      expect(store.offset, 1);
    });

    testWidgets('is a tap and not a pan, so the card stays draggable',
        (tester) async {
      // The desktop grid drags a widget from anywhere on its card, and the two
      // recognizers resolve against each other: a press that moves is the drag.
      // A `TuxWidget` that claimed the pan would pin itself to the desktop.
      var pans = 0;
      final store = _store();
      await pumpTux(
        tester,
        GestureDetector(
          onPanUpdate: (_) => pans++,
          child: _widget(store),
        ),
      );

      await tester.drag(find.byType(TuxArt), const Offset(60, 0));
      await tester.pump();

      expect(pans, greaterThan(0));
      expect(store.offset, 0, reason: 'a drag is not a tap');
    });

    testWidgets('leaves the card draggable at 1x1 too', (tester) async {
      // The portrait layout's hover region covers the whole card, which is the
      // one place a widget could accidentally swallow the grid's drag.
      var pans = 0;
      final store = _store();
      await pumpTux(
        tester,
        GestureDetector(
          onPanUpdate: (_) => pans++,
          child: _widget(store, span: (1, 1)),
        ),
        size: _oneByOne,
      );

      await tester.dragFrom(const Offset(48, 48), const Offset(50, 0));
      await tester.pump();

      expect(pans, greaterThan(0));
      expect(store.offset, 0);
    });
  });

  group('the day turning over', () {
    testWidgets('replaces the line without being rebuilt from above',
        (tester) async {
      var day = _today;
      final store = TuxStore.forTesting(now: () => day);
      addTearDown(store.dispose);

      await pumpTux(tester, _widget(store));
      final yesterday = store.greeting.line;
      expect(_text(yesterday), findsOneWidget);

      day = DateTime(2026, 8, 27, 0, 0, 1);
      store.rollOverNow();
      await tester.pump();

      expect(_text(yesterday), findsNothing);
      expect(_text(greetingForDay(day).line), findsOneWidget);
    });

    testWidgets('brings back the day\'s own line after taps', (tester) async {
      var day = _today;
      final store = TuxStore.forTesting(now: () => day);
      addTearDown(store.dispose);

      await pumpTux(tester, _widget(store));
      await tester.tap(find.byType(TuxArt));
      await tester.pump();
      expect(store.offset, 1);

      day = DateTime(2026, 8, 27, 0, 0, 1);
      store.rollOverNow();
      await tester.pump();

      expect(store.offset, 0);
      expect(_text(greetingForDay(day).line), findsOneWidget);
    });
  });

  group('nothing on the card animates', () {
    testWidgets('it settles, and leaves no ticker behind', (tester) async {
      // The lunar and fortune cards' rule, and this one changes once a day. A
      // `Ticker` added anywhere in here hangs this test rather than failing it.
      await pumpTux(tester, _widget(_store()));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);

      await pumpTux(tester, _widget(_store(), span: (1, 1)), size: _oneByOne);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('the registry entry', () {
    test('is what the "Add widget…" menu needs', () {
      expect(tuxDesktopWidget.type, 'tux');
      expect(tuxDesktopWidget.name, 'Tux');
      expect(tuxDesktopWidget.icon, tuxDesktopWidgetIcon);
      expect(tuxDesktopWidget.description, isNotEmpty);
    });

    test('fits, and defaults to, a 1x1 square', () {
      expect(tuxDesktopWidget.minSpan, (columns: 1, rows: 1));
      expect(tuxDesktopWidget.defaultSpan, (columns: 1, rows: 1));
    });

    test('paints to the rim, and insets per layout instead', () {
      expect(tuxDesktopWidget.padding, EdgeInsets.zero);
    });

    test('clamps a span authored outside its limits', () {
      const item = DesktopWidgetItem(
        id: 'tux-1',
        type: 'tux',
        column: 0,
        row: 0,
        columnSpan: 12,
        rowSpan: 12,
      );
      expect(spanFor(tuxDesktopWidget, item), tuxDesktopWidget.maxSpan);
    });

    test('builds', () {
      expect(
        tuxDesktopWidget.builder,
        isA<Widget Function(BuildContext, DesktopWidgetContext)>(),
      );
    });
  });

  group('the drawing', () {
    test('carries a viewBox and no fixed size', () {
      // `TuxArt` fits it into whatever box the grid gives it, which a root
      // `width`/`height` would argue with.
      expect(kTuxSvg, contains('viewBox='));
      expect(kTuxSvg, isNot(contains('<svg width=')));
      expect(RegExp(r'<svg[^>]*\sheight=').hasMatch(kTuxSvg), isFalse);
    });

    test('carries no stylesheet and nothing that animates', () {
      // `flutter_svg` logs `unhandled element <style/>` for every one it parses
      // and drops SMIL silently — `weather_icons.dart` picks a whole icon
      // family to avoid the first of those.
      expect(kTuxSvg, isNot(contains('<style')));
      expect(kTuxSvg, isNot(contains('<animate')));
      expect(kTuxSvg, isNot(contains('<script')));
    });

    testWidgets('parses', (tester) async {
      // The one thing a string constant cannot be checked for by reading it.
      await tester.runAsync(() async {
        final loader = SvgStringLoader(kTuxSvg);
        final picture = await vg.loadPicture(loader, null);
        expect(picture.size.width, greaterThan(0));
        expect(picture.size.height, greaterThan(0));
        picture.picture.dispose();
      });
    });
  });
}
