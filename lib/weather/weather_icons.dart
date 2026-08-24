// A glyph per row of the WMO table.
//
// The other half of `weather_condition.dart`, split off because this one needs
// a widget library and that one is a plain unit test.
//
// Material Symbols rather than Font Awesome, which is what the bar used before
// through emoji: Font Awesome has a sun, a cloud and a bolt and nothing
// between them, so "mainly clear", "partly cloudy" and "overcast" all had to
// render as the same icon — and the emoji the module fell back to instead
// rendered at whatever size, weight and colour the system font stack decided,
// which is the one thing in a themed bar that no theme could touch. Material
// Symbols carries `clear_day`, `partly_cloudy_day`, `cloudy`, `rainy_light`,
// `rainy`, `rainy_heavy`, `snowing`, `weather_hail`, `thunderstorm` and
// `foggy`: the granularity the condition table already resolves.
//
// Night has its own glyphs for the three conditions where the sky is visible
// through the cloud, and only those: it is the sun or moon in the icon that
// differs, and a raincloud at midnight is the same raincloud.

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:graceful_shell/weather/weather_condition.dart';

/// The icon for [condition]. [night] picks the moonlit variant where there is
/// one.
IconData weatherIcon(WeatherCondition condition, {bool night = false}) {
  return switch (condition.kind) {
    WeatherKind.clear => night ? Symbols.clear_night : Symbols.clear_day,
    WeatherKind.mainlyClear =>
      night ? Symbols.partly_cloudy_night : Symbols.partly_cloudy_day,
    WeatherKind.partlyCloudy =>
      night ? Symbols.partly_cloudy_night : Symbols.partly_cloudy_day,
    WeatherKind.overcast => Symbols.cloud,
    WeatherKind.fog => Symbols.foggy,
    WeatherKind.drizzle => Symbols.rainy_light,
    WeatherKind.freezingDrizzle => Symbols.weather_mix,
    WeatherKind.rain => condition.intensity >= 0.8
        ? Symbols.rainy_heavy
        : condition.intensity <= 0.35
            ? Symbols.rainy_light
            : Symbols.rainy,
    WeatherKind.freezingRain => Symbols.weather_mix,
    WeatherKind.snow =>
      condition.intensity >= 0.8 ? Symbols.snowing_heavy : Symbols.snowing,
    WeatherKind.snowGrains => Symbols.weather_snowy,
    WeatherKind.rainShowers => Symbols.rainy,
    WeatherKind.snowShowers => Symbols.snowing,
    WeatherKind.thunderstorm => Symbols.thunderstorm,
    WeatherKind.thunderstormHail => Symbols.weather_hail,
    // Not a blank: the module still has a temperature to show, and an icon
    // that says "something, and the shell does not know what" is the honest
    // rendering of a code from a table this build predates.
    WeatherKind.unknown => Symbols.question_mark,
  };
}

/// The icon a chance-of-rain figure is printed beside — a raindrop, in place of
/// the `💧` the popup used to spell with an emoji.
const IconData kPrecipitationIcon = Symbols.water_drop;

const IconData kHumidityIcon = Symbols.humidity_mid;
const IconData kWindIcon = Symbols.air;
const IconData kFeelsLikeIcon = Symbols.thermometer;
const IconData kLocationIcon = Symbols.location_on;

/// The bar module with no reading to show. A crossed-out cloud rather than a
/// generic warning triangle: the thing that is unavailable is the weather, and
/// a triangle in a bar reads as the shell itself being in trouble.
const IconData kWeatherUnavailableIcon = Symbols.cloud_off;

/// A weather glyph, at the one weight and fill the shell draws them at.
///
/// Material Symbols is a variable font: `fill` and `weight` are axes rather
/// than separate glyphs, and left at their defaults the icons come out as thin
/// outlines that disappear against a bar at 16px. A slight fill and a medium
/// weight is what makes them read at the sizes the shell uses, and spelling it
/// once here is what stops the bar, the popup and the desktop widget from each
/// picking their own.
class WeatherIcon extends StatelessWidget {
  const WeatherIcon(
    this.icon, {
    super.key,
    required this.size,
    required this.color,
    this.fill = 0.7,
    this.shadows,
  });

  final IconData icon;
  final double size;
  final Color color;

  /// 0 is a hairline outline, 1 a solid shape.
  final double fill;

  /// For an icon drawn over the desktop widget's sky, where the background is
  /// whatever the weather is.
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color,
      fill: fill,
      weight: 500,
      opticalSize: size <= 24 ? 20 : 40,
      shadows: shadows,
    );
  }
}
