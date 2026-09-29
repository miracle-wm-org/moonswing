import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/caldav/ical.dart';
import 'package:moonswing/todo/todo_caldav_map.dart';
import 'package:moonswing/todo/todo_model.dart';

final DateTime _now = DateTime(2026, 9, 29, 10);

TodoItem _card(
  String id, {
  String title = 'Task',
  String body = '',
  TodoColumn column = TodoColumn.todo,
  DateTime? due,
  TodoRecurrence? recurrence,
  TodoRemote? remote,
  TodoExternal? external,
}) => TodoItem(
  id: id,
  title: title,
  body: body,
  column: column,
  created: DateTime(2026, 9, 1),
  due: due,
  recurrence: recurrence,
  history: [TodoMove(from: null, to: column, at: DateTime(2026, 9, 1))],
  remote: remote,
  external: external,
);

String _vtodo(String props, {String uid = 'other-app-1'}) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Other//EN\r\n'
    'BEGIN:VTODO\r\nUID:$uid\r\nDTSTAMP:20260901T000000Z\r\n'
    '$props'
    'END:VTODO\r\nEND:VCALENDAR\r\n';

TodoTaskFields _fields(String ics) =>
    fieldsOfTask(masterTodo(parseICalendar(ics))!);

String _key(String href) => Uri.decodeFull(href);

void main() {
  group('columns', () {
    test('each status reads as its column', () {
      expect(
        _fields(_vtodo('STATUS:NEEDS-ACTION\r\n')).column,
        TodoColumn.todo,
      );
      expect(
        _fields(
          _vtodo('STATUS:NEEDS-ACTION\r\nX-MOONSWING-COLUMN:inbox\r\n'),
        ).column,
        TodoColumn.inbox,
      );
      expect(
        _fields(_vtodo('STATUS:IN-PROCESS\r\n')).column,
        TodoColumn.inProgress,
      );
      expect(
        _fields(_vtodo('STATUS:COMPLETED\r\n')).column,
        TodoColumn.finished,
      );
      expect(
        _fields(_vtodo('STATUS:CANCELLED\r\n')).column,
        TodoColumn.abandoned,
      );
      // No status, but a completion time.
      expect(
        _fields(_vtodo('COMPLETED:20260901T100000Z\r\n')).column,
        TodoColumn.finished,
      );
      expect(_fields(_vtodo('')).column, TodoColumn.todo);
    });

    test('every column survives a round trip', () {
      for (final column in TodoColumn.values) {
        final card = _card('c', column: column);
        final text = writeTask(card, now: _now);
        expect(_fields(text).column, column, reason: column.name);
      }
    });

    test('finishing sets the completion; reopening clears it', () {
      final done = writeTask(
        _card('c', column: TodoColumn.finished),
        now: _now,
      );
      final todo = masterTodo(parseICalendar(done))!;
      expect(todo.property('COMPLETED'), isNotNull);
      expect(todo.property('PERCENT-COMPLETE')!.value, '100');

      final reopened = writeTask(
        _card(
          'c',
          remote: TodoRemote(href: '/c.ics', raw: done),
        ),
        raw: done,
        now: _now,
      );
      final t = masterTodo(parseICalendar(reopened))!;
      expect(t.property('STATUS')!.value, 'NEEDS-ACTION');
      expect(t.property('COMPLETED'), isNull);
      expect(t.property('PERCENT-COMPLETE'), isNull);
    });
  });

  group('repeats', () {
    test('simple rules map; anything more is left alone', () {
      final start = DateTime(2026, 9, 1);
      expect(parseTaskRule('FREQ=DAILY', start: start), (
        every: 1,
        unit: RecurrenceUnit.days,
        start: start,
      ));
      expect(parseTaskRule('FREQ=WEEKLY;INTERVAL=2;WKST=MO', start: start), (
        every: 2,
        unit: RecurrenceUnit.weeks,
        start: start,
      ));
      expect(parseTaskRule('FREQ=YEARLY', start: start), (
        every: 12,
        unit: RecurrenceUnit.months,
        start: start,
      ));
      expect(parseTaskRule('FREQ=WEEKLY;BYDAY=MO,WE', start: start), isNull);
      expect(parseTaskRule('FREQ=DAILY;COUNT=3', start: start), isNull);
      expect(parseTaskRule('FREQ=DAILY', start: null), isNull);
    });

    test('rules encode back', () {
      final start = DateTime(2026, 9, 1);
      for (final rule in [
        (every: 1, unit: RecurrenceUnit.days, start: start),
        (every: 3, unit: RecurrenceUnit.weeks, start: start),
        (every: 2, unit: RecurrenceUnit.months, start: start),
        (every: 24, unit: RecurrenceUnit.months, start: start),
      ]) {
        expect(parseTaskRule(encodeTaskRule(rule), start: start), rule);
      }
    });

    test('a repeat that arrives is owed its next copy after today', () {
      final rule = (
        every: 1,
        unit: RecurrenceUnit.weeks,
        start: DateTime(2026, 9, 1),
      );
      final r = recurrenceFor(rule, _now);
      expect(r.since, DateTime(2026, 9, 29));
      expect(r.owedOn(DateTime(2026, 9, 29)), isNull);
      final future = recurrenceFor((
        every: 1,
        unit: RecurrenceUnit.days,
        start: DateTime(2026, 10, 5),
      ), _now);
      expect(future.owedOn(DateTime(2026, 10, 5)), DateTime(2026, 10, 5));
    });

    test('a rule the board cannot show survives an edit of the title', () {
      final raw = _vtodo(
        'SUMMARY:Gym\r\nDTSTART;VALUE=DATE:20260901\r\n'
        'RRULE:FREQ=WEEKLY;BYDAY=MO,WE\r\n',
      );
      final card = _card(
        'c',
        title: 'Gym and swim',
        remote: TodoRemote(href: '/g.ics', raw: raw),
      );
      final out = masterTodo(
        parseICalendar(writeTask(card, raw: raw, now: _now)),
      )!;
      expect(out.text('SUMMARY'), 'Gym and swim');
      expect(out.property('RRULE')!.value, 'FREQ=WEEKLY;BYDAY=MO,WE');
    });
  });

  group('writing', () {
    test('a new task carries every field', () {
      final card = _card(
        'abc',
        title: 'Pay rent, now',
        body: 'Line 1\nLine 2',
        column: TodoColumn.inbox,
        due: DateTime(2026, 10, 1),
        recurrence: TodoRecurrence(
          every: 1,
          unit: RecurrenceUnit.months,
          start: DateTime(2026, 10, 1),
          since: DateTime(2026, 9, 30),
        ),
      );
      final text = writeTask(card, now: _now);
      final todo = masterTodo(parseICalendar(text))!;
      expect(todo.property('UID')!.value, 'abc@moonswing');
      expect(_fields(text), fieldsOfCard(card));
      expect(todo.property('DUE')!.params['VALUE'], 'DATE');
      expect(todo.property('RRULE')!.value, 'FREQ=MONTHLY');
    });

    test('a patch keeps what the board does not own, and bumps SEQUENCE', () {
      final raw = _vtodo(
        'SUMMARY:Old\r\nSEQUENCE:4\r\nCATEGORIES:home\r\n'
        'DUE;TZID=Europe/London:20260930T170000\r\n'
        'BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\n',
      );
      final card = _card(
        'c',
        title: 'New',
        due: DateTime(2026, 9, 30),
        remote: TodoRemote(href: '/x.ics', raw: raw),
      );
      final todo = masterTodo(
        parseICalendar(writeTask(card, raw: raw, now: _now)),
      )!;
      expect(todo.text('SUMMARY'), 'New');
      expect(todo.property('SEQUENCE')!.value, '5');
      expect(todo.text('CATEGORIES'), 'home');
      expect(todo.childrenNamed('VALARM'), hasLength(1));
      expect(todo.property('UID')!.value, 'other-app-1');
      // The due day did not change, so the time and zone it had are kept.
      expect(todo.property('DUE')!.params['TZID'], 'Europe/London');
    });

    test('a card equal to its task is not dirty; an edit is', () {
      final card = _card('c', title: 'Same', body: 'a\r\nb');
      final raw = writeTask(card, now: _now);
      final synced = card.copyWith(
        remote: TodoRemote(href: '/c.ics', raw: raw),
      );
      expect(needsPush(synced), isFalse);
      expect(needsPush(synced.copyWith(title: 'Other')), isTrue);
      expect(needsPush(card), isTrue);
      final meeting = _card(
        'm',
        external: TodoExternal(
          source: TodoExternal.googleCalendar,
          key: 'k',
          title: 'Standup',
          start: _now,
          end: _now,
        ),
      );
      expect(needsPush(meeting), isFalse);
    });
  });

  group('merge', () {
    const base = TodoTaskFields(title: 'A', body: 'b', column: TodoColumn.todo);

    test('a field one side changed takes that side', () {
      final merged = mergeTaskFields(
        base,
        base.copyWith(title: 'Local'),
        base.copyWith(column: TodoColumn.finished),
      );
      expect(merged.fields.title, 'Local');
      expect(merged.fields.column, TodoColumn.finished);
      expect(merged.conflicts, isEmpty);
    });

    test('a field both changed takes the server and says so', () {
      final merged = mergeTaskFields(
        base,
        base.copyWith(title: 'Local'),
        base.copyWith(title: 'Remote'),
      );
      expect(merged.fields.title, 'Remote');
      expect(merged.conflicts, ['title']);
    });

    test('the same change on both sides is no conflict', () {
      final merged = mergeTaskFields(
        base,
        base.copyWith(due: DateTime(2026, 10, 1)),
        base.copyWith(due: DateTime(2026, 10, 1)),
      );
      expect(merged.conflicts, isEmpty);
    });
  });

  group('pull', () {
    var ids = 0;
    String newId() => 'new-${ids++}';

    test('a new task becomes a card; an unchanged one is not fetched', () {
      final raw = writeTask(_card('a', title: 'Known'), now: _now);
      final known = _card(
        'a',
        title: 'Known',
        remote: TodoRemote(href: '/l/a.ics', etag: '"1"', raw: raw),
      );
      final listed = [
        (href: '/l/a.ics', etag: '"1"'),
        (href: '/l/b.ics', etag: '"9"'),
      ];
      expect(hrefsToFetch([known], listed, _key), ['/l/b.ics']);
      final pull = planPull(
        [known],
        listed,
        [
          (
            href: '/l/b.ics',
            etag: '"9"',
            data: _vtodo('SUMMARY:From phone\r\n'),
          ),
        ],
        _key,
        now: _now,
        newId: newId,
      );
      expect(pull.added.single.title, 'From phone');
      expect(pull.added.single.remote!.etag, '"9"');
      expect(pull.changed, isEmpty);
      expect(pull.removed, isEmpty);
    });

    test('a task changed on the server moves the card and records it', () {
      final raw = writeTask(_card('a', title: 'Call'), now: _now);
      final card = _card(
        'a',
        title: 'Call',
        body: 'edited here',
        remote: TodoRemote(href: '/l/a.ics', etag: '"1"', raw: raw),
      );
      final server = raw
          .replaceFirst('STATUS:NEEDS-ACTION', 'STATUS:COMPLETED')
          .replaceFirst(
            RegExp(r'LAST-MODIFIED:[0-9TZ]+'),
            'LAST-MODIFIED:20260928T080000Z',
          );
      final pull = planPull(
        [card],
        [(href: '/l/a.ics', etag: '"2"')],
        [(href: '/l/a.ics', etag: '"2"', data: server)],
        _key,
        now: _now,
        newId: newId,
      );
      final next = pull.changed.single.next;
      expect(next.column, TodoColumn.finished);
      expect(next.body, 'edited here');
      expect(next.history.last.to, TodoColumn.finished);
      expect(next.history.last.at, DateTime.utc(2026, 9, 28, 8).toLocal());
      expect(next.remote!.etag, '"2"');
      // The body is still the board's, so it goes back.
      expect(needsPush(next), isTrue);
    });

    test('a task deleted on the server takes an unchanged card with it', () {
      final raw = writeTask(_card('a'), now: _now);
      final clean = _card(
        'a',
        remote: TodoRemote(href: '/l/a.ics', etag: '"1"', raw: raw),
      );
      final edited = _card(
        'b',
        title: 'Edited',
        remote: TodoRemote(href: '/l/b.ics', etag: '"1"', raw: raw),
      );
      final pull = planPull(
        [clean, edited],
        const [],
        const [],
        _key,
        now: _now,
        newId: newId,
      );
      expect(pull.removed.single.id, 'a');
      expect(pull.changed.single.next.remote, isNull);
    });

    test("the board's own task, whose answer was lost, is adopted", () {
      final card = _card('a', title: 'Mine');
      final pull = planPull(
        [card],
        [(href: '/l/a%40moonswing.ics', etag: '"1"')],
        [
          (
            href: '/l/a%40moonswing.ics',
            etag: '"1"',
            data: writeTask(card, now: _now),
          ),
        ],
        _key,
        now: _now,
        newId: newId,
      );
      expect(pull.added, isEmpty);
      expect(pull.changed.single.next.remote!.etag, '"1"');
    });

    test('a task deleted here is not brought back', () {
      final pull = planPull(
        const [],
        [(href: '/l/gone.ics', etag: '"1"')],
        [(href: '/l/gone.ics', etag: '"1"', data: _vtodo('SUMMARY:x\r\n'))],
        _key,
        now: _now,
        newId: newId,
        skip: {'/l/gone.ics'},
      );
      expect(pull.isEmpty, isTrue);
    });

    test('a resource with no task in it costs that resource', () {
      final pull = planPull(
        const [],
        [(href: '/l/bad.ics', etag: '"1"')],
        [(href: '/l/bad.ics', etag: '"1"', data: 'not a calendar')],
        _key,
        now: _now,
        newId: newId,
      );
      expect(pull.isEmpty, isTrue);
    });
  });
}
