import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/desktop/widgets/weather_widget.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/modules/weather.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/weather/weather_api.dart';
import 'package:graceful_shell/weather/weather_sky.dart';
import 'package:graceful_shell/weather/weather_store.dart';

import 'weather_fakes.dart';

/// A store with a reading already in it.
///
/// The client is given the *same* snapshot, not left on its defaults: every
/// one of these widgets takes a lease in `initState`, so the fetch that starts
/// there lands during the first `pump` and overwrites whatever was seeded. A
/// fake that answered differently would make each test measure the fake rather
/// than the seed, and only sometimes.
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
  // Never pumpAndSettle: the sky's Ticker never settles. `animate: false`
  // silences it, and one pump is what these layouts need anyway.
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
          animate: false,
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
          animate: false,
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
          animate: false,
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
          animate: false,
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
          animate: false,
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
          animate: false,
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
          animate: false,
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
              animate: false,
            ),
            size: size,
          );

      await pumpAt(const Size(460, 320));
      // Tomorrow onwards; today is spelled out above at three times the size.
      expect(find.text('Tue'), findsOneWidget);
      expect(find.text('Mon'), findsNothing);

      await pumpAt(const Size(200, 150));
      expect(find.text('Tue'), findsNothing);
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
          animate: false,
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
          animate: false,
        ),
      );

      expect(find.text('Weather unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(client.fetchCalls, greaterThan(0));
      store.dispose();
    });

    testWidgets('the forecast strip is set at the card\'s size, not at one '
        'fixed size', (tester) async {
      // The strip was the one part of this card that was illegible at every
      // size: 10px against a 30px reading, and still 10px on a card four times
      // the area. `_CardScale` is what fixed it, and this is the property.
      final store = _seeded();

      Future<double> dayLabelSize(Size size) async {
        await pumpSurface(
          tester,
          WeatherWidget(
            span: (columns: 4, rows: 3),
            store: store,
            animate: false,
          ),
          size: size,
        );
        return tester.widget<Text>(find.text('Tue')).style!.fontSize!;
      }

      final small = await dayLabelSize(const Size(320, 220));
      final large = await dayLabelSize(const Size(620, 410));

      expect(large, greaterThan(small));
      // Not a rounding difference: a card nearly four times the area sets it
      // nearly twice as large.
      expect(large, greaterThan(small * 1.5));
      store.dispose();
    });

    testWidgets('a bigger card answers with the same days set larger, not '
        'with more days', (tester) async {
      // `_forecastDays` scales its per-column budget by the same factor the
      // type does, so growing the card cannot walk the strip back to a row of
      // cramped columns.
      final store = _seeded();

      Future<int> dayCount(Size size) async {
        await pumpSurface(
          tester,
          WeatherWidget(
            span: (columns: 6, rows: 4),
            store: store,
            animate: false,
          ),
          size: size,
        );
        // The strip is the only place a day label is drawn; today is spelled
        // out above it as a temperature rather than as a name.
        return ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
            .where((day) => find.text(day).evaluate().isNotEmpty)
            .length;
      }

      expect(await dayCount(const Size(620, 410)),
          lessThanOrEqualTo(await dayCount(const Size(320, 220))));
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
          animate: false,
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
