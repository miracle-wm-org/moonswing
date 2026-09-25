// How a column's cards are arranged on screen, as opposed to how they are
// stored.
//
// The store keeps one order per column — the user's, set by dragging — and this
// file is the only thing that departs from it: overdue work floats to the top
// of an open column, and the two columns that only ever grow (Finished,
// Abandoned) fold their older cards away under the day they got there.
// Flutter-free, for `test/todo_layout_test.dart`, since every rule here is a
// function of a `today` that the suite would otherwise only test on the day it
// happens to run.

import 'package:moonswing/todo/todo_model.dart';

/// The cards that arrived in a column on one [day].
class TodoDayGroup {
  const TodoDayGroup({required this.day, required this.items});

  /// A day, see [dateOnly].
  final DateTime day;

  /// In the store's order.
  final List<TodoItem> items;
}

/// One column, as it is drawn: [loose] cards first, always showing, then
/// [days] newest first, each of which the board can fold.
class TodoColumnLayout {
  const TodoColumnLayout({required this.loose, this.days = const []});

  final List<TodoItem> loose;
  final List<TodoDayGroup> days;
}

/// Lays [items] — one column's cards, in the store's order — out for [column]
/// on [today].
///
/// - An open column puts its overdue cards first. Both halves keep the store's
///   order, so a drag still decides where a card sits among its peers; it is
///   only "is this late" that outranks it.
/// - Finished keeps today's cards loose, and puts every earlier one under the
///   day it was finished: a list of what got done is read for today, and the
///   history under it is there to be looked up, not scrolled past.
/// - Abandoned puts every card under its day, today's included — nothing there
///   is still anybody's to read through.
///
/// The day a card is filed under is the day it arrived in the column
/// ([TodoItem.movedAt]), which for Finished is the day it was finished.
TodoColumnLayout layoutColumn(
  TodoColumn column,
  List<TodoItem> items,
  DateTime today,
) {
  final day = dateOnly(today);
  switch (column) {
    case TodoColumn.inbox || TodoColumn.todo || TodoColumn.inProgress:
      bool overdue(TodoItem item) => item.due?.isBefore(day) ?? false;
      return TodoColumnLayout(
        loose: [...items.where(overdue), ...items.where((i) => !overdue(i))],
      );
    case TodoColumn.finished:
      return TodoColumnLayout(
        loose: [
          for (final item in items)
            if (dateOnly(item.movedAt) == day) item,
        ],
        days: _byDay([
          for (final item in items)
            if (dateOnly(item.movedAt) != day) item,
        ]),
      );
    case TodoColumn.abandoned:
      return TodoColumnLayout(loose: const [], days: _byDay(items));
  }
}

/// [items] grouped by the day each arrived in its column, newest day first.
List<TodoDayGroup> _byDay(List<TodoItem> items) {
  final groups = <DateTime, List<TodoItem>>{};
  for (final item in items) {
    groups.putIfAbsent(dateOnly(item.movedAt), () => []).add(item);
  }
  final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final day in days) TodoDayGroup(day: day, items: groups[day]!)];
}

/// Which day groups the user has opened or closed by hand.
///
/// A group is folded unless the board is being searched — a match inside a
/// folded group is a result nobody can see — and a click on its heading flips
/// that either way. What a click decided is forgotten when the search changes,
/// so a group closed before a search cannot hide that search's results.
///
/// Flutter-free, like the rest of this file: the board wraps it in a notifier.
class TodoDayFolds {
  final Map<(TodoColumn, DateTime), bool> _open = {};

  /// Whether the [column]'s group for [day] shows its cards.
  bool isOpen(TodoColumn column, DateTime day, {required bool searching}) =>
      _open[(column, dateOnly(day))] ?? searching;

  /// Flips the group, from however it is showing now.
  void toggle(TodoColumn column, DateTime day, {required bool searching}) {
    _open[(column, dateOnly(day))] = !isOpen(column, day, searching: searching);
  }

  /// Forgets every hand-set group. Answers whether there were any.
  bool reset() {
    if (_open.isEmpty) return false;
    _open.clear();
    return true;
  }
}
