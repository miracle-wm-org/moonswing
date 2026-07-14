import 'dart:ui';

import 'package:graceful_shell/overlay/calendar/month.dart';

/// A single calendar entry, normalized away from any one provider's wire format
/// so the UI never has to know whether it came from Google, CalDAV, or Outlook.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
    this.color,
  });

  final String id;
  final String calendarId;
  final String title;

  /// Local start. For an all-day event this is local midnight on the first day.
  final DateTime start;

  /// Local end. For an all-day event this is local midnight on the *last* day —
  /// inclusive, unlike the exclusive end dates most providers send on the wire.
  final DateTime end;

  final bool allDay;
  final String? location;

  /// Usually inherited from the owning calendar's colour.
  final Color? color;

  Duration get duration => end.difference(start);
}

/// Every local day [e] touches, inclusive of both ends.
List<DateTime> daysSpanned(CalendarEvent e) {
  final first = dayKey(e.start);
  var last = dayKey(e.end);

  // A timed event ending exactly at midnight belongs to the day before, not to
  // the zero-length sliver of the next one — otherwise a 23:00–00:00 meeting
  // also shows up on tomorrow's agenda.
  if (!e.allDay && last.isAfter(first) && e.end == last) {
    last = DateTime(last.year, last.month, last.day - 1);
  }
  if (last.isBefore(first)) return [first];

  final days = <DateTime>[];
  for (var d = first; !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
    days.add(d);
  }
  return days;
}

/// Buckets [events] by local day.
///
/// A multi-day event appears under every day it covers, so selecting any day of
/// a week-long trip still shows it. Each bucket is sorted all-day first, then by
/// start time, then by title, which is the order the agenda pane renders in.
Map<DateTime, List<CalendarEvent>> groupByDay(Iterable<CalendarEvent> events) {
  final byDay = <DateTime, List<CalendarEvent>>{};
  for (final e in events) {
    for (final day in daysSpanned(e)) {
      byDay.putIfAbsent(day, () => []).add(e);
    }
  }
  for (final bucket in byDay.values) {
    bucket.sort(compareEvents);
  }
  return byDay;
}

int compareEvents(CalendarEvent a, CalendarEvent b) {
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;
  return a.title.compareTo(b.title);
}
