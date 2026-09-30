import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_calendar_sync.dart';
import 'package:moonswing/todo/todo_model.dart';

final DateTime day = DateTime(2026, 9, 25);

CalendarCardSource meeting(
  String id, {
  int startHour = 10,
  int minutes = 30,
  String title = 'Standup',
  String? link = 'https://meet.google.com/abc',
}) {
  final start = DateTime(2026, 9, 25, startHour);
  return CalendarCardSource(
    key: 'primary/$id',
    title: title,
    start: start,
    end: start.add(Duration(minutes: minutes)),
    link: link,
    url: 'https://calendar.google.com/event?eid=$id',
  );
}

/// Runs one sync at [now], starting ids from [seed].
List<TodoItem>? sync(
  List<TodoItem> items,
  List<CalendarCardSource> sources,
  DateTime now, {
  Set<String> dismissed = const {},
}) {
  var next = 0;
  return syncCalendarCards(
    items,
    sources,
    day: day,
    now: now,
    newId: () => 'card-${next++}',
    dismissed: dismissed,
  );
}

DateTime at(int hour, [int minute = 0]) => DateTime(2026, 9, 25, hour, minute);

void main() {
  test('a card carries its calendar, and follows a recolour', () {
    CalendarCardSource coloured(String color) => CalendarCardSource(
      key: 'work/a',
      title: 'Standup',
      start: at(10),
      end: at(10, 30),
      calendar: 'Work',
      color: color,
    );
    var board = sync(const [], [coloured('#ff0000')], at(8))!;
    expect(board.single.external!.calendar, 'Work');
    expect(board.single.external!.color, '#ff0000');
    expect(sync(board, [coloured('#ff0000')], at(9)), isNull);

    board = sync(board, [coloured('#00ff00')], at(9))!;
    expect(board.single.external!.color, '#00ff00');
  });

  test('a meeting follows the clock through the columns', () {
    final sources = [meeting('a')];
    var board = sync(const [], sources, at(8))!;
    final card = board.single;
    expect(card.column, TodoColumn.todo);
    expect(card.title, 'Standup');
    expect(card.body, contains('10:00–10:30'));
    expect(card.body, contains('Join: https://meet.google.com/abc'));
    expect(card.external!.key, 'primary/a');

    // Nothing moved: no new board, so no write and no notify.
    expect(sync(board, sources, at(9)), isNull);

    board = sync(board, sources, at(10, 5))!;
    expect(board.single.column, TodoColumn.inProgress);
    board = sync(board, sources, at(11))!;
    expect(board.single.column, TodoColumn.finished);
    expect(sync(board, sources, at(12)), isNull);
  });

  test('each move is recorded at the meeting\'s own time', () {
    final sources = [meeting('a')];
    final board = sync(const [], sources, at(8))!;
    // A suspend over the whole meeting: one sync after it is over.
    final after = sync(board, sources, at(15))!;
    final moves = after.single.history;
    expect(moves.last.to, TodoColumn.finished);
    expect(moves.last.at, at(10, 30));
  });

  test('a card created mid-meeting starts in progress', () {
    final board = sync(const [], [meeting('a')], at(10, 10))!;
    expect(board.single.column, TodoColumn.inProgress);
    expect(board.single.history.single.at, at(10, 10));
  });

  test('the next meeting is at the top of Todo', () {
    final board = sync(const [], [
      meeting('late', startHour: 15, title: 'Late'),
      meeting('early', startHour: 11, title: 'Early'),
    ], at(8))!;
    expect(board.map((i) => i.title), ['Early', 'Late']);
  });

  test('a card the user moved is left where they put it', () {
    final sources = [meeting('a')];
    final board = sync(const [], sources, at(8))!;
    final moved = board.single.copyWith(
      column: TodoColumn.finished,
      external: board.single.external!.copyWith(manual: true),
    );
    // Rescheduled while done early: the time is kept, the column is not moved.
    final rescheduled = [meeting('a', startHour: 13)];
    final next = sync([moved], rescheduled, at(13, 5))!;
    expect(next.single.column, TodoColumn.finished);
    expect(next.single.external!.start, at(13));
    expect(next.single.body, contains('13:00–13:30'));
  });

  test('an edit the user made survives a rename on the calendar', () {
    final board = sync(const [], [meeting('a')], at(8))!;
    final edited = board.single.copyWith(
      title: 'My name for it',
      body: 'notes',
    );
    final next = sync([edited], [meeting('a', title: 'Renamed')], at(8))!;
    expect(next.single.title, 'My name for it');
    expect(next.single.body, 'notes');
    expect(next.single.external!.title, 'Renamed');

    // An untouched card takes the new name.
    final untouched = sync(board, [meeting('a', title: 'Renamed')], at(8))!;
    expect(untouched.single.title, 'Renamed');
  });

  test('a meeting gone from today is abandoned, unless the card is manual', () {
    final board = sync(const [], [
      meeting('a'),
      meeting('b', startHour: 14),
    ], at(8))!;
    final next = sync(board, [meeting('a')], at(9))!;
    final b = next.firstWhere((i) => i.external!.key == 'primary/b');
    expect(b.column, TodoColumn.abandoned);

    final manual = [
      for (final item in board)
        item.copyWith(external: item.external!.copyWith(manual: true)),
    ];
    final kept = sync(manual, [meeting('a')], at(9));
    expect(kept, isNull);
  });

  test('yesterday\'s cards are not today\'s to abandon', () {
    final yesterday = CalendarCardSource(
      key: 'primary/old',
      title: 'Old',
      start: DateTime(2026, 9, 24, 10),
      end: DateTime(2026, 9, 24, 11),
    );
    var n = 0;
    final board = syncCalendarCards(
      const [],
      [yesterday],
      day: DateTime(2026, 9, 24),
      now: DateTime(2026, 9, 24, 12),
      newId: () => 'x${n++}',
    )!;
    expect(board.single.column, TodoColumn.finished);
    expect(sync(board, const [], at(9)), isNull);
  });

  test('a card the user deleted is not made again', () {
    expect(
      sync(const [], [meeting('a')], at(8), dismissed: {'primary/a'}),
      isNull,
    );
  });

  test('nothing but calendar cards is touched', () {
    final mine = TodoItem(
      id: 'mine',
      title: 'Write the report',
      body: '',
      column: TodoColumn.todo,
      created: at(7),
    );
    final board = sync([mine], [meeting('a')], at(8))!;
    expect(board, hasLength(2));
    expect(board.firstWhere((i) => i.id == 'mine'), mine);
  });

  test('the external record survives the file format', () {
    final board = sync(const [], [meeting('a')], at(8))!;
    final card = board.single;
    expect(TodoItem.fromJson(card.toJson()), card);
    final manual = card.copyWith(
      external: card.external!.copyWith(manual: true, link: null),
    );
    expect(TodoItem.fromJson(manual.toJson()), manual);
    // A record missing its key costs the record, never the card.
    final json = card.toJson()..['external'] = {'source': 'gcal'};
    final read = TodoItem.fromJson(json)!;
    expect(read.external, isNull);
    expect(read.title, card.title);
  });

  test('the next boundary is the nearest start or end still ahead', () {
    final sources = [meeting('a'), meeting('b', startHour: 14)];
    expect(nextCalendarBoundary(sources, at(8)), at(10));
    expect(nextCalendarBoundary(sources, at(10, 1)), at(10, 30));
    expect(nextCalendarBoundary(sources, at(11)), at(14));
    expect(nextCalendarBoundary(sources, at(15)), isNull);
  });

  test('a card made under the old key is adopted, not duplicated', () {
    final old = sync(const [], [meeting('a')], at(8))!;
    expect(old.single.external!.key, 'primary/a');
    final renamed = CalendarCardSource(
      key: 'me@example.com/a',
      legacyKey: 'primary/a',
      title: 'Standup',
      start: at(10),
      end: at(10, 30),
      link: 'https://meet.google.com/abc',
      url: 'https://calendar.google.com/event?eid=a',
    );
    final board = sync(old, [renamed], at(9))!;
    expect(board, hasLength(1));
    expect(board.single.id, old.single.id);
    expect(board.single.column, TodoColumn.todo, reason: 'not abandoned');
    expect(board.single.external!.key, 'me@example.com/a');

    // A deletion recorded under the old key still holds.
    expect(sync(const [], [renamed], at(9), dismissed: {'primary/a'}), isNull);
  });

  group('advanceCalendarCards, with no calendar to ask', () {
    List<TodoItem> board() => sync(const [], [
      meeting('a', startHour: 9),
      meeting('b', startHour: 11),
    ], at(8))!;

    test('a meeting under way at login moves to In Progress', () {
      final next = advanceCalendarCards(board(), at(9, 10))!;
      final a = next.firstWhere((i) => i.external!.key == 'primary/a');
      expect(a.column, TodoColumn.inProgress);
      expect(a.history.last.at, at(9), reason: 'recorded at its start');
      final b = next.firstWhere((i) => i.external!.key == 'primary/b');
      expect(b.column, TodoColumn.todo);
    });

    test('a meeting that ended before login goes straight to Finished', () {
      final next = advanceCalendarCards(board(), at(12))!;
      for (final item in next) {
        expect(item.column, TodoColumn.finished);
        expect(item.history.last.at, item.external!.end);
      }
      expect(next.map((i) => i.external!.key), [
        'primary/a',
        'primary/b',
      ], reason: 'the column stays in start order');
    });

    test('an earlier day\'s card is finished too', () {
      final next = advanceCalendarCards(board(), DateTime(2026, 9, 26, 8))!;
      expect(next.every((i) => i.column == TodoColumn.finished), isTrue);
    });

    test('a card the user moved, or a closed one, is left alone', () {
      final items = board();
      final manual = [
        for (final i in items)
          i.copyWith(external: i.external!.copyWith(manual: true)),
      ];
      expect(advanceCalendarCards(manual, at(12)), isNull);
      final abandoned = [
        for (final i in items) i.copyWith(column: TodoColumn.abandoned),
      ];
      expect(advanceCalendarCards(abandoned, at(12)), isNull);
    });

    test('nothing to do is null, and the next boundary is still ahead', () {
      final items = board();
      expect(advanceCalendarCards(items, at(8, 30)), isNull);
      expect(nextCalendarCardBoundary(items, at(8, 30)), at(9));
      expect(nextCalendarCardBoundary(items, at(9, 30)), at(11));
      final done = advanceCalendarCards(items, at(12))!;
      expect(nextCalendarCardBoundary(done, at(12)), isNull);
    });
  });
}
