import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/modules/weather.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/weather/weather_api.dart';
import 'package:moonswing/weather/weather_store.dart';

import 'weather_fakes.dart';

/// A popup window is sized to its content: [PopupWindowController] takes no Size,
/// only BoxConstraints, and the Linux backend shrink-wraps the surface around
/// whatever Flutter lays out. So a popup's size is exactly what its content
/// reports under the call site's constraints — which is what these measure, with
/// no popup window involved.
///
/// The cards are pumped bare, with no WindowManager: the popup machinery belongs
/// to the host.
Future<Size> pumpUnder(
  WidgetTester tester,
  Widget child,
  BoxConstraints constraints,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: const ThemeConfig(),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(constraints: constraints, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byWidget(child));
}

// The constraints the call site passes.
const BoxConstraints kWeatherConstraints =
    BoxConstraints(maxWidth: 460, maxHeight: 640);

/// A store holding [days] days of forecast and nothing behind it. The popup
/// reads the store live rather than a snapshot, so this is what it is given.
WeatherStore _weather(int days) {
  final store = WeatherStore.forTesting(client: FakeWeatherClient())
    ..seed(
      current: testReading(),
      forecast: testForecast(days),
      // A short place name on purpose. The header prints the *full* description
      // and that line is ellipsised against the card's own maximum, so a long one
      // legitimately takes the whole 460 and would measure the constraint rather
      // than the content.
      place: const WeatherPlace(name: 'Springfield', latitude: 39.8, longitude: -89.65),
    );
  return store;
}

void main() {
  group('weather forecast', () {
    testWidgets('height tracks the number of days returned', (tester) async {
      final three = await pumpUnder(
        tester,
        WeatherForecastPopup(store: _weather(3)),
        kWeatherConstraints,
      );
      final seven = await pumpUnder(
        tester,
        WeatherForecastPopup(store: _weather(7)),
        kWeatherConstraints,
      );

      // The bug in one assertion: the card used to be 260x300 whatever the API
      // returned, so a short forecast left four rows of dead space.
      expect(seven.height, greaterThan(three.height));
    });

    testWidgets('hugs its widest row instead of filling the constraints',
        (tester) async {
      final size = await pumpUnder(
        tester,
        WeatherForecastPopup(store: _weather(7)),
        kWeatherConstraints,
      );

      // The Table has no flex column, so it shrink-wraps to the sum of its
      // intrinsic column widths.
      expect(size.width, lessThan(kWeatherConstraints.maxWidth));
      expect(size.height, lessThan(kWeatherConstraints.maxHeight));
    });

    testWidgets('columns line up across rows', (tester) async {
      await pumpUnder(
        tester,
        WeatherForecastPopup(store: _weather(7)),
        kWeatherConstraints,
      );

      // What IntrinsicColumnWidth buys over the MainAxisAlignment.spaceBetween
      // this replaced: the temperature cells share a left edge even though the day
      // labels differ in width. Six rows for seven days — today is spelled out in
      // the header above, so the table starts at tomorrow.
      final temps = find.textContaining('/');
      expect(temps, findsNWidgets(6));
      final lefts = tester
          .widgetList<Text>(temps)
          .map((w) => tester.getTopLeft(find.byWidget(w)).dx)
          .toSet();
      expect(lefts, hasLength(1));
    });
  });
}
