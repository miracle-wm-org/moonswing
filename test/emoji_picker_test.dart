import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/emoji/emoji_data.dart';
import 'package:moonswing/emoji/emoji_picker_overlay.dart';
import 'package:moonswing/emoji/emoji_search.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/shell_text_root.dart';

Emoji _e(String char, String name, List<String> keywords) =>
    Emoji(char, name, EmojiCategory.food, keywords);

final _table = [
  _e('🍕', 'pizza', ['italian', 'slice']),
  _e('🍔', 'hamburger', ['burger', 'beef']),
  _e('🍟', 'french fries', ['chips', 'fries']),
].map(SearchableEmoji.new).toList();

class PickerHarness {
  final closing = ValueNotifier(false);
  final copied = <String>[];
  var closedCount = 0;
}

Future<PickerHarness> pumpPicker(
  WidgetTester tester, {
  List<SearchableEmoji>? emoji,
}) async {
  final harness = PickerHarness();
  await tester.pumpWidget(
    // Pumped the way `_windowChrome` builds it: the picker is a root-owned
    // window and takes its text root from there, so a test supplying a bare
    // Directionality of its own would be measuring a different tree.
    ThemeScope(
      theme: const ThemeConfig(),
      child: ShellTextRoot(
        child: Center(
          child: SizedBox(
            width: 900,
            height: 700,
            child: EmojiPickerOverlay(
              closingNotifier: harness.closing,
              onClosed: () => harness.closedCount++,
              onCopy: harness.copied.add,
              emoji: emoji ?? _table,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  group('emojiGridMove', () {
    test('horizontal moves clamp at either end', () {
      expect(emojiGridMove(0, 30, columns: -1), 0);
      expect(emojiGridMove(29, 30, columns: 1), 29);
      expect(emojiGridMove(5, 30, columns: 1), 6);
    });

    test('right at the end of a row steps to the start of the next', () {
      expect(emojiGridMove(kEmojiColumns - 1, 30, columns: 1), kEmojiColumns);
    });

    test('a vertical move is one whole row', () {
      expect(emojiGridMove(0, 30, rows: 1), kEmojiColumns);
      expect(emojiGridMove(kEmojiColumns, 30, rows: -1), 0);
    });

    test('up from the first row holds rather than wrapping to the end', () {
      expect(emojiGridMove(3, 30, rows: -1), 3);
    });

    test('down from the last row holds rather than wrapping to the top', () {
      // A full three rows: 29 is on the last one.
      expect(emojiGridMove(29, 30, rows: 1), 29);
    });

    test('down into the ragged last row lands on its last cell', () {
      // 25 entries: the last row holds indices 20..24, so Down from column 7
      // of the row above has no cell of its own to land on.
      expect(emojiGridMove(17, 25, rows: 1), 24);
    });

    test('down from within the last row itself still holds', () {
      expect(emojiGridMove(22, 25, rows: 1), 22);
    });

    test('a page move travels to the edge rather than holding', () {
      // The rule Up and PageUp share: land in the nearest row you can, in the
      // same column. Up on the first row is already there and so holds; a
      // page from the middle is not, and must travel.
      expect(emojiGridMove(25, 30, rows: -kEmojiVisibleRows), 5);
      expect(emojiGridMove(5, 30, rows: -kEmojiVisibleRows), 5);
    });

    test('a page down lands in the last row, keeping its column', () {
      expect(emojiGridMove(3, 30, rows: kEmojiVisibleRows), 23);
    });

    test('an empty grid answers 0 rather than throwing', () {
      expect(emojiGridMove(4, 0, rows: 1), 0);
      expect(emojiGridMove(4, 0, columns: 1), 0);
    });

    test('a selection past the end is clamped before it is moved', () {
      expect(emojiGridMove(99, 3, columns: 1), 2);
    });
  });

  group('the picker', () {
    testWidgets('shows the whole table before anything is typed', (
      tester,
    ) async {
      await pumpPicker(tester);

      expect(find.text('🍕'), findsWidgets);
      expect(find.text('🍔'), findsOneWidget);
      expect(find.text('🍟'), findsOneWidget);
      // The first row is selected, so the footer names it.
      expect(find.text('pizza'), findsOneWidget);
      expect(find.text('Food & Drink'), findsOneWidget);
    });

    testWidgets('typing filters by name', (tester) async {
      await pumpPicker(tester);
      await _type(tester, 'hamburger');

      expect(find.text('🍔'), findsWidgets);
      expect(find.text('🍟'), findsNothing);
    });

    testWidgets('typing filters by keyword', (tester) async {
      await pumpPicker(tester);
      await _type(tester, 'italian');

      expect(find.text('🍔'), findsNothing);
      expect(find.text('pizza'), findsOneWidget);
    });

    testWidgets('typing filters by category', (tester) async {
      await pumpPicker(tester);
      await _type(tester, 'drink');

      // Every row shares the category, so nothing is filtered out.
      expect(find.text('🍔'), findsOneWidget);
      expect(find.text('🍟'), findsOneWidget);
    });

    testWidgets('a fuzzy query still finds the row', (tester) async {
      await pumpPicker(tester);
      await _type(tester, 'frfrs');

      expect(find.text('french fries'), findsOneWidget);
      expect(find.text('🍔'), findsNothing);
    });

    testWidgets('nothing matching says so', (tester) async {
      await pumpPicker(tester);
      await _type(tester, 'qqqq');

      expect(find.text('No matching emoji'), findsOneWidget);
    });

    testWidgets('enter copies the selection and closes', (tester) async {
      final harness = await pumpPicker(tester);
      await _press(tester, LogicalKeyboardKey.enter);

      expect(harness.copied, ['🍕']);
      // Straight out, with no exit animation: the window exists to hand the
      // keyboard back to whatever is being pasted into.
      expect(harness.closedCount, 1);
      expect(harness.closing.value, isFalse);
    });

    testWidgets('the numeric keypad enter copies too', (tester) async {
      final harness = await pumpPicker(tester);
      await _press(tester, LogicalKeyboardKey.numpadEnter);

      expect(harness.copied, ['🍕']);
      expect(harness.closedCount, 1);
    });

    testWidgets('space belongs to the query, and copies nothing', (
      tester,
    ) async {
      // The key handler must *not* take Space: a key it takes never reaches
      // the field, so binding it would cost every query its spaces.
      final harness = await pumpPicker(tester);
      await _press(tester, LogicalKeyboardKey.space);

      expect(harness.copied, isEmpty);
      expect(harness.closedCount, 0);
      expect(harness.closing.value, isFalse);
    });

    testWidgets('a multi-word query filters', (tester) async {
      await pumpPicker(tester);
      await _type(tester, 'french fries');

      // On the glyphs rather than the name, because `find.text` matches the
      // EditableText too and the query *is* that name.
      expect(find.text('🍟'), findsWidgets);
      expect(find.text('🍔'), findsNothing);
    });

    testWidgets('a query mid-word keeps its results', (tester) async {
      // Every two-word query passes through this state, and no field is
      // folded with a trailing space — without the trim the grid would empty
      // on the keystroke between the words.
      await pumpPicker(tester);
      await _type(tester, 'french ');

      expect(find.text('No matching emoji'), findsNothing);
      expect(find.text('french fries'), findsOneWidget);
    });

    testWidgets('the arrow keys move the selection before copying', (
      tester,
    ) async {
      final harness = await pumpPicker(tester);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('hamburger'), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('french fries'), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(harness.copied, ['🍔']);
    });

    testWidgets('End and Home jump to either end', (tester) async {
      final harness = await pumpPicker(tester);
      await _press(tester, LogicalKeyboardKey.end);
      expect(find.text('french fries'), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.home);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(harness.copied, ['🍕']);
    });

    testWidgets('typing resets the selection to the best match', (
      tester,
    ) async {
      final harness = await pumpPicker(tester);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _type(tester, 'fries');
      await _press(tester, LogicalKeyboardKey.enter);

      expect(harness.copied, ['🍟']);
    });

    testWidgets('escape leaves with nothing copied, playing the exit', (
      tester,
    ) async {
      final harness = await pumpPicker(tester);
      await _press(tester, LogicalKeyboardKey.escape);

      expect(harness.copied, isEmpty);
      // Escape asks for the fade-out rather than tearing the window down, so
      // the close arrives only once the animation has run.
      expect(harness.closing.value, isTrue);
      await tester.pumpAndSettle();
      expect(harness.closedCount, 1);
    });

    testWidgets('a click on the backdrop dismisses', (tester) async {
      final harness = await pumpPicker(tester);
      // The shell has no input-region support, so this surface swallows every
      // click on the monitor; without this a mouse-only user has no way out.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(harness.copied, isEmpty);
      expect(harness.closedCount, 1);
    });

    testWidgets('clicking a cell copies it', (tester) async {
      final harness = await pumpPicker(tester);
      await tester.tap(find.text('🍟'));
      await tester.pumpAndSettle();

      expect(harness.copied, ['🍟']);
      expect(harness.closedCount, 1);
    });

    testWidgets('the footer says how to take the selection', (tester) async {
      await pumpPicker(tester);
      expect(find.text('Enter to copy  ·  Esc to cancel'), findsOneWidget);
    });
  });

  group('pointer cost', () {
    testWidgets('hovering a cell moves the ring without rebuilding the card', (
      tester,
    ) async {
      // The selection follows the pointer, and a `MouseRegion` fires enter and
      // exit as the *content* moves under a stationary cursor — so a scroll with
      // the pointer over the grid moves the selection on every frame. Written
      // with `setState`, each of those frames rebuilt the whole card. Widget
      // identity is what tells a rebuilt subtree from a repainted one.
      await pumpPicker(tester);
      final gridBefore = tester.widget<GridView>(find.byType(GridView));
      final fieldBefore = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      final target = tester.getCenter(find.text('🍟'));

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: const Offset(5, 5));
      addTearDown(() => gesture.removePointer());
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();

      // The ring moved: the footer names the cell under the pointer.
      expect(find.text('french fries'), findsOneWidget);
      expect(
        identical(tester.widget<GridView>(find.byType(GridView)), gridBefore),
        isTrue,
        reason: 'a hover must not rebuild the grid',
      );
      expect(
        identical(
          tester.widget<EditableText>(find.byType(EditableText)),
          fieldBefore,
        ),
        isTrue,
        reason: 'a hover must not rebuild the search field',
      );
    });

    testWidgets('an arrow key moves the ring without rebuilding the card', (
      tester,
    ) async {
      await pumpPicker(tester);
      final gridBefore = tester.widget<GridView>(find.byType(GridView));

      await _press(tester, LogicalKeyboardKey.arrowRight);

      expect(find.text('hamburger'), findsOneWidget);
      expect(
        identical(tester.widget<GridView>(find.byType(GridView)), gridBefore),
        isTrue,
        reason: 'a held arrow key must not rebuild the grid per repeat',
      );
    });

    testWidgets('typing rebuilds the grid and not the field', (tester) async {
      // Both sides of the rule at once. A query genuinely changes what the grid
      // holds, so that half must not be optimised away with the hovers — and it
      // does not change the search field, so rebuilding `OverlaySearchField` and
      // its `EditableText` on every character was work for a widget whose content
      // had not moved.
      await pumpPicker(tester);
      final gridBefore = tester.widget<GridView>(find.byType(GridView));
      final fieldBefore = tester.widget<EditableText>(
        find.byType(EditableText),
      );

      await _type(tester, 'fries');

      expect(
        identical(tester.widget<GridView>(find.byType(GridView)), gridBefore),
        isFalse,
        reason: 'a query changes what the grid holds',
      );
      expect(
        identical(
          tester.widget<EditableText>(find.byType(EditableText)),
          fieldBefore,
        ),
        isTrue,
        reason: 'a keystroke must not rebuild the search field',
      );
    });

    testWidgets('the grid builds little more than it shows', (tester) async {
      // `GridView.builder` is already lazy; what it was over-building is the cache
      // extent, which defaults to 250 logical pixels — five and a half rows either
      // side of a seven-row viewport, so the first frame laid out about a hundred
      // and eighty cells to show seventy. This pins the extent that replaced it.
      final wide = [
        for (var i = 0; i < 400; i++)
          SearchableEmoji(
            Emoji(
              String.fromCharCode(0x41 + (i % 26)),
              'filler $i',
              EmojiCategory.food,
              const [],
            ),
          ),
      ];
      await pumpPicker(tester, emoji: wide);

      // Seven rows visible plus two of cache, ten to a row, and the viewport
      // is not row-aligned — so the ceiling is generous and still far under
      // the 180 the default extent built.
      // One Text per cell, so this is the cell count.
      final built = tester
          .widgetList(
            find.descendant(
              of: find.byType(GridView),
              matching: find.byType(Text),
            ),
          )
          .length;
      expect(built, lessThan(130));
      expect(built, greaterThanOrEqualTo(kEmojiColumns * kEmojiVisibleRows));
    });
  });
}
