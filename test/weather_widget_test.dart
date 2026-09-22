import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/widgets/desktop_widget.dart';
import 'package:moonswing/desktop/widgets/weather_widget.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/modules/weather.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/weather/weather_api.dart';
import 'package:moonswing/weather/weather_sky.dart';
import 'package:moonswing/weather/weather_store.dart';

import 'weather_fakes.dart';

/// A store with a reading already in it.
///
/// The client is given the *same* snapshot rather than left on its defaults:
/// every one of these widgets takes a lease in `initState`, so the fetch that
/// starts there lands during the first `pump` and overwrites whatever was seeded.
WeatherStore _seeded({
  int weatherCode = 0,
  bool isDay = true,
  double? cloudCoverPercent = 5,
  int days = 7,
  WeatherPlace place = kTestPlace,
}) {
  final reading = testReading(
    weatherCode: weatherCode,
    isDay: isDay,
    cloudCoverPercent: cloudCoverPercent,
  );
  final forecast = testForecast(days);
  final client = FakeWeatherClient(
    place: place,
    snapshot: WeatherSnapshot(
      place: place,
      current: reading,
      forecast: forecast,
      unit: TemperatureUnit.fahrenheit,
    ),
  );
  return WeatherStore.forTesting(client: client)
    ..seed(current: reading, forecast: forecast, place: place);
}

Future<void> pumpSurface(
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
  // One pump is what these layouts need. `pumpAndSettle` is *allowed* now that
  // nothing on the card animates — which is the point of `weather_sky_test`'s
  // 'settles' case — but the SVG glyphs resolve their assets over a handful of
  // frames and none of these tests is about a glyph.
  await tester.pump();
}

void main() {
  group('the weather desktop widget', () {
    testWidgets('takes and releases a lease with its lifetime', (tester) async {
      final store = _seeded();
      await pumpSurface(
        tester,
        WeatherWidget(
          span: (columns: 3, rows: 2),
          store: store,
        ),
      );
      expect(store.leaseCount, 1);

      await pumpSurface(tester, const SizedBox.shrink());
      expect(store.leaseCount, 0);
      // The one thing a leaked lease costs: a poller running for a widget that
      // is no longer on any desktop.
      expect(store.polling, isFalse);
      store.dispose();
    });

    testWidgets('draws a sky under the reading', (tester) async {
      final store = _seeded(weatherCode: 71, cloudCoverPercent: 90);
      await pumpSurface(
        tester,
        WeatherWidget(
          span: (columns: 3, rows: 2),
          store: store,
        ),
      );

      expect(find.byType(WeatherSky), findsOneWidget);
      final sky = tester.widget<WeatherSky>(find.byType(WeatherSky));
      // The API's measured cover, not the condition's nominal 0.8.
      expect(sky.cloudCover, closeTo(0.9, 1e-9));
      expect(sky.night, isFalse);
      store.dispose();
    });

    testWidgets('night comes from the location, not from this machine',
        (tester) async {
      final store = _seeded(isDay: false);
      await pumpSurface(
        tester,
        WeatherWidget(
          span: (columns: 3, rows: 2),
          store: store,
        ),
      );
      expect(tester.widget<WeatherSky>(find.byType(WeatherSky)).night, isTrue);
      store.dispose();
    });

    testWidgets('the expanded layout shows the place and the detail row',
        (tester) async {
      final store = _seeded();
      await pumpSurface(
        tester,
        WeatherWidget(
          span: (columns: 4, rows: 3),
          store: store,
        ),
        size: const Size(420, 300),
      );

      expect(find.text('Springfield'), findsOneWidget);
      expect(find.text('72°F'), findsOneWidget);
      expect(find.text('Clear sky'), findsOneWidget);
      // Feels-like, humidity and wind.
      expect(find.text('70°F'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('6 mph'), findsOneWidget);
      store.dispose();
    });

    testWidgets('the compact layout drops to the reading alone',
        (tester) async {
      final store = _seeded();
      await pumpSurface(
        tester,
        WeatherWidget(
          span: (columns: 2, rows: 1),
          store: store,
        ),
        size: const Size(200, 70),
      );

      expect(find.text('72°F'), findsOneWidget);
      expect(find.text('Clear sky'), findsOneWidget);
      // No room for the place or the detail row at 2x1.
      expect(find.text('Springfield'), findsNothing);
      expect(find.text('40%'), findsNothing);
      store.dispose();
    });

    testWidgets('a two-row widget on a short grid falls back rather than '
        'overflowing', (tester) async {
      // The span asks for the expanded layout; the pixels decide whether it
      // fits. A cell is configurable down to 32px.
      final store = _seeded();
      await pumpSurface(
        tester,
        WeatherWidget(
          span: (columns: 3, rows: 2),
          store: store,
        ),
        size: const Size(180, 80),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('72°F'), findsOneWidget);
      store.dispose();
    });

    testWidgets('a card smaller than its content clips instead of overflowing',
        (tester) async {
      final store = _seeded();
      await pumpSurface(
        tester,
        WeatherWidget(
          span: (columns: 2, rows: 1),
          store: store,
        ),
        size: const Size(60, 40),
      );
      expect(tester.takeException(), isNull);
      store.dispose();
    });

    testWidgets('the forecast strip only appears when there is room for it',
        (tester) async {
      final store = _seeded();
      Future<void> pumpAt(Size size) => pumpSurface(
            tester,
            WeatherWidget(
              span: (columns: 4, rows: 3),
              store: store,
            ),
            size: size,
          );

      await pumpAt(const Size(460, 320));
      // Tomorrow onwards; today is spelled out above at three times the size.
      expect(find.text('Tue'), findsOneWidget);
      expect(find.text('Mon'), findsNothing);

      // Too narrow for columns anybody could read, whatever the height.
      await pumpAt(const Size(200, 300));
      expect(find.text('Tue'), findsNothing);

      // And too short for the block, whatever the width: the strip is the
      // first thing the card gives up, and the reading it is under is the last.
      await pumpAt(const Size(460, 170));
      expect(find.text('Tue'), findsNothing);
      expect(find.text('72°F'), findsOneWidget);
      store.dispose();
    });

    testWidgets('loading is a loader, not an empty card', (tester) async {
      // "No weather" is a lie the user would act on — the rule
      // `ShellServicesScope` states for the launcher's empty list.
      final store = WeatherStore.forTesting(
          client: FakeWeatherClient(pending: true));
      await pumpSurface(
        tester,
        WeatherWidget(
          span: (columns: 3, rows: 2),
          store: store,
        ),
      );

      expect(store.loading, isTrue);
      expect(find.byType(LoadingIndicator), findsOneWidget);
      store.dispose();
    });

    testWidgets('a failure says so and offers a retry', (tester) async {
      final client = FakeWeatherClient(
          failWith: const WeatherException('Weather unavailable'));
      final store = WeatherStore.forTesting(client: client)
        ..seed(error: 'Weather unavailable');

      await pumpSurface(
        tester,
        WeatherWidget(
          span: (columns: 3, rows: 2),
          store: store,
        ),
      );

      expect(find.text('Weather unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(client.fetchCalls, greaterThan(0));
      store.dispose();
    });

    testWidgets('the type is set at the card\'s own size, not at one fixed '
        'size', (tester) async {
      // Every size on this card was a literal chosen against a 3x2 widget, so a
      // user who dragged it out to 6x4 got the same 10px day labels in four times
      // the area. `_CardScale` fixed it, and this is the property — measured on
      // the condition label, the one line every expanded card carries.
      final store = _seeded();

      Future<double> conditionSize(Size size) async {
        await pumpSurface(
          tester,
          WeatherWidget(span: (columns: 4, rows: 3), store: store),
          size: size,
        );
        return tester.widget<Text>(find.text('Clear sky')).style!.fontSize!;
      }

      final small = await conditionSize(const Size(320, 220));
      final large = await conditionSize(const Size(620, 410));

      // Not a rounding difference — but not the card's own growth either: the
      // type takes `_scaleExponent` of it, which is what leaves a bigger card
      // room for a block a smaller one could not carry.
      expect(large, greaterThan(small * 1.25));
      expect(large, lessThan(small * 1.94));
      store.dispose();
    });

    testWidgets('the forecast strip grows with the card rather than staying '
        'at one size', (tester) async {
      // The one part of this card that was illegible at every size: it was set
      // at 10px against a 30px reading, and stayed at 10px on a card four times
      // the area.
      final store = _seeded();

      Future<double> dayLabelSize(Size size) async {
        await pumpSurface(
          tester,
          WeatherWidget(span: (columns: 6, rows: 4), store: store),
          size: size,
        );
        return tester.widget<Text>(find.text('Tue').first).style!.fontSize!;
      }

      final small = await dayLabelSize(const Size(460, 320));
      final large = await dayLabelSize(const Size(640, 440));
      expect(large, greaterThan(small));
      store.dispose();
    });

    testWidgets('a bigger card sets the same days larger before it reaches '
        'for more of them', (tester) async {
      // `_forecastDays` scales its per-column budget by the same factor the
      // type does, so a card cannot grow its way back to a row of cramped
      // columns: the day count rises far more slowly than the width does.
      final store = _seeded();

      Future<int> dayCount(Size size) async {
        await pumpSurface(
          tester,
          WeatherWidget(span: (columns: 6, rows: 4), store: store),
          size: size,
        );
        // The strip is the only place a day label is drawn; today is spelled
        // out above it as a temperature rather than as a name.
        return ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
            .where((day) => find.text(day).evaluate().isNotEmpty)
            .length;
      }

      final narrow = await dayCount(const Size(460, 320));
      final wide = await dayCount(const Size(900, 440));
      expect(narrow, greaterThan(0));
      // Nearly twice the width, nowhere near twice the days.
      expect(wide, lessThan(narrow * 2));
      store.dispose();
    });

    testWidgets('the base table is a floor: a card under the reference is '
        'clipped rather than set smaller', (tester) async {
      // `_minWidth`/`_minHeight` already lay the content out at its own minimum
      // and clip it, so scaling *down* as well would shed legibility twice for
      // the same card.
      final store = _seeded();
      await pumpSurface(
        tester,
        WeatherWidget(
          span: (columns: 2, rows: 1),
          store: store,
        ),
        size: const Size(180, 70),
      );

      expect(
        tester.widget<Text>(find.text('Clear sky')).style!.fontSize,
        ShellFontSizes.caption,
      );
      store.dispose();
    });

    test('the registry entry paints to the card rim', () {
      // The sky *is* the card, so the frame gives it no padding. PopupCard
      // clips to the theme's radius, so painting to the edge is rounded free.
      expect(weatherDesktopWidget.padding, EdgeInsets.zero);
      expect(weatherDesktopWidget.type, 'weather');
      expect(weatherDesktopWidget.minSpan.columns, 2);
    });

    test('every other widget keeps the padding it always had', () {
      // The default is what the frame used to hard-code.
      const spec = DesktopWidgetSpec(
        type: 'x',
        name: 'x',
        icon: _anyIcon,
        builder: _noBuilder,
      );
      expect(spec.padding, const EdgeInsets.all(10));
    });
  });

  group('the weather bar module', () {
    testWidgets('shows the icon and the temperature', (tester) async {
      final store = _seeded();
      await pumpSurface(
        tester,
        Align(alignment: Alignment.topLeft, child: Weather(store: store)),
        size: const Size(300, 40),
      );

      expect(find.text('72°F'), findsOneWidget);
      expect(store.leaseCount, 1);
      store.dispose();
    });

    testWidgets('a failure is a visible state, not a blank strip',
        (tester) async {
      final client = FakeWeatherClient(
          failWith: const WeatherException('ipapi.co answered 503'));
      final store = WeatherStore.forTesting(client: client)
        ..seed(error: 'ipapi.co answered 503');

      await pumpSurface(
        tester,
        Align(alignment: Alignment.topLeft, child: Weather(store: store)),
        size: const Size(300, 40),
      );

      // An empty bar is indistinguishable from a module the user never
      // enabled, so the module renders something — and clicking it retries,
      // because the shell cannot notice the network coming back.
      final rendered = tester.getSize(find.byType(Weather));
      expect(rendered.width, greaterThan(0));
      await tester.tap(find.byType(Weather));
      await tester.pump();
      expect(client.fetchCalls, greaterThan(0));
      store.dispose();
    });

    testWidgets('the first load is a fixed-size loader', (tester) async {
      final store = WeatherStore.forTesting(
          client: FakeWeatherClient(pending: true));
      await pumpSurface(
        tester,
        Align(alignment: Alignment.topLeft, child: Weather(store: store)),
        size: const Size(300, 40),
      );

      expect(find.byType(LoadingIndicator), findsOneWidget);
      // The placeholder must not be narrower than the reading that replaces
      // it, or the modules beside it shuffle sideways when it lands.
      expect(tester.getSize(find.byType(Weather)).width, 16);
      store.dispose();
    });
  });
}

const _anyIcon = weatherDesktopWidgetIcon;
Widget _noBuilder(BuildContext context, DesktopWidgetContext widget) =>
    const SizedBox.shrink();
