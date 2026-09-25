import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_layout.dart';
import 'package:moonswing/todo/todo_model.dart';

TodoItem _item(
  String id,
  TodoColumn column, {
  DateTime? due,
  DateTime? movedAt,
}) {
  final at = movedAt ?? DateTime(2026, 9, 20, 10);
  return TodoItem(
    id: id,
    title: id,
    body: '',
    column: column,
    created: at,
    due: due,
    history: [TodoMove(from: null, to: column, at: at)],
  );
}

List<String> _ids(List<TodoItem> items) => [for (final i in items) i.id];

void main() {
  final today = DateTime(2026, 9, 24, 15, 30);

  group('an open column', () {
    for (final column in [
      TodoColumn.inbox,
      TodoColumn.todo,
      TodoColumn.inProgress,
    ]) {
      test('${column.label} puts overdue cards first, keeping order', () {
        final layout = layoutColumn(column, [
          _item('none', column),
          _item('late1', column, due: DateTime(2026, 9, 20)),
          _item('today', column, due: DateTime(2026, 9, 24)),
          _item('soon', column, due: DateTime(2026, 9, 30)),
          _item('late2', column, due: DateTime(2026, 9, 23)),
        ], today);
        expect(_ids(layout.loose), ['late1', 'late2', 'none', 'today', 'soon']);
        expect(layout.days, isEmpty);
      });
    }
  });

  test('Finished keeps today loose and files the rest by day, newest '
      'first', () {
    const c = TodoColumn.finished;
    final layout = layoutColumn(c, [
      _item('old', c, movedAt: DateTime(2026, 9, 1, 9)),
      _item('now1', c, movedAt: DateTime(2026, 9, 24, 0, 5)),
      _item('yest1', c, movedAt: DateTime(2026, 9, 23, 23, 59)),
      _item('now2', c, movedAt: DateTime(2026, 9, 24, 14)),
      _item('yest2', c, movedAt: DateTime(2026, 9, 23, 8)),
      // Overdue means nothing once it is finished.
      _item('late', c, due: DateTime(2026, 1, 1), movedAt: today),
    ], today);
    expect(_ids(layout.loose), ['now1', 'now2', 'late']);
    expect(
      [for (final g in layout.days) g.day],
      [DateTime(2026, 9, 23), DateTime(2026, 9, 1)],
    );
    expect(_ids(layout.days.first.items), ['yest1', 'yest2']);
    expect(_ids(layout.days.last.items), ['old']);
  });

  test('Abandoned files every card by day, today included', () {
    const c = TodoColumn.abandoned;
    final layout = layoutColumn(c, [
      _item('a', c, movedAt: DateTime(2026, 9, 20)),
      _item('b', c, movedAt: DateTime(2026, 9, 24, 9)),
    ], today);
    expect(layout.loose, isEmpty);
    expect(
      [for (final g in layout.days) g.day],
      [DateTime(2026, 9, 24), DateTime(2026, 9, 20)],
    );
  });

  group('TodoDayFolds', () {
    final day = DateTime(2026, 9, 23);

    test('folded by default, open while searching', () {
      final folds = TodoDayFolds();
      expect(folds.isOpen(TodoColumn.finished, day, searching: false), false);
      expect(folds.isOpen(TodoColumn.finished, day, searching: true), true);
    });

    test('a click flips one group in one column', () {
      final folds = TodoDayFolds()
        ..toggle(
          TodoColumn.finished,
          DateTime(2026, 9, 23, 18),
          searching: false,
        );
      expect(folds.isOpen(TodoColumn.finished, day, searching: false), true);
      expect(folds.isOpen(TodoColumn.abandoned, day, searching: false), false);
      expect(
        folds.isOpen(
          TodoColumn.finished,
          DateTime(2026, 9, 22),
          searching: false,
        ),
        false,
      );
    });

    test('a reset forgets clicks, so a search can open what was closed', () {
      final folds = TodoDayFolds()
        ..toggle(TodoColumn.finished, day, searching: true);
      expect(folds.isOpen(TodoColumn.finished, day, searching: true), false);
      expect(folds.reset(), true);
      expect(folds.isOpen(TodoColumn.finished, day, searching: true), true);
      expect(folds.reset(), false);
    });
  });
}
