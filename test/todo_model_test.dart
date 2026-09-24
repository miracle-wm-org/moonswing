import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_model.dart';

TodoItem _item(
  String id, {
  TodoColumn column = TodoColumn.todo,
  String title = 'Item',
  DateTime? due,
  TodoRecurrence? recurrence,
}) => TodoItem(
  id: id,
  title: title,
  body: '',
  column: column,
  created: DateTime(2026, 9, 1, 9),
  due: due,
  recurrence: recurrence,
  history: [TodoMove(from: null, to: column, at: DateTime(2026, 9, 1, 9))],
);

void main() {
  group('dates', () {
    test('parseDate is strict about days that do not exist', () {
      expect(parseDate('2026-09-24'), DateTime(2026, 9, 24));
      expect(parseDate(' 2026-9-4 '), DateTime(2026, 9, 4));
      expect(parseDate('2026-02-30'), isNull);
      expect(parseDate('2028-02-29'), DateTime(2028, 2, 29));
      expect(parseDate('2026-13-01'), isNull);
      expect(parseDate('24/09/2026'), isNull);
      expect(parseDate(''), isNull);
    });

    test('formatDate round-trips', () {
      final day = DateTime(2026, 1, 5);
      expect(formatDate(day), '2026-01-05');
      expect(parseDate(formatDate(day)), day);
    });

    test('addMonths clamps to the end of a shorter month', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
      expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
      expect(addMonths(DateTime(2026, 3, 31), -1), DateTime(2026, 2, 28));
    });
  });

  group('recurrence', () {
    test('a monthly rule on the 31st goes back to the 31st after February', () {
      final rule = TodoRecurrence(
        every: 1,
        unit: RecurrenceUnit.months,
        start: DateTime(2026, 1, 31),
        since: DateTime(2026, 1, 30),
      );
      expect(rule.next, DateTime(2026, 1, 31));
      expect(rule.nextAfter(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
      expect(rule.nextAfter(DateTime(2026, 2, 28)), DateTime(2026, 3, 31));
    });

    test('nothing is owed before the next scheduled day', () {
      final rule = TodoRecurrence(
        every: 2,
        unit: RecurrenceUnit.weeks,
        start: DateTime(2026, 9, 1),
        since: DateTime(2026, 9, 1),
      );
      expect(rule.next, DateTime(2026, 9, 15));
      expect(rule.owedOn(DateTime(2026, 9, 14, 23, 59)), isNull);
      expect(rule.owedOn(DateTime(2026, 9, 15, 0, 1)), DateTime(2026, 9, 15));
    });

    test('a long absence owes one copy, for the latest day missed', () {
      final rule = TodoRecurrence(
        every: 1,
        unit: RecurrenceUnit.days,
        start: DateTime(2020, 1, 1),
        since: DateTime(2020, 1, 1),
      );
      expect(rule.owedOn(DateTime(2026, 9, 24, 8)), DateTime(2026, 9, 24));
    });

    test('a rule starting in the future waits for its start', () {
      final rule = TodoRecurrence(
        every: 3,
        unit: RecurrenceUnit.days,
        start: DateTime(2026, 10, 1),
        since: DateTime(2026, 9, 24),
      );
      expect(rule.next, DateTime(2026, 10, 1));
      expect(rule.owedOn(DateTime(2026, 9, 30)), isNull);
    });

    test('describe', () {
      final rule = TodoRecurrence(
        every: 1,
        unit: RecurrenceUnit.weeks,
        start: DateTime(2026),
        since: DateTime(2026),
      );
      expect(rule.describe(), 'Every week');
      expect(
        TodoRecurrence(
          every: 3,
          unit: RecurrenceUnit.months,
          start: DateTime(2026),
          since: DateTime(2026),
        ).describe(),
        'Every 3 months',
      );
    });
  });

  group('spawnRecurring', () {
    final now = DateTime(2026, 9, 24, 8);
    var counter = 0;
    String newId() => 'new-${++counter}';

    test('the copy lands on top of Todo, due that day, carrying the rule', () {
      final rule = TodoRecurrence(
        every: 1,
        unit: RecurrenceUnit.weeks,
        start: DateTime(2026, 9, 17),
        since: DateTime(2026, 9, 17),
      );
      final items = [
        _item('a', column: TodoColumn.inbox),
        _item('b'),
        _item('r', column: TodoColumn.finished, recurrence: rule),
      ];
      final next = spawnRecurring(items, now, newId, now: now)!;
      expect(next.map((i) => i.id), ['a', 'new-1', 'b', 'r']);
      final copy = next[1];
      expect(copy.column, TodoColumn.todo);
      expect(copy.due, DateTime(2026, 9, 24));
      expect(copy.recurrence!.since, DateTime(2026, 9, 24));
      expect(copy.history.single.to, TodoColumn.todo);
      expect(next[3].recurrence, isNull);

      // Once made, nothing more is owed today.
      expect(spawnRecurring(next, now, newId, now: now), isNull);
    });

    test('nothing owed is no change at all', () {
      expect(spawnRecurring([_item('a')], now, newId, now: now), isNull);
    });
  });

  group('dueReminder', () {
    final today = DateTime(2026, 9, 24, 7);

    test('names what is due today, then what is overdue', () {
      final reminder = dueReminder([
        _item('a', title: 'Pay rent', due: DateTime(2026, 9, 24)),
        _item('b', title: 'Call Sam', due: DateTime(2026, 9, 24)),
        _item('c', title: 'Old', due: DateTime(2026, 9, 20)),
        _item('d', title: 'Later', due: DateTime(2026, 9, 25)),
        _item(
          'e',
          title: 'Done',
          due: DateTime(2026, 9, 24),
          column: TodoColumn.finished,
        ),
      ], today)!;
      expect(reminder.summary, '2 todos are due today');
      expect(reminder.body, contains('Pay rent'));
      expect(reminder.body, contains('Call Sam'));
      expect(reminder.body, contains('Overdue:'));
      expect(reminder.body, contains('Old (2026-09-20)'));
      expect(reminder.body, isNot(contains('Later')));
      expect(reminder.body, isNot(contains('Done')));
    });

    test('one item is named in the summary', () {
      final reminder = dueReminder([
        _item('a', title: 'Pay rent', due: DateTime(2026, 9, 24)),
      ], today)!;
      expect(reminder.summary, 'Due today: Pay rent');
    });

    test('nothing due is silence', () {
      expect(
        dueReminder([_item('a', due: DateTime(2026, 9, 25))], today),
        isNull,
      );
      expect(
        dueReminder([
          _item('a', due: DateTime(2026, 9, 1), column: TodoColumn.abandoned),
        ], today),
        isNull,
      );
    });
  });

  group('the file', () {
    test('round-trips', () {
      final items = [
        _item(
          'a',
          due: DateTime(2026, 10, 2),
          recurrence: TodoRecurrence(
            every: 2,
            unit: RecurrenceUnit.days,
            start: DateTime(2026, 9, 1),
            since: DateTime(2026, 9, 20),
          ),
        ).copyWith(
          body: 'Line one\nLine two',
          history: [
            TodoMove(
              from: null,
              to: TodoColumn.todo,
              at: DateTime(2026, 9, 1, 9),
            ),
            TodoMove(
              from: TodoColumn.todo,
              to: TodoColumn.inProgress,
              at: DateTime(2026, 9, 2, 14, 30),
            ),
          ],
        ),
        _item('b', column: TodoColumn.abandoned),
      ];
      expect(decodeTodoFile(encodeTodoFile(items)), items);
    });

    test('a bad row costs that row; a bad field costs that field', () {
      final items = decodeTodoFile('''
{
  "version": 1,
  "items": [
    {"id": "a", "title": "Fine", "column": "todo"},
    {"id": "b", "title": "No such column", "column": "someday"},
    "not an item",
    {"id": "a", "title": "Duplicate", "column": "inbox"},
    {"id": "c", "title": 7, "column": "in_progress", "due": "2026-02-30",
     "recurrence": {"every": 0, "unit": "days", "start": "2026-01-01"},
     "history": [{"to": "todo", "at": "nonsense"},
                 {"from": "todo", "to": "in_progress",
                  "at": "2026-09-02T12:00:00.000Z"}]}
  ]
}''');
      expect(items.map((i) => i.id), ['a', 'c']);
      final c = items[1];
      expect(c.title, '');
      expect(c.due, isNull);
      expect(c.recurrence, isNull);
      expect(c.history.single.to, TodoColumn.inProgress);
    });

    test('a file that is not a board throws rather than reading as empty', () {
      expect(
        () => decodeTodoFile('{"items": ['),
        throwsA(isA<TodoFormatException>()),
      );
      expect(() => decodeTodoFile('[]'), throwsA(isA<TodoFormatException>()));
      expect(
        () => decodeTodoFile('{"version": 99, "items": []}'),
        throwsA(isA<TodoFormatException>()),
      );
    });
  });
}
