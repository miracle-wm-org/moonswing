import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/modules/weather.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/weather/weather_store.dart';

import 'weather_fakes.dart';

/// The bar's forecast card, pumped the way the shell builds it: under a
/// [ThemeScope] and **nothing else**.
///
/// Popup content is laid out directly under its own FlutterView, so there is no
/// `_windowChrome` above it and nothing supplies a [Directionality] — which every
/// `Text` and `Row` in the card needs. This card's was dropped in the move to
/// `lib/weather/` and it came up empty.
///
/// So the wrapper here is deliberately *not*
/// `popup_content_size_test.dart`'s, which supplies a Directionality of its own
/// and would have measured a card that could not render in the shell.
Future<void> pumpPopup(WidgetTester tester, WeatherStore store) async {
  await tester.pumpWidget(
    ThemeScope(
      theme: const ThemeConfig(),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          // What `WeatherState._togglePopup` passes.
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
          child: WeatherForecastPopup(store: store),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

WeatherStore _seeded({int days = 7, String error = ''}) {
  return WeatherStore.forTesting(client: FakeWeatherClient())
    ..seed(
      current: testReading(temperature: 72),
      forecast: testForecast(days),
      place: kTestPlace,
      error: error,
    );
}

void main() {
  testWidgets('renders with no Directionality above it', (tester) async {
    await pumpPopup(tester, _seeded());

    expect(tester.takeException(), isNull);
    // The reading, and the six days the table shows below today.
    expect(find.text('72°F'), findsOneWidget);
    expect(find.text('Forecast'), findsOneWidget);
    expect(find.textContaining('/'), findsNWidgets(6));
  });

  testWidgets('shows the place and today high/low', (tester) async {
    await pumpPopup(tester, _seeded());

    expect(find.text(kTestPlace.description), findsOneWidget);
    // testForecast's first day: 72 / 51.
    expect(find.text('H 72°  L 51°'), findsOneWidget);
  });

  testWidgets('keeps the last reading on screen through a failed refresh',
      (tester) async {
    await pumpPopup(tester, _seeded(error: 'Weather unavailable'));

    expect(find.text('72°F'), findsOneWidget);
    expect(find.text('Weather unavailable'), findsOneWidget);
  });
}
