// What the sky is doing, as a value rather than an emoji.
//
// The WMO code table Open-Meteo publishes (`weather_code`) is the only thing
// either surface is told about the weather, and both of them need more out of
// it than one glyph: the bar wants an icon and a name, the desktop widget's
// animation wants to know how much cloud to draw, what is falling out of it and
// how hard, and whether to flash. Deriving all of that from a `switch` at each
// call site is how the two drift apart, so it is derived once, here.
//
// Flutter-free on purpose — `lib/media/mpris_store.dart`'s rule. The icon for a
// condition lives in `weather_icons.dart`, which is the half that needs a
// widget library; this half is a plain unit test.

/// Which family of weather a WMO code belongs to.
///
/// The granularity is the code table's own: it distinguishes drizzle from rain
/// and showers from steady fall, and the animation draws those differently.
enum WeatherKind {
  clear,
  mainlyClear,
  partlyCloudy,
  overcast,
  fog,
  drizzle,
  freezingDrizzle,
  rain,
  freezingRain,
  snow,
  snowGrains,
  rainShowers,
  snowShowers,
  thunderstorm,
  thunderstormHail,

  /// A code this build does not know. Rendered, never dropped — the same answer
  /// `DesktopWidgetFrame` gives an unknown widget type.
  unknown,
}

/// What is coming out of the sky, which is what the animation draws.
enum Precipitation { none, drizzle, rain, sleet, snow, hail }

/// One row of the WMO table, resolved.
class WeatherCondition {
  const WeatherCondition({
    required this.kind,
    required this.label,
    required this.cloudCover,
    this.precipitation = Precipitation.none,
    this.intensity = 0,
    this.lightning = false,
  });

  final WeatherKind kind;

  /// The human name — "Partly cloudy", "Heavy snow". What the bar's popup and
  /// the widget print under the temperature.
  final String label;

  /// How much of the sky this condition implies is covered, 0..1.
  ///
  /// A *fallback*, not the reading: Open-Meteo publishes a real `cloud_cover`
  /// percentage and [WeatherReading] prefers it, because "partly cloudy" spans
  /// everything from two wisps to a nearly closed lid and the animation is the
  /// one consumer that can tell the difference. This is what the widget draws
  /// when a response carries no cloud figure.
  final double cloudCover;

  final Precipitation precipitation;

  /// How hard it is coming down, 0..1. Scales the particle count and their
  /// fall speed; 0 whenever [precipitation] is none.
  final double intensity;

  /// Whether the animation flashes.
  final bool lightning;

  bool get isPrecipitating => precipitation != Precipitation.none;

  /// Whether the sky is dark enough that the sun or moon is hidden behind the
  /// lid rather than shining through gaps in it.
  bool get isOvercast => cloudCover >= 0.9;
}

const WeatherCondition _unknown = WeatherCondition(
  kind: WeatherKind.unknown,
  label: 'Unknown',
  cloudCover: 0.4,
);

/// The WMO code table. Spelled once, as data, for the reason
/// `ThemeConfig`'s 28 keys are: three `switch`es over the same codes is three
/// places for one of them to be missed.
const Map<int, WeatherCondition> _table = {
  0: WeatherCondition(
      kind: WeatherKind.clear, label: 'Clear sky', cloudCover: 0.0),
  1: WeatherCondition(
      kind: WeatherKind.mainlyClear, label: 'Mainly clear', cloudCover: 0.2),
  2: WeatherCondition(
      kind: WeatherKind.partlyCloudy, label: 'Partly cloudy', cloudCover: 0.5),
  3: WeatherCondition(
      kind: WeatherKind.overcast, label: 'Overcast', cloudCover: 1.0),
  // A lower nominal cover than the greyness suggests, and deliberately: fog is
  // the *air* being the weather, drawn as haze bands, and a six-cloud lid over
  // them would hide the one thing that distinguishes this condition from
  // overcast.
  45: WeatherCondition(kind: WeatherKind.fog, label: 'Fog', cloudCover: 0.5),
  48: WeatherCondition(
      kind: WeatherKind.fog, label: 'Freezing fog', cloudCover: 0.5),
  51: WeatherCondition(
      kind: WeatherKind.drizzle,
      label: 'Light drizzle',
      cloudCover: 0.75,
      precipitation: Precipitation.drizzle,
      intensity: 0.2),
  53: WeatherCondition(
      kind: WeatherKind.drizzle,
      label: 'Drizzle',
      cloudCover: 0.85,
      precipitation: Precipitation.drizzle,
      intensity: 0.35),
  55: WeatherCondition(
      kind: WeatherKind.drizzle,
      label: 'Dense drizzle',
      cloudCover: 0.95,
      precipitation: Precipitation.drizzle,
      intensity: 0.5),
  56: WeatherCondition(
      kind: WeatherKind.freezingDrizzle,
      label: 'Freezing drizzle',
      cloudCover: 0.9,
      precipitation: Precipitation.sleet,
      intensity: 0.3),
  57: WeatherCondition(
      kind: WeatherKind.freezingDrizzle,
      label: 'Dense freezing drizzle',
      cloudCover: 0.95,
      precipitation: Precipitation.sleet,
      intensity: 0.5),
  61: WeatherCondition(
      kind: WeatherKind.rain,
      label: 'Light rain',
      cloudCover: 0.8,
      precipitation: Precipitation.rain,
      intensity: 0.3),
  63: WeatherCondition(
      kind: WeatherKind.rain,
      label: 'Rain',
      cloudCover: 0.9,
      precipitation: Precipitation.rain,
      intensity: 0.6),
  65: WeatherCondition(
      kind: WeatherKind.rain,
      label: 'Heavy rain',
      cloudCover: 1.0,
      precipitation: Precipitation.rain,
      intensity: 1.0),
  66: WeatherCondition(
      kind: WeatherKind.freezingRain,
      label: 'Freezing rain',
      cloudCover: 0.9,
      precipitation: Precipitation.sleet,
      intensity: 0.5),
  67: WeatherCondition(
      kind: WeatherKind.freezingRain,
      label: 'Heavy freezing rain',
      cloudCover: 1.0,
      precipitation: Precipitation.sleet,
      intensity: 0.85),
  71: WeatherCondition(
      kind: WeatherKind.snow,
      label: 'Light snow',
      cloudCover: 0.8,
      precipitation: Precipitation.snow,
      intensity: 0.3),
  73: WeatherCondition(
      kind: WeatherKind.snow,
      label: 'Snow',
      cloudCover: 0.9,
      precipitation: Precipitation.snow,
      intensity: 0.6),
  75: WeatherCondition(
      kind: WeatherKind.snow,
      label: 'Heavy snow',
      cloudCover: 1.0,
      precipitation: Precipitation.snow,
      intensity: 1.0),
  77: WeatherCondition(
      kind: WeatherKind.snowGrains,
      label: 'Snow grains',
      cloudCover: 0.85,
      precipitation: Precipitation.snow,
      intensity: 0.35),
  80: WeatherCondition(
      kind: WeatherKind.rainShowers,
      label: 'Light showers',
      cloudCover: 0.6,
      precipitation: Precipitation.rain,
      intensity: 0.4),
  81: WeatherCondition(
      kind: WeatherKind.rainShowers,
      label: 'Showers',
      cloudCover: 0.75,
      precipitation: Precipitation.rain,
      intensity: 0.7),
  82: WeatherCondition(
      kind: WeatherKind.rainShowers,
      label: 'Violent showers',
      cloudCover: 0.95,
      precipitation: Precipitation.rain,
      intensity: 1.0),
  85: WeatherCondition(
      kind: WeatherKind.snowShowers,
      label: 'Snow showers',
      cloudCover: 0.7,
      precipitation: Precipitation.snow,
      intensity: 0.5),
  86: WeatherCondition(
      kind: WeatherKind.snowShowers,
      label: 'Heavy snow showers',
      cloudCover: 0.9,
      precipitation: Precipitation.snow,
      intensity: 0.9),
  95: WeatherCondition(
      kind: WeatherKind.thunderstorm,
      label: 'Thunderstorm',
      cloudCover: 1.0,
      precipitation: Precipitation.rain,
      intensity: 0.8,
      lightning: true),
  96: WeatherCondition(
      kind: WeatherKind.thunderstormHail,
      label: 'Thunderstorm with hail',
      cloudCover: 1.0,
      precipitation: Precipitation.hail,
      intensity: 0.8,
      lightning: true),
  99: WeatherCondition(
      kind: WeatherKind.thunderstormHail,
      label: 'Thunderstorm with heavy hail',
      cloudCover: 1.0,
      precipitation: Precipitation.hail,
      intensity: 1.0,
      lightning: true),
};

/// [code]'s condition, or [WeatherKind.unknown] for a code this build does not
/// have. Never throws: the code arrives from a web API, and a value nobody has
/// seen before must cost the icon, not the panel.
WeatherCondition conditionForCode(int code) => _table[code] ?? _unknown;
