import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/modules/system.dart';
import 'package:graceful_shell/modules/weather.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/weather/weather_api.dart';
import 'package:graceful_shell/weather/weather_store.dart';

import 'weather_fakes.dart';

/// A popup window is sized to its content: [PopupWindowController] takes no
/// Size, only BoxConstraints, and the Linux backend shrink-wraps the surface
/// around whatever Flutter lays out. So the size a popup ends up with is
/// exactly the size its content reports under the constraints the call site
/// passes — which is what these tests measure, with no popup window involved.
///
/// The cards are pumped bare, with no PanelWindowManager, for the reason
/// desktop_menu_test.dart states: the popup machinery belongs to the host.
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

// The constraints each call site now passes.
const BoxConstraints kSystemConstraints =
    BoxConstraints(maxWidth: 320, maxHeight: 400);
const BoxConstraints kWeatherConstraints =
    BoxConstraints(maxWidth: 460, maxHeight: 640);

/// A store holding [days] days of forecast and nothing behind it. The popup
/// reads the store live rather than a snapshot, so this is what it is given.
WeatherStore _weather(int days) {
  final store = WeatherStore.forTesting(client: FakeWeatherClient())
    ..seed(
      current: testReading(),
      forecast: testForecast(days),
      // A short place name on purpose. The header prints the *full*
      // description — "Springfield, Illinois, United States" — and that line is
      // ellipsised against the card's own maximum, so a long one legitimately
      // takes the whole 460 and would measure the constraint rather than the
      // content these tests are about.
      place: const WeatherPlace(name: 'Springfield', latitude: 39.8, longitude: -89.65),
    );
  return store;
}

void main() {
  group('system power menu', () {
    testWidgets('hugs its buttons instead of filling the constraints',
        (tester) async {
      final size = await pumpUnder(
        tester,
        SystemPopupContent(onAction: (_) {}),
        kSystemConstraints,
      );

      // The regression this guards: _SystemButton is a default Row holding an
      // Expanded label, so without the IntrinsicWidth every button fills the
      // available width and the menu is exactly maxWidth across.
      expect(size.width, lessThan(kSystemConstraints.maxWidth));
      expect(size.height, lessThan(kSystemConstraints.maxHeight));
    });

    testWidgets('is sized by its rows rather than by a pinned constant',
        (tester) async {
      final size = await pumpUnder(
        tester,
        SystemPopupContent(onAction: (_) {}),
        kSystemConstraints,
      );

      // The 200x202 this replaced was hand-computed for a four-row menu; the
      // menu is five rows now (Restart arrived with `lib/power/`, which is
      // also where the labels and icons moved to). The bound moved with it and
      // the guard did not: a card that had gone back to a pinned constant, or
      // to filling its constraints, would be nowhere near a row's height of
      // this figure.
      expect(size.height, lessThan(250));
    });

    testWidgets('every button is as wide as the menu', (tester) async {
      await pumpUnder(
        tester,
        SystemPopupContent(onAction: (_) {}),
        kSystemConstraints,
      );

      // `stretch` under the IntrinsicWidth: the hover highlights must stay
      // flush with each other rather than each hugging its own label.
      final widths = tester
          .widgetList<GestureDetector>(find.byType(GestureDetector))
          .map((w) => tester.getSize(find.byWidget(w)).width)
          .toSet();
      expect(widths, hasLength(1));
    });
  });

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
      // this replaced: the temperature cells share a left edge even though the
      // day labels beside them differ in width.
      //
      // Six rows for seven days: today is spelled out in the header above, at
      // three times the size, so the table starts at tomorrow.
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
