// `[modules.weather]`, as a typed object.
//
// Beside the store rather than in `modules/weather.dart` for the reason
// `lib/system/system_monitor_config.dart` sits beside its sampler: two surfaces
// read these settings now, and neither of them is the bar module. The module
// file re-exports it, so `settings/shell/modules.dart` and anything else that
// imports it from there is unaffected.

import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/weather/weather_api.dart';

class WeatherConfig {
  const WeatherConfig({
    this.unit = 'fahrenheit',
    this.refreshMinutes = 30,
    this.locationName = '',
    this.latitude,
    this.longitude,
  });

  /// `fahrenheit` or `celsius`; anything else reads as fahrenheit.
  final String unit;

  /// How often the forecast is re-fetched, in minutes.
  ///
  /// Half an hour, which is about how often the reading itself moves: the
  /// current temperature is Open-Meteo's own hourly figure interpolated, so a
  /// ten-minute poll — what this used to be — asked their free API for the same
  /// numbers three times over. The one thing a longer interval costs is how
  /// stale the card can be at its worst, and half an hour of that is invisible
  /// against a reading whose source updates hourly.
  final int refreshMinutes;

  /// What the user calls the place they picked. Empty means "wherever this
  /// machine is", which is what the shell did before a location could be set.
  final String locationName;

  /// The picked coordinates. Both null — or either one null — means automatic:
  /// a half-written pair is not a location, and guessing which half to keep
  /// would put the user's weather somewhere on the prime meridian.
  final double? latitude;
  final double? longitude;

  TemperatureUnit get temperatureUnit => TemperatureUnit.parse(unit);

  /// The place to read weather for, or null to detect it from the IP address.
  WeatherPlace? get place {
    final lat = latitude;
    final lon = longitude;
    if (lat == null || lon == null) return null;
    return WeatherPlace(
      name: locationName.isEmpty ? 'Selected location' : locationName,
      latitude: lat,
      longitude: lon,
    );
  }

  factory WeatherConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const WeatherConfig();
    return WeatherConfig(
      unit: map.stringOr('unit', 'fahrenheit'),
      // Bounded: this is a timer period, and `refresh_minutes = 0` is a tight
      // loop against somebody else's free API.
      refreshMinutes: map.intOr('refresh_minutes', 30, min: 1, max: 1440),
      locationName: map.stringOr('location', ''),
      // Out-of-range coordinates are absent rather than clamped: a latitude of
      // 400 is a typo, and clamping it to 90 would silently show the user the
      // weather at the North Pole.
      latitude: map.doubleOrNull('latitude', min: -90, max: 90),
      longitude: map.doubleOrNull('longitude', min: -180, max: 180),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeatherConfig &&
          other.unit == unit &&
          other.refreshMinutes == refreshMinutes &&
          other.locationName == locationName &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode =>
      Object.hash(unit, refreshMinutes, locationName, latitude, longitude);
}
