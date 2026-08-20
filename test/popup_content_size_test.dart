import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/modules/system.dart';
import 'package:graceful_shell/modules/weather.dart';
import 'package:graceful_shell/scopes.dart';

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
    BoxConstraints(maxWidth: 420, maxHeight: 600);

List<DayForecast> _forecast(int days) => List.generate(
      days,
      (i) => DayForecast(
        dayLabel: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i],
        weatherCode: 0,
        tempMax: 72,
        tempMin: 51,
        precipProbability: 10,
      ),
    );

void main() {
  group('system power menu', () {
    testWidgets('hugs its buttons instead of filling the constraints',
        (tester) async {
      final size = await pumpUnder(
        tester,
        SystemPopupContent(onShowConfirmation: (_, _) {}, onLock: () {}),
        kSystemConstraints,
      );

      // The regression this guards: _SystemButton is a default Row holding an
      // Expanded label, so without the IntrinsicWidth every button fills the
      // available width and the menu is exactly maxWidth across.
      expect(size.width, lessThan(kSystemConstraints.maxWidth));
      expect(size.height, lessThan(kSystemConstraints.maxHeight));
    });

    testWidgets('is smaller than the 200x202 it used to be pinned to',
        (tester) async {
      final size = await pumpUnder(
        tester,
        SystemPopupContent(onShowConfirmation: (_, _) {}, onLock: () {}),
        kSystemConstraints,
      );

      expect(size.height, lessThan(202));
    });

    testWidgets('every button is as wide as the menu', (tester) async {
      await pumpUnder(
        tester,
        SystemPopupContent(onShowConfirmation: (_, _) {}, onLock: () {}),
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
        WeatherForecastPopup(
          forecast: _forecast(3),
          unitLabel: '°F',
          weatherCondition: (_) => '*',
        ),
        kWeatherConstraints,
      );
      final seven = await pumpUnder(
        tester,
        WeatherForecastPopup(
          forecast: _forecast(7),
          unitLabel: '°F',
          weatherCondition: (_) => '*',
        ),
        kWeatherConstraints,
      );

      // The bug in one assertion: the card used to be 260x300 whatever the API
      // returned, so a short forecast left four rows of dead space.
      expect(seven.height, greaterThan(three.height));
      expect(three.height, lessThan(300));
    });

    testWidgets('hugs its widest row instead of filling the constraints',
        (tester) async {
      final size = await pumpUnder(
        tester,
        WeatherForecastPopup(
          forecast: _forecast(7),
          unitLabel: '°F',
          weatherCondition: (_) => '*',
        ),
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
        WeatherForecastPopup(
          forecast: _forecast(7),
          unitLabel: '°F',
          weatherCondition: (_) => '*',
        ),
        kWeatherConstraints,
      );

      // What IntrinsicColumnWidth buys over the MainAxisAlignment.spaceBetween
      // this replaced: the temperature cells share a left edge even though the
      // day labels beside them differ in width.
      final temps = find.textContaining('/');
      expect(temps, findsNWidgets(7));
      final lefts = tester
          .widgetList<Text>(temps)
          .map((w) => tester.getTopLeft(find.byWidget(w)).dx)
          .toSet();
      expect(lefts, hasLength(1));
    });
  });
}
