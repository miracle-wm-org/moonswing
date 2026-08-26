// `[astrology]` and the store that fetches from it: what a birthday parses to,
// when a config change is worth a request, and what a failure costs.

import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/astrology/astrology_config.dart';
import 'package:graceful_shell/astrology/astrology_store.dart';
import 'package:graceful_shell/astrology/horoscope_api.dart';
import 'package:graceful_shell/astrology/zodiac.dart';

import 'astrology_fakes.dart';

AstrologyConfig _born(
  int year,
  int month,
  int day, {
  String period = 'daily',
}) =>
    AstrologyConfig(birthday: DateTime(year, month, day), period: period);

void main() {
  group('AstrologyConfig', () {
    test('defaults', () {
      const config = AstrologyConfig();
      expect(config.birthday, isNull);
      expect(config.sign, isNull);
      expect(config.period, 'daily');
      expect(config.refreshMinutes, 180);
      expect(config.apiBase, kDefaultHoroscopeApiBase);
    });

    test('reads a full table', () {
      final config = AstrologyConfig.fromMap(const {
        'birthday': '1990-04-17',
        'period': 'weekly',
        'refresh_minutes': 360,
        'api_base': 'https://horoscope.internal',
      });
      expect(config.birthday, DateTime(1990, 4, 17));
      expect(config.sign, ZodiacSign.aries);
      expect(config.horoscopePeriod, HoroscopePeriod.weekly);
      expect(config.refreshMinutes, 360);
      expect(config.apiBase, 'https://horoscope.internal');
    });

    test('a wrongly-typed value costs that key alone', () {
      // The one rule of the config layer: a throw out of any fromMap is caught
      // by AppConfig.load, which discards the user's entire config.
      final config = AstrologyConfig.fromMap(const {
        'birthday': 42,
        'period': true,
        'refresh_minutes': 'often',
        'api_base': <String>[],
      });
      expect(config.birthday, isNull);
      expect(config.period, 'daily');
      expect(config.refreshMinutes, 180);
      expect(config.apiBase, kDefaultHoroscopeApiBase);
    });

    test('the refresh interval is clamped, then floored by the period', () {
      // `refresh_minutes = 0` is a tight loop against somebody's free API, and
      // an hourly poll for a monthly horoscope asks for the same paragraph
      // seven hundred times a month.
      expect(
        AstrologyConfig.fromMap(const {'refresh_minutes': 0}).refreshMinutes,
        1,
      );
      expect(
        const AstrologyConfig(period: 'daily', refreshMinutes: 5)
            .refreshInterval,
        HoroscopePeriod.daily.minimumInterval,
      );
      expect(
        const AstrologyConfig(period: 'monthly', refreshMinutes: 60)
            .refreshInterval,
        HoroscopePeriod.monthly.minimumInterval,
      );
      // A configured interval longer than the floor is left alone.
      expect(
        const AstrologyConfig(period: 'daily', refreshMinutes: 600)
            .refreshInterval,
        const Duration(minutes: 600),
      );
    });

    test('carries value equality, which is what makes a keystroke free', () {
      expect(AstrologyConfig.fromMap(const {'birthday': '1990-04-17'}),
          _born(1990, 4, 17));
      expect(const AstrologyConfig() == const AstrologyConfig(period: 'weekly'),
          isFalse);
    });
  });

  group('parseBirthday', () {
    test('reads the string the settings UI writes', () {
      expect(parseBirthday('1990-04-17'), DateTime(1990, 4, 17));
      expect(parseBirthday('  1990-04-17  '), DateTime(1990, 4, 17));
    });

    test('reads a hand-written TOML date through its toString', () {
      // `birthday = 1990-04-17` in the file is a TOML *local date*, which the
      // parser hands back as one of its own types.
      expect(parseBirthday(_TomlishDate('1990-04-17')), DateTime(1990, 4, 17));
    });

    test('takes the date part of a DateTime and nothing else', () {
      expect(
        parseBirthday(DateTime(1990, 4, 17, 23, 59)),
        DateTime(1990, 4, 17),
      );
    });

    test('drops the zone of a hand-written offset date-time', () {
      // The day is the whole of the answer, and a zone that shifts it is worse
      // than the precision it buys.
      expect(
        parseBirthday('1990-04-17T23:00:00-08:00'),
        DateTime(1990, 4, 17),
      );
    });

    test('refuses what is not a date', () {
      for (final raw in ['', '   ', 'yesterday', '17/04/1990', '1990-04']) {
        expect(parseBirthday(raw), isNull, reason: raw);
      }
      expect(parseBirthday(null), isNull);
    });

    test('refuses a day that does not exist rather than rolling it over', () {
      // `DateTime(2001, 13, 40)` is a valid Dart call that answers some day in
      // February 2002, and silently moving somebody's birthday by five months
      // is worse than not reading it.
      expect(parseBirthday('2001-13-01'), isNull);
      expect(parseBirthday('2001-02-30'), isNull);
      expect(parseBirthday('2001-00-10'), isNull);
      // A real leap day still reads.
      expect(parseBirthday('2000-02-29'), DateTime(2000, 2, 29));
      expect(parseBirthday('1900-02-29'), isNull);
    });

    test('out of range is absent rather than clamped', () {
      // The solar series is good for the centuries around J2000 and drifts
      // outside them; a year of 190 is a typo, and answering it with the sign
      // for 1600 would substitute a plausible answer for the one meant.
      expect(parseBirthday('0190-04-17'), isNull);
      expect(parseBirthday('9999-04-17'), isNull);
      expect(parseBirthday('1600-01-01'), isNotNull);
    });
  });

  group('AstrologyStore', () {
    test('the first lease fetches; a second one does not', () {
      final client = FakeHoroscopeClient();
      final store = AstrologyStore.forTesting(
        client: client,
        config: _born(1990, 4, 17),
      );
      addTearDown(store.dispose);

      store.acquire();
      expect(client.calls, 1);
      expect(client.signs.single, 'Aries');
      store.acquire();
      expect(client.calls, 1, reason: 'one request for the machine');

      store.release();
      expect(store.polling, isTrue);
      store.release();
      expect(store.polling, isFalse, reason: 'the last lease stops the timer');
    });

    test('with no birthday it opens nothing at all', () async {
      final client = FakeHoroscopeClient();
      final store = AstrologyStore.forTesting(client: client);
      addTearDown(store.dispose);

      store.acquire();
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, 0);
      expect(store.zodiac, isNull);
      expect(store.error, isEmpty, reason: 'nothing failed');
      expect(store.loading, isFalse);
    });

    test('the sign is arithmetic and needs no network', () {
      final store = AstrologyStore.forTesting(
        client: FakeHoroscopeClient(),
        config: _born(1990, 4, 17),
      );
      addTearDown(store.dispose);
      expect(store.sign, ZodiacSign.aries);
    });

    test('publishes the paragraph it fetched', () async {
      final client = FakeHoroscopeClient(text: 'Mercury is doing something.');
      final store = AstrologyStore.forTesting(
        client: client,
        config: _born(2000, 7, 30),
      );
      addTearDown(store.dispose);

      store.acquire();
      await Future<void>.delayed(Duration.zero);

      expect(client.signs.single, 'Leo');
      expect(store.reading?.text, 'Mercury is doing something.');
      expect(store.error, isEmpty);
      expect(store.updatedAt, isNotNull);
    });

    test('a failed refresh keeps the last paragraph on screen', () async {
      final client = FakeHoroscopeClient(text: 'Kept.');
      final store = AstrologyStore.forTesting(
        client: client,
        config: _born(2000, 7, 30),
      );
      addTearDown(store.dispose);

      store.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(store.reading?.text, 'Kept.');

      client.failWith = const HoroscopeException('example.test answered 503');
      await store.refresh();

      // A horoscope from this morning is worth more than a blank card, and the
      // error line says which one is being looked at. `WeatherStore`'s rule.
      expect(store.reading?.text, 'Kept.');
      expect(store.error, 'example.test answered 503');
    });

    test('a moved sign drops the other sign\'s paragraph and refetches',
        () async {
      final client = FakeHoroscopeClient();
      final store = AstrologyStore.forTesting(
        client: client,
        config: _born(2000, 7, 30),
      );
      addTearDown(store.dispose);

      store.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(store.reading, isNotNull);

      store.configure(_born(1990, 4, 17));
      // Dropped immediately: showing Leo's horoscope under the name Aries is
      // the one wrong answer this card can give.
      expect(store.reading, isNull);
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, 2);
      expect(client.signs.last, 'Aries');
      expect(store.reading, isNotNull);
    });

    test('a moved period refetches; an identical config does nothing',
        () async {
      final client = FakeHoroscopeClient();
      final store = AstrologyStore.forTesting(
        client: client,
        config: _born(2000, 7, 30),
      );
      addTearDown(store.dispose);

      store.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(client.calls, 1);

      // ConfigStore notifies on every keystroke anywhere in the settings UI;
      // the equality check is what makes all of those free.
      store.configure(_born(2000, 7, 30));
      await Future<void>.delayed(Duration.zero);
      expect(client.calls, 1);

      store.configure(_born(2000, 7, 30, period: 'weekly'));
      await Future<void>.delayed(Duration.zero);
      expect(client.calls, 2);
      expect(client.periods.last, HoroscopePeriod.weekly);
    });

    test('a moved server refetches', () async {
      final client = FakeHoroscopeClient();
      final store = AstrologyStore.forTesting(
        client: client,
        config: _born(2000, 7, 30),
      );
      addTearDown(store.dispose);

      store.acquire();
      await Future<void>.delayed(Duration.zero);

      store.configure(AstrologyConfig(
        birthday: DateTime(2000, 7, 30),
        apiBase: 'https://horoscope.internal',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, 2);
      expect(client.bases.last, 'https://horoscope.internal');
    });

    test('a config change while unleased makes no request', () async {
      // Nothing is drawing the card, so there is nothing to fetch for; the next
      // lease is what asks.
      final client = FakeHoroscopeClient();
      final store = AstrologyStore.forTesting(client: client);
      addTearDown(store.dispose);

      store.configure(_born(1990, 4, 17));
      await Future<void>.delayed(Duration.zero);
      expect(client.calls, 0);

      store.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(client.calls, 1);
    });

    test('a refresh in flight is dropped, not queued behind', () async {
      final client = FakeHoroscopeClient(pending: true);
      final store = AstrologyStore.forTesting(
        client: client,
        config: _born(1990, 4, 17),
      );
      addTearDown(store.dispose);

      store.acquire();
      await store.refresh();
      expect(client.calls, 1);
    });
  });
}

/// Stands in for `package:toml`'s own local-date type, whose `toString` is the
/// ISO date. The config layer never imports toml, so this is how that path is
/// exercised without one.
class _TomlishDate {
  const _TomlishDate(this._text);

  final String _text;

  @override
  String toString() => _text;
}
