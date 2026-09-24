import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:moonswing/notification_service.dart';
import 'package:moonswing/todo/todo_database.dart';
import 'package:moonswing/todo/todo_model.dart';

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
/// Five things a change here has to keep true:
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
///  * **Every move is recorded.** A change of column appends a [TodoMove] with
///    the wall-clock time; nothing else does, so reordering within a column is
///    not history.
class TodoStore extends ChangeNotifier {
  TodoStore._({
    String? directory,
    DateTime Function()? now,
    bool autoTimers = true,
  }) : _directory = directory,
       _now = now ?? DateTime.now,
       _autoTimers = autoTimers;

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

  /// Reads the board, makes today's recurring copies and posts the reminder.
  /// What `main()` calls once; later calls are no-ops.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await load();
    startOfDay();
  }

  /// Opens and reads the database, importing an old `todo.json` the first
  /// time. A missing database is an empty board; an unreadable one is
  /// [loadError], and the board on screen is left as it was.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      final db = _db ??= await _open();
      await _importLegacy(db);
      final board = db.readAll();
      _items = List.unmodifiable(board.todos);
      _notes = List.unmodifiable(board.notes);
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
    _armMidnight();
    notifyListeners();
  }

  Future<TodoDatabase> _open() async {
    await Directory(directory).create(recursive: true);
    return TodoDatabase.open(path);
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
  /// is synchronous, so the write has landed (or failed) when this returns.
  Future<void> flush() {
    _writeNow();
    return Future.value();
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

  @override
  void dispose() {
    // A pending edit is written rather than dropped.
    if (_writeTimer != null) _writeNow();
    _writeTimer?.cancel();
    _midnight?.cancel();
    _db?.close();
    _db = null;
    super.dispose();
  }
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
