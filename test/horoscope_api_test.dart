// The horoscope client: the URL it asks for, and the two response shapes it
// has to read.
//
// `weather_api_test.dart`'s target — the parse is a pure function over a
// decoded map, because it is where a shape change at the far end turns into a
// crash and only a live response would otherwise exercise it.

import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/astrology/horoscope_api.dart';

void main() {
  group('horoscopeUrl', () {
    test('builds the daily endpoint the server documents', () {
      final url = horoscopeUrl(
        sign: 'Aries',
        period: HoroscopePeriod.daily,
        apiBase: 'https://example.test',
      );
      expect(url.host, 'example.test');
      expect(url.path, '/api/v1/get-horoscope/daily');
      expect(url.queryParameters['sign'], 'Aries');
      // The daily endpoint's `day` argument is `required=True` in the server's
      // own reqparse, so omitting it is a 400 rather than a default.
      expect(url.queryParameters['day'], 'TODAY');
    });

    test('sends no day to the weekly and monthly endpoints', () {
      // They do not take one, and describing a contract that is not there is
      // how the next person learns the wrong thing about this API.
      for (final period in [
        HoroscopePeriod.weekly,
        HoroscopePeriod.monthly,
      ]) {
        final url = horoscopeUrl(
          sign: 'Leo',
          period: period,
          apiBase: 'https://example.test',
        );
        expect(url.path, '/api/v1/get-horoscope/${period.path}');
        expect(url.queryParameters.containsKey('day'), isFalse);
      }
    });

    test('a trailing slash is the same setting, not a double slash', () {
      final bare = horoscopeUrl(
        sign: 'Leo',
        period: HoroscopePeriod.daily,
        apiBase: 'https://example.test',
      );
      final slashed = horoscopeUrl(
        sign: 'Leo',
        period: HoroscopePeriod.daily,
        apiBase: '  https://example.test///  ',
      );
      expect(slashed, bare);
    });
  });

  group('HoroscopePeriod', () {
    test('parses its path, and a misspelling costs the setting', () {
      expect(HoroscopePeriod.parse('weekly'), HoroscopePeriod.weekly);
      expect(HoroscopePeriod.parse('  MONTHLY '), HoroscopePeriod.monthly);
      expect(HoroscopePeriod.parse('yearly'), HoroscopePeriod.daily);
      expect(HoroscopePeriod.parse(''), HoroscopePeriod.daily);
    });

    test('a longer period polls less often', () {
      expect(
        HoroscopePeriod.monthly.minimumInterval,
        greaterThan(HoroscopePeriod.daily.minimumInterval),
      );
    });
  });

  group('parseHoroscope', () {
    test('reads the deployed instance\'s object shape', () {
      final reading = parseHoroscope(const {
        'success': true,
        'status': 200,
        'data': {
          'date': 'August 26, 2026',
          'horoscope_data': 'A good day for reading release notes.',
        },
      }, HoroscopePeriod.daily);
      expect(reading.text, 'A good day for reading release notes.');
      expect(reading.date, 'August 26, 2026');
      expect(reading.period, HoroscopePeriod.daily);
    });

    test('reads the repository revision\'s bare-string shape', () {
      // The server has shipped `data` both ways; accepting only one of them is
      // a parse that breaks on a deployment nobody told us about.
      final reading = parseHoroscope(const {
        'success': true,
        'data': '  A good day for reading release notes.  ',
      }, HoroscopePeriod.weekly);
      expect(reading.text, 'A good day for reading release notes.');
      expect(reading.date, isEmpty);
      expect(reading.period, HoroscopePeriod.weekly);
    });

    test('a missing date costs the date alone', () {
      // Degrades per field, `parseForecast`'s rule: the paragraph is the
      // reading and the date is an ornament.
      final reading = parseHoroscope(const {
        'data': {'horoscope_data': 'Still a horoscope.'},
      }, HoroscopePeriod.daily);
      expect(reading.text, 'Still a horoscope.');
      expect(reading.date, isEmpty);
    });

    test('a wrongly-typed date is absent rather than stringified', () {
      final reading = parseHoroscope(const {
        'data': {'horoscope_data': 'Still a horoscope.', 'date': 42},
      }, HoroscopePeriod.daily);
      expect(reading.date, isEmpty);
    });

    test('an empty paragraph is a failure, not an empty card', () {
      for (final body in <Map<String, dynamic>>[
        {'data': ''},
        {'data': '   '},
        {'data': <String, dynamic>{'horoscope_data': ''}},
        {'data': <String, dynamic>{}},
      ]) {
        expect(
          () => parseHoroscope(body, HoroscopePeriod.daily),
          throwsA(isA<HoroscopeException>()),
        );
      }
    });

    test('a shape this build predates throws with what the server said', () {
      expect(
        () => parseHoroscope(const {
          'success': false,
          'message': 'No such zodiac sign exists',
        }, HoroscopePeriod.daily),
        throwsA(
          isA<HoroscopeException>().having(
            (e) => e.message,
            'message',
            'No such zodiac sign exists',
          ),
        ),
      );
    });

    test('an unrecognisable body still says something useful', () {
      expect(
        () => parseHoroscope(const {'data': 42}, HoroscopePeriod.daily),
        throwsA(
          isA<HoroscopeException>().having(
            (e) => e.message,
            'message',
            contains('Unexpected response'),
          ),
        ),
      );
    });
  });
}
