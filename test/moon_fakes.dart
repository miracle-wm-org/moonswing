// Shared fakes for the lunar tests.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it. Its whole
// job is the one `weather_fakes.dart` does: every one of these tests drives a
// real `MoonStore`, and the store reaches `WeatherStore` for a location — so
// nothing in the suite may end up on a network the runner does not have.

import 'dart:async';

import 'package:moonswing/weather/weather_api.dart';
import 'package:moonswing/weather/weather_config.dart';
import 'package:moonswing/weather/weather_store.dart';

import 'weather_fakes.dart';

/// A client whose IP lookup fails, the way one behind a firewall does.
class UnreachableLocateClient extends FakeWeatherClient {
  @override
  Future<WeatherPlace> locate() async {
    locateCalls++;
    throw const WeatherException('no route to host');
  }
}

/// A client whose IP lookup never answers, so a store stays in its "still
/// looking" state for the whole of a test.
class SilentLocateClient extends FakeWeatherClient {
  @override
  Future<WeatherPlace> locate() {
    locateCalls++;
    return Completer<WeatherPlace>().future;
  }
}

/// A detached weather store carrying [latitude]/[longitude] as the user's
/// picked location — the common case, and the one that costs no request at all.
/// Pass nulls for the automatic case, which is the one that reaches [client].
WeatherStore weatherStoreAt({
  double? latitude = 39.8,
  double? longitude = -89.65,
  FakeWeatherClient? client,
  String name = 'Springfield',
}) {
  return WeatherStore.forTesting(
    client: client ?? FakeWeatherClient(),
    config: WeatherConfig(
      locationName: name,
      latitude: latitude,
      longitude: longitude,
    ),
  );
}
