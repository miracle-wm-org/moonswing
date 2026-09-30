// A CalDAV calendar's `VEVENT`s as the events the Calendar tab draws.
//
// The tab's model is `GoogleEvent`, which is a plain event and nothing about
// it is Google's but the name and the `htmlLink` a CalDAV event leaves null:
// so a CalDAV event is one of those, keyed by its collection's URL (which no
// Google calendar id can be) and its `UID`, plus the occurrence for a
// recurring one.
//
// A recurring event is normally expanded by the server — the query asks for
// `<c:expand>`, and Radicale, Baïkal, Nextcloud, iCloud and Fastmail all
// answer each occurrence as its own `VEVENT` with a `RECURRENCE-ID`. For one
// that does not, [expandRecurrence] reads the common shapes of `RRULE`
// (daily, weekly on given days, monthly on a day of the month, yearly, with an
// interval, a count or an end) and `EXDATE`; a rule it cannot read shows its
// first occurrence rather than nothing.
//
// Times: UTC is converted to local; a `TZID` goes through the converter the
// caller passes (the store hands in the IANA database), and a zone it does not
// know is read as local wall-clock time, as is a floating time.
//
// Flutter-free, for `test/caldav_events_test.dart`.

import 'package:moonswing/caldav/ical.dart';
import 'package:moonswing/google/google_api.dart';

/// Turns a wall-clock time in the zone named [tzid] into local time, or null
/// when the zone is unknown.
typedef ZoneConverter = DateTime? Function(DateTime wallClock, String tzid);

/// The most occurrences one recurring event is expanded into, and the most
/// it is stepped through on the way to the window.
const int _kMaxOccurrences = 1000;
const int _kMaxSteps = 100000;

/// The events in [data] — one calendar resource — that overlap [from]–[to],
/// drawn from the collection [calendarId] of the account [account].
List<GoogleEvent> eventsFromICalendar(
  String data, {
  required String calendarId,
  required String account,
  required DateTime from,
  required DateTime to,
  ZoneConverter? zone,
}) {
  final calendar = parseICalendar(data);
  if (calendar == null) return const [];
  final vevents = [
    if (calendar.name == 'VEVENT') calendar,
    ...calendar.childrenNamed('VEVENT'),
  ];
  // Overrides of single occurrences, by UID and the occurrence they replace.
  final overridden = <String, Set<DateTime>>{};
  for (final v in vevents) {
    final rid = _when(v.property('RECURRENCE-ID'), zone);
    final uid = v.text('UID');
    if (rid != null && uid != null) {
      (overridden[uid] ??= {}).add(rid.at);
    }
  }
  final out = <GoogleEvent>[];
  for (final v in vevents) {
    final start = _when(v.property('DTSTART'), zone);
    if (start == null) continue;
    final uid = v.text('UID') ?? '${start.at.toIso8601String()}-${out.length}';
    final length = _lengthOf(v, start, zone);
    final rid = _when(v.property('RECURRENCE-ID'), zone);
    final rule = v.property('RRULE')?.value;
    final List<DateTime> starts;
    if (rid == null && rule != null) {
      final skip = {
        for (final p in v.all('EXDATE'))
          for (final part in p.value.split(','))
            ?_when(ICalProperty('EXDATE', part.trim(), p.params), zone)?.at,
        ...?overridden[uid],
      };
      starts = [
        for (final s in expandRecurrence(
          start.at,
          rule,
          until: to,
          // An occurrence that starts before the window may still run into it.
          after: from.subtract(length),
          allDay: start.allDay,
          zone: zone,
        ))
          if (!skip.contains(s)) s,
      ];
    } else {
      starts = [start.at];
    }
    for (final s in starts) {
      final end = start.allDay
          ? DateTime(s.year, s.month, s.day + length.inDays)
          : s.add(length);
      final event = _event(
        v,
        uid: uid,
        occurrence: rid != null || rule != null ? (rid?.at ?? s) : null,
        start: s,
        end: end,
        allDay: start.allDay,
        calendarId: calendarId,
        account: account,
      );
      if (event.start.isBefore(to) && event.end.isAfter(from) ||
          (event.start == event.end &&
              !event.start.isBefore(from) &&
              event.start.isBefore(to))) {
        out.add(event);
      }
    }
  }
  return out;
}

GoogleEvent _event(
  ICalComponent v, {
  required String uid,
  required DateTime? occurrence,
  required DateTime start,
  required DateTime end,
  required bool allDay,
  required String calendarId,
  required String account,
}) {
  final location = _nonEmpty(v.text('LOCATION'));
  final description = _nonEmpty(v.text('DESCRIPTION'));
  final url = _nonEmpty(v.text('URL'));
  return GoogleEvent(
    id: occurrence == null ? uid : '$uid/${formatICalUtc(occurrence)}',
    calendarId: calendarId,
    account: account,
    summary: _nonEmpty(v.text('SUMMARY')) ?? '(No title)',
    start: start,
    end: end.isBefore(start) ? start : end,
    allDay: allDay,
    cancelled: v.text('STATUS')?.trim().toUpperCase() == 'CANCELLED',
    meetingLink: _meetingLink(v, location, description),
    description: description,
    location: location,
    iCalUid: uid,
    descriptionLinks: [?url],
  );
}

String? _nonEmpty(String? text) {
  final trimmed = text?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Where to join the event: an RFC 7986 `CONFERENCE` with a web address, the
/// link Google writes into what it exports, or the first web address in the
/// location — where a pasted call link usually ends up.
String? _meetingLink(ICalComponent v, String? location, String? description) {
  for (final p in v.all('CONFERENCE')) {
    if (_isWeb(p.value.trim())) return p.value.trim();
  }
  final google = v.text('X-GOOGLE-CONFERENCE')?.trim();
  if (google != null && _isWeb(google)) return google;
  if (location != null) {
    final match = RegExp(r'https?://[^\s<>"]+').firstMatch(location);
    if (match != null) return match.group(0);
  }
  return null;
}

bool _isWeb(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}

/// A `DTSTART`-like property as local time, and whether it is a date.
({DateTime at, bool allDay})? _when(ICalProperty? p, ZoneConverter? zone) {
  final parsed = parseICalDateTime(p);
  if (parsed == null) return null;
  if (parsed.dateOnly) return (at: parsed.value, allDay: true);
  if (parsed.utc) return (at: parsed.value.toLocal(), allDay: false);
  final tzid = p!.params['TZID'];
  if (tzid != null && zone != null) {
    final converted = zone(parsed.value, tzid);
    if (converted != null) return (at: converted, allDay: false);
  }
  return (at: parsed.value, allDay: false);
}

/// How long the event is: `DTEND` less `DTSTART`, else `DURATION`, else a day
/// for a date and nothing for a time (RFC 5545 §3.6.1). For an all-day event,
/// whole days.
Duration _lengthOf(
  ICalComponent v,
  ({DateTime at, bool allDay}) start,
  ZoneConverter? zone,
) {
  final end = _when(v.property('DTEND'), zone);
  if (end != null) {
    if (start.allDay) {
      final days = DateTime.utc(end.at.year, end.at.month, end.at.day)
          .difference(DateTime.utc(start.at.year, start.at.month, start.at.day))
          .inDays;
      return Duration(days: days < 1 ? 1 : days);
    }
    final length = end.at.difference(start.at);
    return length.isNegative ? Duration.zero : length;
  }
  final duration = parseICalDuration(v.property('DURATION')?.value);
  if (duration != null && !duration.isNegative) {
    if (start.allDay) {
      final days = duration.inDays;
      return Duration(days: days < 1 ? 1 : days);
    }
    return duration;
  }
  return start.allDay ? const Duration(days: 1) : Duration.zero;
}

/// An RFC 5545 `DURATION` (`P1D`, `PT1H30M`, `P2W`, `-PT15M`), or null.
Duration? parseICalDuration(String? value) {
  final match = RegExp(
    r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
  ).firstMatch(value?.trim().toUpperCase() ?? '');
  if (match == null || value!.trim().toUpperCase().endsWith('T')) return null;
  int n(int group) => int.tryParse(match[group] ?? '') ?? 0;
  final d = Duration(
    days: n(2) * 7 + n(3),
    hours: n(4),
    minutes: n(5),
    seconds: n(6),
  );
  return match[1] == '-' ? -d : d;
}

const Map<String, int> _weekdays = {
  'MO': DateTime.monday,
  'TU': DateTime.tuesday,
  'WE': DateTime.wednesday,
  'TH': DateTime.thursday,
  'FR': DateTime.friday,
  'SA': DateTime.saturday,
  'SU': DateTime.sunday,
};

/// The starts of a recurring event whose first is [start], by the `RRULE`
/// [rule], up to (not including) [until], leaving out those before [after]
/// (which still count towards a `COUNT`). A rule this does not understand
/// yields [start] alone; one with no occurrence left in the span, none.
///
/// Wall-clock arithmetic: each occurrence keeps [start]'s time of day across a
/// daylight-saving change, as a calendar does.
List<DateTime> expandRecurrence(
  DateTime start,
  String rule, {
  required DateTime until,
  DateTime? after,
  bool allDay = false,
  ZoneConverter? zone,
}) {
  final parts = <String, String>{
    for (final part in rule.split(';'))
      if (part.split('=') case [final k, final v])
        k.trim().toUpperCase(): v.trim().toUpperCase(),
  };
  final freq = parts['FREQ'];
  final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
  final count = int.tryParse(parts['COUNT'] ?? '');
  final end = switch (parts['UNTIL']) {
    final u? => _when(ICalProperty('UNTIL', u), zone)?.at,
    null => null,
  };
  if (interval < 1 ||
      !const {'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(freq)) {
    return [start];
  }
  final byDayText = parts['BYDAY'];
  final byDay = <int?>[
    if (byDayText != null)
      for (final d in byDayText.split(',')) _weekdays[d.trim()],
  ];
  // Only plain weekdays on a weekly rule; "2MO" and the like on a monthly one
  // are not read, and the first occurrence stands in for them.
  if (byDayText != null &&
      (freq != 'WEEKLY' || byDay.isEmpty || byDay.contains(null))) {
    return [start];
  }
  if (parts.keys.any(
    (k) => const {
      'BYMONTHDAY',
      'BYMONTH',
      'BYSETPOS',
      'BYYEARDAY',
      'BYWEEKNO',
      'BYHOUR',
      'BYMINUTE',
      'BYSECOND',
    }.contains(k),
  )) {
    return [start];
  }

  DateTime at(int year, int month, int day) => allDay
      ? DateTime(year, month, day)
      : DateTime(year, month, day, start.hour, start.minute, start.second);

  final out = <DateTime>[];
  var seen = 0;
  var steps = 0;
  bool take(DateTime s) {
    if (!s.isBefore(until)) return false;
    if (end != null && s.isAfter(end)) return false;
    if (count != null && seen >= count) return false;
    if (out.length >= _kMaxOccurrences || ++steps > _kMaxSteps) return false;
    if (s.isBefore(start)) return true;
    seen++;
    if (after == null || !s.isBefore(after)) out.add(s);
    return true;
  }

  switch (freq) {
    case 'DAILY':
      for (var i = 0; ; i += interval) {
        if (!take(at(start.year, start.month, start.day + i))) break;
      }
    case 'WEEKLY':
      final days = byDay.isEmpty
          ? [start.weekday]
          : (byDay.whereType<int>().toSet().toList()..sort());
      // The Monday of [start]'s week, as the rule's default `WKST` has it.
      final monday = start.day - (start.weekday - DateTime.monday);
      outer:
      for (var week = 0; ; week += interval) {
        for (final d in days) {
          final s = at(
            start.year,
            start.month,
            monday + week * 7 + (d - DateTime.monday),
          );
          if (s.isBefore(start)) continue;
          if (!take(s)) break outer;
        }
      }
    case 'MONTHLY':
      for (var i = 0; ; i += interval) {
        final month = DateTime(start.year, start.month + i);
        // A month without the day (the 31st of April) has no occurrence.
        if (start.day > DateTime(month.year, month.month + 1, 0).day) {
          if (month.isAfter(until)) break;
          continue;
        }
        if (!take(at(month.year, month.month, start.day))) break;
      }
    case 'YEARLY':
      for (var i = 0; ; i += interval) {
        final year = start.year + i;
        if (start.month == 2 &&
            start.day == 29 &&
            DateTime(year, 3, 0).day != 29) {
          if (year > until.year) break;
          continue;
        }
        if (!take(at(year, start.month, start.day))) break;
      }
  }
  return out;
}
