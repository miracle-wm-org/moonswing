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

  File legacy() => File('${dir.path}/todo.json');
  File database() => File('${dir.path}/notes.db');

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
    expect(database().existsSync(), isTrue);

    final again = TodoStore.forTesting(directory: dir.path, now: () => now);
    addTearDown(again.dispose);
    await again.load();
    expect(again.items, store.items);
    expect(again.items.single.due, DateTime(2026, 9, 30));
  });

  test('a board moves, reorders and deletes across a reopen', () async {
    await store.load();
    final a = store.add(TodoColumn.inbox, title: 'A')!;
    final b = store.add(TodoColumn.inbox, title: 'B')!;
    final c = store.add(TodoColumn.todo, title: 'C', body: 'notes')!;
    await store.flush();
    store.move(a, TodoColumn.inbox, beforeId: b);
    store.move(c, TodoColumn.finished);
    store.delete(b);
    await store.flush();

    final again = TodoStore.forTesting(directory: dir.path, now: () => now);
    addTearDown(again.dispose);
    await again.load();
    expect(again.items, store.items);
    expect(again.itemsIn(TodoColumn.inbox).map((i) => i.id), [a]);
    expect(again.item(c)!.history, hasLength(2));
  });

  test('an old todo.json is imported once and kept', () async {
    final old = [
      TodoItem(
        id: 'old-1',
        title: 'From the file',
        body: 'imported',
        column: TodoColumn.todo,
        created: DateTime(2026, 9, 1, 8),
        due: DateTime(2026, 9, 30),
        history: [
          TodoMove(
            from: null,
            to: TodoColumn.todo,
            at: DateTime(2026, 9, 1, 8),
          ),
        ],
      ),
    ];
    legacy().writeAsStringSync(encodeTodoFile(old));
    await store.load();
    expect(store.items, old);
    expect(legacy().existsSync(), isFalse);
    expect(File('${legacy().path}.imported').existsSync(), isTrue);

    // Put back, it is not imported a second time over the board it became.
    store.delete('old-1');
    await store.flush();
    legacy().writeAsStringSync(encodeTodoFile(old));
    final again = TodoStore.forTesting(directory: dir.path, now: () => now);
    addTearDown(again.dispose);
    await again.load();
    expect(again.items, isEmpty);
  });

  test('a todo.json that will not read is never imported over', () async {
    legacy().writeAsStringSync('{"items": [ broken');
    await store.load();
    expect(store.loaded, isTrue);
    expect(store.loadError, isNotNull);
    expect(store.editable, isFalse);
    expect(store.add(TodoColumn.inbox, title: 'Lost'), isNull);
    await store.flush();
    expect(legacy().readAsStringSync(), '{"items": [ broken');

    // Mended by hand; a retry picks it up and the board is editable again.
    legacy().writeAsStringSync('{"version": 1, "items": []}');
    await store.retry();
    expect(store.loadError, isNull);
    expect(store.editable, isTrue);
  });

  test('a database that will not read is never written into', () async {
    final garbage = List<int>.generate(4096, (i) => i % 251);
    database().writeAsBytesSync(garbage);
    await store.load();
    expect(store.loadError, isNotNull);
    expect(store.editable, isFalse);
    expect(store.add(TodoColumn.inbox, title: 'Lost'), isNull);
    await store.flush();
    expect(database().readAsBytesSync(), garbage);

    database().deleteSync();
    await store.retry();
    expect(store.loadError, isNull);
    expect(store.editable, isTrue);
  });

  test('search finds any part of a card, including an unsaved edit', () async {
    await store.load();
    final bt = store.add(
      TodoColumn.inbox,
      title: 'Fix the Bluetooth bug',
      body: 'Pairing fails after suspend',
    )!;
    await store.flush();
    final groceries = store.add(TodoColumn.todo, title: 'Groceries')!;
    // Not flushed: the search writes it first.
    expect(store.search('luetoo').map((h) => h.id), [bt]);
    expect(store.search('SUSPEND bug').map((h) => h.id), [bt]);
    expect(store.search('ocer').map((h) => h.id), [groceries]);
    expect(store.search('bluetooth groceries'), isEmpty);
    expect(store.search('   '), isEmpty);
  });

  test('notes are kept beside the board and searched with it', () async {
    await store.load();
    final todo = store.add(TodoColumn.inbox, title: 'Call about wifi')!;
    final note = store.addNote(body: 'wifi password is hunter2')!;
    expect(store.notes.single.body, 'wifi password is hunter2');
    expect(store.search('wifi').map((h) => (h.id, h.kind)).toSet(), {
      (todo, EntryKind.todo),
      (note, EntryKind.note),
    });
    expect(store.search('wifi', kind: EntryKind.note).single.id, note);

    now = DateTime(2026, 9, 24, 10);
    store.updateNote(note, title: 'Router', body: 'guest network is open');
    await store.flush();
    final again = TodoStore.forTesting(directory: dir.path, now: () => now);
    addTearDown(again.dispose);
    await again.load();
    expect(again.notes, store.notes);
    expect(again.notes.single.updated, now);
    expect(again.search('hunter'), isEmpty);
    expect(again.search('guest').single.kind, EntryKind.note);

    again.deleteNote(note);
    expect(again.search('guest'), isEmpty);
    expect(again.notes, isEmpty);
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
