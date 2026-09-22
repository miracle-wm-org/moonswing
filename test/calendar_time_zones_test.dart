import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/overlay/calendar/month.dart';
import 'package:moonswing/overlay/calendar/time_zones.dart';

List<TimeZoneName> _zones(List<String> names) =>
    [for (final name in names) TimeZoneName(name)];

void main() {
  group('zoneCityLabel', () {
    test('takes the last segment and un-underscores it', () {
      expect(zoneCityLabel('America/New_York'), 'New York');
      expect(zoneCityLabel('America/Argentina/Buenos_Aires'), 'Buenos Aires');
      expect(zoneCityLabel('UTC'), 'UTC');
    });
  });

  group('formatUtcOffset', () {
    test('formats whole, half and negative offsets', () {
      expect(formatUtcOffset(Duration.zero), 'UTC');
      expect(formatUtcOffset(const Duration(hours: 9)), 'UTC+9');
      expect(formatUtcOffset(const Duration(hours: 5, minutes: 30)), 'UTC+5:30');
      expect(formatUtcOffset(const Duration(hours: -8)), 'UTC-8');
      expect(
        formatUtcOffset(const Duration(hours: -3, minutes: -30)),
        'UTC-3:30',
      );
    });
  });

  group('formatClockTime', () {
    test('pads to 24-hour, with and without seconds', () {
      final t = DateTime(2026, 8, 9, 7, 4, 3);
      expect(formatClockTime(t), '07:04:03');
      expect(formatClockTime(t, seconds: false), '07:04');
    });
  });

  group('formatDayDelta', () {
    test('is empty on the same day and signed otherwise', () {
      expect(formatDayDelta(0), '');
      expect(formatDayDelta(1), '+1d');
      expect(formatDayDelta(-1), '-1d');
      expect(formatDayDelta(2), '+2d');
    });
  });

  group('dayDelta', () {
    test('counts calendar days, not elapsed time', () {
      expect(dayDelta(DateTime(2026, 8, 10, 1), DateTime(2026, 8, 9, 23)), 1);
      expect(dayDelta(DateTime(2026, 8, 8, 23), DateTime(2026, 8, 9, 1)), -1);
      expect(dayDelta(DateTime(2026, 8, 9, 0), DateTime(2026, 8, 9, 23)), 0);
    });

    test('survives a short DST day', () {
      // 26 hours apart in wall-clock terms but only two calendar days; a naive
      // difference().inDays over a 23-hour local day would report 1, not 2.
      expect(dayDelta(DateTime(2026, 3, 30, 1), DateTime(2026, 3, 28, 23)), 2);
    });
  });

  group('rankTimeZones', () {
    final zones = _zones([
      'America/New_York',
      'Asia/Tokyo',
      'Australia/Sydney',
      'Europe/London',
      'Europe/Lisbon',
      'Pacific/Auckland',
      'UTC',
    ]);

    test('an empty query lists everything in order', () {
      expect(
        rankTimeZones(zones, '').map((z) => z.name),
        zones.map((z) => z.name),
      );
    });

    test('an exact city beats a prefix beats a substring', () {
      final results = rankTimeZones(zones, 'lon').map((z) => z.name).toList();
      expect(results.first, 'Europe/London');
      expect(results, isNot(contains('Asia/Tokyo')));
    });

    test('matches a word inside a multi-word city', () {
      expect(
        rankTimeZones(zones, 'york').map((z) => z.name),
        contains('America/New_York'),
      );
    });

    test('matches the region, ranked below any city hit', () {
      final results = rankTimeZones(zones, 'europe').map((z) => z.name);
      expect(results, containsAll(['Europe/London', 'Europe/Lisbon']));
    });

    test('drops everything that does not match', () {
      expect(rankTimeZones(zones, 'zzz'), isEmpty);
    });
  });

  group('the IANA database', () {
    // Also the proof that the package needs no Flutter binding and no asset
    // bundle: this group runs in a plain test with neither.
    setUpAll(ensureTimeZonesInitialized);

    test('offsets follow daylight saving', () {
      // Sydney is AEDT (+11) in January and AEST (+10) in July.
      expect(
        resolveZone('Australia/Sydney', DateTime.utc(2026, 1, 15))!.offset,
        const Duration(hours: 11),
      );
      expect(
        resolveZone('Australia/Sydney', DateTime.utc(2026, 7, 15))!.offset,
        const Duration(hours: 10),
      );
    });

    test('converts to the zone wall clock', () {
      final tokyo = resolveZone('Asia/Tokyo', DateTime.utc(2026, 8, 9, 15))!;
      expect(tokyo.offset, const Duration(hours: 9));
      expect(formatClockTime(tokyo.time), '00:00:00');
      expect(tokyo.time.day, 10);
    });

    test('an unknown zone resolves to null rather than throwing', () {
      expect(resolveZone('Nowhere/Nothing', DateTime.utc(2026, 1, 1)), isNull);
    });

    test('the picker list excludes pseudo-zones but keeps Etc/UTC', () {
      final names = worldTimeZoneNames().map((z) => z.name).toSet();
      expect(names, contains('Europe/London'));
      expect(names, contains('Etc/UTC'));
      expect(names, isNot(contains('Factory')));
      expect(names, isNot(contains('Etc/GMT+5')));
      expect(names.any((n) => n.startsWith('SystemV/')), isFalse);
    });

    test('the picker offers the cities the database does not name', () {
      // The database names zones, not places: India is `Asia/Kolkata`, so a
      // picker built from it alone has no New Delhi to find.
      final zones = worldTimeZoneNames();
      final delhi = zones.singleWhere((z) => z.city == 'New Delhi');
      expect(delhi.name, 'Asia/Kolkata');
      expect(delhi.region, 'Delhi, India');
      // The label is what stops the added clock being titled "Kolkata".
      expect(delhi.label, 'New Delhi');

      expect(rankTimeZones(zones, 'new delhi').first.city, 'New Delhi');
      expect(
        rankTimeZones(zones, 'san francisco').first.name,
        'America/Los_Angeles',
      );
      expect(rankTimeZones(zones, 'cape town').first.name,
          'Africa/Johannesburg');
    });

    test('a zone tzdata has merged away still resolves and is offered', () {
      // The embedded database carries canonical zones only, and tzdata has
      // spent several releases merging zones whose rules have long agreed into
      // one another. `Europe/Amsterdam` is one of the names those merges left
      // behind as a link: it is what everything outside the database still
      // calls Amsterdam's time, it is what the picker writes into the config,
      // and without the link table it resolves to nothing — the row reads
      // "Unknown time zone", and a third of Europe's capitals are missing from
      // the picker entirely.
      final at = DateTime.utc(2026, 1, 1, 12);
      final amsterdam = resolveZone('Europe/Amsterdam', at);
      expect(amsterdam, isNotNull);
      // Same instant, same wall clock as the zone it was merged into.
      expect(amsterdam!.time, resolveZone('Europe/Brussels', at)!.time);
      expect(amsterdam.offset, const Duration(hours: 1));

      for (final zone in const [
        'Europe/Copenhagen',
        'Europe/Oslo',
        'Europe/Stockholm',
        'Asia/Kuala_Lumpur',
        'Atlantic/Reykjavik',
        'America/Nassau',
      ]) {
        expect(resolveZone(zone, at), isNotNull, reason: zone);
      }

      final zones = worldTimeZoneNames();
      final row = zones.singleWhere((z) => z.city == 'Amsterdam');
      expect(row.name, 'Europe/Amsterdam');
      expect(row.label, 'Amsterdam');
      expect(rankTimeZones(zones, 'copenhagen').first.city, 'Copenhagen');
    });

    test('a city its own zone already names gets no second row', () {
      final zones = worldTimeZoneNames();
      final tokyo = zones.singleWhere((z) => z.city == 'Tokyo');
      expect(tokyo.name, 'Asia/Tokyo');
      // An IANA row needs no label: the zone already says what it is called.
      expect(tokyo.label, isNull);
      expect(zones.singleWhere((z) => z.city == 'New York').label, isNull);
    });

    test('a city row still answers to the zone it keeps time in', () {
      // Ranked last, so it can never displace a hit on the name being shown.
      final zones = worldTimeZoneNames();
      final kolkata = rankTimeZones(zones, 'kolkata').map((z) => z.city);
      expect(kolkata.first, 'Kolkata');
      expect(kolkata, contains('New Delhi'));
    });
  });
}
