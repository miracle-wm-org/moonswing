// Shared fakes for the weather tests: an offline [WeatherClient] and the builders
// that make a reading.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it. The point is
// the one `MprisStore.forTesting` makes — every weather test takes a real lease
// on a real store, and none may reach for a network the runner does not have.

import 'dart:async';

import 'package:graceful_shell/weather/weather_api.dart';

const WeatherPlace kTestPlace = WeatherPlace(
  name: 'Springfield',
  latitude: 39.8,
  longitude: -89.65,
  admin: 'Illinois',
  country: 'United States',
);

/// A client that answers from what it was handed, counts its calls, and opens
/// nothing.
class FakeWeatherClient implements WeatherClient {
  FakeWeatherClient({
    this.place = kTestPlace,
    this.snapshot,
    this.results = const [],
    this.failWith,
    this.pending = false,
  });

  WeatherPlace place;
  WeatherSnapshot? snapshot;
  List<WeatherPlace> results;

  /// When set, [fetch] throws it instead of answering.
  WeatherException? failWith;

  /// When true, [fetch] never completes.
  ///
  /// The only way a widget test can hold the store in its loading state: a widget
  /// takes a lease in `initState`, so the fetch it starts lands during the first
  /// `pump` and a seeded loading flag is gone before the frame the test looks at.
  bool pending;

  int locateCalls = 0;
  int fetchCalls = 0;
  final List<String> queries = [];

  @override
  Future<WeatherPlace> locate() async {
    locateCalls++;
    return place;
  }

  @override
  Future<WeatherSnapshot> fetch(WeatherPlace place, TemperatureUnit unit) async {
    fetchCalls++;
    if (pending) return Completer<WeatherSnapshot>().future;
    final failure = failWith;
    if (failure != null) throw failure;
    return snapshot ??
        WeatherSnapshot(
          place: place,
          current: testReading(),
          forecast: testForecast(7),
          unit: unit,
        );
  }

  @override
  Future<List<WeatherPlace>> search(String query) async {
    queries.add(query);
    return results;
  }
}

WeatherReading testReading({
  double temperature = 72,
  int weatherCode = 0,
  bool isDay = true,
  double? cloudCoverPercent = 5,
  double? apparentTemperature = 70,
  int? humidity = 40,
  double? windSpeed = 6,
}) {
  return WeatherReading(
    temperature: temperature,
    weatherCode: weatherCode,
    isDay: isDay,
    cloudCoverPercent: cloudCoverPercent,
    apparentTemperature: apparentTemperature,
    humidity: humidity,
    windSpeed: windSpeed,
  );
}

/// [days] consecutive days from a fixed Monday, so `dayLabel` is stable
/// wherever and whenever the suite runs.
List<DayForecast> testForecast(int days, {int weatherCode = 0}) {
  return List.generate(days, (i) {
    return DayForecast(
      date: DateTime(2026, 1, 5 + i),
      weatherCode: weatherCode,
      tempMax: 72 + i.toDouble(),
      tempMin: 51 + i.toDouble(),
      precipProbability: 10 * i,
    );
  });
}
