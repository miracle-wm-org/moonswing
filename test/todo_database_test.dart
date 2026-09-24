import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_database.dart';
import 'package:moonswing/todo/todo_model.dart';

TodoItem _item(
  String id, {
  String title = '',
  String body = '',
  TodoColumn column = TodoColumn.inbox,
  DateTime? due,
  TodoRecurrence? recurrence,
}) => TodoItem(
  id: id,
  title: title,
  body: body,
  column: column,
  created: DateTime(2026, 9, 20, 10),
  due: due,
  recurrence: recurrence,
  history: [TodoMove(from: null, to: column, at: DateTime(2026, 9, 20, 10))],
);

NoteItem _note(String id, String body, {DateTime? updated}) => NoteItem(
  id: id,
  title: '',
  body: body,
  created: DateTime(2026, 9, 20, 10),
  updated: updated ?? DateTime(2026, 9, 20, 10),
);

TodoChanges _board(List<TodoItem> items, {List<NoteItem> notes = const []}) =>
    TodoChanges(
      todos: [
        for (var i = 0; i < items.length; i++) (item: items[i], position: i),
      ],
      notes: notes,
    );

void main() {
  late TodoDatabase db;
  final at = DateTime(2026, 9, 24, 12);

  setUp(() => db = TodoDatabase.openInMemory());
  tearDown(() => db.close());

  List<String> ids(String query, {EntryKind? kind}) => [
    for (final hit in db.search(query, kind: kind)) hit.id,
  ];

  test('a card reads back exactly as it was written', () {
    final item =
        _item(
          'a',
          title: 'Water plants',
          body: 'The ferns too',
          column: TodoColumn.todo,
          due: DateTime(2026, 9, 30),
          recurrence: TodoRecurrence(
            every: 2,
            unit: RecurrenceUnit.weeks,
            start: DateTime(2026, 9, 2),
            since: DateTime(2026, 9, 16),
          ),
        ).copyWith(
          history: [
            TodoMove(
              from: null,
              to: TodoColumn.inbox,
              at: DateTime(2026, 9, 20),
            ),
            TodoMove(
              from: TodoColumn.inbox,
              to: TodoColumn.todo,
              at: DateTime(2026, 9, 21, 8, 30),
            ),
          ],
        );
    db.apply(_board([item]), at: at);
    expect(db.readAll().todos, [item]);
  });

  test('board order is the written positions, and moves only renumber', () {
    db.apply(_board([_item('a'), _item('b'), _item('c')]), at: at);
    db.apply(
      const TodoChanges(
        positions: [
          (id: 'c', position: 0),
          (id: 'a', position: 1),
          (id: 'b', position: 2),
        ],
      ),
      at: at,
    );
    expect(db.readAll().todos.map((i) => i.id), ['c', 'a', 'b']);
  });

  test('a delete removes the row and its index entry', () {
    db.apply(_board([_item('a', title: 'Unique marker')]), at: at);
    expect(ids('marker'), ['a']);
    db.apply(const TodoChanges(deletes: ['a']), at: at);
    expect(db.readAll().todos, isEmpty);
    expect(ids('marker'), isEmpty);
  });

  test('an edit re-indexes the card', () {
    db.apply(_board([_item('a', title: 'Old words')]), at: at);
    db.apply(_board([_item('a', title: 'New phrasing')]), at: at);
    expect(ids('old'), isEmpty);
    expect(ids('phras'), ['a']);
  });

  group('search', () {
    setUp(() {
      db.apply(
        _board(
          [
            _item(
              'bt',
              title: 'Fix the Bluetooth bug',
              body: 'Pairing fails after suspend',
            ),
            _item('shop', title: 'Groceries', body: 'milk, bread, 100% rye'),
            _item('ui', title: 'Tweak UI spacing', body: 'c++ "quoted" thing'),
          ],
          notes: [_note('wifi', 'Router password is Hunter2')],
        ),
        at: at,
      );
    });

    test('matches the middle of a word, in any case', () {
      expect(ids('LUETOO'), ['bt']);
      expect(ids('unter'), ['wifi']);
    });

    test('needs every term, from title or body', () {
      expect(ids('bluetooth suspend'), ['bt']);
      expect(ids('bluetooth milk'), isEmpty);
    });

    test('ranks a title hit above a body hit', () {
      db.apply(
        TodoChanges(
          todos: [
            (item: _item('body', body: 'mention of zebra'), position: 3),
            (item: _item('title', title: 'Zebra crossing'), position: 4),
          ],
        ),
        at: at,
      );
      expect(ids('zebra'), ['title', 'body']);
    });

    test('takes any string literally', () {
      expect(ids('c++'), ['ui']);
      expect(ids('"quoted"'), ['ui']);
      expect(ids('100%'), ['shop']);
      expect(ids('AND'), isEmpty);
      expect(ids('NOT bug'), isEmpty);
    });

    test('short terms fall back to a scan', () {
      expect(ids('ui'), ['ui']);
      expect(ids('ui spac'), ['ui']);
      expect(ids('%'), ['shop']);
      expect(ids('_'), isEmpty);
    });

    test('finds notes as well as cards, or only one kind', () {
      db.apply(
        TodoChanges(
          todos: [
            (item: _item('call', title: 'Call about router'), position: 3),
          ],
        ),
        at: at,
      );
      expect(db.search('router').map((h) => (h.id, h.kind)).toSet(), {
        ('call', EntryKind.todo),
        ('wifi', EntryKind.note),
      });
      expect(ids('router', kind: EntryKind.note), ['wifi']);
      expect(ids('router', kind: EntryKind.todo), ['call']);
    });

    test('a blank query finds nothing', () {
      expect(ids(''), isEmpty);
      expect(ids('  \t '), isEmpty);
    });
  });

  test('notes read back most recently edited first', () {
    db.apply(
      _board(
        const [],
        notes: [
          _note('old', 'first', updated: DateTime(2026, 9, 1)),
          _note('new', 'second', updated: DateTime(2026, 9, 20)),
        ],
      ),
      at: at,
    );
    expect(db.readAll().notes.map((n) => n.id), ['new', 'old']);
    expect(db.readAll().todos, isEmpty);
  });

  test('importing a file keeps the rows already there, once', () {
    db.apply(_board([_item('a', title: 'Database copy')]), at: at);
    expect(db.importedJson, isFalse);
    db.importJson([_item('a', title: 'File copy'), _item('b')], at: at);
    expect(db.importedJson, isTrue);
    final todos = db.readAll().todos;
    expect(todos.map((i) => i.id), ['a', 'b']);
    expect(todos.first.title, 'Database copy');
  });

  group('on disk', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('todo_db_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a file that is not a database is refused, untouched', () {
      final file = File('${dir.path}/notes.db')
        ..writeAsStringSync('not a database, just somebody\'s file' * 200);
      final before = file.readAsBytesSync();
      expect(
        () => TodoDatabase.open(file.path),
        throwsA(isA<TodoFormatException>()),
      );
      expect(file.readAsBytesSync(), before);
    });

    test('a database from a newer shell is refused', () {
      final path = '${dir.path}/notes.db';
      TodoDatabase.open(path).close();
      // Bump the schema version by hand, the way a later shell would.
      final raw = File(path).readAsBytesSync();
      // user_version is the big-endian int at offset 60 of the header.
      raw[63] = kTodoSchemaVersion + 1;
      File(path).writeAsBytesSync(raw);
      expect(
        () => TodoDatabase.open(path),
        throwsA(
          isA<TodoFormatException>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('what is written survives a reopen', () {
      final path = '${dir.path}/notes.db';
      final first = TodoDatabase.open(path);
      first.apply(_board([_item('a', title: 'Kept')]), at: at);
      first.close();
      final second = TodoDatabase.open(path);
      addTearDown(second.close);
      expect(second.readAll().todos.single.title, 'Kept');
      expect([for (final h in second.search('kep')) h.id], ['a']);
    });
  });

  group('query building', () {
    test('quotes every term and doubles its quotes', () {
      expect(ftsQueryFor(['bug', 'say "hi"']), '"bug" "say ""hi"""');
    });

    test('escapes LIKE wildcards', () {
      expect(likePatternFor(r'5%_a\b'), r'%5\%\_a\\b%');
    });
  });
}
