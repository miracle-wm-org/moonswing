import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

/// The host the trigger is measured through — a settings row's worth of width.
const _hostKey = ValueKey('host');
const _hostWidth = 220.0;

List<SettingsDropdownItem<String>> _items(int n) => [
      for (var i = 0; i < n; i++)
        SettingsDropdownItem<String>(value: 'v$i', label: 'Device $i'),
    ];

/// Pumps the control the way a settings pane does: under a ThemeScope, with a
/// root Overlay for the list to float into.
Future<void> pumpDropdown(
  WidgetTester tester, {
  required List<SettingsDropdownItem<String>> items,
  String? selected,
  ValueChanged<String>? onSelected,
  Alignment alignment = Alignment.topLeft,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Align(
                  alignment: alignment,
                  child: SizedBox(
                    key: _hostKey,
                    width: _hostWidth,
                    child: SettingsDropdown<String>(
                      items: items,
                      selected: selected,
                      onSelected: onSelected ?? (_) {},
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Taps the trigger and settles the post-frame scroll-to-selection.
Future<void> openList(WidgetTester tester, {required String on}) async {
  await tester.tap(find.text(on));
  await tester.pump();
  await tester.pump();
}

/// The list is open when an item other than the selected one is on screen —
/// the trigger shows only the selection.
bool _listOpen() => find.text('Device 1').evaluate().isNotEmpty;

/// The effects list's shape: a name and a sentence explaining it.
const _described = <SettingsDropdownItem<String>>[
  SettingsDropdownItem<String>(
    value: 'none',
    label: 'None',
    description: 'The card appears and disappears with no animation.',
  ),
  SettingsDropdownItem<String>(
    value: 'grow',
    label: 'Grow from edge',
    description: 'The card unrolls out of the bar it is anchored to, growing '
        'from the edge they share.',
  ),
];

/// Pumps the control the way a `SettingsRow` does: as an *inflexible* child of
/// a Row, so the trigger shrink-wraps its label and the card cannot borrow the
/// row's width.
Future<void> pumpInRow(
  WidgetTester tester, {
  required List<SettingsDropdownItem<String>> items,
  String? selected,
  ValueChanged<String>? onSelected,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    SettingsDropdown<String>(
                      key: _hostKey,
                      items: items,
                      selected: selected,
                      onSelected: onSelected ?? (_) {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the selection and no list until tapped', (tester) async {
    await pumpDropdown(tester, items: _items(3), selected: 'v0');

    expect(find.text('Device 0'), findsOneWidget);
    expect(_listOpen(), isFalse);

    await openList(tester, on: 'Device 0');

    expect(_listOpen(), isTrue);
    expect(find.text('Device 2'), findsOneWidget);
  });

  testWidgets('a selection no item carries shows an em dash', (tester) async {
    await pumpDropdown(tester, items: _items(3), selected: 'gone');

    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('the list floats: opening does not grow the row',
      (tester) async {
    await pumpDropdown(tester, items: _items(3), selected: 'v0');
    final closed = tester.getRect(find.byKey(_hostKey));

    await openList(tester, on: 'Device 0');

    // The whole point of the change: the card is in the root Overlay, so the
    // pane under the control does not move when it opens.
    expect(tester.getRect(find.byKey(_hostKey)), closed);
  });

  testWidgets('the card is as wide as the trigger', (tester) async {
    await pumpDropdown(tester, items: _items(3), selected: 'v0');
    await openList(tester, on: 'Device 0');

    // The list sits inside the card's 1px border on each side.
    expect(
      tester.getSize(find.byType(ListView)).width,
      moreOrLessEquals(_hostWidth - 2, epsilon: 0.01),
    );
  });

  testWidgets('a short list carries no filter field', (tester) async {
    await pumpDropdown(tester, items: _items(3), selected: 'v0');
    await openList(tester, on: 'Device 0');

    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('a long list carries one, and typing filters', (tester) async {
    await pumpDropdown(tester, items: _items(10), selected: 'v0');
    await openList(tester, on: 'Device 0');

    expect(find.byType(EditableText), findsOneWidget);

    // Not the whole label: the filter field renders what was typed into it,
    // and would be a second match for it.
    await tester.enterText(find.byType(EditableText), '7');
    await tester.pump();

    expect(find.text('Device 7'), findsOneWidget);
    expect(find.text('Device 1'), findsNothing);
  });

  testWidgets('picking a row reports it and closes the list', (tester) async {
    final picked = <String>[];
    await pumpDropdown(
      tester,
      items: _items(3),
      selected: 'v0',
      onSelected: picked.add,
    );
    await openList(tester, on: 'Device 0');

    await tester.tap(find.text('Device 1'));
    await tester.pump();

    expect(picked, ['v1']);
    expect(_listOpen(), isFalse);
  });

  testWidgets('tapping the backdrop dismisses without a change',
      (tester) async {
    final picked = <String>[];
    await pumpDropdown(
      tester,
      items: _items(3),
      selected: 'v0',
      onSelected: picked.add,
    );
    await openList(tester, on: 'Device 0');

    // Bottom-right corner: the full-screen dismiss layer, clear of the card.
    await tester.tapAt(tester
        .getSize(find.byType(Overlay).first)
        .bottomRight(const Offset(-5, -5)));
    await tester.pump();

    expect(_listOpen(), isFalse);
    expect(picked, isEmpty);
  });

  testWidgets('a row keeps its detail tag', (tester) async {
    await pumpDropdown(
      tester,
      items: const [
        SettingsDropdownItem<String>(value: 'a', label: 'Device 0'),
        SettingsDropdownItem<String>(
            value: 'b', label: 'Device 1', detail: 'preferred'),
      ],
      selected: 'a',
    );
    await openList(tester, on: 'Device 0');

    expect(find.text('preferred'), findsOneWidget);
  });

  testWidgets('the trigger opens from every corner of its box',
      (tester) async {
    // The house rule `test/tap_target_test.dart` pins for the shared controls,
    // asserted here because this one cannot go in that table: it needs an Overlay
    // to open into, and once open there is more than one HoverRegion on screen.
    // Each corner is taken on its own and dismissed after.
    await pumpDropdown(tester, items: _items(3), selected: 'v0');
    final box = tester.getRect(find.byKey(_hostKey));
    final away = tester
        .getSize(find.byType(Overlay).first)
        .bottomRight(const Offset(-5, -5));

    for (final corner in <Offset>[
      box.topLeft + const Offset(2, 2),
      box.topRight + const Offset(-2, 2),
      box.bottomLeft + const Offset(2, -2),
      box.bottomRight + const Offset(-2, -2),
    ]) {
      await tester.tapAt(corner);
      await tester.pump();
      await tester.pump();
      expect(_listOpen(), isTrue, reason: 'dead corner at $corner');

      await tester.tapAt(away);
      await tester.pump();
    }
  });

  testWidgets('with no room below, the card opens upwards', (tester) async {
    await pumpDropdown(
      tester,
      items: _items(3),
      selected: 'v0',
      alignment: Alignment.bottomLeft,
    );
    await openList(tester, on: 'Device 0');

    expect(
      tester.getTopLeft(find.byType(ListView)).dy,
      lessThan(tester.getTopLeft(find.byKey(_hostKey)).dy),
    );
  });

  testWidgets('an unbounded slot shrink-wraps rather than throwing',
      (tester) async {
    // What a `SettingsRow` gives its control: an inflexible child of a Row, which
    // `RenderFlex` lays out with an unbounded main axis. An `Expanded` inside that
    // throws from `performLayout` — an error `RenderObject.layout` catches,
    // leaving the subtree mounted but never laid out, which the settings pane saw
    // as a semantics assertion and a hit-test failure per pointer event.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => Row(
                    children: [
                      const Expanded(child: SizedBox()),
                      SettingsDropdown<String>(
                        key: _hostKey,
                        items: _items(3),
                        selected: 'v0',
                        onSelected: (_) {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    // Sized to its content rather than to the screen, and still tappable —
    // the hit test is what an unlaid-out subtree loses.
    final trigger = tester.getSize(find.byKey(_hostKey));
    expect(trigger.width, greaterThan(0));
    final overlay = tester.getSize(find.byType(Overlay)).width;
    expect(trigger.width, lessThan(overlay));

    await openList(tester, on: 'Device 0');
    expect(_listOpen(), isTrue);
  });
  group('a described list', () {
    testWidgets("takes its own width rather than the trigger's", (tester) async {
      await pumpInRow(tester, items: _described, selected: 'none');
      final trigger = tester.getRect(find.byKey(_hostKey));

      await openList(tester, on: 'None');

      final card = tester.getRect(find.byType(ListView));
      // The defect: a card matched to a trigger showing "None" is a card a
      // sentence cannot be read in.
      expect(card.width, greaterThan(trigger.width));
      // It grows leftwards from the trigger's right edge, which in a settings
      // row is where the pane's width is — rightwards there is nothing but the
      // edge of the panel. (The list sits inside the card's 1px border.)
      expect(card.right, moreOrLessEquals(trigger.right - 1, epsilon: 1.0));
      expect(card.left, lessThan(trigger.left));
    });

    testWidgets('carries every sentence, and overflows nothing',
        (tester) async {
      await pumpInRow(tester, items: _described, selected: 'none');
      await openList(tester, on: 'None');

      for (final item in _described) {
        expect(find.text(item.description!), findsOneWidget);
      }
      // A sentence in the `detail` slot is laid out unflexed beside an
      // `Expanded` label: it takes the whole row, leaves the label no width,
      // and overflows the card it is drawn in. A `description` wraps, into a
      // row whose extent was measured to hold it.
      expect(tester.takeException(), isNull);
      expect(find.text('None'), findsWidgets);
      expect(find.text('Grow from edge'), findsOneWidget);
    });

    testWidgets('sizes its rows to the prose, not to a name', (tester) async {
      await pumpInRow(tester, items: _described, selected: 'none');
      await openList(tester, on: 'None');

      final row = tester.getSize(
        find.ancestor(
          of: find.text(_described.last.description!),
          matching: find.byType(HoverRegion),
        ),
      );
      // The 34px a label alone needs, which is what an undescribed list uses.
      expect(row.height, greaterThan(34));
    });

    testWidgets('picking a row still reports it', (tester) async {
      final picked = <String>[];
      await pumpInRow(
        tester,
        items: _described,
        selected: 'none',
        onSelected: picked.add,
      );
      await openList(tester, on: 'None');

      await tester.tap(find.text('Grow from edge'));
      await tester.pump();

      expect(picked, ['grow']);
    });
  });

  group('describedDropdownRowHeight', () {
    const labelStyle = TextStyle(fontSize: 13);
    const descriptionStyle = TextStyle(fontSize: 11);
    const long = 'The card unrolls out of the bar it is anchored to, growing '
        'from the edge they share.';

    double heightOf(
      List<String> descriptions, {
      double width = 200,
      TextScaler scaler = TextScaler.noScaling,
    }) =>
        describedDropdownRowHeight(
          descriptions: descriptions,
          contentWidth: width,
          labelStyle: labelStyle,
          descriptionStyle: descriptionStyle,
          textScaler: scaler,
        );

    // testWidgets rather than test: laying text out needs the binding, and
    // this file's other cases are the only thing that would have initialized
    // it. Nothing is pumped.
    testWidgets('grows as the prose wraps to more lines', (tester) async {
      expect(heightOf([long], width: 120),
          greaterThan(heightOf([long], width: 600)));
    });

    testWidgets('answers for the tallest description, not the first',
        (tester) async {
      expect(heightOf(['Short.', long]), heightOf([long]));
      expect(heightOf(['Short.', long]),
          greaterThan(heightOf(['Short.'])));
    });

    testWidgets("follows the theme's font size through the scaler",
        (tester) async {
      // A row extent measured in the platform default is a measurement of a
      // different card: `font_size` scales the whole ShellFontSizes ladder.
      expect(
        heightOf([long], scaler: const TextScaler.linear(1.6)),
        greaterThan(heightOf([long])),
      );
    });
  });
}
