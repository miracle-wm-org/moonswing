// Calendar events as cards: the arithmetic that keeps one card per meeting on
// the board and moves it Todo → In Progress → Finished as the meeting comes and
// goes.
//
// Pure, like `spawnRecurring`, and for the same reason: the store calls it at
// start-up, on every calendar refresh and at each event's start and end, and a
// test can step the clock through a whole day without a timer. It knows nothing
// about Google. The sync above it turns events into [CalendarCardSource]s.
//
// Rules, each one a thing the user would otherwise have to undo by hand:
//
//  * **The column follows the clock until the user moves the card.** After that
//    it is theirs (`TodoExternal.manual`), and a meeting they have marked done
//    early stays done.
//  * **A field is refreshed only while it is still the sync's own.** A title or
//    body the user has edited stays edited, and a rename on the calendar does
//    not stamp on it.
//  * **A move is recorded at the moment it happened.** A board that catches up
//    after a suspend records the meeting starting at its start time, not at the
//    wakeup.
//  * **A meeting that disappears from today is abandoned, not deleted.** It may
//    have been cancelled or declined. The card stays visible and the user bins
//    it.

import 'package:moonswing/todo/todo_model.dart';

/// One calendar event, as the board needs it.
class CalendarCardSource {
  const CalendarCardSource({
    required this.key,
    required this.title,
    required this.start,
    required this.end,
    this.link,
    this.url,
    this.calendar,
    this.color,
    this.legacyKey,
  });

  /// Stable per occurrence: `<calendar id>/<event id>`.
  final String key;

  /// What an earlier build keyed the same occurrence as, when that differs. A
  /// card found under it is adopted and re-keyed, rather than abandoned while
  /// a duplicate is made beside it.
  final String? legacyKey;
  final String title;

  /// Local wall-clock times; [end] is exclusive.
  final DateTime start;
  final DateTime end;

  /// Where to join it.
  final String? link;

  /// The event's own page.
  final String? url;

  /// The name of the calendar the event is on.
  final String? calendar;

  /// `#rrggbb` the calendar draws the event in.
  final String? color;
}

/// The column an event belongs in at [now].
TodoColumn calendarColumnAt(DateTime start, DateTime end, DateTime now) {
  if (now.isBefore(start)) return TodoColumn.todo;
  if (now.isBefore(end)) return TodoColumn.inProgress;
  return TodoColumn.finished;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// The body the sync writes: when, then where to join, then the event's page.
/// The URLs are plain text on purpose, because `findLinks` already makes them
/// clickable on a card.
String calendarCardBody({
  required DateTime start,
  required DateTime end,
  String? link,
  String? url,
}) {
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  final lines = [
    sameDay
        ? '${_clock(start)}–${_clock(end)}'
        : '${formatDate(start)} ${_clock(start)} – '
              '${formatDate(end)} ${_clock(end)}',
    if (link != null) 'Join: $link',
    if (url != null && url != link) url,
  ];
  return lines.join('\n');
}

String _bodyOf(TodoExternal e) =>
    calendarCardBody(start: e.start, end: e.end, link: e.link, url: e.url);

String _bodyFor(CalendarCardSource s) =>
    calendarCardBody(start: s.start, end: s.end, link: s.link, url: s.url);

bool _overlapsDay(DateTime start, DateTime end, DateTime day) {
  final from = dateOnly(day);
  final to = addDays(from, 1);
  return start.isBefore(to) && (end.isAfter(from) || start == from);
}

/// Brings [items] in line with [sources], the timed events on [day] (the
/// synced calendars' whole answer for that day, cancelled ones already left
/// out).
///
/// Returns the new board, or null when nothing changed, so the caller neither
/// writes nor notifies. [dismissed] holds the keys whose cards the user deleted.
/// Those are not made again.
List<TodoItem>? syncCalendarCards(
  List<TodoItem> items,
  List<CalendarCardSource> sources, {
  required DateTime day,
  required DateTime now,
  required String Function() newId,
  Set<String> dismissed = const {},
}) {
  final byKey = <String, TodoItem>{
    for (final item in items)
      if (item.external case final e?
          when e.source == TodoExternal.googleCalendar)
        e.key: item,
  };
  final wanted = <String, CalendarCardSource>{
    for (final s in sources)
      if (_overlapsDay(s.start, s.end, day)) s.key: s,
  };
  final wantedLegacy = {for (final s in wanted.values) ?s.legacyKey};

  var next = [...items];
  var changed = false;

  void replace(TodoItem old, TodoItem updated, {required bool moved}) {
    if (!moved) {
      final at = next.indexWhere((i) => i.id == old.id);
      next[at] = updated;
    } else {
      next.removeWhere((i) => i.id == old.id);
      _insertAtTop(next, updated);
    }
    changed = true;
  }

  // Latest first, each inserted at the top of its column, so the column ends
  // up in start order with the next meeting at the top.
  final ordered = wanted.values.toList()
    ..sort((a, b) => b.start.compareTo(a.start));
  for (final source in ordered) {
    final target = calendarColumnAt(source.start, source.end, now);
    final legacy = source.legacyKey;
    final existing =
        byKey[source.key] ??
        (legacy == null || wanted.containsKey(legacy) ? null : byKey[legacy]);
    if (existing == null) {
      if (dismissed.contains(source.key) ||
          (legacy != null && dismissed.contains(legacy))) {
        continue;
      }
      _insertAtTop(
        next,
        TodoItem(
          id: newId(),
          title: source.title,
          body: _bodyFor(source),
          column: target,
          created: now,
          history: [TodoMove(from: null, to: target, at: now)],
          external: TodoExternal(
            source: TodoExternal.googleCalendar,
            key: source.key,
            title: source.title,
            start: source.start,
            end: source.end,
            link: source.link,
            url: source.url,
            calendar: source.calendar,
            color: source.color,
          ),
        ),
      );
      changed = true;
      continue;
    }

    final was = existing.external!;
    final external = was.copyWith(
      key: source.key,
      title: source.title,
      start: source.start,
      end: source.end,
      link: source.link,
      url: source.url,
      calendar: source.calendar,
      color: source.color,
    );
    var updated = existing.copyWith(
      title: existing.title == was.title ? source.title : null,
      body: existing.body == _bodyOf(was) ? _bodyFor(source) : null,
      external: external,
    );
    final moves = !was.manual && existing.column != target;
    if (moves) {
      updated = _moved(updated, target, switch (target) {
        TodoColumn.inProgress => source.start,
        TodoColumn.finished => source.end,
        _ => now,
      }, now);
    }
    if (updated != existing) replace(existing, updated, moved: moves);
  }

  // Today's cards whose events are gone.
  for (final entry in byKey.entries) {
    final item = entry.value;
    final e = item.external!;
    if (wanted.containsKey(entry.key) ||
        wantedLegacy.contains(entry.key) ||
        e.manual ||
        !item.column.isOpen ||
        !_overlapsDay(e.start, e.end, day)) {
      continue;
    }
    // Looked up afresh: the loop above may have replaced it.
    final current = next.firstWhere((i) => i.id == item.id);
    replace(
      current,
      _moved(current, TodoColumn.abandoned, now, now),
      moved: true,
    );
  }

  return changed ? next : null;
}

/// [item] in [to], with the move recorded at [at], clamped between the card's
/// last move and [now] so history stays in order.
TodoItem _moved(TodoItem item, TodoColumn to, DateTime at, DateTime now) {
  var when = at.isAfter(now) ? now : at;
  final last = item.movedAt;
  if (when.isBefore(last)) when = last;
  return item.copyWith(
    column: to,
    history: [
      ...item.history,
      TodoMove(from: item.column, to: to, at: when),
    ],
  );
}

void _insertAtTop(List<TodoItem> items, TodoItem item) {
  final at = items.indexWhere((i) => i.column == item.column);
  items.insert(at < 0 ? items.length : at, item);
}

/// The next instant after [now] at which a card in [sources] changes column,
/// or null when none does again today.
DateTime? nextCalendarBoundary(
  Iterable<CalendarCardSource> sources,
  DateTime now,
) {
  DateTime? best;
  for (final s in sources) {
    for (final t in [s.start, s.end]) {
      if (t.isAfter(now) && (best == null || t.isBefore(best))) best = t;
    }
  }
  return best;
}
