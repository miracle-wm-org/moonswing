// The mapping from the WMO table to the Meteocons set.
//
// A slug is a string, and the pack is a version constraint like any other: an
// upstream rename is a silent degrade to `not-available` on whichever row it
// hit — visible in the shell only to somebody who happens to be looking at that
// weather. This is the guardrail `weather_icons.dart`'s "costs the icon, not
// the panel" rule needs on the other side, and it is why `_glyph` degrades
// rather than throws: the throw would be louder but it would be in a `build`.

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/weather/weather_condition.dart';
import 'package:graceful_shell/weather/weather_icons.dart';

/// Every code `conditionForCode` actually knows. Derived rather than listed, so
/// a row added to the table is a row this test starts covering.
List<int> _knownCodes() => [
      for (var code = 0; code <= 99; code++)
        if (conditionForCode(code).kind != WeatherKind.unknown) code,
    ];

void main() {
  test('the table is what is being covered', () {
    // A sanity check on the derivation above: if `conditionForCode` ever
    // answered `unknown` for everything, every assertion below would pass
    // vacuously.
    expect(_knownCodes().length, greaterThan(20));
  });

  test('every condition resolves to a slug the installed pack ships', () {
    for (final code in _knownCodes()) {
      for (final night in [false, true]) {
        final glyph = weatherIcon(conditionForCode(code), night: night);
        expect(
          glyph.name,
          isNot('not-available'),
          reason: 'WMO $code (${conditionForCode(code).label}, '
              'night: $night) has no Meteocon',
        );
      }
    }
  });

  test('a code this build predates is drawn, never dropped', () {
    // The other half of `conditionForCode`'s promise: the module still has a
    // temperature to show, so "something, and the shell does not know what" is
    // the honest picture rather than a blank.
    final glyph = weatherIcon(conditionForCode(4242));
    expect(glyph.name, 'not-available');
  });

  test('night changes the glyph only where the sky is visible', () {
    // It is the sun or the moon in the icon that differs; a raincloud at
    // midnight is the same raincloud.
    bool differs(int code) =>
        weatherIcon(conditionForCode(code)).name !=
        weatherIcon(conditionForCode(code), night: true).name;

    expect(differs(0), isTrue, reason: 'clear sky');
    expect(differs(2), isTrue, reason: 'partly cloudy');
    expect(differs(80), isTrue, reason: 'showers fall through a break');

    expect(differs(3), isFalse, reason: 'overcast hides the sun by definition');
    expect(differs(65), isFalse, reason: 'heavy rain');
    expect(differs(75), isFalse, reason: 'heavy snow');
  });

  test('a shower is a different picture from steady rain', () {
    // The distinction Material Symbols could not draw, and the reason the set
    // was worth changing.
    expect(
      weatherIcon(conditionForCode(80)).name,
      isNot(weatherIcon(conditionForCode(63)).name),
    );
  });

  test('the supporting glyphs are the ones the pack is asked for', () {
    expect(kHumidityIcon.name, 'humidity');
    expect(kWindIcon.name, 'wind');
    expect(kFeelsLikeIcon.name, 'thermometer');
    expect(kPrecipitationIcon.name, 'raindrop');
    expect(kWeatherUnavailableIcon.name, 'not-available');
  });

  group('the three renderings', () {
    Future<void> pumpIcon(WidgetTester tester, WeatherIcon icon) async {
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: Center(child: icon)),
      );
      // Never pumpAndSettle: an animated glyph is a Ticker, and the asset loads
      // land within a handful of frames either way.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    String assetOf(WidgetTester tester) {
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      return (picture.bytesLoader as SvgAssetLoader).assetName;
    }

    testWidgets('a tint is an outlined glyph, never a flattened fill one',
        (tester) async {
      // `srcIn` over a full-colour Meteocon would paint `partly-cloudy-day` as
      // one blob where the sun and the cloud used to be. The `line` family is
      // outlined, so the shapes survive being painted one colour.
      await pumpIcon(
        tester,
        WeatherIcon(
          weatherIcon(conditionForCode(2)),
          size: 21,
          color: const Color(0xFFFFFFFF),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(assetOf(tester), 'assets/line/svg-static/partly-cloudy-day.svg');
    });

    testWidgets('an untinted still glyph is the fill family in its own colours',
        (tester) async {
      await pumpIcon(
        tester,
        WeatherIcon(weatherIcon(conditionForCode(0)), size: 52),
      );
      expect(tester.takeException(), isNull);
      expect(assetOf(tester), 'assets/fill/svg-static/clear-day.svg');
    });

    testWidgets('nothing here reaches for the pack\'s animated formats',
        (tester) async {
      // The hero glyph on the desktop card used to be a Lottie — a `Ticker`
      // running for as long as a wallpaper widget was on screen, beside a sky
      // running another. Both are gone, so this asserts the *absence*: every
      // rendering is an SVG picture, and there is no flag that turns one into
      // anything else.
      await pumpIcon(
        tester,
        WeatherIcon(weatherIcon(conditionForCode(61)), size: 58),
      );
      expect(tester.takeException(), isNull);
      expect(assetOf(tester), 'assets/fill/svg-static/rain.svg');
      // And the tree settles, which a Lottie's ticker never let it do.
      await tester.pumpAndSettle();
    });
  });
}
