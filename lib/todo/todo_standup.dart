// The standup summary: what was finished, what is under way and what is still
// to do, since the last time the summary was taken — and the summaries taken
// before it, kept so an old one can still be copied.
//
// Flutter-free and I/O-free, for `test/todo_standup_test.dart`. Nothing here is
// clever — the board already records when every card changed column
// ([TodoItem.history]), so "since last time" is a comparison of those times
// against one stored instant, and the text is a list per column.

import 'package:moonswing/todo/todo_model.dart';

/// How far back the first summary looks, when there is no earlier one to
/// measure from: a day, the gap between two standups.
const Duration kStandupFirstWindow = Duration(days: 1);

/// One standup summary as it was taken: the text, when, and the instant it
/// counted from — which is what the next summary goes back to counting from
/// when this one is invalidated.
class StandupSummary {
  const StandupSummary({
    required this.takenAt,
    required this.since,
    required this.report,
  });

  final DateTime takenAt;

  /// The previous summary's [takenAt], or null for a first summary (which
  /// looked back [kStandupFirstWindow]).
  final DateTime? since;

  final String report;

  @override
  bool operator ==(Object other) =>
      other is StandupSummary &&
      other.takenAt == takenAt &&
      other.since == since &&
      other.report == report;

  @override
  int get hashCode => Object.hash(takenAt, since, report);
}

/// The standup summary for [items] at [now], counting activity after [since]
/// (or [kStandupFirstWindow] before [now] when there has been no summary yet).
///
/// Plain text, meant to be pasted into a chat:
///
///  * **Done** — cards that arrived in Finished after [since] and are still
///    there, so one finished and then reopened is not claimed as done.
///  * **In progress** — everything in In Progress, with the ones moved there
///    after [since] marked as started.
///  * **To do** — everything in Todo, with its due date, overdue ones first.
///  * **Dropped** — cards that arrived in Abandoned after [since]; left out
///    when there are none, because an empty "Dropped" is noise.
///
/// The Inbox is left out: it is what has not been looked at yet, not a plan.
/// So is every card the calendar sync put on the board ([TodoItem.external]),
/// in any column: a meeting is not work to report on.
String standupReport(
  List<TodoItem> board, {
  required DateTime? since,
  required DateTime now,
}) {
  final items = [
    for (final item in board)
      if (item.external == null) item,
  ];
  final from = since ?? now.subtract(kStandupFirstWindow);
  final today = dateOnly(now);
  bool arrivedSince(TodoItem item) => item.movedAt.isAfter(from);

  final done = [
    for (final item in items)
      if (item.column == TodoColumn.finished && arrivedSince(item)) item,
  ]..sort((a, b) => a.movedAt.compareTo(b.movedAt));
  final dropped = [
    for (final item in items)
      if (item.column == TodoColumn.abandoned && arrivedSince(item)) item,
  ]..sort((a, b) => a.movedAt.compareTo(b.movedAt));
  final inProgress = [
    for (final item in items)
      if (item.column == TodoColumn.inProgress) item,
  ];
  // Board order within each group, overdue first: a stable sort keeps it.
  final todo = [
    for (final item in items)
      if (item.column == TodoColumn.todo) item,
  ];
  int urgency(TodoItem item) {
    final due = item.due;
    if (due == null) return 2;
    return due.isAfter(today) ? 2 : (due == today ? 1 : 0);
  }

  _stableSort(todo, (a, b) => urgency(a).compareTo(urgency(b)));

  String dueNote(TodoItem item) {
    final due = item.due;
    if (due == null) return '';
    if (due.isBefore(today)) return ' (overdue, was due ${formatDate(due)})';
    if (due == today) return ' (due today)';
    return ' (due ${formatDate(due)})';
  }

  final lines = <String>[
    'Standup — ${describeStandupDay(now)}',
    since == null
        ? 'Covering the last 24 hours.'
        : 'Since ${describeStandupMoment(since, now: now)}.',
    '',
    'Done:',
    if (done.isEmpty) '• Nothing finished',
    for (final item in done) '• ${_titleOf(item)}',
    '',
    'In progress:',
    if (inProgress.isEmpty) '• Nothing in progress',
    for (final item in inProgress)
      '• ${_titleOf(item)}${arrivedSince(item) ? ' (started)' : ''}'
          '${dueNote(item)}',
    '',
    'To do:',
    if (todo.isEmpty) '• Nothing left to do',
    for (final item in todo) '• ${_titleOf(item)}${dueNote(item)}',
    if (dropped.isNotEmpty) ...[
      '',
      'Dropped:',
      for (final item in dropped) '• ${_titleOf(item)}',
    ],
  ];
  return lines.join('\n');
}

String _titleOf(TodoItem item) {
  final title = item.title.trim();
  // The first line only: a pasted list of bullets wants one line per card.
  if (title.isNotEmpty) return title.split('\n').first.trim();
  final body = item.body.trim();
  return body.isEmpty ? 'Untitled' : body.split('\n').first.trim();
}

void _stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final order = compare(a.$2, b.$2);
    return order != 0 ? order : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}

const List<String> _kWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "Friday 2026-09-25".
String describeStandupDay(DateTime day) =>
    '${_kWeekdays[day.weekday - 1]} ${formatDate(day)}';

/// "today at 09:05", "yesterday at 17:30", or "Monday 2026-09-21 at 09:00" —
/// when the last summary was taken, relative to [now].
String describeStandupMoment(DateTime moment, {required DateTime now}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(moment.hour)}:${two(moment.minute)}';
  final day = dateOnly(moment);
  final today = dateOnly(now);
  if (day == today) return 'today at $time';
  if (day == addDays(today, -1)) return 'yesterday at $time';
  return '${describeStandupDay(day)} at $time';
}
