import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/modules/todo.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/todo/todo_controller.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_overlay.dart';
import 'package:moonswing/todo/todo_store.dart';

TodoItem _item(
  String id,
  TodoColumn column, {
  DateTime? due,
  List<TodoMove>? history,
}) => TodoItem(
  id: id,
  title: 'Card $id',
  body: 'Body of $id',
  column: column,
  created: DateTime(2026, 9, 20, 10),
  due: due,
  history:
      history ??
      [TodoMove(from: null, to: column, at: DateTime(2026, 9, 20, 10))],
);

void main() {
  late ValueNotifier<bool> closing;
  late int closed;
  late DateTime now;

  setUp(() {
    closing = ValueNotifier(false);
    closed = 0;
    now = DateTime(2026, 9, 24, 12);
  });

  tearDown(() => closing.dispose());

  Future<TodoStore> pump(WidgetTester tester, List<TodoItem> items) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = TodoStore.forTesting(items: items, now: () => now);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: TodoOverlay(
          closingNotifier: closing,
          onClosed: () => closed++,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('draws the five columns and their cards', (tester) async {
    await pump(tester, [
      _item('a', TodoColumn.inbox),
      _item('b', TodoColumn.inProgress, due: DateTime(2026, 9, 24)),
    ]);
    for (final column in TodoColumn.values) {
      // "Todo" is also the board's own heading.
      expect(
        find.text(column.label),
        findsNWidgets(column == TodoColumn.todo ? 2 : 1),
      );
    }
    expect(find.text('Card a'), findsOneWidget);
    expect(find.text('Body of a'), findsOneWidget);
    // The due chip reads relative to today.
    expect(find.text('Today'), findsOneWidget);
    // When the card arrived in its column.
    expect(find.text('20 Sep 2026, 10:00'), findsNWidgets(2));
  });

  testWidgets('the add button creates an item in its own column', (
    tester,
  ) async {
    final store = await pump(tester, []);
    // The fourth column's plus: Finished.
    final adds = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'SettingsIconButton',
    );
    expect(adds, findsNWidgets(TodoColumn.values.length));
    await tester.tap(adds.at(TodoColumn.values.indexOf(TodoColumn.finished)));
    await tester.pumpAndSettle();
    expect(find.text('New item'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'Write report');
    await tester.pump();
    await tester.tap(find.text('Tomorrow'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final item = store.itemsIn(TodoColumn.finished).single;
    expect(item.title, 'Write report');
    expect(item.due, DateTime(2026, 9, 25));
    expect(find.text('New item'), findsNothing);
    expect(find.text('Write report'), findsOneWidget);
  });

  testWidgets('a card dragged onto another column moves there, with the time', (
    tester,
  ) async {
    final store = await pump(tester, [_item('a', TodoColumn.inbox)]);
    now = DateTime(2026, 9, 24, 15, 30);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Card a')),
    );
    await tester.pump();
    // Onto the empty In Progress column's placeholder.
    await gesture.moveTo(tester.getCenter(find.text('Drop a card here').at(1)));
    await tester.pump();
    await gesture.moveBy(const Offset(4, 4));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final moved = store.item('a')!;
    expect(moved.column, TodoColumn.inProgress);
    expect(moved.history.last.from, TodoColumn.inbox);
    expect(moved.history.last.at, DateTime(2026, 9, 24, 15, 30));
  });

  testWidgets('a card dropped on another card lands above it', (tester) async {
    final store = await pump(tester, [
      _item('a', TodoColumn.inbox),
      _item('b', TodoColumn.finished),
      _item('c', TodoColumn.finished),
    ]);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Card a')),
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Card c')));
    await tester.pump();
    await gesture.moveBy(const Offset(2, 2));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(store.itemsIn(TodoColumn.finished).map((i) => i.id), [
      'b',
      'a',
      'c',
    ]);
  });

  testWidgets('clicking a card opens it with its history', (tester) async {
    await pump(tester, [
      _item(
        'a',
        TodoColumn.inProgress,
        history: [
          TodoMove(
            from: null,
            to: TodoColumn.inbox,
            at: DateTime(2026, 9, 20, 10),
          ),
          TodoMove(
            from: TodoColumn.inbox,
            to: TodoColumn.inProgress,
            at: DateTime(2026, 9, 22, 8, 5),
          ),
        ],
      ),
    ]);
    await tester.tap(find.text('Card a'));
    await tester.pumpAndSettle();
    expect(find.text('Edit item'), findsOneWidget);
    expect(find.text('Created in Inbox'), findsOneWidget);
    expect(find.text('Inbox → In Progress'), findsOneWidget);
    expect(find.text('22 Sep 2026, 08:05'), findsWidgets);
  });

  testWidgets('Escape closes the editor, then the board', (tester) async {
    await pump(tester, [_item('a', TodoColumn.inbox)]);
    await tester.tap(find.text('Card a'));
    await tester.pumpAndSettle();
    expect(find.text('Edit item'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Edit item'), findsNothing);
    expect(closing.value, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closing.value, isTrue);
    expect(closed, 1);
  });

  testWidgets('a repeating item shows when its next copy comes', (
    tester,
  ) async {
    final store = await pump(tester, [_item('a', TodoColumn.todo)]);
    await tester.tap(find.text('Card a'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'SettingsToggle',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('The next one is on'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rule = store.item('a')!.recurrence!;
    expect(rule.every, 1);
    expect(rule.unit, RecurrenceUnit.weeks);
    // The card being edited stands for today; the first copy is a week out.
    expect(rule.next, DateTime(2026, 10, 1));
  });

  testWidgets('the bar button asks for the board on its own output', (
    tester,
  ) async {
    final controller = TodoController.forTesting();
    addTearDown(controller.dispose);
    final store = TodoStore.forTesting(
      items: [_item('a', TodoColumn.todo, due: DateTime(2026, 9, 23))],
      now: () => now,
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: TodoButton(controller: controller, store: store),
          ),
        ),
      ),
    );
    // One overdue item.
    expect(find.text('1'), findsOneWidget);
    var signals = 0;
    controller.addListener(() => signals++);
    await tester.tap(find.byType(TodoButton));
    expect(signals, 1);
    // No DisplayScope above it: the root falls back to the focused output.
    expect(controller.output, isNull);
  });
}
