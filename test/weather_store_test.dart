import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/weather/weather_api.dart';
import 'package:moonswing/weather/weather_config.dart';
import 'package:moonswing/weather/weather_store.dart';

import 'weather_fakes.dart';

void main() {
  group('WeatherConfig', () {
    test('defaults', () {
      const config = WeatherConfig();
      expect(config.unit, 'fahrenheit');
      expect(config.refreshMinutes, 30);
      expect(config.locationName, '');
      expect(config.place, isNull);
    });

    test('reads a full location', () {
      final config = WeatherConfig.fromMap(const {
        'unit': 'celsius',
        'refresh_minutes': 45,
        'location': 'Berlin, Germany',
        'latitude': 52.52,
        'longitude': 13.405,
      });
      expect(config.temperatureUnit, TemperatureUnit.celsius);
      expect(config.refreshMinutes, 45);
      expect(config.place?.name, 'Berlin, Germany');
      expect(config.place?.latitude, 52.52);
    });

    test('a half-written pair is not a location', () {
      // Guessing which half to keep would put the user's weather somewhere on
      // the prime meridian.
      expect(
        WeatherConfig.fromMap(const {'location': 'Berlin', 'latitude': 52.5})
            .place,
        isNull,
      );
      expect(
        WeatherConfig.fromMap(const {'location': 'Berlin', 'longitude': 13.4})
            .place,
        isNull,
      );
    });

    test('a wrongly-typed value costs that key alone', () {
      // The one rule of the config layer: a throw out of any fromMap discards
      // the user's entire config.
      final config = WeatherConfig.fromMap(const {
        'unit': 42,
        'refresh_minutes': 'soon',
        'location': 'Berlin',
        'latitude': 52.5,
        'longitude': 13.4,
      });
      expect(config.unit, 'fahrenheit');
      expect(config.refreshMinutes, 30);
      expect(config.place, isNotNull);
    });

    test('an out-of-range coordinate is absent, not clamped', () {
      // A latitude of 400 is a typo; clamping it to 90 would silently show the
      // user the weather at the North Pole.
      final config = WeatherConfig.fromMap(
          const {'location': 'X', 'latitude': 400.0, 'longitude': 13.4});
      expect(config.latitude, isNull);
      expect(config.place, isNull);
    });

    test('the refresh interval is bounded away from a tight loop', () {
      expect(WeatherConfig.fromMap(const {'refresh_minutes': 0}).refreshMinutes,
          1);
      expect(
          WeatherConfig.fromMap(const {'refresh_minutes': -5}).refreshMinutes,
          1);
    });

    test('a TOML float lands as an int', () {
      expect(
          WeatherConfig.fromMap(const {'refresh_minutes': 15.0}).refreshMinutes,
          15);
    });

    test('value equality, so configure() can refuse a no-op', () {
      expect(const WeatherConfig(), const WeatherConfig());
      expect(const WeatherConfig(locationName: 'a'),
          isNot(const WeatherConfig(locationName: 'b')));
    });
  });

  group('WeatherStore leases', () {
    test('the first lease fetches immediately', () async {
      final client = FakeWeatherClient();
      final store = WeatherStore.forTesting(client: client);

      expect(store.loading, isTrue);
      store.acquire();
      await pumpEventQueue();

      expect(client.fetchCalls, 1);
      expect(store.loading, isFalse);
      expect(store.hasReading, isTrue);
      expect(store.temperatureText, '72°F');
      store.release();
      store.dispose();
    });

    test('a second lease does not fetch again', () async {
      // The whole point of the store: two bars on two monitors plus a desktop
      // widget used to mean three geolocation lookups and three pollers.
      final client = FakeWeatherClient();
      final store = WeatherStore.forTesting(client: client);

      store.acquire();
      await pumpEventQueue();
      store.acquire();
      store.acquire();
      await pumpEventQueue();

      expect(client.fetchCalls, 1);
      expect(client.locateCalls, 1);
      expect(store.leaseCount, 3);
      store
        ..release()
        ..release()
        ..release();
      expect(store.polling, isFalse);
      store.dispose();
    });

    test('releasing the last lease stops the timer', () async {
      final store = WeatherStore.forTesting(client: FakeWeatherClient());
      store.acquire();
      expect(store.polling, isTrue);
      await pumpEventQueue();
      store.release();
      expect(store.polling, isFalse);
      // An over-release must not go negative and leave the next acquire
      // thinking it is the second.
      store.release();
      expect(store.leaseCount, 0);
      store.dispose();
    });

    test('the IP lookup happens once, not once per refresh', () async {
      final client = FakeWeatherClient();
      final store = WeatherStore.forTesting(client: client);
      store.acquire();
      await pumpEventQueue();
      await store.refresh();
      await store.refresh();

      expect(client.fetchCalls, 3);
      expect(client.locateCalls, 1);
      store.release();
      store.dispose();
    });

    test('a configured location skips the IP lookup entirely', () async {
      final client = FakeWeatherClient();
      final store = WeatherStore.forTesting(
        client: client,
        config: const WeatherConfig(
          locationName: 'Berlin',
          latitude: 52.5,
          longitude: 13.4,
        ),
      );
      store.acquire();
      await pumpEventQueue();

      expect(client.locateCalls, 0);
      expect(store.place?.name, 'Berlin');
      store.release();
      store.dispose();
    });
  });

  group('WeatherStore failures', () {
    test('a failure is a visible state, not a silent one', () async {
      final client = FakeWeatherClient(
          failWith: const WeatherException('api.open-meteo.com answered 429'));
      final store = WeatherStore.forTesting(client: client);

      store.acquire();
      await pumpEventQueue();

      expect(store.loading, isFalse);
      expect(store.hasReading, isFalse);
      expect(store.error, contains('429'));
      store.release();
      store.dispose();
    });

    test('a failed refresh keeps the last reading on screen', () async {
      // An hour-old temperature is worth more than a blank card; the error line
      // says which one is being looked at.
      final client = FakeWeatherClient();
      final store = WeatherStore.forTesting(client: client);
      store.acquire();
      await pumpEventQueue();
      expect(store.hasReading, isTrue);

      client.failWith = const WeatherException('offline');
      await store.refresh();

      expect(store.hasReading, isTrue);
      expect(store.error, 'offline');
      store.release();
      store.dispose();
    });

    test('a recovered refresh clears the error', () async {
      final client =
          FakeWeatherClient(failWith: const WeatherException('offline'));
      final store = WeatherStore.forTesting(client: client);
      store.acquire();
      await pumpEventQueue();
      expect(store.error, isNotEmpty);

      client.failWith = null;
      await store.refresh();
      expect(store.error, isEmpty);
      expect(store.hasReading, isTrue);
      store.release();
      store.dispose();
    });
  });

  group('WeatherStore.configure', () {
    test('a changed unit refetches rather than waiting out the interval',
        () async {
      // Waiting ten minutes to see a setting take effect reads as the setting
      // not working.
      final client = FakeWeatherClient();
      final store = WeatherStore.forTesting(client: client);
      store.acquire();
      await pumpEventQueue();
      expect(client.fetchCalls, 1);

      store.configure(const WeatherConfig(unit: 'celsius'));
      await pumpEventQueue();

      expect(client.fetchCalls, 2);
      expect(store.unitLabel, '°C');
      store.release();
      store.dispose();
    });

    test('a changed location refetches and re-resolves', () async {
      final client = FakeWeatherClient();
      final store = WeatherStore.forTesting(client: client);
      store.acquire();
      await pumpEventQueue();

      store.configure(const WeatherConfig(
          locationName: 'Berlin', latitude: 52.5, longitude: 13.4));
      await pumpEventQueue();

      expect(client.fetchCalls, 2);
      expect(store.place?.name, 'Berlin');
      store.release();
      store.dispose();
    });

    test('an unchanged config does nothing', () async {
      // `Module.loadAll` pushes config on every sweep, and the settings UI
      // notifies on every keystroke anywhere in it.
      final client = FakeWeatherClient();
      final store = WeatherStore.forTesting(client: client);
      store.acquire();
      await pumpEventQueue();

      store.configure(const WeatherConfig());
      store.configure(const WeatherConfig());
      await pumpEventQueue();

      expect(client.fetchCalls, 1);
      store.release();
      store.dispose();
    });

    test('an unleased store does not start fetching on a config change',
        () async {
      final client = FakeWeatherClient();
      final store = WeatherStore.forTesting(client: client);
      store.configure(const WeatherConfig(unit: 'celsius'));
      await pumpEventQueue();

      expect(client.fetchCalls, 0);
      expect(store.polling, isFalse);
      store.dispose();
    });
  });
}
