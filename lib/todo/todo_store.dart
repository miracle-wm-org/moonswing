import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'package:moonswing/notification_service.dart';
import 'package:moonswing/todo/todo_backup.dart';
import 'package:moonswing/todo/todo_database.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_standup.dart';

/// How long a burst of edits waits before the board is written. A drag is one
/// write; so is a flurry of moves across the board.
const Duration kTodoWriteDebounce = Duration(milliseconds: 300);

/// The todo board — every item, in board order — and the notes kept beside
/// it, over the SQLite database they live in.
///
/// The singleton-[ChangeNotifier] shape, because the bar button on every
/// monitor and the overlay are separate FlutterViews that all read it. The
/// board is held in memory, because every surface reads it synchronously; the
/// database ([TodoDatabase]) is where it is kept and what [search] asks.
///
/// Six things a change here has to keep true:
///
///  * **User data, not configuration.** The board is in
///    `$XDG_DATA_HOME/moonswing/notes.db`, never `config.toml`: it is written
///    on every drag, and a config file is hand-edited and pasted into bug
///    reports. Each write is one transaction of only the rows that changed, so
///    a crash mid-write leaves the last board rather than half of this one. A
///    board saved as `todo.json` before the database is imported once and the
///    file renamed to `todo.json.imported`, never deleted.
///  * **A database it could not read is never written into.** A board that
///    failed to open or read — or an old `todo.json` that failed to parse — is
///    shown as an error with a retry, and every edit is refused until a read
///    succeeds; the alternative is replacing somebody's list with the empty one
///    this store started from.
///  * **A search sees the edit just made.** Writes are debounced, so [search]
///    writes anything pending before it asks the index.
///  * **The day turns over on a timer, and only when it matters.** Recurring
///    items make their copies and the reminder is posted at start-up and then
///    at each local midnight — but the midnight timer exists only while there
///    is a recurring or dated open item for it to act on, so a shell with no
///    board wakes for this never.
///  * **The database is never the only copy.** Every write that lands is
///    mirrored to [backupPath], a JSON file in a directory of its own (so it
///    can be a Git repository without the database in it). A database that is
///    missing is restored from that file; one that is *damaged* is renamed
///    aside — never deleted — and rebuilt from it. Nothing else is: a
///    database from a newer shell, or one the loader cannot open for want of
///    a library, is not damaged and is left alone. The file is written only
///    from a board that read cleanly, so a failed read never empties it.
///  * **Every move is recorded.** A change of column appends a [TodoMove] with
///    the wall-clock time; nothing else does, so reordering within a column is
///    not history.
class TodoStore extends ChangeNotifier {
  TodoStore._({
    String? directory,
    DateTime Function()? now,
    bool autoTimers = true,
    bool backups = true,
  }) : _directory = directory,
       _now = now ?? DateTime.now,
       _autoTimers = autoTimers,
       _backups = backups;

  static final TodoStore instance = TodoStore._()
    ..onReminder = postTodoReminder;

  /// A store over [directory] that a test drives by hand: no debounce timer and
  /// no midnight timer (a pending [Timer] fails the widget binding's end-of-test
  /// invariants), so call [flush] and [startOfDay] instead.
  ///
  /// [items] starts it already loaded with that board, and no file read — a
  /// widget test's fake clock never completes real I/O. [inMemory] puts it
  /// over an in-memory database (seeded with [items]) rather than none, for a
  /// test that searches through the real index; SQLite is synchronous, so that
  /// is fake-clock-safe too.
  @visibleForTesting
  factory TodoStore.forTesting({
    String? directory,
    DateTime Function()? now,
    List<TodoItem>? items,
    List<NoteItem>? notes,
    bool inMemory = false,
  }) {
    final store = TodoStore._(
      directory: directory,
      now: now,
      autoTimers: false,
      // Only over a directory the test owns: a store with none would mirror
      // its board into the real data directory.
      backups: directory != null,
    );
    if (items != null || notes != null) {
      store
        .._items = List.unmodifiable(items ?? const <TodoItem>[])
        .._notes = List.unmodifiable(notes ?? const <NoteItem>[])
        .._loaded = true;
    }
    if (inMemory) {
      store._db = TodoDatabase.openInMemory();
      store._writeNow();
    }
    return store;
  }

  final String? _directory;
  final DateTime Function() _now;
  final bool _autoTimers;
  final bool _backups;

  /// Called with the backup file's contents each time a backup write succeeds
  /// — after every write that lands, and once after the board is read. The
  /// backup servers
  /// (`todo_remote_backup.dart`) listen here.
  void Function(String contents)? onBackupWritten;

  /// Called with the reminder the start of each day produces. Injectable so a
  /// test never posts into the shell's notification list; the singleton wires
  /// [postTodoReminder].
  void Function(String summary, String body)? onReminder;

  List<TodoItem> _items = const [];
  List<NoteItem> _notes = const [];
  bool _loaded = false;
  bool _loading = false;
  String? _loadError;
  String? _writeError;
  bool _started = false;
  DateTime? _lastStandup;
  Timer? _writeTimer;
  Timer? _midnight;
  int _idCounter = 0;

  /// Null until the first [load] opens it, and again after a failed open, so
  /// [retry] reopens.
  TodoDatabase? _db;

  /// What the database holds, as of the last write that landed: the diff
  /// between these and the board is the next write.
  Map<String, TodoItem> _savedItems = const {};
  Map<String, int> _savedOrder = const {};
  Map<String, NoteItem> _savedNotes = const {};

  late final TodoBackupFile _backupFile = TodoBackupFile(backupPath);

  /// Backup writes, one after another: each waits for the last, so an older
  /// board can never land after a newer one.
  Future<void> _backupChain = Future.value();
  String? _backupError;
  DateTime? _backupSaved;
  String? _recoveryNotice;

  /// Set when the database was found damaged and could not be rebuilt — there
  /// was no backup to rebuild it from. [restore] may then set it aside.
  bool _damaged = false;

  /// The board file's directory. Resolved per call, so a test that sets
  /// `XDG_DATA_HOME` is not defeated by a value cached at start-up.
  String get directory {
    final override = _directory;
    if (override != null) return override;
    final env = Platform.environment;
    final data = env['XDG_DATA_HOME'];
    if (data != null && data.isNotEmpty) return '$data/moonswing';
    return '${env['HOME'] ?? '.'}/.local/share/moonswing';
  }

  /// The database.
  String get path => '$directory/notes.db';

  /// Where the board was kept before the database, read once to import it.
  String get legacyPath => '$directory/todo.json';

  /// The backup file, which every write that lands is mirrored to.
  String get backupPath =>
      '${todoBackupDirectory(directory)}/$kTodoBackupFileName';

  /// Why the last backup write failed, or null.
  String? get backupError => _backupError;

  /// When the backup file was last known to match the board, or null before
  /// the first write.
  DateTime? get backupSaved => _backupSaved;

  /// What happened to the database on the way in — rebuilt from the backup,
  /// or restored because it was missing — or null. Shown until dismissed,
  /// because a board that quietly came back from a backup is a board that may
  /// be missing the last few changes, and the user is the one who knows.
  String? get recoveryNotice => _recoveryNotice;

  void dismissRecoveryNotice() {
    if (_recoveryNotice == null) return;
    _recoveryNotice = null;
    notifyListeners();
  }

  /// The backup file's contents for the board as it stands, or null while the
  /// board is not [editable] — a board that did not read is never backed up,
  /// here or anywhere else.
  String? get backupContents =>
      editable ? encodeTodoBackup(_items, _notes) : null;

  /// Every item, in board order.
  List<TodoItem> get items => _items;

  /// Every note, most recently edited first.
  List<NoteItem> get notes => _notes;

  /// Whether the database has been read — successfully or not. Until then the
  /// overlay shows a loader rather than an empty board it would be lying about.
  bool get loaded => _loaded;

  /// Why the board could not be read, or null. While set, edits are refused.
  String? get loadError => _loadError;

  /// Why the last write did not land, or null. The board on screen is still the
  /// user's; it is the database that is behind.
  String? get writeError => _writeError;

  /// Whether edits are accepted: the file has been read, and read cleanly.
  bool get editable => _loaded && _loadError == null;

  DateTime get now => _now();

  /// The items in [column], top to bottom.
  List<TodoItem> itemsIn(TodoColumn column) => [
    for (final item in _items)
      if (item.column == column) item,
  ];

  TodoItem? item(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  NoteItem? note(String id) {
    for (final note in _notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  /// Open items due today or earlier — what the bar button counts.
  int get dueCount {
    final today = _now();
    return _items.where((i) => i.isDueBy(today)).length;
  }

  /// When the last standup summary was taken, or null before the first.
  DateTime? get lastStandup => _lastStandup;

  /// The standup summary of the board since [lastStandup] (see
  /// [standupReport]), and records now as the next one's starting point.
  /// Null while the board is not [editable]: a board that did not read has
  /// nothing true to report.
  ///
  /// The instant is kept in the database's `meta` table, so it survives a
  /// restart; a failure to write it costs only that, and the summary is still
  /// returned; only a restart would then count from the earlier summary.
  String? takeStandup() {
    if (!editable) return null;
    final now = _now();
    final report = standupReport(_items, since: _lastStandup, now: now);
    _lastStandup = now;
    try {
      _db?.recordStandup(now);
    } on SqliteException catch (e) {
      debugPrint('todo: could not record the standup time: ${e.message}');
    }
    return report;
  }

  /// Reads the board, makes today's recurring copies and posts the reminder.
  /// What `main()` calls once; later calls are no-ops.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await load();
    startOfDay();
  }

  /// Opens and reads the database, importing an old `todo.json` the first
  /// time. A missing database is restored from the backup file when there is
  /// one, and is otherwise an empty board; a damaged one is rebuilt from the
  /// backup file; any other failure is [loadError], and the board on screen is
  /// left as it was.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      var db = _db;
      if (db == null) {
        final existed = await File(path).exists();
        try {
          db = _db = await _open();
          _damaged = false;
          if (!existed) await _restoreMissing(db);
        } on TodoDatabaseDamaged catch (e) {
          db = _db = await _rebuild(e.message);
        }
      }
      await _importLegacy(db);
      ({List<TodoItem> todos, List<NoteItem> notes}) board;
      try {
        board = db.readAll();
      } on SqliteException catch (e) {
        if (!isDamage(e)) rethrow;
        db = _db = await _rebuild('$path is damaged: ${e.message}');
        board = db.readAll();
      }
      _items = List.unmodifiable(board.todos);
      _notes = List.unmodifiable(board.notes);
      _lastStandup = db.standupAt;
      _markSaved();
      _loadError = null;
    } on TodoFormatException catch (e) {
      _loadError = e.message;
    } catch (e) {
      _loadError = 'Could not read $path: $e';
    } finally {
      _loading = false;
      _loaded = true;
    }
    // Mirrors a board that read (and only one that did — this checks) to the
    // backup file: a first write, or none at all when the file matches.
    _queueBackup();
    _armMidnight();
    notifyListeners();
  }

  Future<TodoDatabase> _open() async {
    await Directory(directory).create(recursive: true);
    return TodoDatabase.open(path);
  }

  /// A database that was not there is filled from the backup file, if there
  /// is one with anything in it: the database was deleted, or this is a new
  /// machine with the backup put back from wherever the user keeps it.
  Future<void> _restoreMissing(TodoDatabase db) async {
    final ({TodoBackup backup, DateTime saved})? saved;
    try {
      saved = await _backupFile.read();
    } on TodoFormatException catch (e) {
      // Not a board: the database stays empty and the file is left as it is
      // until the first edit rewrites it — by which time the user has been
      // told.
      _recoveryNotice =
          '$path was missing, and the backup at $backupPath could not be '
          'read to restore it: ${e.message}';
      return;
    }
    if (saved == null || saved.backup.isEmpty) return;
    db.replaceAll(saved.backup.items, saved.backup.notes, at: _now());
    _recoveryNotice =
        '$path was missing, so the board was restored from the backup saved '
        '${_describeMoment(saved.saved)} (${saved.backup.summary}).';
  }

  /// Sets the damaged database aside and builds a new one from the backup
  /// file. Throws [TodoFormatException] — the board stays unreadable, and
  /// nothing is renamed — when there is no backup to build from.
  Future<TodoDatabase> _rebuild(String reason) async {
    _db?.close();
    _db = null;
    final ({TodoBackup backup, DateTime saved})? saved;
    try {
      saved = await _backupFile.read();
    } on TodoFormatException catch (e) {
      _damaged = true;
      throw TodoFormatException(
        '$reason\nThe backup at $backupPath could not be read either: '
        '${e.message}',
      );
    }
    if (saved == null) {
      _damaged = true;
      throw TodoFormatException(
        '$reason\nThere is no backup at $backupPath to rebuild it from.',
      );
    }
    final aside = await _setAside();
    final db = await _open();
    db.replaceAll(saved.backup.items, saved.backup.notes, at: _now());
    _damaged = false;
    _recoveryNotice =
        'The database could not be read ($reason). It was rebuilt from the '
        'backup saved ${_describeMoment(saved.saved)} '
        '(${saved.backup.summary}), and the damaged file was kept as $aside.';
    return db;
  }

  /// Renames the database — and its write-ahead log and shared memory, which
  /// belong to it — out of the way, and returns where it went. Never a delete:
  /// a damaged database may still hold something worth recovering by hand.
  Future<String> _setAside() async {
    final stamp = _now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final aside = '$path.damaged-$stamp';
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.rename('$aside$suffix');
    }
    return aside;
  }

  /// Replaces the whole board with [backup] — a restore from a backup server,
  /// or from the backup file after the user put an older one back.
  ///
  /// The board being replaced is saved first, beside the backup file, as
  /// `todo-before-restore-<time>.json`, and that path is returned (null when
  /// the board was empty). Works on a board that did not read only when the
  /// reason was damage: a database from a newer shell is not this one's to
  /// replace. Throws [TodoFormatException] when it cannot be done.
  Future<String?> restore(TodoBackup backup) async {
    if (!editable && !_damaged) {
      throw TodoFormatException(
        _loadError ?? 'The board has not been read yet.',
      );
    }
    _writeNow();
    String? kept;
    if (editable && (_items.isNotEmpty || _notes.isNotEmpty)) {
      final stamp = _now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      kept =
          '${todoBackupDirectory(directory)}/todo-before-restore-$stamp.json';
      try {
        await TodoBackupFile(kept).write(encodeTodoBackup(_items, _notes));
      } on FileSystemException catch (e) {
        throw TodoFormatException(
          'The board was not replaced, because a copy of it could not be '
          'saved first: ${e.message}',
        );
      }
    }
    var db = _db;
    if (db == null && _damaged) {
      try {
        await _setAside();
        db = _db = await _open();
      } on TodoFormatException {
        rethrow;
      } catch (e) {
        throw TodoFormatException('Could not make a new database: $e');
      }
    }
    try {
      // No database and not damaged is a test's store, held in memory only.
      db?.replaceAll(backup.items, backup.notes, at: _now());
    } catch (e) {
      throw TodoFormatException('Could not write the restored board: $e');
    }
    _damaged = false;
    _items = List.unmodifiable(backup.items);
    _notes = List.unmodifiable(backup.notes);
    _markSaved();
    _loadError = null;
    _writeError = null;
    _recoveryNotice = null;
    _loaded = true;
    _queueBackup();
    _armMidnight();
    notifyListeners();
    await _backupChain;
    return kept;
  }

  /// The backup file as it is on disk — for a restore from it, after the user
  /// has put back a copy they kept.
  Future<({TodoBackup backup, DateTime saved})?> readBackupFile() =>
      _backupFile.read();

  /// Mirrors the board to the backup file, after whatever backup write is
  /// already under way.
  void _queueBackup() {
    if (!_backups || !editable) return;
    final contents = encodeTodoBackup(_items, _notes);
    _backupChain = _backupChain.then((_) => _writeBackup(contents));
  }

  Future<void> _writeBackup(String contents) async {
    String? error;
    var wrote = false;
    try {
      wrote = await _backupFile.write(contents);
      if (wrote) {
        _backupSaved = _now();
      } else {
        _backupSaved ??= await _backupFile.lastModified();
      }
    } catch (e) {
      error = 'Could not write the backup to $backupPath: $e';
    }
    final changed = error != _backupError || wrote;
    _backupError = error;
    // Unchanged contents too: the first write after start-up is usually an
    // unchanged file, and a server that was not sent the last board before a
    // restart is still owed it. The listener compares digests itself.
    if (error == null) onBackupWritten?.call(contents);
    if (changed && !_disposed) notifyListeners();
  }

  /// Imports the board a shell from before the database saved as `todo.json`,
  /// once. The file is renamed rather than deleted, and the database records
  /// the import, so a file put back is not imported twice. One that will not
  /// parse throws, which refuses edits exactly as an unreadable board always
  /// has — an empty board with the old one sitting unread beside it is how the
  /// old one gets forgotten.
  Future<void> _importLegacy(TodoDatabase db) async {
    if (db.importedJson) return;
    final file = File(legacyPath);
    if (!await file.exists()) return;
    final items = decodeTodoFile(await file.readAsString());
    db.importJson(items, at: _now());
    try {
      await file.rename('$legacyPath.imported');
    } catch (_) {
      // Harmless: the import is recorded in the database either way.
    }
  }

  /// Reads the database again after a failure, and — if it now reads — runs the
  /// start of the day that failure skipped.
  Future<void> retry() async {
    final wasBroken = _loadError != null;
    await load();
    if (wasBroken && _loadError == null) startOfDay(remind: false);
    if (_writeError != null && editable) _scheduleWrite();
  }

  /// Makes any recurring copies owed today and, when [remind], posts what is due.
  ///
  /// Public for tests, which step [now] rather than waiting for midnight.
  @visibleForTesting
  void startOfDay({bool remind = true}) {
    if (!editable) return;
    final now = _now();
    final spawned = spawnRecurring(_items, now, _newId, now: now);
    if (spawned != null) {
      _items = List.unmodifiable(spawned);
      _scheduleWrite();
    }
    if (remind) {
      final reminder = dueReminder(_items, now);
      if (reminder != null) onReminder?.call(reminder.summary, reminder.body);
    }
    _armMidnight();
    // Also on a quiet day: the date moved, so the bar's due count may have.
    notifyListeners();
  }

  String _newId() {
    _idCounter++;
    return '${_now().microsecondsSinceEpoch.toRadixString(36)}'
        '-${_idCounter.toRadixString(36)}';
  }

  /// Creates an item at the top of [column] and returns its id, or null when
  /// the board is not [editable].
  String? add(
    TodoColumn column, {
    required String title,
    String body = '',
    DateTime? due,
    TodoRecurrence? recurrence,
  }) {
    if (!editable) return null;
    final now = _now();
    final item = TodoItem(
      id: _newId(),
      title: title,
      body: body,
      column: column,
      created: now,
      due: due == null ? null : dateOnly(due),
      recurrence: recurrence,
      history: [TodoMove(from: null, to: column, at: now)],
    );
    final next = [..._items];
    final firstInColumn = next.indexWhere((i) => i.column == column);
    next.insert(firstInColumn < 0 ? next.length : firstInColumn, item);
    _commit(next);
    return item.id;
  }

  /// Replaces the editable fields of [id]. A different [column] is a move, and
  /// is recorded as one.
  void update(
    String id, {
    required String title,
    required String body,
    required TodoColumn column,
    required DateTime? due,
    required TodoRecurrence? recurrence,
  }) {
    final current = item(id);
    if (!editable || current == null) return;
    final edited = current.copyWith(
      title: title,
      body: body,
      due: due == null ? null : dateOnly(due),
      recurrence: recurrence,
    );
    if (column == current.column) {
      _commit([for (final i in _items) i.id == id ? edited : i]);
      return;
    }
    // A column change from the editor lands at the top of its new column, the
    // way a new item does.
    _moveItem(edited, column, beforeId: _firstIdIn(column));
  }

  /// Moves [id] into [column], just above [beforeId] — or to the bottom of the
  /// column when that is null or not in it. A change of column is recorded
  /// with the time; a reorder within one is not.
  void move(String id, TodoColumn column, {String? beforeId}) {
    final current = item(id);
    if (!editable || current == null || beforeId == id) return;
    _moveItem(current, column, beforeId: beforeId);
  }

  void _moveItem(TodoItem current, TodoColumn column, {String? beforeId}) {
    final moved = column == current.column
        ? current
        : current.copyWith(
            column: column,
            history: [
              ...current.history,
              TodoMove(from: current.column, to: column, at: _now()),
            ],
          );
    final next = [
      for (final i in _items)
        if (i.id != current.id) i,
    ];
    var at = beforeId == null
        ? -1
        : next.indexWhere((i) => i.id == beforeId && i.column == column);
    if (at < 0) {
      // The bottom of the column: after its last item, or at the end.
      final last = next.lastIndexWhere((i) => i.column == column);
      at = last < 0 ? next.length : last + 1;
    }
    next.insert(at, moved);
    // A drop back where it started changes nothing and is not a write.
    if (listEquals(next, _items)) return;
    _commit(next);
  }

  String? _firstIdIn(TodoColumn column) {
    for (final i in _items) {
      if (i.column == column) return i.id;
    }
    return null;
  }

  void delete(String id) {
    if (!editable || item(id) == null) return;
    _commit([
      for (final i in _items)
        if (i.id != id) i,
    ]);
  }

  /// Creates a note and returns its id, or null when the store is not
  /// [editable]. Notes share the board's database and its search index, and
  /// have no column: they are text to be found again, not work to be done.
  String? addNote({String title = '', required String body}) {
    if (!editable) return null;
    final now = _now();
    final note = NoteItem(
      id: _newId(),
      title: title,
      body: body,
      created: now,
      updated: now,
    );
    _commitNotes([note, ..._notes]);
    return note.id;
  }

  /// Replaces a note's text; the note moves to the front, as the most
  /// recently edited. Unchanged text is not a write.
  void updateNote(String id, {required String title, required String body}) {
    final current = note(id);
    if (!editable || current == null) return;
    if (current.title == title && current.body == body) return;
    final edited = current.copyWith(title: title, body: body, updated: _now());
    _commitNotes([
      edited,
      for (final n in _notes)
        if (n.id != id) n,
    ]);
  }

  void deleteNote(String id) {
    if (!editable || note(id) == null) return;
    _commitNotes([
      for (final n in _notes)
        if (n.id != id) n,
    ]);
  }

  /// What matches [query] — cards and notes, or only [kind] — best first.
  ///
  /// Every whitespace-separated term has to appear somewhere in the title or
  /// body, in any case; see [TodoDatabase.search]. With no database to ask (a
  /// test's store, or one whose last write failed and so is behind the board)
  /// the same rule is applied to what is in memory, in board order.
  List<SearchHit> search(String query, {EntryKind? kind}) {
    final terms = searchTerms(query);
    if (terms.isEmpty) return const [];
    // Whatever is pending goes first — a diff, so with nothing pending it
    // costs a comparison and no write.
    _writeNow();
    final db = _db;
    if (db != null && editable && _writeError == null) {
      try {
        return db.search(query, kind: kind);
      } catch (_) {
        // The index is a way of asking, not the only one: fall through.
      }
    }
    return [
      if (kind != EntryKind.note)
        for (final i in _items)
          if (entryMatches(i.title, i.body, terms))
            (id: i.id, kind: EntryKind.todo),
      if (kind != EntryKind.todo)
        for (final n in _notes)
          if (entryMatches(n.title, n.body, terms))
            (id: n.id, kind: EntryKind.note),
    ];
  }

  void _commit(List<TodoItem> next) {
    _items = List.unmodifiable(next);
    _armMidnight();
    _scheduleWrite();
    notifyListeners();
  }

  void _commitNotes(List<NoteItem> next) {
    _notes = List.unmodifiable(next);
    _scheduleWrite();
    notifyListeners();
  }

  void _scheduleWrite() {
    if (!_autoTimers) return;
    _writeTimer?.cancel();
    _writeTimer = Timer(kTodoWriteDebounce, () {
      _writeTimer = null;
      unawaited(flush());
    });
  }

  /// Writes the board now. A `Future` for the callers that await it; SQLite
  /// is synchronous, so the database write has landed (or failed) when this
  /// is called, and the backup file's when it completes.
  Future<void> flush() {
    _writeNow();
    return _backupChain;
  }

  /// Writes what changed since the last write that landed, in one transaction.
  /// A write that fails leaves the saved snapshot where it was, so the next
  /// one carries this one's changes too.
  void _writeNow() {
    _writeTimer?.cancel();
    _writeTimer = null;
    final db = _db;
    if (!editable || db == null) return;
    String? error;
    final changes = _diff();
    if (!changes.isEmpty) {
      try {
        db.apply(changes, at: _now());
        _markSaved();
        _queueBackup();
      } catch (e) {
        error = 'Could not save $path: $e';
      }
    }
    if (error == _writeError) return;
    _writeError = error;
    notifyListeners();
  }

  TodoChanges _diff() {
    final todos = <({TodoItem item, int position})>[];
    final positions = <({String id, int position})>[];
    final notes = <NoteItem>[];
    final live = <String>{};
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      live.add(item.id);
      if (_savedItems[item.id] != item) {
        todos.add((item: item, position: i));
      } else if (_savedOrder[item.id] != i) {
        positions.add((id: item.id, position: i));
      }
    }
    for (final note in _notes) {
      live.add(note.id);
      if (_savedNotes[note.id] != note) notes.add(note);
    }
    return TodoChanges(
      todos: todos,
      positions: positions,
      notes: notes,
      deletes: [
        for (final id in _savedItems.keys)
          if (!live.contains(id)) id,
        for (final id in _savedNotes.keys)
          if (!live.contains(id)) id,
      ],
    );
  }

  void _markSaved() {
    _savedItems = {for (final i in _items) i.id: i};
    _savedOrder = {for (var i = 0; i < _items.length; i++) _items[i].id: i};
    _savedNotes = {for (final n in _notes) n.id: n};
  }

  /// One timer, to just past the next local midnight, and only while the
  /// board has something the date changes: a recurring item, or an open item
  /// with a due date.
  void _armMidnight() {
    final wanted =
        _autoTimers &&
        editable &&
        _items.any(
          (i) => i.recurrence != null || (i.column.isOpen && i.due != null),
        );
    if (!wanted) {
      _midnight?.cancel();
      _midnight = null;
      return;
    }
    if (_midnight != null) return;
    final now = _now();
    // A second past midnight, measured as a calendar step rather than
    // `Duration(days: 1)` so a daylight-saving night still lands on it.
    final wake = addDays(dateOnly(now), 1).add(const Duration(seconds: 1));
    _midnight = Timer(wake.difference(now), () {
      _midnight = null;
      startOfDay();
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    // A pending edit is written rather than dropped.
    if (_writeTimer != null) _writeNow();
    _writeTimer?.cancel();
    _midnight?.cancel();
    _db?.close();
    _db = null;
    super.dispose();
  }
}

/// "at 14:05 on 2026-09-24", for the recovery notice.
String _describeMoment(DateTime moment) {
  final local = moment.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'at ${two(local.hour)}:${two(local.minute)} on ${formatDate(local)}';
}

/// Reads the board and runs the start of the day: today's recurring copies,
/// then the reminder of what is due. Not a `ShellService` — there is nothing a
/// panel waits on, and a board that will not read is the overlay's to say, not
/// a start-up failure.
void startTodoService() => unawaited(TodoStore.instance.start());

/// Posts the start-of-day reminder to the shell's own notification list.
///
/// The shell is the session's notification daemon, so this is a store write
/// rather than a D-Bus round trip to itself. No timeout: it is posted once a
/// day, often before anybody is looking, and has to still be there when they
/// are.
void postTodoReminder(String summary, String body) {
  final store = NotificationStore.instance;
  store.addOrReplace(
    NotificationItem(
      id: store.allocateId(),
      appName: 'Todo',
      summary: summary,
      body: body,
      actions: const [],
      expireTimeout: 0,
      arrivedAt: DateTime.now(),
    ),
  );
}
