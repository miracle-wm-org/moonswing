// A card on the board as a task on a CalDAV task list (an iCalendar `VTODO`),
// and back — and the three-way merge that reconciles the two when both sides
// changed.
//
// What a task list can hold of a card is [TodoTaskFields]: the title, the
// notes, the column, the due day and a simple repeat. Everything else about a
// card stays on this machine — its move history, its place in the column —
// and everything else about a task stays on the server: an outgoing write
// patches only the properties of the fields that changed into the task as the
// server last had it (see [writeTask]), so an alarm, categories, a
// `BYDAY` repeat the board cannot show, or another app's own properties go
// back exactly as they came.
//
// The columns are the task's `STATUS`: NEEDS-ACTION is Todo, IN-PROCESS is In
// Progress, COMPLETED is Finished and CANCELLED is Abandoned. The Inbox has no
// status of its own, so an Inbox card is NEEDS-ACTION with
// `X-MOONSWING-COLUMN:inbox`, which other clients keep and ignore.
//
// Flutter-free and I/O-free, for `test/todo_caldav_map_test.dart`.

import 'package:moonswing/caldav/ical.dart';
import 'package:moonswing/todo/todo_model.dart';

/// The shell's `PRODID`.
const String kTodoProdId = '-//Moonswing//Todo board//EN';

/// The property that keeps a card in the Inbox rather than Todo.
const String kColumnProperty = 'X-MOONSWING-COLUMN';

/// A repeat a task list and the board can both say: every [every] [unit]s
/// from [start]. The card's own `since` is bookkeeping, not the rule.
typedef TaskRule = ({int every, RecurrenceUnit unit, DateTime start});

/// What a task list holds of a card.
class TodoTaskFields {
  const TodoTaskFields({
    required this.title,
    required this.body,
    required this.column,
    this.due,
    this.rule,
  });

  final String title;
  final String body;
  final TodoColumn column;

  /// A day.
  final DateTime? due;
  final TaskRule? rule;

  TodoTaskFields copyWith({
    String? title,
    String? body,
    TodoColumn? column,
    Object? due = _keep,
    Object? rule = _keep,
  }) => TodoTaskFields(
    title: title ?? this.title,
    body: body ?? this.body,
    column: column ?? this.column,
    due: identical(due, _keep) ? this.due : due as DateTime?,
    rule: identical(rule, _keep) ? this.rule : rule as TaskRule?,
  );

  static const Object _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is TodoTaskFields &&
      other.title == title &&
      other.body == body &&
      other.column == column &&
      other.due == due &&
      other.rule == rule;

  @override
  int get hashCode => Object.hash(title, body, column, due, rule);

  @override
  String toString() =>
      'TodoTaskFields($title, $column, due: $due, rule: $rule)';
}

String _oneLineEnd(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

TaskRule? _ruleOf(TodoRecurrence? r) =>
    r == null ? null : (every: r.every, unit: r.unit, start: r.start);

/// What [card] would put on a task list. Line ends are the one thing
/// normalised, because a TEXT value has only the one.
TodoTaskFields fieldsOfCard(TodoItem card) => TodoTaskFields(
  title: _oneLineEnd(card.title),
  body: _oneLineEnd(card.body),
  column: card.column,
  due: card.due,
  rule: _ruleOf(card.recurrence),
);

/// The task in [calendar]: its first `VTODO` that is not an override of one
/// occurrence (`RECURRENCE-ID`), or null when there is none.
ICalComponent? masterTodo(ICalComponent? calendar) {
  if (calendar == null) return null;
  for (final c in calendar.childrenNamed('VTODO')) {
    if (c.property('RECURRENCE-ID') == null) return c;
  }
  return null;
}

/// [vtodo] as the board would show it.
TodoTaskFields fieldsOfTask(ICalComponent vtodo) {
  final status = vtodo.property('STATUS')?.value.trim().toUpperCase();
  final percent = int.tryParse(
    vtodo.property('PERCENT-COMPLETE')?.value.trim() ?? '',
  );
  final column = switch (status) {
    'COMPLETED' => TodoColumn.finished,
    'CANCELLED' => TodoColumn.abandoned,
    'IN-PROCESS' => TodoColumn.inProgress,
    'NEEDS-ACTION' => _openColumn(vtodo),
    // No status at all: a completion time or a full percentage still says it.
    _ when vtodo.property('COMPLETED') != null || percent == 100 =>
      TodoColumn.finished,
    _ => _openColumn(vtodo),
  };
  final due = parseICalDateTime(vtodo.property('DUE'))?.localDay;
  return TodoTaskFields(
    title: vtodo.text('SUMMARY') ?? '',
    body: vtodo.text('DESCRIPTION') ?? '',
    column: column,
    due: due,
    rule: parseTaskRule(
      vtodo.property('RRULE')?.value,
      start: parseICalDateTime(vtodo.property('DTSTART'))?.localDay ?? due,
    ),
  );
}

TodoColumn _openColumn(ICalComponent vtodo) =>
    vtodo.property(kColumnProperty)?.value.trim().toLowerCase() == 'inbox'
    ? TodoColumn.inbox
    : TodoColumn.todo;

/// [rrule] as a [TaskRule], or null when there is none, or it says more than
/// "every N days, weeks, months or years" — a `BYDAY`, a `COUNT`, an `UNTIL` —
/// which the board cannot show. The rule is then left on the server as it is,
/// and the card simply does not repeat here.
TaskRule? parseTaskRule(String? rrule, {required DateTime? start}) {
  if (rrule == null || start == null) return null;
  String? freq;
  var interval = 1;
  for (final part in rrule.trim().split(';')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    if (eq < 0) return null;
    final key = part.substring(0, eq).trim().toUpperCase();
    final value = part.substring(eq + 1).trim().toUpperCase();
    switch (key) {
      case 'FREQ':
        freq = value;
      case 'INTERVAL':
        final n = int.tryParse(value);
        if (n == null || n < 1) return null;
        interval = n;
      case 'WKST':
        // Which day a week starts on changes nothing without a BYDAY.
        break;
      default:
        return null;
    }
  }
  final (unit, factor) = switch (freq) {
    'DAILY' => (RecurrenceUnit.days, 1),
    'WEEKLY' => (RecurrenceUnit.weeks, 1),
    'MONTHLY' => (RecurrenceUnit.months, 1),
    'YEARLY' => (RecurrenceUnit.months, 12),
    _ => (null, 0),
  };
  if (unit == null) return null;
  final every = interval * factor;
  if (every > kMaxRecurrenceInterval) return null;
  return (every: every, unit: unit, start: dateOnly(start));
}

/// [rule] as an `RRULE` value.
String encodeTaskRule(TaskRule rule) {
  final (freq, interval) = switch (rule.unit) {
    RecurrenceUnit.days => ('DAILY', rule.every),
    RecurrenceUnit.weeks => ('WEEKLY', rule.every),
    RecurrenceUnit.months when rule.every % 12 == 0 => (
      'YEARLY',
      rule.every ~/ 12,
    ),
    RecurrenceUnit.months => ('MONTHLY', rule.every),
  };
  return interval == 1 ? 'FREQ=$freq' : 'FREQ=$freq;INTERVAL=$interval';
}

/// The fields both sides should end up with, given what they last agreed on
/// ([base]) and what each has now.
///
/// Field by field: a field only one side changed takes that side's value. A
/// field both changed, to different values, takes the server's — the other
/// app's edit was made by somebody who could see it, and the board's is still
/// in its history for its column — and is reported in [conflicts] by name.
({TodoTaskFields fields, List<String> conflicts}) mergeTaskFields(
  TodoTaskFields base,
  TodoTaskFields local,
  TodoTaskFields remote,
) {
  final conflicts = <String>[];
  T pick<T>(String name, T b, T l, T r) {
    if (l == b) return r;
    if (r == b || r == l) return l;
    conflicts.add(name);
    return r;
  }

  return (
    fields: TodoTaskFields(
      title: pick('title', base.title, local.title, remote.title),
      body: pick('notes', base.body, local.body, remote.body),
      column: pick('column', base.column, local.column, remote.column),
      due: pick('due date', base.due, local.due, remote.due),
      rule: pick('repeat', base.rule, local.rule, remote.rule),
    ),
    conflicts: conflicts,
  );
}

/// [card] with [fields] applied: a change of column recorded as a move at
/// [movedAt], and a changed repeat started afresh from [today] (see
/// [recurrenceFor]).
TodoItem applyTaskFields(
  TodoItem card,
  TodoTaskFields fields, {
  required DateTime movedAt,
  required DateTime today,
}) {
  final rule = fields.rule;
  final recurrence = rule == _ruleOf(card.recurrence)
      ? card.recurrence
      : rule == null
      ? null
      : recurrenceFor(rule, today);
  return card.copyWith(
    title: fields.title,
    body: fields.body,
    column: fields.column,
    due: fields.due,
    recurrence: recurrence,
    history: fields.column == card.column
        ? null
        : [
            ...card.history,
            TodoMove(from: card.column, to: fields.column, at: movedAt),
          ],
  );
}

/// A repeat that arrived from the task list, as the board keeps one.
///
/// The card it arrived on *is* the current occurrence, so the next copy is
/// owed at the first scheduled day after [today] — or at [TaskRule.start]
/// itself when that is still to come.
TodoRecurrence recurrenceFor(TaskRule rule, DateTime today) {
  final day = dateOnly(today);
  return TodoRecurrence(
    every: rule.every,
    unit: rule.unit,
    start: rule.start,
    since: rule.start.isAfter(day) ? addDays(rule.start, -1) : day,
  );
}

/// A new card for [vtodo], fetched from the list at [href].
TodoItem cardForTask(
  ICalComponent vtodo, {
  required String id,
  required TodoRemote remote,
  required DateTime now,
}) {
  final fields = fieldsOfTask(vtodo);
  final created =
      parseICalDateTime(vtodo.property('CREATED'))?.value.toLocal() ??
      parseICalDateTime(vtodo.property('DTSTAMP'))?.value.toLocal() ??
      now;
  final rule = fields.rule;
  return TodoItem(
    id: id,
    title: fields.title,
    body: fields.body,
    column: fields.column,
    created: created,
    due: fields.due,
    recurrence: rule == null ? null : recurrenceFor(rule, now),
    history: [TodoMove(from: null, to: fields.column, at: created)],
    remote: remote,
  );
}

/// When [vtodo] was last changed, or null when it does not say.
DateTime? taskModified(ICalComponent vtodo) =>
    parseICalDateTime(vtodo.property('LAST-MODIFIED'))?.value.toLocal() ??
    parseICalDateTime(vtodo.property('DTSTAMP'))?.value.toLocal();

/// The `UID` a card the board sends for the first time is given.
String taskUidFor(TodoItem card) => '${card.id}@moonswing';

/// The card id in a [taskUidFor] UID, or null for a task some other client
/// made.
String? cardIdOfUid(String? uid) {
  const suffix = '@moonswing';
  if (uid == null || !uid.endsWith(suffix)) return null;
  final id = uid.substring(0, uid.length - suffix.length);
  return id.isEmpty ? null : id;
}

/// The resource name a card the board sends for the first time is written to,
/// inside the collection.
String taskFileFor(TodoItem card) =>
    '${Uri.encodeComponent(taskUidFor(card))}.ics';

/// [card] as the `.ics` text to send.
///
/// With [raw] — the task as the server last had it — the fields that differ
/// from what [raw] says are patched into it and everything else is left as it
/// was. Without it (or with a [raw] that holds no task) a new task is written,
/// named [taskUidFor].
String writeTask(TodoItem card, {String? raw, required DateTime now}) {
  final calendar = raw == null ? null : parseICalendar(raw);
  final existing = masterTodo(calendar);
  final want = fieldsOfCard(card);
  final stamp = formatICalUtc(now);
  if (calendar == null || existing == null) {
    final vtodo = ICalComponent('VTODO')
      ..set('UID', taskUidFor(card))
      ..set('DTSTAMP', stamp)
      ..set('CREATED', formatICalUtc(card.created))
      ..set('LAST-MODIFIED', stamp);
    _patch(vtodo, null, want, now);
    final cal = ICalComponent('VCALENDAR', children: [vtodo])
      ..set('VERSION', '2.0')
      ..set('PRODID', kTodoProdId);
    return encodeICalendar(cal);
  }
  final base = fieldsOfTask(existing);
  if (base != want) {
    _patch(existing, base, want, now);
    existing
      ..set('DTSTAMP', stamp)
      ..set('LAST-MODIFIED', stamp);
    final sequence = int.tryParse(
      existing.property('SEQUENCE')?.value.trim() ?? '',
    );
    existing.set('SEQUENCE', '${(sequence ?? 0) + 1}');
  }
  return encodeICalendar(calendar);
}

/// Writes the fields of [want] that differ from [base] (all of them, with no
/// base) into [vtodo].
void _patch(
  ICalComponent vtodo,
  TodoTaskFields? base,
  TodoTaskFields want,
  DateTime now,
) {
  if (base?.title != want.title) vtodo.setText('SUMMARY', want.title);
  if (base?.body != want.body) {
    if (want.body.isEmpty) {
      vtodo.remove('DESCRIPTION');
    } else {
      vtodo.setText('DESCRIPTION', want.body);
    }
  }
  if (base?.column != want.column) _setColumn(vtodo, want.column, now);
  if (base == null || base.due != want.due) {
    final due = want.due;
    if (due == null) {
      vtodo.remove('DUE');
    } else {
      vtodo.set('DUE', formatICalDate(due), {'VALUE': 'DATE'});
    }
  }
  // A repeat needs its anchor written down, or the server's copy would take
  // it from DUE and move it with every change of due date.
  if (want.rule case final rule? when vtodo.property('DTSTART') == null) {
    vtodo.set('DTSTART', formatICalDate(rule.start), {'VALUE': 'DATE'});
  }
  if (base == null || base.rule != want.rule) {
    final rule = want.rule;
    if (rule == null) {
      // DTSTART is the task's start as much as the repeat's anchor, so it
      // stays; only the repeat goes.
      vtodo.remove('RRULE');
    } else {
      vtodo
        ..set('DTSTART', formatICalDate(rule.start), {'VALUE': 'DATE'})
        ..set('RRULE', encodeTaskRule(rule));
    }
  }
}

void _setColumn(ICalComponent vtodo, TodoColumn column, DateTime now) {
  void reopen() {
    vtodo.remove('COMPLETED');
    if (vtodo.property('PERCENT-COMPLETE')?.value.trim() == '100') {
      vtodo.remove('PERCENT-COMPLETE');
    }
  }

  switch (column) {
    case TodoColumn.finished:
      vtodo
        ..set('STATUS', 'COMPLETED')
        ..set('COMPLETED', formatICalUtc(now))
        ..set('PERCENT-COMPLETE', '100');
    case TodoColumn.abandoned:
      vtodo
        ..set('STATUS', 'CANCELLED')
        ..remove('COMPLETED');
    case TodoColumn.inProgress:
      vtodo.set('STATUS', 'IN-PROCESS');
      reopen();
    case TodoColumn.todo || TodoColumn.inbox:
      vtodo.set('STATUS', 'NEEDS-ACTION');
      reopen();
  }
  if (column == TodoColumn.inbox) {
    vtodo.set(kColumnProperty, 'inbox');
  } else {
    vtodo.remove(kColumnProperty);
  }
}

/// Whether [card] goes to the task list at all: every card but a calendar
/// meeting, which is the calendar's to keep and would come back from a phone
/// as a second copy of the meeting.
bool isSyncedCard(TodoItem card) => card.external == null;

/// What the task list last had of [card] — the base a merge compares against —
/// or null when it has not been sent, or its record will not parse.
///
/// Remembered per record: every write of the board asks this of every card,
/// and a record is immutable and outlives the card copies that carry it.
TodoTaskFields? baseOf(TodoItem card) {
  final remote = card.remote;
  if (remote == null) return null;
  final known = _bases[remote];
  if (known != null) return known.fields;
  final todo = masterTodo(parseICalendar(remote.raw));
  final fields = todo == null ? null : fieldsOfTask(todo);
  _bases[remote] = (fields: fields);
  return fields;
}

final Expando<({TodoTaskFields? fields})> _bases = Expando('task bases');

/// Whether [card] has something the task list has not: it was never sent, or
/// a field changed since it last was.
bool needsPush(TodoItem card, {TodoTaskFields? Function(TodoItem)? base}) {
  if (!isSyncedCard(card)) return false;
  if (card.remote == null) return true;
  final was = (base ?? baseOf)(card);
  return was == null || was != fieldsOfCard(card);
}

/// What one pull changes on the board.
class TodoPull {
  const TodoPull({
    this.added = const [],
    this.changed = const [],
    this.removed = const [],
    this.conflicts = const [],
  });

  /// Tasks the board has no card for yet.
  final List<TodoItem> added;

  /// Cards to replace, each with the version the plan was made from — the
  /// store applies it only if the card is still that version, so an edit made
  /// while the server was answering is never lost to it.
  final List<({TodoItem was, TodoItem next})> changed;

  /// Cards whose tasks were deleted on the server, as the plan saw them.
  final List<TodoItem> removed;

  /// "Title: due date, notes" for each card both sides changed.
  final List<String> conflicts;

  bool get isEmpty =>
      added.isEmpty && changed.isEmpty && removed.isEmpty && conflicts.isEmpty;
}

/// Which of [listed] need fetching: those the board has no card for, and those
/// whose version is not the one the card last saw. [key] compares hrefs.
List<String> hrefsToFetch(
  List<TodoItem> cards,
  List<({String href, String? etag})> listed,
  String Function(String href) key, {
  Set<String> skip = const {},
}) {
  final known = <String, TodoRemote>{};
  for (final c in cards) {
    final r = c.remote;
    if (r != null) known[key(r.href)] = r;
  }
  return [
    for (final entry in listed)
      if (!skip.contains(key(entry.href)))
        if (known[key(entry.href)] case final r
            when r == null || r.etag == null || r.etag != entry.etag)
          entry.href,
  ];
}

/// Reconciles [cards] with the task list: [listed] is every task on it (so a
/// synced card missing from it was deleted there) and [fetched] the ones
/// [hrefsToFetch] asked for. [key] compares hrefs; [skip] holds the keys of
/// tasks deleted here whose delete has not reached the server, which are
/// not brought back.
///
/// Per task:
///
///  * **New on the server** — a new card, unless its UID is one this board
///    made for a card that has no record yet (a write whose answer was lost),
///    which is adopted instead of copied.
///  * **Changed on the server** — merged with the card by [mergeTaskFields]
///    against what both last agreed on; a card unchanged here simply takes
///    the server's version.
///  * **Deleted on the server** — the card goes too, unless it was changed
///    here since, in which case it is kept and sent again as a new task: an
///    edit is newer than the delete it did not know about.
TodoPull planPull(
  List<TodoItem> cards,
  List<({String href, String? etag})> listed,
  List<({String href, String? etag, String data})> fetched,
  String Function(String href) key, {
  required DateTime now,
  required String Function() newId,
  Set<String> skip = const {},
}) {
  final byKey = <String, TodoItem>{
    for (final c in cards)
      if (c.remote case final r?) key(r.href): c,
  };
  final byId = {for (final c in cards) c.id: c};
  final added = <TodoItem>[];
  final changed = <({TodoItem was, TodoItem next})>[];
  final removed = <TodoItem>[];
  final conflicts = <String>[];
  final adopted = <String>{};

  for (final resource in fetched) {
    final k = key(resource.href);
    if (skip.contains(k)) continue;
    final todo = masterTodo(parseICalendar(resource.data));
    // A resource that holds no task costs that resource.
    if (todo == null) continue;
    final record = TodoRemote(
      href: resource.href,
      etag: resource.etag,
      raw: resource.data,
    );
    final remoteFields = fieldsOfTask(todo);
    final movedAt = taskModified(todo) ?? now;
    final card = byKey[k];
    if (card == null) {
      final ownId = cardIdOfUid(todo.property('UID')?.value.trim());
      final own = ownId == null ? null : byId[ownId];
      if (own != null && own.remote == null && adopted.add(own.id)) {
        // The server has the task this card was sent as; the card is what the
        // user has now, so it keeps its fields and is sent again if they
        // differ.
        changed.add((was: own, next: own.copyWith(remote: record)));
      } else {
        added.add(cardForTask(todo, id: newId(), remote: record, now: now));
      }
      continue;
    }
    if (!isSyncedCard(card)) continue;
    final base = baseOf(card);
    final local = fieldsOfCard(card);
    TodoTaskFields fields;
    if (base == null) {
      // Nothing to merge against: the board's version stands and is sent.
      fields = local;
    } else {
      final merged = mergeTaskFields(base, local, remoteFields);
      fields = merged.fields;
      if (merged.conflicts.isNotEmpty) {
        final title = card.title.trim().isEmpty
            ? 'Untitled'
            : card.title.trim();
        conflicts.add('$title: ${merged.conflicts.join(', ')}');
      }
    }
    final next = applyTaskFields(
      card,
      fields,
      movedAt: movedAt,
      today: now,
    ).copyWith(remote: record);
    if (next != card) changed.add((was: card, next: next));
  }

  final present = {for (final e in listed) key(e.href)};
  for (final entry in byKey.entries) {
    if (present.contains(entry.key)) continue;
    final card = entry.value;
    if (!isSyncedCard(card)) continue;
    if (needsPush(card)) {
      changed.add((was: card, next: card.copyWith(remote: null)));
    } else {
      removed.add(card);
    }
  }
  return TodoPull(
    added: added,
    changed: changed,
    removed: removed,
    conflicts: conflicts,
  );
}
