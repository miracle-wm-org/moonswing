import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_calendar_sync.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

CalendarCardSource _meeting(String id, int hour) => CalendarCardSource(
  key: 'primary/$id',
  title: 'Meeting $id',
  start: DateTime(2026, 9, 25, hour),
  end: DateTime(2026, 9, 25, hour, 30),
);

/// The store's half of the calendar sync: what the user does to a synced card
/// is what the sync respects.
void main() {
  late DateTime now;
  late TodoStore store;
  final day = DateTime(2026, 9, 25);

  setUp(() {
    now = DateTime(2026, 9, 25, 8);
    store = TodoStore.forTesting(now: () => now, items: const []);
  });

  tearDown(() => store.dispose());

  test('the sync adds and moves cards, and says so once per change', () {
    var notified = 0;
    store.addListener(() => notified++);
    final sources = [_meeting('a', 10)];

    store.applyCalendarSync(sources, day: day);
    expect(store.itemsIn(TodoColumn.todo).single.title, 'Meeting a');
    expect(notified, 1);

    store.applyCalendarSync(sources, day: day);
    expect(notified, 1, reason: 'nothing moved, so nothing is published');

    now = DateTime(2026, 9, 25, 10, 1);
    store.applyCalendarSync(sources, day: day);
    expect(store.itemsIn(TodoColumn.inProgress), hasLength(1));
    expect(notified, 2);
  });

  test('a card the user drags is theirs from then on', () {
    final sources = [_meeting('a', 10)];
    store.applyCalendarSync(sources, day: day);
    final id = store.items.single.id;

    store.move(id, TodoColumn.finished);
    expect(store.item(id)!.external!.manual, isTrue);

    now = DateTime(2026, 9, 25, 10, 1);
    store.applyCalendarSync(sources, day: day);
    expect(store.item(id)!.column, TodoColumn.finished);
  });

  test('a card the user deletes stays deleted', () {
    final sources = [_meeting('a', 10)];
    store.applyCalendarSync(sources, day: day);
    store.delete(store.items.single.id);
    store.applyCalendarSync(sources, day: day);
    expect(store.items, isEmpty);
  });

  test('an editor save that changes the column counts as a move', () {
    store.applyCalendarSync([_meeting('a', 10)], day: day);
    final card = store.items.single;
    store.update(
      card.id,
      title: card.title,
      body: card.body,
      column: TodoColumn.abandoned,
      due: null,
      recurrence: null,
    );
    expect(store.item(card.id)!.external!.manual, isTrue);
  });

  test('the board moves its cards by their own times, with no sync', () {
    store.applyCalendarSync([_meeting('a', 10)], day: day);
    // Logged in again at 10:05, before the calendar has answered.
    now = DateTime(2026, 9, 25, 10, 5);
    store.resumed();
    expect(store.itemsIn(TodoColumn.inProgress), hasLength(1));
    now = DateTime(2026, 9, 25, 11);
    store.resumed();
    expect(store.itemsIn(TodoColumn.finished), hasLength(1));
  });

  test('the start of the day finishes yesterday\'s meetings', () {
    store.applyCalendarSync([_meeting('a', 10)], day: day);
    now = DateTime(2026, 9, 26, 8);
    store.startOfDay(remind: false);
    expect(store.itemsIn(TodoColumn.finished), hasLength(1));
  });
}
