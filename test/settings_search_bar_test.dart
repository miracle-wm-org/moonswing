// The settings search bar, and the row a picked result lands on.
//
// Both halves are pinned here because neither is reachable in its real home: a
// settings pane lives inside a layer-shell window no widget test can pump, so
// these have to be pumped the way the overlay builds them — under a `ThemeScope`,
// a `SettingsHighlightScope`, and the `DefaultTextEditingShortcuts` the overlay
// supplies in place of the `WidgetsApp` this shell does not have.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/settings/settings_catalog.dart';
import 'package:graceful_shell/overlay/settings/settings_highlight.dart';
import 'package:graceful_shell/overlay/settings/settings_search.dart';
import 'package:graceful_shell/overlay/settings/settings_search_bar.dart';
import 'package:graceful_shell/scopes.dart';

Widget _chrome({
  required Widget child,
  SettingsHighlightController? highlight,
}) {
  final tree = Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextEditingShortcuts(
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(theme: const ThemeConfig(), child: child),
      ),
    ),
  );
  if (highlight == null) return tree;
  return SettingsHighlightScope(controller: highlight, child: tree);
}

Future<List<SettingsField>> _pumpBar(
  WidgetTester tester,
  FocusNode focus,
  List<SettingsField> picked,
) async {
  await tester.pumpWidget(
    _chrome(
      // The bar fills the settings body, as `_buildSettingsBody` gives it —
      // its field is drawn in the top-left corner and, while results are open,
      // the rest is a dismiss barrier.
      child: SettingsSearchBar(focusNode: focus, onJump: picked.add),
    ),
  );
  await tester.pump();
  return picked;
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(EditableText), query);
  await tester.pump();
}

/// The result rows on screen, in order.
List<String> _rows(WidgetTester tester) => [
  for (final row in tester.widgetList<Text>(
    find.descendant(
      of: find.byType(SettingsSearchResults),
      matching: find.byType(Text),
    ),
  ))
    row.data ?? '',
];

void main() {
  group('SettingsSearchBar', () {
    testWidgets('shows nothing until something is typed', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await _pumpBar(tester, focus, []);

      expect(find.byType(SettingsSearchResults), findsNothing);
      await _type(tester, 'blur');
      expect(find.byType(SettingsSearchResults), findsOneWidget);
      // Cleared back to nothing, rather than to everything.
      await _type(tester, '');
      expect(find.byType(SettingsSearchResults), findsNothing);
    });

    testWidgets('a result carries its label, its section and its sentence', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await _pumpBar(tester, focus, []);
      await _type(tester, 'blur when unlocking');

      final rows = _rows(tester);
      expect(rows, contains('Blur when unlocking'));
      expect(rows, contains('Shell › Lock Screen'));
      expect(
        rows.any((r) => r.contains('blurs once the password field appears')),
        isTrue,
      );
    });

    testWidgets('tapping a result reports it and clears the card', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final picked = await _pumpBar(tester, focus, <SettingsField>[]);
      await _type(tester, 'week starts');

      await tester.tap(find.text('Week starts on'));
      await tester.pump();

      expect(picked, hasLength(1));
      expect(picked.single.id, 'calendar.week_start');
      // The card is over the pane the jump is about to scroll; leaving it up
      // would cover the row that has just flashed.
      expect(find.byType(SettingsSearchResults), findsNothing);
    });

    testWidgets('clicking away dismisses the card without picking', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final picked = await _pumpBar(tester, focus, <SettingsField>[]);
      await _type(tester, 'blur');
      expect(find.byType(SettingsSearchResults), findsOneWidget);

      // Well below the card, which is 52 + at most 340 tall.
      await tester.tapAt(const Offset(600, 560));
      await tester.pump();

      expect(find.byType(SettingsSearchResults), findsNothing);
      expect(picked, isEmpty);
    });

    // The barrier is the *first* child of the bar's stack and the field and
    // card are the second, so a click on either of those is hit-tested first
    // and never reaches it. Clicking back into the field to edit the query is
    // the everyday case that would break if that order were reversed.
    testWidgets('a click on the bar itself is not a dismissal', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final picked = await _pumpBar(tester, focus, <SettingsField>[]);
      await _type(tester, 'popup shadow');

      await tester.tap(find.byType(SettingsTextField));
      await tester.pump();

      expect(find.byType(SettingsSearchResults), findsOneWidget);
      expect(picked, isEmpty);
    });

    testWidgets('the arrow keys move the selection and Enter takes it', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final picked = await _pumpBar(tester, focus, <SettingsField>[]);
      await _type(tester, 'popup shadow');

      final expected = rankSettings(SettingsCatalog.searchable, 'popup shadow');
      expect(expected.length, greaterThan(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(picked.single, expected[1]);
    });

    testWidgets('the selection cannot run off either end of the list', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final picked = await _pumpBar(tester, focus, <SettingsField>[]);
      await _type(tester, 'week starts');

      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      }
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picked.single.id, 'calendar.week_start');
    });

    testWidgets('Enter with no matches picks nothing rather than throwing', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final picked = await _pumpBar(tester, focus, <SettingsField>[]);
      await _type(tester, 'zzzzzzzz');
      expect(find.byType(SettingsSearchResults), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picked, isEmpty);
    });

    // Escape has two jobs in this panel and the field only takes the first of
    // them: with a query to end it ends it, and with the field already empty it
    // goes on up to the overlay's own handler, which closes the panel.
    testWidgets('Escape ends the search, then stops being ours', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var escapes = 0;
      await tester.pumpWidget(
        _chrome(
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                escapes++;
              }
              return KeyEventResult.ignored;
            },
            child: Align(
              alignment: Alignment.topLeft,
              child: SettingsSearchBar(focusNode: focus, onJump: (_) {}),
            ),
          ),
        ),
      );
      await _type(tester, 'blur');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(SettingsSearchResults), findsNothing);
      expect(escapes, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(escapes, 1);
    });
  });

  group('SettingsRow.field', () {
    /// A scrollable page of catalogued rows, as a category pane builds them
    /// **while a jump is landing**.
    ///
    /// Eagerly, which is the point: the pane's own `SliverList` never builds a
    /// child far past the viewport, so a row forty settings down has no element to
    /// claim the jump — which is why `_ShellCategoryView` widens its
    /// `scrollCacheExtent` for the frame the target lands in. A `Column` in a
    /// `SingleChildScrollView` is that state, stated in a test.
    Future<void> pumpRows(
      WidgetTester tester,
      SettingsHighlightController highlight,
    ) async {
      await tester.pumpWidget(
        _chrome(
          highlight: highlight,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final field in SettingsCatalog.moduleFields)
                  SettingsRow.field(field, control: const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// Whether [label]'s row is inside the 800x600 test viewport.
    bool onScreen(WidgetTester tester, String label) {
      final rect = tester.getRect(find.text(label).first);
      return rect.top >= 0 && rect.bottom <= 600;
    }

    testWidgets('takes its label from the catalogue', (tester) async {
      final highlight = SettingsHighlightController();
      addTearDown(highlight.dispose);
      await pumpRows(tester, highlight);
      expect(find.text(SettingsCatalog.clockShowDate.label), findsOneWidget);
    });

    testWidgets('a jump claims the row, scrolls to it, and settles', (
      tester,
    ) async {
      final highlight = SettingsHighlightController();
      addTearDown(highlight.dispose);
      await pumpRows(tester, highlight);

      // Far enough down the page to be below the fold to begin with.
      final target = SettingsCatalog.recorderQuality;
      expect(onScreen(tester, target.label), isFalse);

      highlight.jumpTo(target);
      // One frame carries the whole exchange: the notify reaches the row, which
      // claims the target during its rebuild, and the post-frame callback at the
      // end of that same frame scrolls to it and clears it. A cleared target is
      // therefore the observable form of "a row took this".
      await tester.pump();
      expect(highlight.target, isNull);

      // The scroll lands on the next layout.
      await tester.pump();
      expect(onScreen(tester, target.label), isTrue);

      // The pulse ends by itself: the controller is disposed the moment it
      // finishes, so a row the user has searched for once does not keep a
      // ticker for the life of the pane.
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('an unrelated jump leaves every row alone', (tester) async {
      final highlight = SettingsHighlightController();
      addTearDown(highlight.dispose);
      await pumpRows(tester, highlight);
      final before = tester.getRect(
        find.text(SettingsCatalog.clockShowDate.label),
      );

      // A field with no row on this page.
      highlight.jumpTo(SettingsCatalog.lockBlurSigma);
      await tester.pump();
      await tester.pump();

      // Unclaimed, so it is still pending — which is what the category view
      // reads to keep holding its page mounted.
      expect(highlight.claimed, isFalse);
      expect(highlight.target, isNotNull);
      expect(
        tester.getRect(find.text(SettingsCatalog.clockShowDate.label)),
        before,
      );
      // Nothing claimed it, so it expires rather than sitting there holding a
      // category page mounted.
      await tester.pump(kSettingsHighlightTimeout + const Duration(seconds: 1));
      expect(highlight.target, isNull);
    });

    testWidgets('a row outside a settings overlay is unaffected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _chrome(
          child: ListView(
            children: [
              SettingsRow.field(
                SettingsCatalog.clockShowDate,
                control: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Show date'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
