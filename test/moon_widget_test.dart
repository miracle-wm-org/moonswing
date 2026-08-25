// The lunar desktop widget: what it shows at each size, and what it says when
// the shell does not know where the user is.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/desktop/widgets/moon_widget.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/moon/moon_render.dart';
import 'package:graceful_shell/moon/moon_store.dart';
import 'package:graceful_shell/scopes.dart';

import 'moon_fakes.dart';
import 'weather_fakes.dart';

/// The first quarter of 18 January 2024 — half lit, so the readout is a value
/// no rounding can turn into 0 or 100.
final DateTime _quarter = DateTime.utc(2024, 1, 18, 3, 53);

MoonStore _store({
  double? latitude = 39.8,
  double? longitude = -89.65,
  FakeWeatherClient? client,
  DateTime? at,
}) {
  final weather = weatherStoreAt(
    latitude: latitude,
    longitude: longitude,
    client: client,
  );
  addTearDown(weather.dispose);
  return MoonStore.forTesting(weather: weather, clock: () => at ?? _quarter);
}

Future<void> pumpMoon(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(320, 200),
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
  // Two pumps rather than `pumpAndSettle`: the location lookup lands in a
  // microtask, and the loader this widget can show is a `SpinKitRing`, which
  // never settles.
  await tester.pump();
  await tester.pump();
}

void main() {
  group('the lunar desktop widget', () {
    testWidgets('takes and releases a lease with its lifetime', (tester) async {
      final store = _store();
      await pumpMoon(
        tester,
        MoonWidget(span: (columns: 3, rows: 2), store: store),
      );
      expect(store.leaseCount, 1);
      expect(store.ticking, isTrue);

      await pumpMoon(tester, const SizedBox.shrink());
      expect(store.leaseCount, 0);
      expect(store.ticking, isFalse);
      store.dispose();
    });

    testWidgets('the compact layout is the disc, the phase and the fraction',
        (tester) async {
      final store = _store();
      await pumpMoon(
        tester,
        MoonWidget(span: (columns: 2, rows: 1), store: store),
        size: const Size(200, 70),
      );

      expect(find.text('First quarter'), findsOneWidget);
      expect(find.text('50% lit'), findsOneWidget);
      expect(find.byType(MoonDisc), findsOneWidget);
      // Nothing else fits, and nothing else is claimed to.
      expect(find.textContaining('Springfield'), findsNothing);
      store.dispose();
    });

    testWidgets('the expanded layout adds the place and the times',
        (tester) async {
      final store = _store();
      await pumpMoon(
        tester,
        MoonWidget(span: (columns: 3, rows: 2), store: store),
        size: const Size(320, 200),
      );

      expect(find.text('First quarter'), findsOneWidget);
      expect(find.text('Springfield'), findsOneWidget);
      expect(find.textContaining('day '), findsOneWidget);
      expect(store.times, isNotNull);
      // The location is known, so the row is times rather than an explanation.
      expect(find.textContaining('Set a weather location'), findsNothing);
      store.dispose();
    });

    testWidgets('a circumpolar Moon is spelled out rather than left blank',
        (tester) async {
      // 80°N on the full Moon of 25 January 2024: it never sets, in whatever
      // twenty-four hours the runner's local day happens to be.
      final store = _store(
        latitude: 80,
        longitude: 20,
        at: DateTime.utc(2024, 1, 25, 17, 54),
      );
      await pumpMoon(
        tester,
        MoonWidget(span: (columns: 3, rows: 2), store: store),
        size: const Size(320, 200),
      );

      expect(find.text('Up all day and all night'), findsOneWidget);
      store.dispose();
    });

    testWidgets('with no location it says what is missing, not what failed',
        (tester) async {
      final store = _store(
        latitude: null,
        longitude: null,
        client: UnreachableLocateClient(),
      );
      await pumpMoon(
        tester,
        MoonWidget(span: (columns: 3, rows: 2), store: store),
        size: const Size(320, 200),
      );

      expect(
        find.textContaining('Set a weather location'),
        findsOneWidget,
      );
      // The half of the card that does not need a location is untouched: this
      // is not an error state, it is a smaller card.
      expect(find.text('First quarter'), findsOneWidget);
      expect(find.textContaining('50% lit'), findsOneWidget);
      store.dispose();
    });

    testWidgets('a lookup in flight shows a loader, not an empty row',
        (tester) async {
      final store = _store(
        latitude: null,
        longitude: null,
        client: SilentLocateClient(),
      );
      await pumpMoon(
        tester,
        MoonWidget(span: (columns: 3, rows: 2), store: store),
        size: const Size(320, 200),
      );

      expect(find.byType(LoadingIndicator), findsOneWidget);
      expect(find.text('Finding your location'), findsOneWidget);
      store.dispose();
    });

    testWidgets('a tall card carries the consequences', (tester) async {
      final store = _store(at: DateTime.utc(2024, 1, 25, 17, 54));
      await pumpMoon(
        tester,
        MoonWidget(span: (columns: 4, rows: 4), store: store),
        size: const Size(360, 320),
      );

      expect(find.text('Full moon'), findsOneWidget);
      expect(find.text('Spring tides'), findsOneWidget);
      // The detail line under a title, which a narrow card drops.
      expect(find.textContaining('high water'), findsOneWidget);
      store.dispose();
    });

    testWidgets('a short card drops the facts before the reading',
        (tester) async {
      final store = _store(at: DateTime.utc(2024, 1, 25, 17, 54));
      await pumpMoon(
        tester,
        MoonWidget(span: (columns: 3, rows: 2), store: store),
        size: const Size(320, 180),
      );

      expect(find.text('Full moon'), findsOneWidget);
      expect(find.text('Spring tides'), findsNothing);
      store.dispose();
    });

    testWidgets('the southern hemisphere turns the disc over', (tester) async {
      final store = _store(latitude: -33.87, longitude: 151.21);
      await pumpMoon(
        tester,
        MoonWidget(span: (columns: 3, rows: 2), store: store),
      );

      final disc = tester.widget<MoonDisc>(find.byType(MoonDisc));
      expect(disc.southernView, isTrue);
      expect(disc.waxing, isTrue);
      expect(disc.illumination, closeTo(0.5, 0.01));
      store.dispose();
    });

    testWidgets('renders at every size the grid can give it', (tester) async {
      // The overflow sweep the media and weather widgets carry: a card smaller
      // than its content is laid out at its own minimum and clipped, never
      // reported as a flex overflow on a surface nobody reads the console for.
      for (final size in const [
        Size(96, 40),
        Size(150, 64),
        Size(200, 128),
        Size(320, 150),
        Size(480, 400),
        Size(720, 560),
      ]) {
        final store = _store();
        await pumpMoon(
          tester,
          MoonWidget(
            span: (columns: 3, rows: size.height > 100 ? 2 : 1),
            store: store,
          ),
          size: size,
        );
        expect(tester.takeException(), isNull, reason: 'at $size');
        store.dispose();
      }
    });
  });

  group('the registry entry', () {
    test('is what the Add widget… menu shows', () {
      expect(moonDesktopWidget.type, 'moon_phase');
      expect(moonDesktopWidget.name, 'Moon phase');
      expect(moonDesktopWidget.icon, moonDesktopWidgetIcon);
      // The card is the sky, so the frame gives it no inset of its own.
      expect(moonDesktopWidget.padding, EdgeInsets.zero);
      expect(moonDesktopWidget.minSpan, (columns: 2, rows: 1));
      expect(moonDesktopWidget.defaultSpan, (columns: 3, rows: 2));
    });

    test('a config authored outside the limits is clamped, not rewritten', () {
      const item = DesktopWidgetItem(
        id: 'moon_phase',
        type: 'moon_phase',
        columnSpan: 9,
        rowSpan: 9,
      );
      expect(spanFor(moonDesktopWidget, item), moonDesktopWidget.maxSpan);
      expect(item.columnSpan, 9);
    });
  });
}
