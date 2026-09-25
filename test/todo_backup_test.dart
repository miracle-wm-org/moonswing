import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_backup.dart';
import 'package:moonswing/todo/todo_model.dart';

TodoItem _item(String id, TodoColumn column) => TodoItem(
  id: id,
  title: 'Card $id',
  body: 'Body of $id',
  column: column,
  created: DateTime(2026, 9, 20, 10),
  due: DateTime(2026, 9, 30),
  recurrence: TodoRecurrence(
    every: 2,
    unit: RecurrenceUnit.weeks,
    start: DateTime(2026, 9, 1),
    since: DateTime(2026, 9, 15),
  ),
  history: [TodoMove(from: null, to: column, at: DateTime(2026, 9, 20, 10))],
);

NoteItem _note(String id, DateTime created) => NoteItem(
  id: id,
  title: 'Note $id',
  body: 'Text of $id',
  created: created,
  updated: created.add(const Duration(hours: 1)),
);

void main() {
  group('format', () {
    test('a board survives the round trip', () {
      final items = [_item('b', TodoColumn.todo), _item('a', TodoColumn.inbox)];
      final notes = [_note('n1', DateTime(2026, 9, 21, 8))];
      final backup = decodeTodoBackup(encodeTodoBackup(items, notes));
      expect(backup.items, items);
      expect(backup.notes, notes);
      expect(backup.summary, '2 cards and 1 note');
    });

    test('cards keep board order; notes are written oldest first', () {
      final older = _note('old', DateTime(2026, 1, 1));
      final newer = _note('new', DateTime(2026, 6, 1));
      final a = encodeTodoBackup(const [], [newer, older]);
      final b = encodeTodoBackup(const [], [older, newer]);
      // The store's notes are most-recently-edited first, so editing one
      // reorders them; the file must not.
      expect(a, b);
      final json = jsonDecode(a) as Map;
      expect((json['notes'] as List).map((n) => (n as Map)['id']), [
        'old',
        'new',
      ]);
      expect(a, endsWith('}\n'));
    });

    test('an old todo.json reads as a backup of its cards', () {
      final items = [_item('a', TodoColumn.inbox)];
      final backup = decodeTodoBackup(encodeTodoFile(items));
      expect(backup.items, items);
      expect(backup.notes, isEmpty);
    });

    test('a bad row costs that row, a duplicate id the later copy', () {
      final backup = decodeTodoBackup(
        jsonEncode({
          'format': kTodoBackupFormat,
          'version': 1,
          'items': [
            _item('a', TodoColumn.inbox).toJson(),
            {'id': 'x', 'column': 'nowhere'},
            _item('a', TodoColumn.todo).toJson(),
          ],
          'notes': [
            {'title': 'no id'},
            _note('n', DateTime(2026, 1, 1)).toJson(),
          ],
        }),
      );
      expect(backup.items.single.column, TodoColumn.inbox);
      expect(backup.notes.single.id, 'n');
    });

    test('refuses what is not a board, or is from a newer shell', () {
      expect(
        () => decodeTodoBackup('not json'),
        throwsA(isA<TodoFormatException>()),
      );
      expect(
        () => decodeTodoBackup('{"format": "something-else"}'),
        throwsA(isA<TodoFormatException>()),
      );
      expect(
        () => decodeTodoBackup(
          jsonEncode({'format': kTodoBackupFormat, 'version': 99}),
        ),
        throwsA(isA<TodoFormatException>()),
      );
    });
  });

  group('file', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('todo_backup_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes, and does not rewrite identical contents', () async {
      final file = TodoBackupFile('${dir.path}/backup/todo-backup.json');
      expect(await file.write('one\n'), isTrue);
      expect(await file.write('one\n'), isFalse);
      // A fresh writer over the same file reads it before deciding.
      expect(await TodoBackupFile(file.path).write('one\n'), isFalse);
      expect(await file.write('two\n'), isTrue);
      expect(File(file.path).readAsStringSync(), 'two\n');
      // No temporary file left behind to be committed by mistake.
      expect(Directory('${dir.path}/backup').listSync().map((e) => e.path), [
        file.path,
      ]);
    });

    test('writes through a symlink rather than over it', () async {
      final elsewhere = File('${dir.path}/dotfiles/todo.json')
        ..createSync(recursive: true);
      final link = Link('${dir.path}/backup/todo-backup.json')
        ..createSync(elsewhere.path, recursive: true);
      await TodoBackupFile(link.path).write('board\n');
      expect(FileSystemEntity.isLinkSync(link.path), isTrue);
      expect(elsewhere.readAsStringSync(), 'board\n');
    });

    test('reads back what it wrote, and nothing when there is none', () async {
      final file = TodoBackupFile('${dir.path}/todo-backup.json');
      expect(await file.read(), isNull);
      await file.write(encodeTodoBackup([_item('a', TodoColumn.inbox)], []));
      final saved = await file.read();
      expect(saved!.backup.items.single.id, 'a');
    });
  });

  test('the digest is 64-bit FNV-1a', () {
    // The published test vectors.
    expect(todoBackupDigest(''), 'cbf29ce484222325');
    expect(todoBackupDigest('a'), 'af63dc4c8601ec8c');
    expect(todoBackupDigest('foobar'), '85944171f73967e8');
  });
}
