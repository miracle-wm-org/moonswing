// The lease, the tick, and where the location comes from.
//
// Every test here builds a detached `WeatherStore` with a fake client, because
// that is the only thing in `lib/moon/` that can reach a network — and the
// point of the store is that most of the time it does not even do that.

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/moon/moon_store.dart';
import 'package:graceful_shell/weather/weather_config.dart';
import 'package:graceful_shell/weather/weather_store.dart';

import 'moon_fakes.dart';
import 'weather_fakes.dart';

MoonStore _moon(WeatherStore weather, {DateTime? at}) {
  final store = MoonStore.forTesting(
    weather: weather,
    clock: () => at ?? DateTime.utc(2024, 1, 25, 17, 54),
  );
  addTearDown(store.dispose);
  addTearDown(weather.dispose);
  return store;
}

void main() {
  group('the reading', () {
    test('answers before anything has taken a lease', () {
      final store = _moon(weatherStoreAt());
      // No lease, no timer, no location — and still a correct phase, because
      // there is nothing to wait for. This is the difference between this store
      // and `WeatherStore`, and the reason the widget has no loading state.
      expect(store.reading.illuminationPercent, 100);
      expect(store.reading.phase.label, 'Full moon');
      expect(store.ticking, isFalse);
    });

    test('is recomputed as the clock moves', () {
      var now = DateTime.utc(2024, 1, 11, 11, 57);
      final weather = weatherStoreAt();
      final store = MoonStore.forTesting(weather: weather, clock: () => now);
      addTearDown(store.dispose);
      addTearDown(weather.dispose);

      expect(store.reading.illuminationPercent, 0);
      now = DateTime.utc(2024, 1, 25, 17, 54);
      store.refresh();
      expect(store.reading.illuminationPercent, 100);
    });
  });

  group('leases', () {
    test('the first starts the tick and the last stops it', () {
      final store = _moon(weatherStoreAt());
      expect(store.ticking, isFalse);

      store.acquire();
      expect(store.leaseCount, 1);
      expect(store.ticking, isTrue);

      store.acquire();
      store.release();
      // Still one holder: a two-monitor desktop must not stop the machine's
      // only ticker when one of its widgets goes away.
      expect(store.ticking, isTrue);

      store.release();
      expect(store.leaseCount, 0);
      expect(store.ticking, isFalse);
    });

    test('releasing more than was taken cannot go negative', () {
      final store = _moon(weatherStoreAt());
      store.release();
      expect(store.leaseCount, 0);
    });
  });

  group('the location', () {
    test('comes from the weather config without any lookup at all', () async {
      final client = FakeWeatherClient();
      final store = _moon(weatherStoreAt(client: client));
      store.acquire();
      await pumpEventQueue();

      expect(client.locateCalls, 0, reason: 'the config already said where');
      expect(store.place?.name, 'Springfield');
      expect(store.locating, isFalse);
      expect(store.times, isNotNull);
      expect(store.reading.altitudeDegrees, isNotNull);
    });

    test('falls back to one IP lookup when the config has none', () async {
      final client = FakeWeatherClient();
      final weather = WeatherStore.forTesting(client: client);
      final store = _moon(weather);
      store.acquire();
      await pumpEventQueue();

      expect(client.locateCalls, 1);
      expect(store.place, kTestPlace);
      expect(store.times, isNotNull);
      // No forecast was fetched: the Moon wants a location, not the weather.
      expect(client.fetchCalls, 0);
      expect(weather.polling, isFalse);
    });

    test('a lookup that fails costs the times and nothing else', () async {
      final store = _moon(
        WeatherStore.forTesting(client: UnreachableLocateClient()),
      );
      store.acquire();
      await pumpEventQueue();

      expect(store.place, isNull);
      expect(store.hasLocation, isFalse);
      expect(store.locating, isFalse, reason: 'asked and answered, badly');
      expect(store.times, isNull);
      expect(store.reading.altitudeDegrees, isNull);
      // The half of the widget that does not need a location is unaffected.
      expect(store.reading.illuminationPercent, 100);
    });

    test('a lookup still in flight reads as looking, not as absent', () async {
      final store = _moon(
        WeatherStore.forTesting(client: SilentLocateClient()),
      );
      store.acquire();
      await pumpEventQueue();

      expect(store.locating, isTrue);
      expect(store.place, isNull);
    });

    test('the southern hemisphere turns the disc over', () async {
      final store = _moon(weatherStoreAt(latitude: -33.87, longitude: 151.21));
      store.acquire();
      await pumpEventQueue();

      expect(store.reading.southernView, isTrue);
    });

    test('a weather location change is adopted', () async {
      final weather = weatherStoreAt();
      final store = _moon(weather);
      store.acquire();
      await pumpEventQueue();
      final first = store.times;
      expect(store.place?.latitude, 39.8);

      weather.configure(const WeatherConfig(
        locationName: 'Sydney',
        latitude: -33.87,
        longitude: 151.21,
      ));
      // `configure` notifies only while the weather itself is polling, so the
      // store's own listener may not fire — the next tick has to notice too.
      store.refresh();
      await pumpEventQueue();
      store.refresh();

      expect(store.place?.name, 'Sydney');
      expect(store.reading.southernView, isTrue);
      expect(store.times, isNot(same(first)));
    });
  });

  group('the facts', () {
    test('are derived once per reading, not once per read', () async {
      final store = _moon(weatherStoreAt());
      store.acquire();
      await pumpEventQueue();

      final first = store.facts;
      // Every desktop widget on the machine reads this from its `build`, which
      // runs on every frame of a drag: the same reading has to answer with the
      // same list rather than re-walking the ephemeris for each of them.
      expect(identical(store.facts, first), isTrue);
      expect(first, isNotEmpty);
    });

    test('are rebuilt when the reading moves', () async {
      var now = DateTime.utc(2024, 1, 11, 11, 57);
      final weather = weatherStoreAt();
      final store = MoonStore.forTesting(weather: weather, clock: () => now);
      addTearDown(store.dispose);
      addTearDown(weather.dispose);
      store.acquire();
      await pumpEventQueue();

      final atNew = store.facts;
      now = DateTime.utc(2024, 1, 25, 17, 54);
      store.refresh();
      expect(identical(store.facts, atNew), isFalse);
      // A new Moon is the month's dark sky and a full one is not, so the two
      // lists really are different rather than merely different objects.
      expect(
        atNew.map((fact) => fact.title),
        contains('Best week for faint things'),
      );
      expect(
        store.facts.map((fact) => fact.title),
        isNot(contains('Best week for faint things')),
      );
    });
  });

  group('notifications', () {
    test('a tick that changes nothing does not wake every desktop', () async {
      final store = _moon(weatherStoreAt());
      store.acquire();
      await pumpEventQueue();

      var notifications = 0;
      store.addListener(() => notifications++);
      store.refresh();
      store.refresh();
      // Same clock, same place, same numbers: the `_publish` rule every store
      // watched by every monitor follows.
      expect(notifications, 0);
    });

    test('a real change does notify', () async {
      var now = DateTime.utc(2024, 1, 11, 11, 57);
      final weather = weatherStoreAt();
      final store = MoonStore.forTesting(weather: weather, clock: () => now);
      addTearDown(store.dispose);
      addTearDown(weather.dispose);
      store.acquire();
      await pumpEventQueue();

      var notifications = 0;
      store.addListener(() => notifications++);
      now = DateTime.utc(2024, 1, 18, 3, 53);
      store.refresh();
      expect(notifications, 1);
    });
  });
}
