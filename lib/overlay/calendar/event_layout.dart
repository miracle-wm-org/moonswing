// The arithmetic behind the Calendar tab's event views: where a timed event
// sits in a day column, how events that overlap share it, and the words for
// when something happens.
//
// Pure and Flutter-free, like `month.dart`, so every rule here is a unit test
// rather than a pumped widget.

import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/overlay/calendar/month.dart';

/// Minutes in a day, the height of a day column in minutes.
const int kMinutesPerDay = 24 * 60;

/// The shortest an event is drawn, in minutes, so a zero-length reminder or a
/// five-minute check-in still has a box to click.
const int kMinEventMinutes = 20;

/// One timed event placed in a day column.
class PlacedEvent {
  const PlacedEvent({
    required this.event,
    required this.top,
    required this.bottom,
    required this.column,
    required this.columns,
  });

  final GoogleEvent event;

  /// Minutes after the day's midnight where the box starts and ends, clipped
  /// to the day and stretched to at least [kMinEventMinutes].
  final int top;
  final int bottom;

  /// Which of [columns] side-by-side lanes it takes. Events that overlap share
  /// the width of their cluster; one on its own has all of it.
  final int column;
  final int columns;

  @override
  String toString() =>
      'PlacedEvent(${event.id}, $top–$bottom, $column/$columns)';
}

/// Whether [e] belongs in a day's time grid rather than its all-day strip.
/// A timed event spanning a whole day or more reads as a banner, the way
/// Google draws it.
bool isTimedForGrid(GoogleEvent e) =>
    !e.allDay && e.end.difference(e.start) < const Duration(hours: 24);

/// Lays [events] — the day's timed ones — out in the column for [day].
///
/// The classic calendar packing: sort by start (longer first on a tie), walk
/// the events gathering *clusters* of ones that transitively overlap, give
/// each event the first lane in its cluster that is free by its start, and
/// divide the width by the cluster's lane count.
List<PlacedEvent> layoutDay(List<GoogleEvent> events, DateTime day) {
  final midnight = dayKey(day);
  int minuteOf(DateTime t) {
    final m = t.difference(midnight).inMinutes;
    return m.clamp(0, kMinutesPerDay);
  }

  final spans = [
    for (final e in events)
      if (!e.cancelled && e.overlapsDay(midnight))
        (event: e, top: minuteOf(e.start), bottom: minuteOf(e.end)),
  ];
  final sized =
      [
        for (final s in spans)
          (
            event: s.event,
            top: s.top > kMinutesPerDay - kMinEventMinutes
                ? kMinutesPerDay - kMinEventMinutes
                : s.top,
            bottom: s.bottom - s.top < kMinEventMinutes
                ? (s.top > kMinutesPerDay - kMinEventMinutes
                      ? kMinutesPerDay
                      : s.top + kMinEventMinutes)
                : s.bottom,
          ),
      ]..sort((a, b) {
        final byTop = a.top.compareTo(b.top);
        return byTop != 0 ? byTop : b.bottom.compareTo(a.bottom);
      });

  final placed = <PlacedEvent>[];
  var cluster = <({GoogleEvent event, int top, int bottom, int lane})>[];
  var laneEnds = <int>[];
  var clusterEnd = -1;

  void flush() {
    for (final c in cluster) {
      placed.add(
        PlacedEvent(
          event: c.event,
          top: c.top,
          bottom: c.bottom,
          column: c.lane,
          columns: laneEnds.length,
        ),
      );
    }
    cluster = [];
    laneEnds = [];
    clusterEnd = -1;
  }

  for (final s in sized) {
    if (s.top >= clusterEnd) flush();
    var lane = laneEnds.indexWhere((end) => end <= s.top);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(s.bottom);
    } else {
      laneEnds[lane] = s.bottom;
    }
    cluster.add((event: s.event, top: s.top, bottom: s.bottom, lane: lane));
    if (s.bottom > clusterEnd) clusterEnd = s.bottom;
  }
  flush();
  return placed;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// `09:30`.
String clockLabel(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "10:00–10:30", "All day", or the part of a multi-day event on [day]
/// ("…–11:00" for one that began the day before).
String eventTimeLabel(GoogleEvent e, DateTime day) {
  if (e.allDay) return 'All day';
  final midnight = dayKey(day);
  final next = DateTime(midnight.year, midnight.month, midnight.day + 1);
  final from = e.start.isBefore(midnight) ? null : e.start;
  final to = e.end.isAfter(next) ? null : e.end;
  String at(DateTime? t) => t == null ? '…' : clockLabel(t);
  if (from != null && to != null && from == to) return at(from);
  return '${at(from)}–${at(to)}';
}

/// "Friday 25 September".
String longDayLabel(DateTime d) =>
    '${weekdayNames[d.weekday % 7]} ${d.day} ${monthNames[d.month - 1]}';

/// When [e] happens, in full, for its details card: "Friday 25 September ·
/// 10:00–10:30", "Friday 25 September · All day", or a span across days.
String eventWhenLabel(GoogleEvent e) {
  if (e.allDay) {
    // An all-day end is exclusive: the day after the last one.
    final last = e.end.isAfter(e.start)
        ? e.end.subtract(const Duration(days: 1))
        : e.start;
    if (isSameDay(last, e.start)) return '${longDayLabel(e.start)} · All day';
    return '${longDayLabel(e.start)} – ${longDayLabel(last)} · All day';
  }
  // An end is exclusive too, so one at midnight finishes the day before.
  final last = e.end.isAfter(e.start)
      ? e.end.subtract(const Duration(microseconds: 1))
      : e.start;
  if (isSameDay(e.start, last)) {
    return '${longDayLabel(e.start)} · '
        '${clockLabel(e.start)}–${clockLabel(e.end)}';
  }
  return '${longDayLabel(e.start)} ${clockLabel(e.start)} – '
      '${longDayLabel(e.end)} ${clockLabel(e.end)}';
}

/// The week holding [day], starting on [weekStart] (a [DateTime] weekday).
List<DateTime> weekOf(DateTime day, int weekStart) {
  final d = dayKey(day);
  final back = (d.weekday - weekStart) % 7;
  final first = DateTime(d.year, d.month, d.day - back);
  return [
    for (var i = 0; i < 7; i++)
      DateTime(first.year, first.month, first.day + i),
  ];
}

/// "21 – 27 Sep 2026", "28 Sep – 4 Oct 2026", "29 Dec 2025 – 4 Jan 2026".
String weekRangeLabel(List<DateTime> week) {
  final a = week.first;
  final b = week.last;
  if (a.year != b.year) {
    return '${a.day} ${monthAbbrev[a.month - 1]} ${a.year} – '
        '${b.day} ${monthAbbrev[b.month - 1]} ${b.year}';
  }
  if (a.month != b.month) {
    return '${a.day} ${monthAbbrev[a.month - 1]} – '
        '${b.day} ${monthAbbrev[b.month - 1]} ${b.year}';
  }
  return '${a.day} – ${b.day} ${monthAbbrev[b.month - 1]} ${b.year}';
}
