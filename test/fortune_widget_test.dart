// The fortune desktop widget: what it shows before, during and after a fetch,
// and the two ways of asking for another one.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/desktop/widgets/fortune_widget.dart';
import 'package:graceful_shell/fortune/fortune_reader.dart';
import 'package:graceful_shell/fortune/fortune_store.dart';
import 'package:graceful_shell/fortune/lamp_scene.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/scopes.dart';

const Size _card = Size(320, 200);

/// A store whose reader answers with each of [texts] in turn.
FortuneStore _store(List<String> texts) {
  var calls = 0;
  final store = FortuneStore.forTesting(
    reader: FortuneReader(runner: (_, _) async {
      final text = texts[calls.clamp(0, texts.length - 1)];
      calls++;
      return ProcessResult(0, 0, '$text\n', '');
    }),
  );
  addTearDown(store.dispose);
  return store;
}

/// A store with no `fortune` on the machine at all.
FortuneStore _missing() {
  final store = FortuneStore.forTesting(
    reader: FortuneReader(
      runner: (_, _) async => throw const ProcessException('fortune', []),
    ),
  );
  addTearDown(store.dispose);
  return store;
}

Future<void> pumpFortune(
  WidgetTester tester,
  Widget child, {
  Size size = _card,
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
  // Two pumps rather than `pumpAndSettle`: the fetch lands in a microtask, and
  // the loader the card can show before the first one arrives is a
  // `SpinKitRing`, which never settles. Once a fortune is on screen the card
  // itself settles — `nothing on the card animates` below pins that.
  await tester.pump();
  await tester.pump();
}

/// The widget as the card builds it. There is no `animate` flag to turn off:
/// nothing on this card moves.
Widget _widget(FortuneStore store, {GridSpanArg span = const (3, 2)}) =>
    FortuneWidget(span: (columns: span.$1, rows: span.$2), store: store);

typedef GridSpanArg = (int, int);

void main() {
  group('the fortune desktop widget', () {
    testWidgets('takes and releases a lease with its lifetime', (tester) async {
      final store = _store(['A lease is a fork.']);

      await pumpFortune(tester, _widget(store));
      expect(store.leaseCount, 1);

      await pumpFortune(tester, const SizedBox.shrink());
      expect(store.leaseCount, 0);
    });

    testWidgets('fetches a fortune when the desktop first draws it',
        (tester) async {
      // The "when you start the shell" half: nothing else asks for one.
      final store = _store(['The lamp is lit.']);

      await pumpFortune(tester, _widget(store));

      expect(find.text('The lamp is lit.'), findsOneWidget);
    });

    testWidgets('shows a loader until the first fortune lands', (tester) async {
      final store = _store(['Eventually.']);

      await pumpFortune(tester, _widget(store));
      await tester.pump();
      expect(find.byType(LoadingIndicator), findsNothing);

      // A store that has not been asked yet: the card's own first frame.
      final pending = FortuneStore.forTesting(
        reader: FortuneReader(runner: (_, _) => Completer<ProcessResult>().future),
      );
      addTearDown(pending.dispose);
      await pumpFortune(tester, _widget(pending));
      expect(find.byType(LoadingIndicator), findsOneWidget);
    });

    testWidgets('nothing on the card animates', (tester) async {
      // The picture is a still frame, the fortune is replaced outright and the
      // button does not spin: a wallpaper decoration on an otherwise idle
      // machine has no business repainting. A ticker anywhere in here would
      // hang this test rather than fail it, which is the point of pumping to
      // settle.
      final store = _store(['Still.']);

      await pumpFortune(tester, _widget(store));
      await tester.pumpAndSettle();

      expect(find.text('Still.'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a new fortune arrives without a transition', (tester) async {
      final store = _store(['First.', 'Second.']);
      await pumpFortune(tester, _widget(store));

      await tester.tap(find.byType(FortuneRefreshButton));
      await tester.pump();
      await tester.pump();

      // No frame in which both are on screen, and nothing left running after.
      expect(find.text('First.'), findsNothing);
      expect(find.text('Second.'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('the refresh button asks for another one', (tester) async {
      final store = _store(['First.', 'Second.']);

      await pumpFortune(tester, _widget(store));
      expect(find.text('First.'), findsOneWidget);

      await tester.tap(find.byType(FortuneRefreshButton));
      await tester.pump();
      await tester.pump();

      expect(find.text('Second.'), findsOneWidget);
    });

    testWidgets('rubbing the lamp asks for another one', (tester) async {
      // A genie's lamp that could not be rubbed would be a picture of the wrong
      // thing.
      final store = _store(['First.', 'Second.']);
      await pumpFortune(tester, _widget(store));

      await tester.tapAt(LampGeometry.forCard(_card).tapTarget.center);
      await tester.pump();
      await tester.pump();

      expect(find.text('Second.'), findsOneWidget);
    });

    testWidgets('taps the button rather than the card underneath it',
        (tester) async {
      // A `GestureDetector` with no `behavior:` defers to its child, and
      // everything a round button is built from answers `hitTestSelf == false`.
      // `HoverRegion` is what makes the box and the target the same rect — this
      // taps a corner of it, where a glyph-sized target would miss.
      final store = _store(['First.', 'Second.']);
      await pumpFortune(tester, _widget(store));

      final box = tester.getRect(find.byType(FortuneRefreshButton));
      await tester.tapAt(box.topLeft + const Offset(2, 2));
      await tester.pump();
      await tester.pump();

      expect(find.text('Second.'), findsOneWidget);
    });

    testWidgets('says so when the machine has no fortune command',
        (tester) async {
      // The overwhelmingly likely reason this card is empty, and the one the
      // user can fix in one command.
      final store = _missing();

      await pumpFortune(tester, _widget(store));

      expect(find.textContaining('not installed'), findsOneWidget);
      expect(find.text('Install the fortune-mod package'), findsOneWidget);
    });

    testWidgets('keeps the last fortune when a refresh fails', (tester) async {
      var succeed = true;
      final store = FortuneStore.forTesting(
        reader: FortuneReader(runner: (_, _) async {
          if (succeed) return ProcessResult(0, 0, 'Kept.\n', '');
          throw const ProcessException('fortune', []);
        }),
      );
      addTearDown(store.dispose);

      await pumpFortune(tester, _widget(store));
      expect(find.text('Kept.'), findsOneWidget);

      succeed = false;
      await tester.tap(find.byType(FortuneRefreshButton));
      await tester.pump();
      await tester.pump();

      // An hour-old fortune beats a blank card.
      expect(find.text('Kept.'), findsOneWidget);
    });

    testWidgets('draws at the smallest span the registry allows',
        (tester) async {
      // 2x1 on a 32px grid: the card is well under the widget's own floor, so
      // it is laid out at that floor and clipped rather than overflowing every
      // frame.
      final store = _store(['Small.']);

      await pumpFortune(
        tester,
        _widget(store, span: (2, 1)),
        size: const Size(76, 32),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FortuneWidget), findsOneWidget);
    });

    testWidgets('draws at the largest span the registry allows',
        (tester) async {
      final store = _store(['Large.']);

      await pumpFortune(
        tester,
        _widget(store, span: (6, 4)),
        size: const Size(744, 396),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Large.'), findsOneWidget);
    });
  });

  group('the registry entry', () {
    test('is the type a config names', () {
      // Stable forever once shipped: it is what a user's `[[desktop.widgets]]`
      // says.
      expect(fortuneDesktopWidget.type, 'fortune');
      expect(fortuneDesktopWidget.name, 'Fortune');
      expect(fortuneDesktopWidget.icon, fortuneDesktopWidgetIcon);
      expect(fortuneDesktopWidget.description, isNotEmpty);
    });

    test('paints its own card to the rim', () {
      expect(fortuneDesktopWidget.padding, EdgeInsets.zero);
    });

    test('clamps a span authored outside its limits', () {
      const item = DesktopWidgetItem(
        id: 'fortune',
        type: 'fortune',
        column: 0,
        row: 0,
        columnSpan: 40,
        rowSpan: 40,
      );

      expect(spanFor(fortuneDesktopWidget, item), fortuneDesktopWidget.maxSpan);
      expect(fortuneDesktopWidget.minSpan, (columns: 2, rows: 1));
      expect(fortuneDesktopWidget.defaultSpan, (columns: 3, rows: 2));
    });
  });
}
