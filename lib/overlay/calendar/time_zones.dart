// The calendar tab's time zone layer.
//
// The only file in the shell that imports `package:timezone`. Keeping it that
// way is what lets [rankTimeZones] and the formatters be plain unit tests, and
// what keeps `config.dart` — parsed at start-up, long before the overlay exists
// — free of the dependency.
//
// The database is *data*, not the formatting machinery `month.dart` refuses:
// daylight-saving tables change every few months by political decision.

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:timezone/data/latest.dart' show initializeTimeZones;
import 'package:timezone/timezone.dart' as tz;

import 'package:graceful_shell/world_cities.dart';

bool _initialized = false;

/// Loads the IANA database. Idempotent, and cheap after the first call.
///
/// Deliberately not called from `main()`: the calendar starts no service, and
/// `package:timezone/data/latest.dart` embeds the database as a Dart byte
/// literal, so nothing forces it earlier. The cost is one parse the first time
/// the overlay is opened.
///
/// `standalone.dart` and `browser.dart` read the database from disk or over HTTP;
/// neither is usable here.
void ensureTimeZonesInitialized() {
  if (_initialized) return;
  initializeTimeZones();
  _initialized = true;
}

/// A wall clock in some zone, at some instant.
@immutable
class ZoneTime {
  const ZoneTime({
    required this.time,
    required this.offset,
    required this.abbreviation,
  });

  /// The wall clock in the zone. A `TZDateTime` in practice, but typed as
  /// [DateTime] so no caller outside this file needs the package.
  final DateTime time;

  /// Offset from UTC *at that instant*, so it follows daylight saving.
  final Duration offset;

  /// The zone's abbreviation at that instant — `BST`, `AEDT`, or a numeric
  /// `+0530` for the zones that have never had a letter form.
  final String abbreviation;
}

/// One row of the zone picker: a place, the zone it keeps time in, and its
/// searchable text pre-folded to lower case.
///
/// The folding happens once, when the list is built — the [SearchableApp] trick
/// from `lib/launcher/app_search.dart`.
///
/// A row is one of two things. An **IANA row** is a zone standing for itself:
/// [name] is the zone, [city] its last segment, [region] its first, and [label]
/// null. A **city row** comes from `lib/world_cities.dart` and is a place the
/// database has no name for — New Delhi, San Francisco, Cape Town — so [name] is
/// still the zone that gets stored and [label] is what the world-clock row must
/// be titled: without it, picking New Delhi gives a clock labelled Kolkata.
@immutable
class TimeZoneName {
  TimeZoneName(String name)
      : this._(
          name: name,
          city: zoneCityLabel(name),
          region: name.contains('/') ? name.split('/').first : name,
          label: null,
        );

  /// A place the IANA database does not name, keeping time in [zone].
  TimeZoneName.place({
    required String zone,
    required String city,
    required String region,
  }) : this._(name: zone, city: city, region: region, label: city);

  TimeZoneName._({
    required this.name,
    required this.city,
    required this.region,
    required this.label,
  })  : _city = city.toLowerCase(),
        _region = region.toLowerCase(),
        // The zone's own name stays searchable on a city row, so typing
        // `kolkata` still turns up every Indian city and `asia` still turns up
        // the continent — it is ranked last, so it can never displace a hit on
        // the name the row is actually showing.
        _full = ('${name.replaceAll('_', ' ').replaceAll('/', ' ')} '
                '$city $region')
            .toLowerCase();

  /// The raw IANA name, e.g. `America/Argentina/Buenos_Aires`. This is what is
  /// stored in the config.
  final String name;

  /// What the row is called: the zone's last segment, humanised (`Buenos
  /// Aires`), or a city the database does not name (`New Delhi`).
  final String city;

  /// Where it is: the zone's first segment (`America`), or a city's country
  /// and region (`California, United States`).
  final String region;

  /// The label a world clock added from this row must carry, or null when the
  /// zone's own city segment already says it.
  final String? label;

  final String _city;
  final String _region;
  final String _full;
}

List<TimeZoneName>? _names;

/// The IANA *backward* links this shell's own data names, and the canonical zone
/// each now points at.
///
/// `package:timezone/data/latest.dart` carries only the **canonical** zones, 341
/// of them. tzdata has spent recent releases merging zones whose rules have
/// agreed since the 1970s, and what a merged zone leaves behind is a *link*:
/// `Europe/Amsterdam` is still the name of Amsterdam's time, but the rules now
/// live under `Europe/Brussels`.
///
/// That is 38 of the cities in `lib/world_cities.dart`, and without this table
/// every one is dropped by [_buildZoneNames]' degradation rule — so the picker
/// silently does not offer a third of Europe's capitals, and a config naming one
/// renders "Unknown time zone" for a name every airline ticket still uses.
///
/// Switching the embedded variant to `latest_all` is the other fix and is worse:
/// it carries 206 more pickable names, nearly all deprecated spellings of zones
/// already listed, and nothing in the package's API says which of two identical
/// zones is the current name.
///
/// Two things to keep. It is a **fallback**, consulted only when the database
/// does not know the name itself, so a link tzdata later splits back out is
/// answered by the database. And every entry links *to a zone this build
/// carries*, which `test/world_cities_test.dart` checks.
const Map<String, String> _kZoneLinks = {
  'Africa/Accra': 'Africa/Abidjan',
  'Africa/Addis_Ababa': 'Africa/Nairobi',
  'Africa/Dakar': 'Africa/Abidjan',
  'Africa/Dar_es_Salaam': 'Africa/Nairobi',
  'Africa/Gaborone': 'Africa/Maputo',
  'Africa/Harare': 'Africa/Maputo',
  'Africa/Kampala': 'Africa/Nairobi',
  'Africa/Kigali': 'Africa/Maputo',
  'Africa/Kinshasa': 'Africa/Lagos',
  'Africa/Luanda': 'Africa/Lagos',
  'Africa/Lusaka': 'Africa/Maputo',
  'America/Nassau': 'America/Toronto',
  'Asia/Bahrain': 'Asia/Qatar',
  'Asia/Brunei': 'Asia/Kuching',
  'Asia/Kuala_Lumpur': 'Asia/Singapore',
  'Asia/Kuwait': 'Asia/Riyadh',
  'Asia/Muscat': 'Asia/Dubai',
  'Asia/Phnom_Penh': 'Asia/Bangkok',
  'Asia/Vientiane': 'Asia/Bangkok',
  'Atlantic/Reykjavik': 'Africa/Abidjan',
  'Europe/Amsterdam': 'Europe/Brussels',
  'Europe/Bratislava': 'Europe/Prague',
  'Europe/Copenhagen': 'Europe/Berlin',
  'Europe/Ljubljana': 'Europe/Belgrade',
  'Europe/Luxembourg': 'Europe/Brussels',
  'Europe/Monaco': 'Europe/Paris',
  'Europe/Oslo': 'Europe/Berlin',
  'Europe/Sarajevo': 'Europe/Belgrade',
  'Europe/Skopje': 'Europe/Belgrade',
  'Europe/Stockholm': 'Europe/Berlin',
  'Europe/Zagreb': 'Europe/Belgrade',
  'Indian/Antananarivo': 'Africa/Nairobi',
};

/// The [tz.Location] for [name], following [_kZoneLinks] when the database does
/// not carry the name itself. Null when neither answers.
tz.Location? _locationFor(String name) {
  final locations = tz.timeZoneDatabase.locations;
  final direct = locations[name];
  if (direct != null) return direct;
  final canonical = _kZoneLinks[name];
  return canonical == null ? null : locations[canonical];
}

/// Whether [name] is worth offering in the picker.
///
/// Drops the region-less pseudo-zones (`Factory`, and the `EST`/`SystemV/`
/// aliases) because none is a place, and the whole `Etc/` block **except**
/// `Etc/UTC`, because `Etc/GMT+5` counts its offset backwards — the one entry
/// guaranteed to be read wrong. `Etc/UTC` stays: it is the one name with no city
/// that people want.
bool _isPickableZone(String name) {
  if (!name.contains('/')) return false;
  if (name.startsWith('SystemV/')) return false;
  if (name.startsWith('Etc/')) return name == 'Etc/UTC';
  return true;
}

/// Every row the picker offers: the IANA zones, plus the cities from
/// `lib/world_cities.dart` those zones do not name.
///
/// The database's names are *zones* rather than places, so a picker built from it
/// alone has no New Delhi (India is `Asia/Kolkata`), no San Francisco and no Cape
/// Town — which reads as a search that does not work.
///
/// Three things this merge has to keep true:
///
/// - **A city whose zone already carries its name is not added twice.** Tokyo,
///   London and New York keep their one IANA row.
/// - **A city whose zone this build cannot resolve is dropped**, never thrown for
///   — the `TomlReader` rule applied to data the shell ships. "Resolve" rather
///   than "is listed", since a city naming a merged zone goes through
///   [_kZoneLinks]. `test/world_cities_test.dart` stops either degradation from
///   quietly hiding a typo.
/// - **The order stays the zone's**, so an empty query reads down the database
///   alphabetically and the cities sit with the zone they keep time in.
List<TimeZoneName> worldTimeZoneNames() {
  ensureTimeZonesInitialized();
  return _names ??= _buildZoneNames();
}

List<TimeZoneName> _buildZoneNames() {
  final zones = <TimeZoneName>[
    for (final name in (tz.timeZoneDatabase.locations.keys.toList()..sort()))
      if (_isPickableZone(name)) TimeZoneName(name),
  ];
  final named = <String>{
    for (final zone in zones) '${zone.name}\u0000${zone._city}',
  };

  for (final city in kWorldCities) {
    // Resolvable rather than listed: a city naming a zone tzdata has since
    // merged away keeps its own name, and `_kZoneLinks` is what finds the
    // rules behind it.
    if (_locationFor(city.zone) == null) continue;
    if (named.contains('${city.zone}\u0000${city.name.toLowerCase()}')) {
      continue;
    }
    zones.add(
      TimeZoneName.place(
        zone: city.zone,
        city: city.name,
        region: city.qualifier,
      ),
    );
  }

  zones.sort((a, b) {
    final byZone = a.name.compareTo(b.name);
    if (byZone != 0) return byZone;
    return a.city.compareTo(b.city);
  });
  return zones;
}

/// The wall clock in [zone] at the instant [now], or null when the database does
/// not know the zone.
///
/// Looked up in the map rather than through `getLocation`, which throws: a
/// hand-edited or deprecated name in the config must render as a row the user can
/// see and delete, never take down a build. A name tzdata has since made a link is
/// followed through [_kZoneLinks] rather than treated as unknown.
ZoneTime? resolveZone(String zone, DateTime now) {
  ensureTimeZonesInitialized();
  final location = _locationFor(zone);
  if (location == null) return null;
  final t = tz.TZDateTime.from(now, location);
  return ZoneTime(
    time: t,
    offset: t.timeZoneOffset,
    abbreviation: t.timeZoneName,
  );
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/// How well a field matched, low is better — the `app_search.dart` convention.
const int _kNoMatch = 1 << 30;

int _scoreField(String field, String query) {
  if (field.isEmpty) return _kNoMatch;
  if (field == query) return 0;
  if (field.startsWith(query)) return 1;
  // A word-boundary hit ("york" in "New York") beats one mid-word ("ork").
  if (field.contains(' $query')) return 2;
  if (field.contains(query)) return 3;
  return _kNoMatch;
}

int _scoreZone(TimeZoneName zone, String query) {
  var best = _scoreField(zone._city, query);
  // Each later field is offset so it can never beat an earlier one: a substring
  // hit in the city still ranks above an exact hit on the region.
  const step = 4;
  final region = _scoreField(zone._region, query);
  if (region != _kNoMatch && region + step < best) best = region + step;
  final full = _scoreField(zone._full, query);
  if (full != _kNoMatch && full + step * 2 < best) best = full + step * 2;
  return best;
}

/// The zones matching [query], best first.
///
/// An empty query lists everything alphabetically, so the picker has something to
/// show before the user types.
///
/// Abbreviations and UTC offsets are deliberately not searchable: both have to be
/// resolved per candidate, and both change under daylight saving — a search for
/// `BST` that worked in July would fail in January.
List<TimeZoneName> rankTimeZones(
  List<TimeZoneName> zones,
  String query, {
  int limit = 200,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return zones.take(limit).toList();

  final scored = <(int, TimeZoneName)>[];
  for (final zone in zones) {
    final score = _scoreZone(zone, normalized);
    if (score != _kNoMatch) scored.add((score, zone));
  }

  scored.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    if (byScore != 0) return byScore;
    return a.$2.name.compareTo(b.$2.name);
  });

  return [for (final (_, zone) in scored.take(limit)) zone];
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

/// The city segment of an IANA name, humanised: `America/New_York` -> `New
/// York`. Names with no `/` (only `UTC` survives the filter) are returned bare.
String zoneCityLabel(String zone) =>
    zone.split('/').last.replaceAll('_', ' ');

/// `14:32:07`, or `14:32` with [seconds] false.
///
/// 24-hour throughout, matching the bar's `modules/clock.dart`. There is no
/// 12-hour option anywhere in the config today and adding one belongs to a
/// change of its own.
String formatClockTime(DateTime t, {bool seconds = true}) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  if (!seconds) return '$h:$m';
  return '$h:$m:${t.second.toString().padLeft(2, '0')}';
}

/// `UTC`, `UTC+5:30`, `UTC-8`.
String formatUtcOffset(Duration offset) {
  if (offset == Duration.zero) return 'UTC';
  final sign = offset.isNegative ? '-' : '+';
  final total = offset.abs();
  final hours = total.inHours;
  final minutes = total.inMinutes % 60;
  if (minutes == 0) return 'UTC$sign$hours';
  return 'UTC$sign$hours:${minutes.toString().padLeft(2, '0')}';
}

/// The calendar-day badge: empty on the same day, `+1d` / `-2d` otherwise.
String formatDayDelta(int delta) {
  if (delta == 0) return '';
  return delta > 0 ? '+${delta}d' : '${delta}d';
}

// ---------------------------------------------------------------------------
// The clock seam
// ---------------------------------------------------------------------------

/// Where the clock column gets "now" and its zone conversions.
///
/// An interface rather than direct calls so widget tests can freeze time and
/// hand over a handful of offsets, and never load the database or depend on the
/// machine's own zone — the `weekStart` injection seam, applied to the clock.
abstract class ClockSource {
  const ClockSource();

  DateTime get now;

  /// Zones the picker offers.
  List<TimeZoneName> get zoneNames;

  /// The wall clock in [zone] at [at], or null when the zone is unknown.
  ZoneTime? resolve(String zone, DateTime at);
}

/// The real clock and the real database.
class SystemClockSource extends ClockSource {
  const SystemClockSource();

  @override
  DateTime get now => DateTime.now();

  @override
  List<TimeZoneName> get zoneNames => worldTimeZoneNames();

  @override
  ZoneTime? resolve(String zone, DateTime at) => resolveZone(zone, at);
}

/// A frozen clock over a fixed offset table.
///
/// [now] is read as a wall clock **at UTC**, so a zone's time is its offset
/// added to it. Converting through [DateTime.toUtc] instead would make every
/// expected value depend on the time zone the test machine happens to be in.
@visibleForTesting
class FixedClockSource extends ClockSource {
  FixedClockSource({
    required this.now,
    this.offsets = const <String, Duration>{},
    List<String> zones = const <String>[],
  }) : zoneNames = [for (final zone in zones) TimeZoneName(zone)];

  @override
  final DateTime now;

  /// Zone name to its offset from UTC. A zone absent from this map resolves to
  /// null, which is how tests exercise the unknown-zone row.
  final Map<String, Duration> offsets;

  @override
  final List<TimeZoneName> zoneNames;

  @override
  ZoneTime? resolve(String zone, DateTime at) {
    final offset = offsets[zone];
    if (offset == null) return null;
    return ZoneTime(time: at.add(offset), offset: offset, abbreviation: '');
  }
}
