import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:moonswing/notification_service.dart';
import 'package:moonswing/todo/todo_model.dart';

/// How long a burst of edits waits before the board is written. A drag is one
/// write; so is a flurry of moves across the board.
const Duration kTodoWriteDebounce = Duration(milliseconds: 300);

/// The todo board: every item, in board order, and the file it lives in.
///
/// The singleton-[ChangeNotifier] shape, because the bar button on every
/// monitor and the overlay are separate FlutterViews that all read it.
///
/// Four things a change here has to keep true:
///
///  * **User data, not configuration.** The board is in
///    `$XDG_DATA_HOME/moonswing/todo.json`, never `config.toml`: it is written
///    on every drag, and a config file is hand-edited and pasted into bug
///    reports. Written atomically (temp file, then rename), so a crash
///    mid-write leaves yesterday's board rather than half of today's.
///  * **A file it could not read is never written over.** A board that failed
///    to parse is shown as an error with a retry, and every edit is refused
///    until a read succeeds — the alternative is replacing somebody's list with
///    the empty one this store started from.
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
  /// widget test's fake clock never completes real I/O.
  @visibleForTesting
  factory TodoStore.forTesting({
    String? directory,
    DateTime Function()? now,
    List<TodoItem>? items,
  }) {
    final store = TodoStore._(
      directory: directory,
      now: now,
      autoTimers: false,
    );
    if (items != null) {
      store
        .._items = List.unmodifiable(items)
        .._loaded = true;
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
  bool _loaded = false;
  bool _loading = false;
  String? _loadError;
  String? _writeError;
  bool _started = false;
  Timer? _writeTimer;
  Timer? _midnight;
  Future<void> _writing = Future.value();
  int _idCounter = 0;

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

  String get path => '$directory/todo.json';

  /// Every item, in board order.
  List<TodoItem> get items => _items;

  /// Whether the file has been read — successfully or not. Until then the
  /// overlay shows a loader rather than an empty board it would be lying about.
  bool get loaded => _loaded;

  /// Why the board could not be read, or null. While set, edits are refused.
  String? get loadError => _loadError;

  /// Why the last write did not land, or null. The board on screen is still the
  /// user's; it is the file that is behind.
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

  /// Reads the board file. A missing file is an empty board; an unreadable one
  /// is [loadError], and the board on screen is left as it was.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      final file = File(path);
      if (!await file.exists()) {
        _items = const [];
      } else {
        _items = List.unmodifiable(decodeTodoFile(await file.readAsString()));
      }
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

  /// Reads the file again after a failure, and — if it now reads — runs the
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

  void _commit(List<TodoItem> next) {
    _items = List.unmodifiable(next);
    _armMidnight();
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

  /// Writes the board now. Writes are chained, so two flushes cannot race each
  /// other's rename.
  Future<void> flush() {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (!editable) return _writing;
    final contents = encodeTodoFile(_items);
    return _writing = _writing.then((_) => _write(contents));
  }

  Future<void> _write(String contents) async {
    String? error;
    try {
      await Directory(directory).create(recursive: true);
      final tmp = File('$path.tmp');
      await tmp.writeAsString(contents, flush: true);
      await tmp.rename(path);
      error = null;
    } catch (e) {
      error = 'Could not save $path: $e';
    }
    if (error == _writeError) return;
    _writeError = error;
    notifyListeners();
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
    _writeTimer?.cancel();
    _midnight?.cancel();
    super.dispose();
  }
}

/// Reads the board and runs the start of the day: today's recurring copies,
/// then the reminder of what is due. Not a `ShellService` — there is nothing a
/// panel waits on, and a board file that will not read is the overlay's to
/// say, not a start-up failure.
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
