// The web half of the weather: where the machine is, what the sky is doing
// there, and how to find a place by name.
//
// Flutter-free and behind an interface for two reasons. The store leases a
// poller both the bar and the desktop widget read, so a test driving it must not
// reach the network; and the parsing is where a shape change at Open-Meteo turns
// into a crash, so it is a pure function over a decoded map.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:moonswing/weather/weather_condition.dart';

/// Which scale temperatures are reported in.
enum TemperatureUnit {
  celsius('°C', 'celsius'),
  fahrenheit('°F', 'fahrenheit');

  const TemperatureUnit(this.label, this.apiName);

  /// The degree suffix every readout prints.
  final String label;

  /// Open-Meteo's `temperature_unit` value.
  final String apiName;

  /// [name]'s unit, defaulting to [fahrenheit] — a config value is a string the
  /// user typed and a misspelling must cost the setting, not the module.
  static TemperatureUnit parse(String name) =>
      name.toLowerCase() == 'celsius' ? celsius : fahrenheit;
}

/// Somewhere weather can be read for: a set of coordinates with a name on it.
///
/// The name is carried rather than looked up because the coordinates are what the
/// forecast API wants and the name is what the user recognises; resolving one
/// from the other on every render would be a geocoding request per frame.
class WeatherPlace {
  const WeatherPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.admin = '',
    this.country = '',
  });

  final String name;
  final double latitude;
  final double longitude;

  /// The state, province or region, when the geocoder gives one.
  final String admin;
  final String country;

  /// "Springfield, Illinois, United States" — as much of it as there is.
  String get description => [name, admin, country]
      .where((part) => part.isNotEmpty)
      .join(', ');

  /// "Illinois, United States" — the disambiguating half, for the second line
  /// of a picker row where [name] is already the first.
  String get qualifier =>
      [admin, country].where((part) => part.isNotEmpty).join(', ');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeatherPlace &&
          other.name == name &&
          other.latitude == latitude &&
          other.longitude == longitude &&
          other.admin == admin &&
          other.country == country;

  @override
  int get hashCode => Object.hash(name, latitude, longitude, admin, country);

  @override
  String toString() => 'WeatherPlace($description, $latitude, $longitude)';
}

/// One day of the daily forecast.
class DayForecast {
  const DayForecast({
    required this.date,
    required this.weatherCode,
    required this.tempMax,
    required this.tempMin,
    required this.precipProbability,
  });

  final DateTime date;
  final int weatherCode;
  final double tempMax;
  final double tempMin;
  final int precipProbability;

  WeatherCondition get condition => conditionForCode(weatherCode);

  /// "Mon". Spelled here rather than through `intl` — the calendar's
  /// `month.dart` refuses that dependency for the same reason, and seven
  /// three-letter labels are not formatting machinery.
  String get dayLabel {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(date.weekday - 1).clamp(0, 6)];
  }
}

/// The current conditions, as one snapshot.
class WeatherReading {
  const WeatherReading({
    required this.temperature,
    required this.weatherCode,
    required this.isDay,
    this.apparentTemperature,
    this.cloudCoverPercent,
    this.humidity,
    this.windSpeed,
  });

  final double temperature;
  final int weatherCode;

  /// Whether the sun is up *there* — the API answers this for the location's
  /// own longitude, which is the only correct answer for a world clock's worth
  /// of distance between the user and the place they are watching.
  final bool isDay;

  final double? apparentTemperature;

  /// The real sky coverage, 0..100, when the response carries one.
  final double? cloudCoverPercent;

  final int? humidity;
  final double? windSpeed;

  WeatherCondition get condition => conditionForCode(weatherCode);

  /// How much cloud the animation draws, 0..1.
  ///
  /// The measured figure wins over the condition's nominal one: "partly cloudy"
  /// spans two wisps to a nearly closed lid, and the sky is the one consumer that
  /// can show the difference.
  double get cloudCover {
    final measured = cloudCoverPercent;
    if (measured == null) return condition.cloudCover;
    return (measured / 100).clamp(0.0, 1.0);
  }
}

/// Everything one refresh produces.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.place,
    required this.current,
    required this.forecast,
    required this.unit,
  });

  final WeatherPlace place;
  final WeatherReading current;
  final List<DayForecast> forecast;
  final TemperatureUnit unit;
}

/// The seam the store polls through. [OpenMeteoClient] is the one
/// implementation; a test supplies its own and never opens a socket.
abstract class WeatherClient {
  /// Where this machine is, by its IP address. Used when the user has picked no
  /// location.
  Future<WeatherPlace> locate();

  Future<WeatherSnapshot> fetch(WeatherPlace place, TemperatureUnit unit);

  /// Places matching [query], for the settings picker. Empty for a query too
  /// short to be worth a request.
  Future<List<WeatherPlace>> search(String query);
}

/// Thrown when a lookup fails in a way the user should be told about. The store
/// turns it into the one line of text both surfaces show in place of a reading.
class WeatherException implements Exception {
  const WeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Open-Meteo (forecast + geocoding) and ipapi.co (the IP fallback). No key,
/// no account, and — deliberately — no request until a widget holds a lease.
class OpenMeteoClient implements WeatherClient {
  const OpenMeteoClient({http.Client? httpClient}) : _client = httpClient;

  final http.Client? _client;

  Future<String> _get(Uri url) async {
    final client = _client;
    final response = client == null
        ? await http.get(url)
        : await client.get(url);
    if (response.statusCode != 200) {
      throw WeatherException('${url.host} answered ${response.statusCode}');
    }
    return response.body;
  }

  @override
  Future<WeatherPlace> locate() async {
    final body = await _get(Uri.parse('https://ipapi.co/json/'));
    return parseIpLocation(jsonDecode(body) as Map<String, dynamic>);
  }

  @override
  Future<WeatherSnapshot> fetch(WeatherPlace place, TemperatureUnit unit) async {
    final url = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${place.latitude}',
      'longitude': '${place.longitude}',
      'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,'
          'is_day,weather_code,cloud_cover,wind_speed_10m',
      'daily': 'temperature_2m_max,temperature_2m_min,weather_code,'
          'precipitation_probability_max',
      'timezone': 'auto',
      'temperature_unit': unit.apiName,
    });
    final body = await _get(url);
    return parseForecast(
      jsonDecode(body) as Map<String, dynamic>,
      place: place,
      unit: unit,
    );
  }

  @override
  Future<List<WeatherPlace>> search(String query) async {
    final trimmed = query.trim();
    // One letter matches most of the world; the request is not worth making
    // and its result is not worth showing.
    if (trimmed.length < 2) return const [];
    final url = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': trimmed,
      'count': '10',
      'language': 'en',
      'format': 'json',
    });
    final body = await _get(url);
    return parseGeocoding(jsonDecode(body) as Map<String, dynamic>);
  }
}

/// ipapi.co's answer. Its `city` is occasionally absent on a datacentre
/// address, in which case the region or the country carries the name — a place
/// with no name at all reads as a bug in the shell rather than a thin answer
/// from a free geolocation service.
WeatherPlace parseIpLocation(Map<String, dynamic> json) {
  final lat = _asDouble(json['latitude']);
  final lon = _asDouble(json['longitude']);
  if (lat == null || lon == null) {
    throw const WeatherException('Could not determine your location');
  }
  final city = _asString(json['city']);
  final region = _asString(json['region']);
  final country = _asString(json['country_name']);
  return WeatherPlace(
    name: city.isNotEmpty
        ? city
        : region.isNotEmpty
            ? region
            : country.isNotEmpty
                ? country
                : 'Current location',
    latitude: lat,
    longitude: lon,
    admin: city.isNotEmpty ? region : '',
    country: country,
  );
}

/// The geocoding endpoint's answer. A result missing coordinates is dropped
/// rather than shown, because picking it would store a location that can never
/// be fetched for.
List<WeatherPlace> parseGeocoding(Map<String, dynamic> json) {
  final results = json['results'];
  if (results is! List) return const [];
  final places = <WeatherPlace>[];
  for (final entry in results) {
    if (entry is! Map<String, dynamic>) continue;
    final lat = _asDouble(entry['latitude']);
    final lon = _asDouble(entry['longitude']);
    final name = _asString(entry['name']);
    if (lat == null || lon == null || name.isEmpty) continue;
    places.add(WeatherPlace(
      name: name,
      latitude: lat,
      longitude: lon,
      admin: _asString(entry['admin1']),
      country: _asString(entry['country']),
    ));
  }
  return places;
}

/// The forecast endpoint's answer.
///
/// A missing `current` block is fatal — there is no reading to show — while a
/// missing or ragged `daily` block costs the forecast alone. The day loop is
/// bounded by the shortest column for the same reason: Open-Meteo returns
/// parallel arrays, and one short array must not take the whole parse down with
/// a range error.
WeatherSnapshot parseForecast(
  Map<String, dynamic> json, {
  required WeatherPlace place,
  required TemperatureUnit unit,
}) {
  final current = json['current'];
  if (current is! Map<String, dynamic>) {
    throw const WeatherException('No current conditions in the response');
  }
  final temperature = _asDouble(current['temperature_2m']);
  final code = _asDouble(current['weather_code']);
  if (temperature == null || code == null) {
    throw const WeatherException('No current conditions in the response');
  }

  final reading = WeatherReading(
    temperature: temperature,
    weatherCode: code.round(),
    // Absent (an older API revision, a cached response) reads as day: a sunlit
    // card is the less alarming of the two wrong answers.
    isDay: (_asDouble(current['is_day']) ?? 1) >= 0.5,
    apparentTemperature: _asDouble(current['apparent_temperature']),
    cloudCoverPercent: _asDouble(current['cloud_cover']),
    humidity: _asDouble(current['relative_humidity_2m'])?.round(),
    windSpeed: _asDouble(current['wind_speed_10m']),
  );

  return WeatherSnapshot(
    place: place,
    current: reading,
    forecast: _parseDaily(json['daily']),
    unit: unit,
  );
}

List<DayForecast> _parseDaily(Object? daily) {
  if (daily is! Map<String, dynamic>) return const [];
  final times = daily['time'];
  final maxima = daily['temperature_2m_max'];
  final minima = daily['temperature_2m_min'];
  final codes = daily['weather_code'];
  if (times is! List || maxima is! List || minima is! List || codes is! List) {
    return const [];
  }
  final precipitation = daily['precipitation_probability_max'];

  final count = [times.length, maxima.length, minima.length, codes.length]
      .reduce((a, b) => a < b ? a : b);
  final days = <DayForecast>[];
  for (var i = 0; i < count; i++) {
    final date = DateTime.tryParse('${times[i]}');
    final high = _asDouble(maxima[i]);
    final low = _asDouble(minima[i]);
    final code = _asDouble(codes[i]);
    if (date == null || high == null || low == null || code == null) continue;
    days.add(DayForecast(
      date: date,
      weatherCode: code.round(),
      tempMax: high,
      tempMin: low,
      precipProbability: precipitation is List && i < precipitation.length
          ? (_asDouble(precipitation[i])?.round() ?? 0)
          : 0,
    ));
  }
  return days;
}

/// A JSON number, or null for anything else. NaN and infinity are absent for
/// `TomlReader`'s reason: they survive `clamp` and `toInt()` throws on them.
double? _asDouble(Object? value) {
  if (value is num) return value.isFinite ? value.toDouble() : null;
  if (value is String) {
    final parsed = double.tryParse(value);
    return parsed != null && parsed.isFinite ? parsed : null;
  }
  return null;
}

String _asString(Object? value) => value is String ? value.trim() : '';
