import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/overlay/calendar/time_zones.dart';
import 'package:graceful_shell/world_cities.dart';

WorldCity _city(String name, {String country = 'Nowhere', String zone = 'Etc/UTC'}) =>
    WorldCity(
      name: name,
      country: country,
      zone: zone,
      latitude: 0,
      longitude: 0,
    );

void main() {
  group('the table', () {
    test('carries the cities the IANA database does not name', () {
      final names = {for (final city in kWorldCities) city.name};
      // The four the picker was reported missing, and their neighbours: none
      // of them is an IANA zone name, which is the whole reason this exists.
      expect(
        names,
        containsAll([
          'New Delhi',
          'Mumbai',
          'Bengaluru',
          'Chennai',
          'San Francisco',
          'Boston',
          'Seattle',
          'Cape Town',
          'Barcelona',
          'Osaka',
          'Melbourne',
          'Rio de Janeiro',
        ]),
      );
    });

    test('names no city twice', () {
      // Two rows with one name are two rows nothing can tell apart, and in the
      // clock picker they would both write the same zone.
      final seen = <String>{};
      final repeated = [
        for (final city in kWorldCities)
          if (!seen.add('${city.name}|${city.country}')) city.name,
      ];
      expect(repeated, isEmpty);
    });

    test('every coordinate is on Earth', () {
      for (final city in kWorldCities) {
        expect(city.latitude, inInclusiveRange(-90, 90), reason: city.name);
        expect(city.longitude, inInclusiveRange(-180, 180), reason: city.name);
      }
    });

    test('every zone is one the IANA database knows', () {
      // The guardrail behind `_buildZoneNames`' degradation: a city whose zone
      // this build cannot resolve is dropped from the picker rather than
      // thrown for, so a typo here would be invisible without this test.
      ensureTimeZonesInitialized();
      final unknown = [
        for (final city in kWorldCities)
          if (resolveZone(city.zone, DateTime.utc(2026, 1, 1)) == null)
            '${city.name} -> ${city.zone}',
      ];
      expect(unknown, isEmpty);
    });

    test('describes and qualifies a place the way the weather row does', () {
      final austin = kWorldCities.firstWhere((city) => city.name == 'Austin');
      expect(austin.description, 'Austin, Texas, United States');
      expect(austin.qualifier, 'Texas, United States');

      final tokyo = kWorldCities.firstWhere((city) => city.name == 'Tokyo');
      expect(tokyo.description, 'Tokyo, Japan');
      expect(tokyo.qualifier, 'Japan');
    });
  });

  group('rankWorldCities', () {
    final cities = [
      _city('London', country: 'United Kingdom'),
      _city('New Delhi', country: 'India'),
      _city('New York', country: 'United States'),
      _city('Delhi Ridge', country: 'India'),
      _city('Mumbai', country: 'India'),
    ];

    test('an empty query answers the head of the table', () {
      expect(
        rankWorldCities(cities, '', limit: 2).map((c) => c.name),
        ['London', 'New Delhi'],
      );
    });

    test('a prefix beats a word-boundary hit beats a substring', () {
      final results = rankWorldCities(cities, 'delhi').map((c) => c.name);
      // "Delhi Ridge" starts with it; "New Delhi" has it on a word boundary.
      expect(results, ['Delhi Ridge', 'New Delhi']);
    });

    test('the country matches, ranked under every city hit', () {
      final results =
          rankWorldCities(cities, 'india', limit: 10).map((c) => c.name);
      expect(results, ['New Delhi', 'Delhi Ridge', 'Mumbai']);
    });

    test('an alias is searchable and never displayed', () {
      final bombay = [
        WorldCity(
          name: 'Mumbai',
          country: 'India',
          zone: 'Asia/Kolkata',
          latitude: 19.08,
          longitude: 72.88,
          aliases: const ['Bombay'],
        ),
      ];
      expect(rankWorldCities(bombay, 'bombay').single.name, 'Mumbai');
      expect(rankWorldCities(bombay, 'mumbai').single.name, 'Mumbai');
    });

    test('the shipped table answers the names people still type', () {
      String top(String query) => rankWorldCities(kWorldCities, query).first.name;
      expect(top('bangalore'), 'Bengaluru');
      expect(top('bombay'), 'Mumbai');
      expect(top('saigon'), 'Ho Chi Minh City');
      expect(top('peking'), 'Beijing');
      expect(top('calcutta'), 'Kolkata');
    });

    test('drops everything that does not match, and honours the limit', () {
      expect(rankWorldCities(cities, 'zzz'), isEmpty);
      expect(rankWorldCities(cities, 'new', limit: 1), hasLength(1));
    });

    test('is case- and whitespace-insensitive', () {
      expect(rankWorldCities(cities, '  NEW DELHI ').first.name, 'New Delhi');
    });
  });
}
