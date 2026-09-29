// The todo board's data, and the arithmetic behind it.
//
// Flutter-free and I/O-free, for `test/todo_model_test.dart`: the recurrence
// rule, the due-today reminder and the file format are the parts that can be
// wrong on a date the test suite does not happen to run on, so they are plain
// functions of a `today` the caller passes in.

import 'dart:convert';

/// The board's five columns, left to right.
///
/// The order *is* the board: [TodoColumn.values] is what the overlay lays out,
/// so a new column goes where it should appear.
enum TodoColumn {
  inbox('inbox', 'Inbox'),
  todo('todo', 'Todo'),
  inProgress('in_progress', 'In Progress'),
  finished('finished', 'Finished'),
  abandoned('abandoned', 'Abandoned');

  const TodoColumn(this.wireName, this.label);

  /// How the column is spelled in `todo.json`. Never [name], which is a Dart
  /// identifier and would make renaming a member a file-format change.
  final String wireName;

  final String label;

  /// Whether an item here is still somebody's to do. A finished or abandoned
  /// item is past due by definition and is never a reason to remind anyone.
  bool get isOpen => this != finished && this != abandoned;

  static TodoColumn? fromWire(Object? value) {
    for (final column in values) {
      if (column.wireName == value) return column;
    }
    return null;
  }
}

/// The unit a recurrence counts in.
enum RecurrenceUnit {
  days('days', 'days', 'day'),
  weeks('weeks', 'weeks', 'week'),
  months('months', 'months', 'month');

  const RecurrenceUnit(this.wireName, this.plural, this.singular);

  final String wireName;
  final String plural;
  final String singular;

  static RecurrenceUnit? fromWire(Object? value) {
    for (final unit in values) {
      if (unit.wireName == value) return unit;
    }
    return null;
  }
}

/// The longest interval a recurrence may name, in any unit. Past this the
/// arithmetic is still right but the rule is almost certainly a typo.
const int kMaxRecurrenceInterval = 999;

/// A calendar day, with the time of day thrown away.
///
/// Every date on the board — a due date, a recurrence's start — is a *day*, and
/// comparing two `DateTime`s that disagree about the hour is how "due today"
/// stops being true at noon. Built with the local constructor, so the day is the
/// user's day and not UTC's.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// `2026-09-24`: how a day is written in the file and read from the editor.
String formatDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Reads [formatDate]'s spelling back, or null.
///
/// Strict on purpose: `DateTime.tryParse` accepts `2026-02-30` and quietly
/// answers the second of March, which in a due-date field is a different day
/// from the one the user typed.
DateTime? parseDate(String text) {
  final match = RegExp(r'^\s*(\d{4})-(\d{1,2})-(\d{1,2})\s*$').firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1) return null;
  if (day > _daysInMonth(year, month)) return null;
  return DateTime(year, month, day);
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// [day] plus [count] calendar days.
///
/// Not `add(Duration(days:))`: a day across a daylight-saving change is 23 or
/// 25 hours long, and adding 24 of them lands on the wrong date at midnight.
DateTime addDays(DateTime day, int count) =>
    DateTime(day.year, day.month, day.day + count);

/// [day] plus [count] months, with the day of the month clamped to the length
/// of the month it lands in — the 31st of January plus one month is the 28th
/// (or 29th) of February, never the 3rd of March.
DateTime addMonths(DateTime day, int count) {
  final monthIndex = day.month - 1 + count;
  final year =
      day.year + (monthIndex >= 0 ? monthIndex ~/ 12 : (monthIndex - 11) ~/ 12);
  final month = monthIndex % 12 + 1;
  final clamped = day.day.clamp(1, _daysInMonth(year, month));
  return DateTime(year, month, clamped);
}

/// "Every [every] [unit], starting [start]": when a recurring item makes a
/// fresh copy of itself.
///
/// The occurrences are counted from [start] rather than stepped from the last
/// one, and that is what keeps a monthly rule honest: stepping would take the
/// 31st to the 28th in February and then keep it on the 28th for good, while
/// counting puts the March one back on the 31st.
///
/// [since] is the last day a copy was made for (or the day the rule was set),
/// and the next copy is the first occurrence *after* it. A shell that was off
/// for a fortnight makes one copy when it comes back, not fourteen — a list of
/// stale duplicates is a chore, and the most recent one is the one that is
/// still owed.
class TodoRecurrence {
  const TodoRecurrence({
    required this.every,
    required this.unit,
    required this.start,
    required this.since,
  });

  /// At least 1.
  final int every;
  final RecurrenceUnit unit;

  /// The first scheduled day. A day, see [dateOnly].
  final DateTime start;

  /// The day the most recent copy was made for, or the rule was last set.
  final DateTime since;

  /// The [index]th scheduled day, counting [start] as the 0th.
  DateTime occurrence(int index) => switch (unit) {
    RecurrenceUnit.days => addDays(start, index * every),
    RecurrenceUnit.weeks => addDays(start, index * every * 7),
    RecurrenceUnit.months => addMonths(start, index * every),
  };

  /// The index of the first scheduled day strictly after [after].
  int _firstIndexAfter(DateTime after) {
    final day = dateOnly(after);
    if (start.isAfter(day)) return 0;
    // Estimated rather than walked, so a daily rule set years ago is not a loop
    // of a thousand iterations; then corrected by the few steps the estimate
    // can be off by (months are not all the same length).
    final span = day.difference(start).inDays;
    final stepDays = switch (unit) {
      RecurrenceUnit.days => every,
      RecurrenceUnit.weeks => every * 7,
      RecurrenceUnit.months => every * 31,
    };
    var index = span ~/ stepDays;
    while (index > 0 && occurrence(index - 1).isAfter(day)) {
      index--;
    }
    while (!occurrence(index).isAfter(day)) {
      index++;
    }
    return index;
  }

  /// The first scheduled day strictly after [after].
  DateTime nextAfter(DateTime after) => occurrence(_firstIndexAfter(after));

  /// The next day a copy will be made on.
  DateTime get next => nextAfter(since);

  /// The latest scheduled day on or before [today], if one is owed a copy —
  /// that is, if it falls after [since]. Null when nothing is due yet.
  DateTime? owedOn(DateTime today) {
    final index = _firstIndexAfter(today);
    if (index == 0) return null;
    final latest = occurrence(index - 1);
    return latest.isAfter(dateOnly(since)) ? latest : null;
  }

  TodoRecurrence copyWith({DateTime? since}) => TodoRecurrence(
    every: every,
    unit: unit,
    start: start,
    since: since ?? this.since,
  );

  /// "Every 2 weeks", "Every day".
  String describe() =>
      every == 1 ? 'Every ${unit.singular}' : 'Every $every ${unit.plural}';

  Map<String, Object?> toJson() => {
    'every': every,
    'unit': unit.wireName,
    'start': formatDate(start),
    'since': formatDate(since),
  };

  /// Null for anything that does not describe a rule — which costs the item its
  /// recurrence, never the item.
  static TodoRecurrence? fromJson(Object? json) {
    if (json is! Map) return null;
    final every = json['every'];
    final unit = RecurrenceUnit.fromWire(json['unit']);
    final start = json['start'] is String ? parseDate(json['start']) : null;
    if (every is! int || every < 1 || unit == null || start == null) {
      return null;
    }
    final since = json['since'] is String ? parseDate(json['since']) : null;
    return TodoRecurrence(
      every: every.clamp(1, kMaxRecurrenceInterval),
      unit: unit,
      start: start,
      // A rule with no record of its last copy is treated as set the day before
      // it starts, so its first scheduled day is still owed one.
      since: since ?? addDays(start, -1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TodoRecurrence &&
      other.every == every &&
      other.unit == unit &&
      other.start == start &&
      other.since == since;

  @override
  int get hashCode => Object.hash(every, unit, start, since);
}

/// One entry in an item's history: it arrived in [to] at [at].
///
/// [from] is null for the entry that records the item being created.
class TodoMove {
  const TodoMove({required this.from, required this.to, required this.at});

  final TodoColumn? from;
  final TodoColumn to;

  /// Local wall-clock time. Written to the file in UTC, so a move recorded
  /// before a time-zone change still reads as the instant it happened.
  final DateTime at;

  Map<String, Object?> toJson() => {
    if (from != null) 'from': from!.wireName,
    'to': to.wireName,
    'at': at.toUtc().toIso8601String(),
  };

  static TodoMove? fromJson(Object? json) {
    if (json is! Map) return null;
    final to = TodoColumn.fromWire(json['to']);
    final at = json['at'] is String ? DateTime.tryParse(json['at']) : null;
    if (to == null || at == null) return null;
    return TodoMove(
      from: TodoColumn.fromWire(json['from']),
      to: to,
      at: at.toLocal(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TodoMove &&
      other.from == from &&
      other.to == to &&
      other.at == at;

  @override
  int get hashCode => Object.hash(from, to, at);
}

/// Where a card came from, when it came from somewhere other than the user: a
/// calendar event the Google sync keeps on the board.
///
/// It records what the sync last wrote — the title, the times, the links — so
/// the next sync can tell a field the user has edited from one it wrote itself
/// and leave the user's edit alone. [manual] is set the first time the user
/// moves the card between columns. From then on the column is the user's and
/// the sync stops moving it. [calendar] and [color] say where the card came
/// from, so the board can draw it in its calendar's colour; they are not the
/// user's to edit, so every sync rewrites them.
class TodoExternal {
  const TodoExternal({
    required this.source,
    required this.key,
    required this.title,
    required this.start,
    required this.end,
    this.link,
    this.url,
    this.calendar,
    this.color,
    this.manual = false,
  });

  /// [source] for a Google Calendar event.
  static const String googleCalendar = 'gcal';

  /// Which sync owns the card, e.g. [googleCalendar].
  final String source;

  /// The event's identity within [source]: `<calendar id>/<event id>`.
  final String key;

  /// The title the sync last wrote.
  final String title;

  /// Local wall-clock times.
  final DateTime start;
  final DateTime end;

  /// Where to join it (a Meet or Zoom link), if anywhere.
  final String? link;

  /// The event's own page.
  final String? url;

  /// The name of the calendar the event is on, if known.
  final String? calendar;

  /// `#rrggbb` the calendar draws the event in, if known.
  final String? color;

  /// The user has moved the card, so the sync no longer does.
  final bool manual;

  static const Object _keep = Object();

  TodoExternal copyWith({
    String? key,
    String? title,
    DateTime? start,
    DateTime? end,
    Object? link = _keep,
    Object? url = _keep,
    Object? calendar = _keep,
    Object? color = _keep,
    bool? manual,
  }) => TodoExternal(
    source: source,
    key: key ?? this.key,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
    link: identical(link, _keep) ? this.link : link as String?,
    url: identical(url, _keep) ? this.url : url as String?,
    calendar: identical(calendar, _keep) ? this.calendar : calendar as String?,
    color: identical(color, _keep) ? this.color : color as String?,
    manual: manual ?? this.manual,
  );

  Map<String, Object?> toJson() => {
    'source': source,
    'key': key,
    'title': title,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    if (link != null) 'link': link,
    if (url != null) 'url': url,
    if (calendar != null) 'calendar': calendar,
    if (color != null) 'color': color,
    if (manual) 'manual': true,
  };

  /// Null for a record missing its source, key or times. The card itself is
  /// kept; it simply stops being synced.
  static TodoExternal? fromJson(Object? json) {
    if (json is! Map) return null;
    final source = json['source'];
    final key = json['key'];
    final start = json['start'] is String
        ? DateTime.tryParse(json['start'] as String)?.toLocal()
        : null;
    final end = json['end'] is String
        ? DateTime.tryParse(json['end'] as String)?.toLocal()
        : null;
    if (source is! String ||
        source.isEmpty ||
        key is! String ||
        key.isEmpty ||
        start == null ||
        end == null) {
      return null;
    }
    String? text(String name) =>
        json[name] is String && (json[name] as String).isNotEmpty
        ? json[name] as String
        : null;
    return TodoExternal(
      source: source,
      key: key,
      title: text('title') ?? '',
      start: start,
      end: end,
      link: text('link'),
      url: text('url'),
      calendar: text('calendar'),
      color: text('color'),
      manual: json['manual'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TodoExternal &&
      other.source == source &&
      other.key == key &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.link == link &&
      other.url == url &&
      other.calendar == calendar &&
      other.color == color &&
      other.manual == manual;

  @override
  int get hashCode => Object.hash(
    source,
    key,
    title,
    start,
    end,
    link,
    url,
    calendar,
    color,
    manual,
  );
}

/// One card on the board.
class TodoItem {
  const TodoItem({
    required this.id,
    required this.title,
    required this.body,
    required this.column,
    required this.created,
    this.due,
    this.recurrence,
    this.history = const [],
    this.external,
  });

  /// Stable for the life of the item, and unique within the file.
  final String id;
  final String title;
  final String body;
  final TodoColumn column;

  /// When the item was made. Local wall-clock time.
  final DateTime created;

  /// The day it is due, if any. A day, see [dateOnly].
  final DateTime? due;

  /// The rule this item makes copies of itself by, if any.
  final TodoRecurrence? recurrence;

  /// Every column the item has been in, oldest first, starting with the one it
  /// was created in.
  final List<TodoMove> history;

  /// The calendar event this card mirrors, if it is one. See [TodoExternal].
  final TodoExternal? external;

  /// When it arrived in the column it is in now.
  DateTime get movedAt => history.isEmpty ? created : history.last.at;

  /// Whether it is still open and due on or before [today].
  bool isDueBy(DateTime today) {
    final day = due;
    return column.isOpen && day != null && !day.isAfter(dateOnly(today));
  }

  /// Sentinel for [copyWith], so a nullable field can be cleared by passing
  /// null rather than meaning "leave it alone".
  static const Object _keep = Object();

  TodoItem copyWith({
    String? title,
    String? body,
    TodoColumn? column,
    Object? due = _keep,
    Object? recurrence = _keep,
    List<TodoMove>? history,
    Object? external = _keep,
  }) => TodoItem(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    column: column ?? this.column,
    created: created,
    due: identical(due, _keep) ? this.due : due as DateTime?,
    recurrence: identical(recurrence, _keep)
        ? this.recurrence
        : recurrence as TodoRecurrence?,
    history: history ?? this.history,
    external: identical(external, _keep)
        ? this.external
        : external as TodoExternal?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (body.isNotEmpty) 'body': body,
    'column': column.wireName,
    'created': created.toUtc().toIso8601String(),
    if (due != null) 'due': formatDate(due!),
    if (recurrence != null) 'recurrence': recurrence!.toJson(),
    'history': [for (final move in history) move.toJson()],
    if (external != null) 'external': external!.toJson(),
  };

  /// Null for a row that cannot be an item at all: no id, or a column the board
  /// does not have. Anything less than that costs the one field.
  static TodoItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final column = TodoColumn.fromWire(json['column']);
    if (id is! String || id.isEmpty || column == null) return null;
    final created = json['created'] is String
        ? DateTime.tryParse(json['created'])?.toLocal()
        : null;
    final history = <TodoMove>[
      if (json['history'] case final List<Object?> moves)
        for (final move in moves) ?TodoMove.fromJson(move),
    ];
    return TodoItem(
      id: id,
      title: json['title'] is String ? json['title'] as String : '',
      body: json['body'] is String ? json['body'] as String : '',
      column: column,
      created:
          created ??
          (history.isNotEmpty
              ? history.first.at
              : DateTime.fromMillisecondsSinceEpoch(0)),
      due: json['due'] is String ? parseDate(json['due'] as String) : null,
      recurrence: TodoRecurrence.fromJson(json['recurrence']),
      history: history,
      external: TodoExternal.fromJson(json['external']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TodoItem &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.column == column &&
      other.created == created &&
      other.due == due &&
      other.recurrence == recurrence &&
      _listEquals(other.history, history) &&
      other.external == external;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    body,
    column,
    created,
    due,
    recurrence,
    Object.hashAll(history),
    external,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What a row in the store is: a card on the board, or a free-standing note.
///
/// Both live in the one table and the one search index, so a search from
/// anywhere finds either; only a [todo] has a column, a due date or a history.
enum EntryKind {
  todo('todo'),
  note('note');

  const EntryKind(this.wireName);

  /// How the kind is spelled in the database. Never [name], for
  /// [TodoColumn.wireName]'s reason.
  final String wireName;

  static EntryKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

/// A raw note: text to be found again later, with no column and no date.
class NoteItem {
  const NoteItem({
    required this.id,
    required this.title,
    required this.body,
    required this.created,
    required this.updated,
  });

  /// Unique across notes *and* todos — they share the store's id space.
  final String id;
  final String title;
  final String body;

  /// Local wall-clock times.
  final DateTime created;
  final DateTime updated;

  NoteItem copyWith({String? title, String? body, DateTime? updated}) =>
      NoteItem(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        created: created,
        updated: updated ?? this.updated,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    if (title.isNotEmpty) 'title': title,
    'body': body,
    'created': created.toUtc().toIso8601String(),
    'updated': updated.toUtc().toIso8601String(),
  };

  /// Null for a row with no id; anything less costs the one field, as
  /// [TodoItem.fromJson] does.
  static NoteItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    DateTime? moment(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toLocal() : null;
    final created =
        moment(json['created']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return NoteItem(
      id: id,
      title: json['title'] is String ? json['title'] as String : '',
      body: json['body'] is String ? json['body'] as String : '',
      created: created,
      updated: moment(json['updated']) ?? created,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoteItem &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.created == created &&
      other.updated == updated;

  @override
  int get hashCode => Object.hash(id, title, body, created, updated);
}

/// One thing a search found.
typedef SearchHit = ({String id, EntryKind kind});

/// The words of a search [query]: split on whitespace, blanks dropped.
///
/// Every term has to appear, anywhere and in any case, in an entry's title or
/// body — the rule both the database's index and [entryMatches] apply, so the
/// highlight on a card never disagrees with the reason it was shown.
List<String> searchTerms(String query) => [
  for (final term in query.trim().split(RegExp(r'\s+')))
    if (term.isNotEmpty) term,
];

/// Whether every one of [terms] appears in [title] or [body], ignoring case.
bool entryMatches(String title, String body, List<String> terms) {
  final haystack = '${title.toLowerCase()}\n${body.toLowerCase()}';
  return terms.every((term) => haystack.contains(term.toLowerCase()));
}

/// The JSON file format's version — the board's format before it moved to
/// SQLite (see `todo_database.dart`), now read once to import an old board.
/// Checked only to refuse a *newer* file.
const int kTodoFileVersion = 1;

/// Why the board — the old file, or the database — could not be read.
class TodoFormatException implements Exception {
  const TodoFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `todo.json`'s contents, in board order.
String encodeTodoFile(List<TodoItem> items) =>
    const JsonEncoder.withIndent('  ').convert({
      'version': kTodoFileVersion,
      'items': [for (final item in items) item.toJson()],
    });

/// The items in [source], in board order.
///
/// A row that is not an item costs that row; a duplicate id costs the later
/// copy. Only a file that is not a board at all throws — and the store then
/// refuses to write over it, because the alternative is replacing somebody's
/// list with an empty one.
List<TodoItem> decodeTodoFile(String source) {
  final Object? json;
  try {
    json = jsonDecode(source);
  } on FormatException catch (e) {
    throw TodoFormatException('todo.json is not valid JSON: ${e.message}');
  }
  if (json is! Map) {
    throw const TodoFormatException('todo.json does not hold a board.');
  }
  final version = json['version'];
  if (version is int && version > kTodoFileVersion) {
    throw TodoFormatException(
      'todo.json was written by a newer version of the shell (format '
      '$version).',
    );
  }
  final rows = json['items'];
  if (rows is! List) return const [];
  final seen = <String>{};
  return [
    for (final row in rows)
      if (TodoItem.fromJson(row) case final item? when seen.add(item.id)) item,
  ];
}

/// Makes a copy of every recurring item that is owed one on [today].
///
/// Returns the new board, or null when nothing was owed. The copy lands in
/// [TodoColumn.todo], due on the day it was scheduled for, and *takes the rule
/// with it*: the newest copy is the one that carries the recurrence, so editing
/// or deleting it is how a repeating item is changed or stopped, and an old copy
/// left in Finished cannot keep spawning. [newId] mints an id per copy.
List<TodoItem>? spawnRecurring(
  List<TodoItem> items,
  DateTime today,
  String Function() newId, {
  required DateTime now,
}) {
  final result = <TodoItem>[];
  final copies = <TodoItem>[];
  var changed = false;
  for (final item in items) {
    final rule = item.recurrence;
    final owed = rule?.owedOn(today);
    if (rule == null || owed == null) {
      result.add(item);
      continue;
    }
    changed = true;
    result.add(item.copyWith(recurrence: null));
    copies.add(
      TodoItem(
        id: newId(),
        title: item.title,
        body: item.body,
        column: TodoColumn.todo,
        created: now,
        due: owed,
        recurrence: rule.copyWith(since: owed),
        history: [TodoMove(from: null, to: TodoColumn.todo, at: now)],
      ),
    );
  }
  if (!changed) return null;
  // Copies go to the top of Todo, where a list of today's things is read from.
  final firstTodo = result.indexWhere((i) => i.column == TodoColumn.todo);
  result.insertAll(firstTodo < 0 ? result.length : firstTodo, copies);
  return result;
}

/// What the start-of-day reminder says, or null when there is nothing to say.
///
/// Items due on [today] are the point; anything still open from an earlier day
/// is mentioned after them, because a reminder that stays silent about what was
/// missed yesterday is how it gets missed again.
({String summary, String body})? dueReminder(
  List<TodoItem> items,
  DateTime today,
) {
  final day = dateOnly(today);
  final dueToday = [
    for (final item in items)
      if (item.column.isOpen && item.due == day) item,
  ];
  final overdue = [
    for (final item in items)
      if (item.column.isOpen && item.due != null && item.due!.isBefore(day))
        item,
  ];
  if (dueToday.isEmpty && overdue.isEmpty) return null;
  String titleOf(TodoItem item) =>
      item.title.trim().isEmpty ? 'Untitled' : item.title.trim();
  final lines = <String>[
    for (final item in dueToday) '• ${titleOf(item)}',
    if (overdue.isNotEmpty) ...[
      if (dueToday.isNotEmpty) '',
      'Overdue:',
      for (final item in overdue)
        '• ${titleOf(item)} (${formatDate(item.due!)})',
    ],
  ];
  final summary = dueToday.isEmpty
      ? (overdue.length == 1
            ? '1 todo is overdue'
            : '${overdue.length} todos are overdue')
      : (dueToday.length == 1
            ? 'Due today: ${titleOf(dueToday.single)}'
            : '${dueToday.length} todos are due today');
  return (summary: summary, body: lines.join('\n'));
}
