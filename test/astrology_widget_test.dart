// The astrology desktop widget: what it shows in each of its four states, that
// the half of it which is arithmetic survives the half that is a network, and
// that nothing on it moves.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/astrology/astrology_config.dart';
import 'package:graceful_shell/astrology/astrology_store.dart';
import 'package:graceful_shell/astrology/horoscope_api.dart';
import 'package:graceful_shell/astrology/zodiac.dart';
import 'package:graceful_shell/astrology/zodiac_sky.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart' show GridSpan;
import 'package:graceful_shell/desktop/widgets/astrology_widget.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/sky_icon_button.dart';

import 'astrology_fakes.dart';

const Size _card = Size(320, 210);

/// A birthday in the middle of an arc, so no time zone the runner might be in
/// can move it onto a cusp.
final AstrologyConfig _leo =
    AstrologyConfig(birthday: DateTime(2000, 7, 30));

AstrologyStore _store(
  FakeHoroscopeClient client, {
  AstrologyConfig config = const AstrologyConfig(),
}) {
  final store = AstrologyStore.forTesting(client: client, config: config);
  addTearDown(store.dispose);
  return store;
}

Future<void> pumpCard(
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
  // the loader the card shows before it arrives is a `SpinKitRing`, which never
  // settles. Once a horoscope is on screen the card itself settles — "nothing
  // on the card animates" below pins that.
  await tester.pump();
  await tester.pump();
}

Widget _widget(AstrologyStore store, {GridSpan span = (columns: 3, rows: 2)}) =>
    AstrologyWidget(span: span, store: store);

void main() {
  group('the astrology desktop widget', () {
    testWidgets('takes and releases a lease with its lifetime', (tester) async {
      final store = _store(FakeHoroscopeClient(), config: _leo);

      await pumpCard(tester, _widget(store));
      expect(store.leaseCount, 1);

      await pumpCard(tester, const SizedBox.shrink());
      expect(store.leaseCount, 0);
    });

    testWidgets('names the sign and draws its constellation', (tester) async {
      final store = _store(FakeHoroscopeClient(), config: _leo);

      await pumpCard(tester, _widget(store));

      expect(find.text('Leo'), findsOneWidget);
      final sky = tester.widget<ZodiacSky>(find.byType(ZodiacSky));
      expect(sky.sign, ZodiacSign.leo);
    });

    testWidgets('shows the horoscope it fetched', (tester) async {
      final store = _store(
        FakeHoroscopeClient(text: 'Mercury is doing something.'),
        config: _leo,
      );

      await pumpCard(tester, _widget(store));

      expect(find.text('Mercury is doing something.'), findsOneWidget);
    });

    testWidgets('says where the words came from', (tester) async {
      // The paragraph is somebody else's copy, fetched from a server the shell
      // does not run. A horoscope presented as the shell's own would be the one
      // thing on this desktop pretending to an authority it has not got.
      final store = _store(FakeHoroscopeClient(), config: _leo);

      await pumpCard(tester, _widget(store));

      expect(
        find.textContaining(kHoroscopeAttribution),
        findsOneWidget,
      );
    });

    testWidgets('shows a loader until the first horoscope lands',
        (tester) async {
      final store = _store(FakeHoroscopeClient(pending: true), config: _leo);

      await pumpCard(tester, _widget(store));

      expect(find.byType(LoadingIndicator), findsOneWidget);
      // The half that is arithmetic does not wait for the half that is not.
      expect(find.text('Leo'), findsOneWidget);
    });

    testWidgets('asks the user for a birthday when there is none',
        (tester) async {
      final client = FakeHoroscopeClient();
      final store = _store(client);

      await pumpCard(tester, _widget(store));

      // The one actionable empty state, and the reason the card says anything
      // at all rather than sitting blank.
      expect(find.textContaining('Set your birthday'), findsOneWidget);
      expect(find.text('Set birthday…'), findsOneWidget);
      // No sign to name, and naming one anyway — a default, a placeholder —
      // would be the card answering a question it is about to say it cannot
      // answer.
      expect(find.text('Astrology'), findsOneWidget);
      expect(client.calls, 0, reason: 'there is nothing to fetch');
      // No sign, so no figure: drawing somebody else's would be the card
      // answering a question it has just said it cannot answer.
      expect(tester.widget<ZodiacSky>(find.byType(ZodiacSky)).sign, isNull);
      // And no refresh button, because it could not do anything.
      expect(find.byType(SkyIconButton), findsNothing);
    });

    testWidgets('offers a retry when the fetch failed', (tester) async {
      final client = FakeHoroscopeClient(
        failWith: const HoroscopeException('example.test answered 503'),
      );
      final store = _store(client, config: _leo);

      await pumpCard(tester, _widget(store));

      expect(find.text('example.test answered 503'), findsOneWidget);
      // Every failure here is recoverable without restarting the shell, and the
      // shell cannot detect the recovery happening.
      expect(find.text('Retry'), findsOneWidget);
      // The sign survives the network.
      expect(find.text('Leo'), findsOneWidget);

      client.failWith = null;
      client.text = 'Back again.';
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Back again.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('the corner button asks again', (tester) async {
      final client = FakeHoroscopeClient(text: 'First.');
      final store = _store(client, config: _leo);

      await pumpCard(tester, _widget(store));
      expect(find.text('First.'), findsOneWidget);

      client.text = 'Second.';
      await tester.tap(find.byType(SkyIconButton));
      await tester.pump();
      await tester.pump();

      expect(find.text('Second.'), findsOneWidget);
      expect(find.text('First.'), findsNothing);
    });

    testWidgets('the corner button is hit at its corner, not just its centre',
        (tester) async {
      // `tap_target_test.dart`'s rule: a centre tap passes on a control whose
      // box is a bare glyph, which is the bug it exists to catch.
      final client = FakeHoroscopeClient(text: 'First.');
      final store = _store(client, config: _leo);

      await pumpCard(tester, _widget(store));

      client.text = 'Second.';
      final box = tester.getRect(find.byType(SkyIconButton));
      await tester.tapAt(box.topLeft + const Offset(2, 2));
      await tester.pump();
      await tester.pump();

      expect(find.text('Second.'), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the last horoscope on screen',
        (tester) async {
      final client = FakeHoroscopeClient(text: 'Kept.');
      final store = _store(client, config: _leo);

      await pumpCard(tester, _widget(store));
      expect(find.text('Kept.'), findsOneWidget);

      client.failWith = const HoroscopeException('example.test answered 503');
      await tester.tap(find.byType(SkyIconButton));
      await tester.pump();
      await tester.pump();

      // A horoscope from this morning beats a blank card.
      expect(find.text('Kept.'), findsOneWidget);
    });

    testWidgets('draws at the smallest span the registry allows',
        (tester) async {
      // Laid out at its own minimum and clipped, never a flex overflow reported
      // every frame on a surface whose console nobody is reading.
      final store = _store(FakeHoroscopeClient(), config: _leo);

      await pumpCard(
        tester,
        _widget(store, span: astrologyDesktopWidget.minSpan),
        size: const Size(96, 48),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ZodiacSky), findsOneWidget);
    });

    testWidgets('nothing on the card animates', (tester) async {
      // The lunar and fortune widgets' rule: no ticker anywhere, so a tree
      // containing this may be settled. A ticker added in here hangs this test
      // rather than merely failing it.
      final store = _store(FakeHoroscopeClient(), config: _leo);

      await pumpCard(tester, _widget(store));
      await tester.pumpAndSettle();

      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a card the grid grew keeps the same content', (tester) async {
      final store = _store(
        FakeHoroscopeClient(text: 'The same paragraph, set larger.'),
        config: _leo,
      );

      await pumpCard(
        tester,
        _widget(store, span: (columns: 6, rows: 4)),
        size: const Size(636, 420),
      );

      expect(find.text('The same paragraph, set larger.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the registry entry', () {
    test('is what the desktop menu and the config name it by', () {
      expect(astrologyDesktopWidget.type, 'astrology');
      expect(astrologyDesktopWidget.name, 'Astrology');
      expect(astrologyDesktopWidget.icon, astrologyDesktopWidgetIcon);
      expect(astrologyDesktopWidget.description, isNotEmpty);
      // The sky is the card, the way the weather widget's is.
      expect(astrologyDesktopWidget.padding, EdgeInsets.zero);
      expect(astrologyDesktopWidget.minSpan, (columns: 2, rows: 1));
      expect(astrologyDesktopWidget.defaultSpan, (columns: 3, rows: 2));
    });

    test('a span authored outside the limits is clamped, not rewritten', () {
      const item = DesktopWidgetItem(
        id: 'astrology-1',
        type: 'astrology',
        column: 0,
        row: 0,
        columnSpan: 40,
        rowSpan: 40,
      );
      expect(spanFor(astrologyDesktopWidget, item),
          astrologyDesktopWidget.maxSpan);
    });
  });
}
