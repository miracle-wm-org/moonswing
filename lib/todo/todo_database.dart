// The todo board's database: every card and every note, and the index that
// searches them.
//
// Flutter-free, like `todo_model.dart`, for `test/todo_database_test.dart`,
// which runs it against an in-memory database. The store above it keeps the
// board in memory and hands this a diff to write; nothing here decides what the
// board looks like.

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_standup.dart';

/// The schema's version, kept in `PRAGMA user_version`. A *newer* database is
/// refused — one a later shell wrote is not one this one may write into — and
/// an older one is brought forward by [_migrate].
///
///  1. The board.
///  2. `entries.external`: the calendar event a card mirrors.
///  3. `standups`: every standup summary taken, so an old one can be copied
///     again.
///  4. `entries.remote`: the task a card is on the synced CalDAV task list;
///     `remote_tombstones`: tasks deleted here and still owed a delete there.
const int kTodoSchemaVersion = 4;

/// The oldest SQLite with FTS5's `trigram` tokenizer, as
/// `sqlite3_libversion_number` spells it.
const int kMinSqliteVersion = 3034000;

/// Refuses a SQLite too old for the index.
///
/// The shell ships its own (package:sqlite3's build hook puts it in the
/// bundle's `lib/`), but it is found by *name* — the embedder `dlopen`s
/// `libsqlite3.so` and lets the loader search — and `LD_LIBRARY_PATH` is
/// searched before the bundle. The snap's own entries come first, so there it
/// cannot happen; a plain install run with a `LD_LIBRARY_PATH` holding some
/// other `libsqlite3.so` gets that one instead, and this says so rather than
/// failing on the index with a message about tokenizers.
void _checkLibrary() {
  final version = sqlite3.version;
  if (version.versionNumber >= kMinSqliteVersion) return;
  throw TodoFormatException(
    'The SQLite library loaded is ${version.libVersion}, and the todo board '
    'needs 3.34 or newer. The shell ships its own; an older libsqlite3.so '
    'found first on LD_LIBRARY_PATH is the usual reason it was not used.',
  );
}

/// The `meta` key recording that an old `todo.json` has been imported, so that
/// a file left behind (or put back) is not imported a second time over the
/// board it became.
const String _kImportedJsonKey = 'imported_todo_json';

/// The `meta` key holding when the last standup summary was taken, which the
/// next one counts from. UTC, ISO 8601. Kept apart from the `standups` table,
/// which a database from before schema 3 has no rows in for the instant it
/// already recorded.
const String _kStandupKey = 'standup_at';

/// The `meta` key holding the calendar events whose cards the user deleted, so
/// the calendar sync does not put them straight back. A JSON list of keys.
const String _kDismissedCalendarKey = 'calendar_dismissed';

/// The `meta` key holding the CalDAV task list the board syncs with, as JSON
/// (see [TodoRemoteLink]). Kept with the board rather than with the account,
/// because the cards' [TodoRemote] records are only meaningful against it.
const String _kRemoteLinkKey = 'caldav_link';

/// The CalDAV task list the board is linked to, and how far the last sync got.
class TodoRemoteLink {
  const TodoRemoteLink({
    required this.url,
    required this.name,
    this.color,
    this.changeToken,
  });

  /// The collection, absolute, ending in `/`.
  final String url;
  final String name;

  /// `#rrggbb`, when the server has one.
  final String? color;

  /// The collection's change token at the end of the last full sync, or null
  /// before the first. See `CalDavClient.changeToken`.
  final String? changeToken;

  TodoRemoteLink copyWith({Object? changeToken = _keep}) => TodoRemoteLink(
    url: url,
    name: name,
    color: color,
    changeToken: identical(changeToken, _keep)
        ? this.changeToken
        : changeToken as String?,
  );

  static const Object _keep = Object();

  Map<String, Object?> toJson() => {
    'url': url,
    'name': name,
    if (color != null) 'color': color,
    if (changeToken != null) 'change_token': changeToken,
  };

  static TodoRemoteLink? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    String? text(String key) =>
        json[key] is String ? json[key] as String : null;
    return TodoRemoteLink(
      url: url,
      name: text('name') ?? url,
      color: text('color'),
      changeToken: text('change_token'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TodoRemoteLink &&
      other.url == url &&
      other.name == name &&
      other.color == color &&
      other.changeToken == changeToken;

  @override
  int get hashCode => Object.hash(url, name, color, changeToken);
}

/// A task deleted on the board whose delete the server has not had yet.
typedef TodoTombstone = ({String href, String? etag});

/// SQLite's primary result codes for a file that is damaged, or is not a
/// database at all.
const int _kSqliteCorrupt = 11;
const int _kSqliteNotADatabase = 26;

/// Whether [e] says the file itself is damaged — as opposed to locked, full,
/// read-only or from a newer shell, none of which a rebuild would mend.
bool isDamage(SqliteException e) {
  final code = e.resultCode & 0xff;
  return code == _kSqliteCorrupt || code == _kSqliteNotADatabase;
}

/// The database file is damaged: not a database, or one whose pages do not
/// check out. Unlike every other [TodoFormatException] this one may be
/// recovered from — the store sets the file aside and rebuilds the board from
/// its backup — because nothing in the file can be trusted to be written into
/// anyway.
class TodoDatabaseDamaged extends TodoFormatException {
  const TodoDatabaseDamaged(super.message);
}

/// What one write changes: rows to insert or replace, rows whose only change
/// is their place on the board, and rows to delete.
class TodoChanges {
  const TodoChanges({
    this.todos = const [],
    this.positions = const [],
    this.notes = const [],
    this.deletes = const [],
  });

  /// Cards to write whole, each with its place in board order.
  final List<({TodoItem item, int position})> todos;

  /// Cards that only moved within the board order.
  final List<({String id, int position})> positions;

  final List<NoteItem> notes;

  /// Ids of cards or notes to remove.
  final List<String> deletes;

  bool get isEmpty =>
      todos.isEmpty && positions.isEmpty && notes.isEmpty && deletes.isEmpty;
}

/// The FTS5 query for [terms]: each one a quoted string, which in a `trigram`
/// index matches it as a substring anywhere, and all of them required.
///
/// Quoting is what makes *any* string searchable — `c++`, `a-b`, `NOT`, a stray
/// `"` — rather than something FTS5 parses as its own syntax and rejects.
String ftsQueryFor(List<String> terms) =>
    terms.map((term) => '"${term.replaceAll('"', '""')}"').join(' ');

/// A `LIKE` pattern matching [term] anywhere, with its own `%`, `_` and `\`
/// taken literally (the query says `ESCAPE '\'`).
String likePatternFor(String term) =>
    '%${term.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}')}%';

/// The shortest term a `trigram` index can look up. Shorter ones are matched
/// with `LIKE` instead — a scan, but of a table of somebody's own notes.
const int _kTrigram = 3;

/// One SQLite database holding the board and the notes.
///
/// Both kinds are rows of the one `entries` table and the one `entries_fts`
/// index, which is what lets a search find either. The index is an external-
/// content FTS5 table kept in step by triggers, so no write path can forget it;
/// it is keyed on `seq`, an `INTEGER PRIMARY KEY`, because an implicit rowid
/// may be renumbered by `VACUUM` and would then point the index at the wrong
/// rows.
class TodoDatabase {
  TodoDatabase._(this._db);

  final Database _db;

  /// Opens (creating if need be) the database at [path].
  ///
  /// Throws [TodoFormatException] for anything that means "do not write here":
  /// a file that is not a database, a schema from a newer shell, or a SQLite
  /// too old for the index (see [_checkLibrary]). Nothing is written before the file has
  /// been read and found to be ours.
  static TodoDatabase open(String path) {
    _checkLibrary();
    final Database db;
    try {
      db = sqlite3.open(path);
    } on SqliteException catch (e) {
      throw TodoFormatException('Could not open $path: ${e.message}');
    }
    return _prepare(db, path);
  }

  /// An empty database in memory, for tests.
  static TodoDatabase openInMemory() {
    _checkLibrary();
    return _prepare(sqlite3.openInMemory(), 'The in-memory database');
  }

  static TodoDatabase _prepare(Database db, String label) {
    try {
      final int version;
      try {
        // The first statement is the one that reads the header, so this is
        // where a file that is not a database says so.
        version = db.userVersion;
      } on SqliteException catch (e) {
        final message =
            '$label is not a database the shell can read: ${e.message}';
        throw isDamage(e)
            ? TodoDatabaseDamaged(message)
            : TodoFormatException(message);
      }
      if (version > kTodoSchemaVersion) {
        throw TodoFormatException(
          '$label was written by a newer version of the shell (schema '
          '$version).',
        );
      }
      try {
        // WAL: a write is one append, and a crash mid-write leaves the last
        // committed board. NORMAL is durable against the shell dying, which is
        // the failure this has to survive.
        db.execute('PRAGMA journal_mode = WAL');
        db.execute('PRAGMA synchronous = NORMAL');
        if (version == 0) {
          _createSchema(db);
        } else if (version < kTodoSchemaVersion) {
          _migrate(db, version);
        }
        // A header that reads is not a board that does: a torn page further
        // in only shows when something reads it, which for the index may be
        // the first search. `quick_check` walks every page, once, at start-up
        // — milliseconds for somebody's notes.
        final check = db.select('PRAGMA quick_check(1)');
        final verdict = check.isEmpty ? 'ok' : check.first.values.first;
        if (verdict != 'ok') {
          throw TodoDatabaseDamaged('$label is damaged: $verdict');
        }
      } on SqliteException catch (e) {
        final message = '$label could not be set up: ${e.message}';
        throw isDamage(e)
            ? TodoDatabaseDamaged(message)
            : TodoFormatException(message);
      }
      return TodoDatabase._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static void _createSchema(Database db) {
    _transactionOn(db, () {
      db.execute('''
        CREATE TABLE entries(
          seq          INTEGER PRIMARY KEY,
          id           TEXT NOT NULL UNIQUE,
          kind         TEXT NOT NULL CHECK (kind IN ('todo', 'note')),
          position     INTEGER NOT NULL DEFAULT 0,
          title        TEXT NOT NULL DEFAULT '',
          body         TEXT NOT NULL DEFAULT '',
          board_column TEXT,
          created      TEXT NOT NULL,
          updated      TEXT NOT NULL,
          due          TEXT,
          recurrence   TEXT,
          history      TEXT NOT NULL DEFAULT '[]',
          external     TEXT,
          remote       TEXT
        )''');
      db.execute('CREATE INDEX entries_order ON entries(kind, position)');
      // `trigram`, not the default word tokenizer: "any string" includes the
      // middle of a word — `luetoo` finds Bluetooth — and it folds case.
      db.execute('''
        CREATE VIRTUAL TABLE entries_fts USING fts5(
          title, body,
          content = 'entries', content_rowid = 'seq',
          tokenize = 'trigram'
        )''');
      db.execute('''
        CREATE TRIGGER entries_ai AFTER INSERT ON entries BEGIN
          INSERT INTO entries_fts(rowid, title, body)
            VALUES (new.seq, new.title, new.body);
        END''');
      db.execute('''
        CREATE TRIGGER entries_ad AFTER DELETE ON entries BEGIN
          INSERT INTO entries_fts(entries_fts, rowid, title, body)
            VALUES ('delete', old.seq, old.title, old.body);
        END''');
      db.execute('''
        CREATE TRIGGER entries_au AFTER UPDATE OF title, body ON entries BEGIN
          INSERT INTO entries_fts(entries_fts, rowid, title, body)
            VALUES ('delete', old.seq, old.title, old.body);
          INSERT INTO entries_fts(rowid, title, body)
            VALUES (new.seq, new.title, new.body);
        END''');
      db.execute(
        'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      _createStandups(db);
      _createTombstones(db);
      db.userVersion = kTodoSchemaVersion;
    });
  }

  /// Brings a database written by an older shell forward, one version at a
  /// time, in one transaction: a failure leaves it exactly as it was.
  static void _migrate(Database db, int from) {
    _transactionOn(db, () {
      if (from < 2) {
        db.execute('ALTER TABLE entries ADD COLUMN external TEXT');
      }
      if (from < 3) _createStandups(db);
      if (from < 4) {
        db.execute('ALTER TABLE entries ADD COLUMN remote TEXT');
        _createTombstones(db);
      }
      db.userVersion = kTodoSchemaVersion;
    });
  }

  static void _createStandups(Database db) {
    db.execute('''
      CREATE TABLE standups(
        seq      INTEGER PRIMARY KEY,
        taken_at TEXT NOT NULL,
        since    TEXT,
        report   TEXT NOT NULL
      )''');
  }

  static void _createTombstones(Database db) {
    db.execute('''
      CREATE TABLE remote_tombstones(
        href TEXT PRIMARY KEY,
        etag TEXT
      )''');
  }

  static void _transactionOn(Database db, void Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      body();
      db.execute('COMMIT');
    } catch (_) {
      if (!db.autocommit) db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _transaction(void Function() body) => _transactionOn(_db, body);

  /// Every card in board order, and every note, most recently edited first.
  ///
  /// A row that cannot be a card costs that row, by [TodoItem.fromJson]'s
  /// rules — and is left in the table untouched, since the store only ever
  /// writes the rows it read.
  ({List<TodoItem> todos, List<NoteItem> notes}) readAll() {
    final todos = <TodoItem>[
      for (final row in _db.select(
        "SELECT * FROM entries WHERE kind = 'todo' ORDER BY position, seq",
      ))
        ?_todoFromRow(row),
    ];
    final notes = <NoteItem>[
      for (final row in _db.select(
        "SELECT * FROM entries WHERE kind = 'note' ORDER BY updated DESC, seq",
      ))
        ?_noteFromRow(row),
    ];
    return (todos: todos, notes: notes);
  }

  /// Writes [changes] in one transaction: all of it lands, or none of it.
  /// [at] is the time recorded as the rows' last update.
  void apply(TodoChanges changes, {required DateTime at}) {
    if (changes.isEmpty) return;
    final updated = at.toUtc().toIso8601String();
    _transaction(() {
      if (changes.deletes.isNotEmpty) {
        final delete = _db.prepare('DELETE FROM entries WHERE id = ?');
        try {
          for (final id in changes.deletes) {
            delete.execute([id]);
          }
        } finally {
          delete.close();
        }
      }
      if (changes.todos.isNotEmpty) {
        final upsert = _db.prepare(_kUpsertTodo);
        try {
          for (final (:item, :position) in changes.todos) {
            upsert.execute(_todoParameters(item, position, updated));
          }
        } finally {
          upsert.close();
        }
      }
      if (changes.positions.isNotEmpty) {
        final place = _db.prepare(
          'UPDATE entries SET position = ? WHERE id = ?',
        );
        try {
          for (final (:id, :position) in changes.positions) {
            place.execute([position, id]);
          }
        } finally {
          place.close();
        }
      }
      if (changes.notes.isNotEmpty) {
        final upsert = _db.prepare(_kUpsertNote);
        try {
          for (final note in changes.notes) {
            upsert.execute([
              note.id,
              note.title,
              note.body,
              note.created.toUtc().toIso8601String(),
              note.updated.toUtc().toIso8601String(),
            ]);
          }
        } finally {
          upsert.close();
        }
      }
    });
  }

  /// When the last standup summary was taken, or null before the first.
  DateTime? get standupAt {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [
      _kStandupKey,
    ]);
    if (rows.isEmpty) return null;
    final value = rows.single['value'];
    return value is String ? DateTime.tryParse(value)?.toLocal() : null;
  }

  /// Every standup summary taken, newest first. A row whose times do not
  /// parse costs that row.
  List<StandupSummary> get standups => [
    for (final row in _db.select(
      'SELECT taken_at, since, report FROM standups ORDER BY seq DESC',
    ))
      ?_standupFromRow(row),
  ];

  static StandupSummary? _standupFromRow(Row row) {
    final takenAt = row['taken_at'];
    final since = row['since'];
    final report = row['report'];
    if (takenAt is! String || report is! String) return null;
    final taken = DateTime.tryParse(takenAt)?.toLocal();
    if (taken == null) return null;
    return StandupSummary(
      takenAt: taken,
      since: since is String ? DateTime.tryParse(since)?.toLocal() : null,
      report: report,
    );
  }

  /// Keeps [summary] and records its [StandupSummary.takenAt] as when the last
  /// standup summary was taken, together.
  void recordStandup(StandupSummary summary) {
    _transaction(() {
      _db.execute(
        'INSERT INTO standups(taken_at, since, report) VALUES (?, ?, ?)',
        [
          summary.takenAt.toUtc().toIso8601String(),
          summary.since?.toUtc().toIso8601String(),
          summary.report,
        ],
      );
      _setStandupAt(summary.takenAt);
    });
  }

  void _setStandupAt(DateTime? at) {
    if (at == null) {
      _db.execute('DELETE FROM meta WHERE key = ?', [_kStandupKey]);
    } else {
      _db.execute('INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)', [
        _kStandupKey,
        at.toUtc().toIso8601String(),
      ]);
    }
  }

  /// The calendar events whose cards the user deleted.
  Set<String> get dismissedCalendarKeys {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [
      _kDismissedCalendarKey,
    ]);
    if (rows.isEmpty) return <String>{};
    final value = rows.single['value'];
    final decoded = value is String ? _decodeJson(value) : null;
    return {
      if (decoded is List)
        for (final key in decoded)
          if (key is String) key,
    };
  }

  /// Records [keys] as [dismissedCalendarKeys].
  void recordDismissedCalendarKeys(Iterable<String> keys) {
    _db.execute('INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)', [
      _kDismissedCalendarKey,
      jsonEncode(keys.toList()),
    ]);
  }

  /// The task list the board syncs with, or null when it is not linked.
  TodoRemoteLink? get remoteLink {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [
      _kRemoteLinkKey,
    ]);
    if (rows.isEmpty) return null;
    final value = rows.single['value'];
    return TodoRemoteLink.fromJson(value is String ? _decodeJson(value) : null);
  }

  /// Records [link] as [remoteLink], or forgets it.
  void recordRemoteLink(TodoRemoteLink? link) {
    if (link == null) {
      _db.execute('DELETE FROM meta WHERE key = ?', [_kRemoteLinkKey]);
    } else {
      _db.execute('INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)', [
        _kRemoteLinkKey,
        jsonEncode(link.toJson()),
      ]);
    }
  }

  /// The tasks deleted here and still owed a delete on the server.
  List<TodoTombstone> get tombstones => [
    for (final row in _db.select('SELECT href, etag FROM remote_tombstones'))
      if (row['href'] case final String href)
        (
          href: href,
          etag: row['etag'] is String ? row['etag'] as String : null,
        ),
  ];

  /// Adds [add] to [tombstones] and removes [remove] (by href), together.
  void recordTombstones({
    Iterable<TodoTombstone> add = const [],
    Iterable<String> remove = const [],
  }) {
    _transaction(() {
      for (final t in add) {
        _db.execute(
          'INSERT OR REPLACE INTO remote_tombstones(href, etag) VALUES (?, ?)',
          [t.href, t.etag],
        );
      }
      for (final href in remove) {
        _db.execute('DELETE FROM remote_tombstones WHERE href = ?', [href]);
      }
    });
  }

  /// Forgets every tombstone — the board is no longer linked.
  void clearTombstones() => _db.execute('DELETE FROM remote_tombstones');

  /// Whether an old `todo.json` has already been imported.
  bool get importedJson => _db.select('SELECT 1 FROM meta WHERE key = ?', [
    _kImportedJsonKey,
  ]).isNotEmpty;

  /// Imports [items] — an old `todo.json`, in board order — below whatever is
  /// already on the board, and records that it was done, in one transaction.
  void importJson(List<TodoItem> items, {required DateTime at}) {
    final updated = at.toUtc().toIso8601String();
    _transaction(() {
      final start =
          (_db
                  .select(
                    "SELECT COALESCE(MAX(position) + 1, 0) AS next FROM entries "
                    "WHERE kind = 'todo'",
                  )
                  .single['next']
              as int?) ??
          0;
      // An id already in the table keeps its row: the database is newer than
      // the file it was imported from.
      final insert = _db.prepare('$_kInsertTodo ON CONFLICT(id) DO NOTHING');
      try {
        for (var i = 0; i < items.length; i++) {
          insert.execute(_todoParameters(items[i], start + i, updated));
        }
      } finally {
        insert.close();
      }
      _db.execute('INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)', [
        _kImportedJsonKey,
        updated,
      ]);
    });
  }

  /// Replaces everything in the database with [items] (in board order) and
  /// [notes], in one transaction — a restore from a backup. Also records the
  /// old `todo.json` as imported: the backup is newer than any file left over
  /// from before the database.
  void replaceAll(
    List<TodoItem> items,
    List<NoteItem> notes, {
    required DateTime at,
  }) {
    final updated = at.toUtc().toIso8601String();
    _transaction(() {
      _db.execute('DELETE FROM entries');
      final insert = _db.prepare(_kUpsertTodo);
      try {
        for (var i = 0; i < items.length; i++) {
          insert.execute(_todoParameters(items[i], i, updated));
        }
      } finally {
        insert.close();
      }
      final note = _db.prepare(_kUpsertNote);
      try {
        for (final n in notes) {
          note.execute([
            n.id,
            n.title,
            n.body,
            n.created.toUtc().toIso8601String(),
            n.updated.toUtc().toIso8601String(),
          ]);
        }
      } finally {
        note.close();
      }
      _db.execute('INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)', [
        _kImportedJsonKey,
        updated,
      ]);
    });
  }

  /// What matches [query], best first: every whitespace-separated term has to
  /// appear somewhere in an entry's title or body, in any case. [kind] narrows
  /// it to cards or to notes.
  ///
  /// Terms of three characters or more go through the trigram index, ranked by
  /// `bm25` with a title hit worth ten body hits; shorter ones (which a
  /// trigram cannot hold) are a `LIKE` over the same rows — whose case folding
  /// is ASCII-only, which for a one- or two-letter term is the price of not
  /// scanning in Dart.
  List<SearchHit> search(String query, {EntryKind? kind, int limit = 500}) {
    final terms = searchTerms(query);
    if (terms.isEmpty) return const [];
    final long = [
      for (final t in terms)
        if (t.runes.length >= _kTrigram) t,
    ];
    final short = [
      for (final t in terms)
        if (t.runes.length < _kTrigram) t,
    ];
    final where = <String>[];
    final parameters = <Object?>[];
    if (long.isNotEmpty) {
      where.add('entries_fts MATCH ?');
      parameters.add(ftsQueryFor(long));
    }
    for (final term in short) {
      where.add(r"(e.title LIKE ? ESCAPE '\' OR e.body LIKE ? ESCAPE '\')");
      final pattern = likePatternFor(term);
      parameters
        ..add(pattern)
        ..add(pattern);
    }
    if (kind != null) {
      where.add('e.kind = ?');
      parameters.add(kind.wireName);
    }
    parameters.add(limit);
    final sql = long.isNotEmpty
        ? 'SELECT e.id, e.kind FROM entries_fts '
              'JOIN entries e ON e.seq = entries_fts.rowid '
              'WHERE ${where.join(' AND ')} '
              'ORDER BY bm25(entries_fts, 10.0, 1.0), e.kind, e.position '
              'LIMIT ?'
        : 'SELECT e.id, e.kind FROM entries e '
              'WHERE ${where.join(' AND ')} '
              'ORDER BY e.kind, e.position, e.updated DESC LIMIT ?';
    return [
      for (final row in _db.select(sql, parameters))
        if (EntryKind.fromWire(row['kind']) case final kind?)
          (id: row['id'] as String, kind: kind),
    ];
  }

  void close() => _db.close();
}

const String _kInsertTodo = '''
  INSERT INTO entries(
    id, kind, position, title, body, board_column,
    created, updated, due, recurrence, history, external, remote)
  VALUES (?, 'todo', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''';

const String _kUpsertTodo =
    '''
  $_kInsertTodo
  ON CONFLICT(id) DO UPDATE SET
    kind = 'todo',
    position = excluded.position,
    title = excluded.title,
    body = excluded.body,
    board_column = excluded.board_column,
    updated = excluded.updated,
    due = excluded.due,
    recurrence = excluded.recurrence,
    history = excluded.history,
    external = excluded.external,
    remote = excluded.remote''';

const String _kUpsertNote = '''
  INSERT INTO entries(id, kind, title, body, created, updated)
  VALUES (?, 'note', ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    kind = 'note',
    title = excluded.title,
    body = excluded.body,
    updated = excluded.updated''';

/// A card's row, spelled by [TodoItem.toJson] so the database and the old file
/// cannot disagree about how a date or a move is written.
List<Object?> _todoParameters(TodoItem item, int position, String updated) {
  final json = item.toJson();
  return [
    item.id,
    position,
    item.title,
    item.body,
    item.column.wireName,
    json['created'],
    updated,
    json['due'],
    item.recurrence == null ? null : jsonEncode(json['recurrence']),
    jsonEncode(json['history']),
    item.external == null ? null : jsonEncode(json['external']),
    item.remote == null ? null : jsonEncode(json['remote']),
  ];
}

/// Read back through [TodoItem.fromJson], so a damaged cell costs what it
/// would have cost in the old file: that field, or — with no id or no column —
/// that row.
TodoItem? _todoFromRow(Row row) => TodoItem.fromJson({
  'id': row['id'],
  'title': row['title'],
  'body': row['body'],
  'column': row['board_column'],
  'created': row['created'],
  'due': row['due'],
  'recurrence': _decodeJson(row['recurrence']),
  'history': _decodeJson(row['history']),
  'external': _decodeJson(row['external']),
  'remote': _decodeJson(row['remote']),
});

NoteItem? _noteFromRow(Row row) {
  final id = row['id'];
  if (id is! String || id.isEmpty) return null;
  final created = _parseMoment(row['created']);
  return NoteItem(
    id: id,
    title: row['title'] is String ? row['title'] as String : '',
    body: row['body'] is String ? row['body'] as String : '',
    created: created ?? DateTime.fromMillisecondsSinceEpoch(0),
    updated:
        _parseMoment(row['updated']) ??
        created ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

DateTime? _parseMoment(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

Object? _decodeJson(Object? value) {
  if (value is! String) return null;
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}
