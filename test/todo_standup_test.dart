import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_standup.dart';
import 'package:moonswing/todo/todo_store.dart';

TodoItem _item(
  String title,
  TodoColumn column, {
  required DateTime at,
  DateTime? due,
}) => TodoItem(
  id: title,
  title: title,
  body: '',
  column: column,
  created: DateTime(2026, 9, 1),
  due: due,
  history: [
    TodoMove(from: null, to: TodoColumn.inbox, at: DateTime(2026, 9, 1)),
    TodoMove(from: TodoColumn.inbox, to: column, at: at),
  ],
);

void main() {
  final now = DateTime(2026, 9, 25, 9, 30);
  final last = DateTime(2026, 9, 24, 9, 15);
  final before = DateTime(2026, 9, 23, 12);
  final after = DateTime(2026, 9, 24, 15);

  group('standupReport', () {
    test('sorts the board into done, in progress, to do and dropped', () {
      final report = standupReport(
        [
          _item('Old win', TodoColumn.finished, at: before),
          _item('Shipped login', TodoColumn.finished, at: after),
          _item('Carry on', TodoColumn.inProgress, at: before),
          _item('Picked up', TodoColumn.inProgress, at: after),
          _item('Later', TodoColumn.todo, at: before),
          _item(
            'Late',
            TodoColumn.todo,
            at: before,
            due: DateTime(2026, 9, 20),
          ),
          _item('Idea', TodoColumn.inbox, at: after),
          _item('Gave up', TodoColumn.abandoned, at: after),
        ],
        since: last,
        now: now,
      );
      expect(
        report,
        'Standup — Friday 2026-09-25\n'
        'Since yesterday at 09:15.\n'
        '\n'
        'Done:\n'
        '• Shipped login\n'
        '\n'
        'In progress:\n'
        '• Carry on\n'
        '• Picked up (started)\n'
        '\n'
        'To do:\n'
        '• Late (overdue, was due 2026-09-20)\n'
        '• Later\n'
        '\n'
        'Dropped:\n'
        '• Gave up',
      );
    });

    test('an empty board says so rather than printing bare headings', () {
      final report = standupReport(const [], since: null, now: now);
      expect(report, contains('Covering the last 24 hours.'));
      expect(report, contains('• Nothing finished'));
      expect(report, contains('• Nothing in progress'));
      expect(report, contains('• Nothing left to do'));
      expect(report, isNot(contains('Dropped')));
    });

    test('the first summary looks back one day', () {
      final report = standupReport(
        [
          _item('Recent', TodoColumn.finished, at: after),
          _item('Too old', TodoColumn.finished, at: before),
        ],
        since: null,
        now: now,
      );
      expect(report, contains('• Recent'));
      expect(report, isNot(contains('Too old')));
    });
  });

  group('TodoStore.takeStandup', () {
    late Directory dir;
    late DateTime clock;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('todo_standup_test');
      clock = DateTime(2026, 9, 24, 9, 0);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('each summary counts from the last, across a restart', () async {
      var store = TodoStore.forTesting(directory: dir.path, now: () => clock);
      await store.load();
      final id = store.add(TodoColumn.todo, title: 'Ticket')!;
      expect(store.takeStandup()!.report, contains('• Ticket'));
      expect(store.lastStandup, clock);

      clock = DateTime(2026, 9, 24, 14, 0);
      store.move(id, TodoColumn.finished);
      await store.flush();
      store.dispose();

      clock = DateTime(2026, 9, 25, 9, 0);
      store = TodoStore.forTesting(directory: dir.path, now: () => clock);
      await store.load();
      expect(store.lastStandup, DateTime(2026, 9, 24, 9, 0));
      final report = store.takeStandup()!.report;
      expect(report, contains('Since yesterday at 09:00.'));
      expect(report, contains('Done:\n• Ticket'));

      clock = DateTime(2026, 9, 26, 9, 0);
      expect(
        store.takeStandup()!.report,
        contains('Done:\n• Nothing finished'),
      );
      store.dispose();
    });

    test('every summary is kept, newest first, across a restart', () async {
      var store = TodoStore.forTesting(directory: dir.path, now: () => clock);
      await store.load();
      final first = store.takeStandup()!;
      expect(first.since, isNull);
      clock = DateTime(2026, 9, 25, 9, 0);
      final second = store.takeStandup()!;
      expect(second.since, DateTime(2026, 9, 24, 9, 0));
      expect(store.standups, [second, first]);
      await store.flush();
      store.dispose();

      store = TodoStore.forTesting(directory: dir.path, now: () => clock);
      await store.load();
      expect(store.standups, [second, first]);
      store.dispose();
    });

    test('invalidating the latest makes the next one cover it again', () async {
      var store = TodoStore.forTesting(directory: dir.path, now: () => clock);
      await store.load();
      final id = store.add(TodoColumn.todo, title: 'Ticket')!;
      final first = store.takeStandup()!;

      clock = DateTime(2026, 9, 24, 14, 0);
      store.move(id, TodoColumn.finished);
      clock = DateTime(2026, 9, 25, 9, 0);
      expect(store.takeStandup()!.report, contains('Done:\n• Ticket'));

      expect(store.invalidateLatestStandup(), isTrue);
      expect(store.standups, [first]);
      expect(store.lastStandup, DateTime(2026, 9, 24, 9, 0));
      await store.flush();
      store.dispose();

      // The invalidation survives a restart, and the next summary still
      // reports the card as done.
      clock = DateTime(2026, 9, 25, 9, 30);
      store = TodoStore.forTesting(directory: dir.path, now: () => clock);
      await store.load();
      expect(store.standups, [first]);
      expect(store.lastStandup, DateTime(2026, 9, 24, 9, 0));
      final retaken = store.takeStandup()!;
      expect(retaken.since, DateTime(2026, 9, 24, 9, 0));
      expect(retaken.report, contains('Since yesterday at 09:00.'));
      expect(retaken.report, contains('Done:\n• Ticket'));

      // Invalidating back past the first summary starts over.
      expect(store.invalidateLatestStandup(), isTrue);
      expect(store.invalidateLatestStandup(), isTrue);
      expect(store.standups, isEmpty);
      expect(store.lastStandup, isNull);
      expect(store.invalidateLatestStandup(), isFalse);
      await store.flush();
      store.dispose();

      store = TodoStore.forTesting(directory: dir.path, now: () => clock);
      await store.load();
      expect(store.lastStandup, isNull);
      expect(store.standups, isEmpty);
      store.dispose();
    });
  });
}
