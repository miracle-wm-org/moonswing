// The calendar tab's time zone layer.
//
// This is the only file in the shell that imports `package:timezone`. Keeping
// it that way is what lets [rankTimeZones] and the formatters be plain unit
// tests with no database behind them, and what keeps `config.dart` — which is
// parsed at start-up, long before the overlay exists — free of the dependency.
//
// The database is *data*, not the formatting machinery `month.dart` refuses:
// daylight-saving transition tables change every few months by political
// decision and cannot be hand-rolled.

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:timezone/data/latest.dart' show initializeTimeZones;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;

/// Loads the IANA database. Idempotent, and cheap after the first call.
///
/// Deliberately not called from `main()`: the calendar starts no service, and
/// `package:timezone/data/latest.dart` embeds the database as a Dart byte
/// literal — there is no asset bundle and no binding that would force it
/// earlier. The cost is one parse the first time the overlay is opened.
///
/// `standalone.dart` and `browser.dart` are the variants that read the database
/// from disk or over HTTP; neither is usable here.
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

/// An IANA zone name with its searchable text pre-folded to lower case.
///
/// The folding happens once, when the list is built, rather than on every
/// keystroke across four hundred zones — the [SearchableApp] trick from
/// `lib/launcher/app_search.dart`.
@immutable
class TimeZoneName {
  TimeZoneName(this.name)
      : city = zoneCityLabel(name),
        region = name.contains('/') ? name.split('/').first : name,
        _city = zoneCityLabel(name).toLowerCase(),
        _region =
            (name.contains('/') ? name.split('/').first : name).toLowerCase(),
        _full = name.replaceAll('_', ' ').replaceAll('/', ' ').toLowerCase();

  /// The raw IANA name, e.g. `America/Argentina/Buenos_Aires`. This is what is
  /// stored in the config.
  final String name;

  /// The last segment, humanised: `Buenos Aires`.
  final String city;

  /// The first segment: `America`.
  final String region;

  final String _city;
  final String _region;
  final String _full;
}

List<TimeZoneName>? _names;

/// Whether [name] is worth offering in the picker.
///
/// Drops the region-less pseudo-zones (`Factory`, and the `EST`/`SystemV/`
/// aliases the fuller database variants carry) because none of them is a place,
/// and the whole `Etc/` block **except** `Etc/UTC` because `Etc/GMT+5` counts
/// its offset backwards — the one entry in the database guaranteed to be read
/// wrong. `Etc/UTC` stays: it is the one name with no city that people want.
bool _isPickableZone(String name) {
  if (!name.contains('/')) return false;
  if (name.startsWith('SystemV/')) return false;
  if (name.startsWith('Etc/')) return name == 'Etc/UTC';
  return true;
}

/// Every zone the picker offers, sorted by name.
List<TimeZoneName> worldTimeZoneNames() {
  ensureTimeZonesInitialized();
  return _names ??= [
    for (final name in (tz.timeZoneDatabase.locations.keys.toList()..sort()))
      if (_isPickableZone(name)) TimeZoneName(name),
  ];
}

/// The wall clock in [zone] at the instant [now], or null when the database
/// does not know the zone.
///
/// Looked up in the map rather than through `getLocation`, which throws: a
/// hand-edited or deprecated name in the config must render as a row the user
/// can see and delete, never take down a build.
ZoneTime? resolveZone(String zone, DateTime now) {
  ensureTimeZonesInitialized();
  final location = tz.timeZoneDatabase.locations[zone];
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
/// An empty query lists everything alphabetically, so the picker has something
/// to show before the user types.
///
/// Abbreviations and UTC offsets are deliberately not searchable: both have to
/// be resolved from the database per candidate, and both change under daylight
/// saving — a search for `BST` that worked in July would fail in January.
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
