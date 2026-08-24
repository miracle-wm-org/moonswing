import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/weather/weather_api.dart';
import 'package:graceful_shell/weather/weather_condition.dart';

const _place = WeatherPlace(name: 'Test', latitude: 0, longitude: 0);

Map<String, dynamic> _json(String source) =>
    jsonDecode(source) as Map<String, dynamic>;

void main() {
  group('parseForecast', () {
    final full = _json('''
{
  "current": {
    "temperature_2m": 21.4,
    "apparent_temperature": 19.8,
    "relative_humidity_2m": 63,
    "is_day": 0,
    "weather_code": 61,
    "cloud_cover": 82,
    "wind_speed_10m": 11.3
  },
  "daily": {
    "time": ["2026-01-05", "2026-01-06", "2026-01-07"],
    "temperature_2m_max": [8.1, 9.4, 4.0],
    "temperature_2m_min": [1.2, 3.3, -2.0],
    "weather_code": [61, 3, 71],
    "precipitation_probability_max": [80, 10, 55]
  }
}
''');

    test('reads the current block', () {
      final snapshot = parseForecast(full,
          place: _place, unit: TemperatureUnit.celsius);

      expect(snapshot.current.temperature, 21.4);
      expect(snapshot.current.weatherCode, 61);
      expect(snapshot.current.condition.kind, WeatherKind.rain);
      expect(snapshot.current.isDay, isFalse);
      expect(snapshot.current.apparentTemperature, 19.8);
      expect(snapshot.current.humidity, 63);
      expect(snapshot.current.windSpeed, 11.3);
    });

    test('the measured cloud cover wins over the condition\'s nominal one', () {
      final snapshot = parseForecast(full,
          place: _place, unit: TemperatureUnit.celsius);

      // Code 61 nominally implies 0.8; the response says 82%, and the sky is
      // the one consumer that can show the difference.
      expect(snapshot.current.cloudCover, closeTo(0.82, 1e-9));
      expect(snapshot.current.condition.cloudCover, 0.8);
    });

    test('falls back to the condition when the response carries no figure', () {
      final snapshot = parseForecast(
        _json('{"current": {"temperature_2m": 5, "weather_code": 3}}'),
        place: _place,
        unit: TemperatureUnit.celsius,
      );
      expect(snapshot.current.cloudCover, 1.0);
    });

    test('reads the daily block, in order', () {
      final snapshot = parseForecast(full,
          place: _place, unit: TemperatureUnit.celsius);

      expect(snapshot.forecast, hasLength(3));
      expect(snapshot.forecast.first.tempMax, 8.1);
      expect(snapshot.forecast.first.precipProbability, 80);
      expect(snapshot.forecast.last.weatherCode, 71);
      // 2026-01-05 is a Monday.
      expect(snapshot.forecast.first.dayLabel, 'Mon');
      expect(snapshot.forecast[1].dayLabel, 'Tue');
    });

    test('a missing current block is fatal', () {
      // There is no reading to show, so this is the one case that must throw
      // rather than degrade — the store turns it into the visible error line.
      expect(
        () => parseForecast(_json('{"daily": {}}'),
            place: _place, unit: TemperatureUnit.celsius),
        throwsA(isA<WeatherException>()),
      );
    });

    test('a missing daily block costs the forecast, not the reading', () {
      final snapshot = parseForecast(
        _json('{"current": {"temperature_2m": 5, "weather_code": 0}}'),
        place: _place,
        unit: TemperatureUnit.fahrenheit,
      );
      expect(snapshot.current.temperature, 5);
      expect(snapshot.forecast, isEmpty);
    });

    test('a short parallel array truncates rather than throwing', () {
      // Open-Meteo returns parallel arrays; one short array must not take the
      // whole parse down with a range error.
      final snapshot = parseForecast(
        _json('''
{
  "current": {"temperature_2m": 5, "weather_code": 0},
  "daily": {
    "time": ["2026-01-05", "2026-01-06", "2026-01-07"],
    "temperature_2m_max": [8, 9],
    "temperature_2m_min": [1, 3],
    "weather_code": [0, 0]
  }
}
'''),
        place: _place,
        unit: TemperatureUnit.celsius,
      );
      expect(snapshot.forecast, hasLength(2));
      // A missing precipitation column reads as zero rather than dropping days.
      expect(snapshot.forecast.first.precipProbability, 0);
    });

    test('a day with a hole in it is dropped, not half-built', () {
      final snapshot = parseForecast(
        _json('''
{
  "current": {"temperature_2m": 5, "weather_code": 0},
  "daily": {
    "time": ["2026-01-05", "2026-01-06"],
    "temperature_2m_max": [8, null],
    "temperature_2m_min": [1, 3],
    "weather_code": [0, 0],
    "precipitation_probability_max": [0, 0]
  }
}
'''),
        place: _place,
        unit: TemperatureUnit.celsius,
      );
      expect(snapshot.forecast, hasLength(1));
    });

    test('absent is_day reads as day', () {
      final snapshot = parseForecast(
        _json('{"current": {"temperature_2m": 5, "weather_code": 0}}'),
        place: _place,
        unit: TemperatureUnit.celsius,
      );
      expect(snapshot.current.isDay, isTrue);
    });

    test('a non-finite temperature is absent rather than propagated', () {
      // NaN survives clamp() and `toInt()` throws on it — the discipline
      // TomlReader states, applied to the other end of the pipe.
      final snapshot = parseForecast(
        _json('''
{"current": {"temperature_2m": 5, "weather_code": 0,
             "apparent_temperature": "not a number"}}'''),
        place: _place,
        unit: TemperatureUnit.celsius,
      );
      expect(snapshot.current.apparentTemperature, isNull);
    });
  });

  group('parseGeocoding', () {
    test('reads the results', () {
      final places = parseGeocoding(_json('''
{"results": [
  {"name": "Springfield", "latitude": 39.8, "longitude": -89.6,
   "admin1": "Illinois", "country": "United States"},
  {"name": "Berlin", "latitude": 52.5, "longitude": 13.4,
   "country": "Germany"}
]}
'''));

      expect(places, hasLength(2));
      expect(places.first.description,
          'Springfield, Illinois, United States');
      expect(places.first.qualifier, 'Illinois, United States');
      expect(places.last.description, 'Berlin, Germany');
    });

    test('a result with no coordinates is dropped', () {
      // Picking it would store a location that can never be fetched for.
      final places = parseGeocoding(
          _json('{"results": [{"name": "Nowhere", "country": "X"}]}'));
      expect(places, isEmpty);
    });

    test('no results is an empty list, not a throw', () {
      expect(parseGeocoding(_json('{"generationtime_ms": 0.3}')), isEmpty);
      expect(parseGeocoding(_json('{"results": []}')), isEmpty);
    });
  });

  group('parseIpLocation', () {
    test('reads city, region and country', () {
      final place = parseIpLocation(_json('''
{"city": "Springfield", "region": "Illinois", "country_name": "United States",
 "latitude": 39.8, "longitude": -89.65}
'''));
      expect(place.name, 'Springfield');
      expect(place.description, 'Springfield, Illinois, United States');
    });

    test('falls back down the name chain rather than answering blank', () {
      // ipapi.co drops `city` on some addresses, and a place with no name at
      // all reads as a bug in the shell rather than a thin answer from a free
      // service.
      final place = parseIpLocation(_json(
          '{"region": "Bavaria", "latitude": 48.1, "longitude": 11.5}'));
      expect(place.name, 'Bavaria');
    });

    test('no coordinates is a reportable failure', () {
      expect(
        () => parseIpLocation(_json('{"error": true}')),
        throwsA(isA<WeatherException>()),
      );
    });
  });

  group('TemperatureUnit', () {
    test('parses the config values and defaults to fahrenheit', () {
      expect(TemperatureUnit.parse('celsius'), TemperatureUnit.celsius);
      expect(TemperatureUnit.parse('Celsius'), TemperatureUnit.celsius);
      expect(TemperatureUnit.parse('fahrenheit'), TemperatureUnit.fahrenheit);
      // A misspelling costs the setting, not the module.
      expect(TemperatureUnit.parse('kelvin'), TemperatureUnit.fahrenheit);
    });
  });
}
