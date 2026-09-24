import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

void main() {
  late Directory dir;
  late DateTime now;
  late TodoStore store;
  late List<(String, String)> reminders;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('todo_store_test');
    now = DateTime(2026, 9, 24, 9, 0);
    reminders = [];
    store = TodoStore.forTesting(directory: dir.path, now: () => now)
      ..onReminder = (summary, body) => reminders.add((summary, body));
  });

  tearDown(() {
    store.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File file() => File('${dir.path}/todo.json');

  test('a missing file is an empty, editable board', () async {
    await store.load();
    expect(store.loaded, isTrue);
    expect(store.editable, isTrue);
    expect(store.items, isEmpty);
  });

  test(
    'a new item goes on top of its column and records its creation',
    () async {
      await store.load();
      final first = store.add(TodoColumn.inbox, title: 'First')!;
      final second = store.add(TodoColumn.inbox, title: 'Second')!;
      expect(store.itemsIn(TodoColumn.inbox).map((i) => i.id), [second, first]);
      final created = store.item(first)!.history.single;
      expect(created.from, isNull);
      expect(created.to, TodoColumn.inbox);
      expect(created.at, now);
    },
  );

  test('a move between columns is recorded with its time', () async {
    await store.load();
    final id = store.add(TodoColumn.inbox, title: 'Ticket')!;
    now = DateTime(2026, 9, 24, 11, 15);
    store.move(id, TodoColumn.inProgress);
    now = DateTime(2026, 9, 25, 16, 40);
    store.move(id, TodoColumn.finished);

    final item = store.item(id)!;
    expect(item.column, TodoColumn.finished);
    expect(item.history.map((m) => (m.from, m.to, m.at)), [
      (null, TodoColumn.inbox, DateTime(2026, 9, 24, 9)),
      (TodoColumn.inbox, TodoColumn.inProgress, DateTime(2026, 9, 24, 11, 15)),
      (
        TodoColumn.inProgress,
        TodoColumn.finished,
        DateTime(2026, 9, 25, 16, 40),
      ),
    ]);
    expect(item.movedAt, DateTime(2026, 9, 25, 16, 40));
  });

  test('a reorder within a column is not history', () async {
    await store.load();
    final a = store.add(TodoColumn.todo, title: 'A')!;
    final b = store.add(TodoColumn.todo, title: 'B')!;
    expect(store.itemsIn(TodoColumn.todo).map((i) => i.id), [b, a]);
    store.move(a, TodoColumn.todo, beforeId: b);
    expect(store.itemsIn(TodoColumn.todo).map((i) => i.id), [a, b]);
    expect(store.item(a)!.history, hasLength(1));
  });

  test('a drop above a card in another column lands there', () async {
    await store.load();
    final x = store.add(TodoColumn.todo, title: 'X')!;
    final y = store.add(TodoColumn.todo, title: 'Y')!;
    final moving = store.add(TodoColumn.inbox, title: 'Moving')!;
    store.move(moving, TodoColumn.todo, beforeId: x);
    expect(store.itemsIn(TodoColumn.todo).map((i) => i.id), [y, moving, x]);
    expect(store.itemsIn(TodoColumn.inbox), isEmpty);
  });

  test('changing the column from the editor is a recorded move', () async {
    await store.load();
    final id = store.add(TodoColumn.inbox, title: 'T')!;
    store.update(
      id,
      title: 'T2',
      body: 'b',
      column: TodoColumn.abandoned,
      due: null,
      recurrence: null,
    );
    final item = store.item(id)!;
    expect(item.title, 'T2');
    expect(item.column, TodoColumn.abandoned);
    expect(item.history.last.from, TodoColumn.inbox);
  });

  test('flush writes a board that reads back', () async {
    await store.load();
    store.add(TodoColumn.todo, title: 'Saved', due: DateTime(2026, 9, 30, 13));
    await store.flush();
    expect(file().existsSync(), isTrue);
    expect(File('${file().path}.tmp').existsSync(), isFalse);

    final again = TodoStore.forTesting(directory: dir.path, now: () => now);
    addTearDown(again.dispose);
    await again.load();
    expect(again.items, store.items);
    expect(again.items.single.due, DateTime(2026, 9, 30));
  });

  test('a file that will not read is never written over', () async {
    file().writeAsStringSync('{"items": [ broken');
    await store.load();
    expect(store.loaded, isTrue);
    expect(store.loadError, isNotNull);
    expect(store.editable, isFalse);
    expect(store.add(TodoColumn.inbox, title: 'Lost'), isNull);
    await store.flush();
    expect(file().readAsStringSync(), '{"items": [ broken');

    // Mended by hand; a retry picks it up and the board is editable again.
    file().writeAsStringSync('{"version": 1, "items": []}');
    await store.retry();
    expect(store.loadError, isNull);
    expect(store.editable, isTrue);
  });

  test('the start of the day spawns recurring copies and reminds', () async {
    await store.load();
    store.add(
      TodoColumn.finished,
      title: 'Water plants',
      recurrence: TodoRecurrence(
        every: 1,
        unit: RecurrenceUnit.weeks,
        start: DateTime(2026, 9, 17),
        since: DateTime(2026, 9, 17),
      ),
    );
    store.add(TodoColumn.inbox, title: 'Tomorrow', due: DateTime(2026, 9, 25));

    store.startOfDay();

    final todo = store.itemsIn(TodoColumn.todo);
    expect(todo.single.title, 'Water plants');
    expect(todo.single.due, DateTime(2026, 9, 24));
    expect(todo.single.recurrence, isNotNull);
    expect(store.itemsIn(TodoColumn.finished).single.recurrence, isNull);
    expect(reminders.single.$1, 'Due today: Water plants');
    expect(store.dueCount, 1);

    // The next day: the other item is due, the plants are overdue, and no new
    // copy is owed until the week is up.
    now = DateTime(2026, 9, 25, 0, 0, 1);
    reminders.clear();
    store.startOfDay();
    expect(store.itemsIn(TodoColumn.todo), hasLength(1));
    expect(reminders.single.$1, 'Due today: Tomorrow');
    expect(reminders.single.$2, contains('Water plants (2026-09-24)'));
    expect(store.dueCount, 2);
  });

  test('a quiet day posts nothing', () async {
    await store.load();
    store.add(TodoColumn.inbox, title: 'Undated');
    store.startOfDay();
    expect(reminders, isEmpty);
  });
}
