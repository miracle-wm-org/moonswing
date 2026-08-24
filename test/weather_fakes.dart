// Shared fakes for the weather tests: an offline [WeatherClient] and the
// builders that make a reading.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it. The point
// of it is the same one `MprisStore.forTesting` makes — every weather test in
// the suite takes a real lease on a real store, and not one of them may reach
// for a network the test runner does not have.

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
  });

  WeatherPlace place;
  WeatherSnapshot? snapshot;
  List<WeatherPlace> results;

  /// When set, [fetch] throws it instead of answering.
  WeatherException? failWith;

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
