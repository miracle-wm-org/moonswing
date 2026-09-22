import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

const _fonts = ['Cantarell', 'JetBrains Mono', 'Ubuntu Sans'];

/// Pumps the field the way the settings pane does: under a ThemeScope, with a
/// root Overlay for the list to float into.
///
/// Returns the notifier driving `value`. An Overlay reads `initialEntries` only
/// on its first build, so a second `pumpWidget` would never reach the field —
/// a test that changes the family has to push it through here.
Future<ValueNotifier<String>> pumpField(
  WidgetTester tester, {
  required String value,
  required ValueChanged<String> onChanged,
  bool locked = false,
  VoidCallback? onLockedTap,
  List<String> fonts = _fonts,
}) async {
  final selected = ValueNotifier<String>(value);
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
                  alignment: Alignment.topLeft,
                  child: ValueListenableBuilder<String>(
                    valueListenable: selected,
                    builder: (_, v, _) => SettingsFontField(
                      value: v,
                      fonts: fonts,
                      locked: locked,
                      onLockedTap: onLockedTap,
                      onChanged: onChanged,
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
  return selected;
}

/// Taps the trigger and settles the post-frame scroll-to-selection.
Future<void> openList(WidgetTester tester, {String on = 'Ubuntu Sans'}) async {
  await tester.tap(find.text(on));
  await tester.pump();
  await tester.pump();
}

/// The list is open when a family other than the selected one is on screen —
/// the trigger shows only the selection.
bool _listOpen() => find.text('JetBrains Mono').evaluate().isNotEmpty;

void main() {
  testWidgets('shows the current family and no list until tapped',
      (tester) async {
    await pumpField(tester, value: 'Ubuntu Sans', onChanged: (_) {});

    expect(find.text('Ubuntu Sans'), findsOneWidget);
    expect(_listOpen(), isFalse);

    await openList(tester);

    expect(_listOpen(), isTrue);
    expect(find.text('Cantarell'), findsOneWidget);
  });

  testWidgets('typing filters the list', (tester) async {
    await pumpField(tester, value: 'Ubuntu Sans', onChanged: (_) {});
    await openList(tester);

    await tester.enterText(find.byType(EditableText).first, 'mono');
    await tester.pump();

    expect(find.text('JetBrains Mono'), findsOneWidget);
    expect(find.text('Cantarell'), findsNothing);
  });

  testWidgets('a non-matching filter says so rather than showing nothing',
      (tester) async {
    await pumpField(tester, value: 'Ubuntu Sans', onChanged: (_) {});
    await openList(tester);

    await tester.enterText(find.byType(EditableText).first, 'zzzz');
    await tester.pump();

    expect(find.text('No matching font'), findsOneWidget);
  });

  testWidgets('picking a row reports it and closes the list', (tester) async {
    final picked = <String>[];
    await pumpField(
      tester,
      value: 'Ubuntu Sans',
      onChanged: picked.add,
    );
    await openList(tester);

    await tester.tap(find.text('JetBrains Mono'));
    await tester.pump();

    expect(picked, ['JetBrains Mono']);
    expect(_listOpen(), isFalse);
  });

  testWidgets('tapping the backdrop dismisses without a change',
      (tester) async {
    final picked = <String>[];
    await pumpField(tester, value: 'Ubuntu Sans', onChanged: picked.add);
    await openList(tester);

    // Bottom-right corner: the full-screen dismiss layer, clear of the popup.
    await tester.tapAt(tester.getSize(find.byType(Overlay).first).bottomRight(
          const Offset(-5, -5),
        ));
    await tester.pump();

    expect(_listOpen(), isFalse);
    expect(picked, isEmpty);
  });

  testWidgets('locked routes the tap to onLockedTap and opens nothing',
      (tester) async {
    var duplicated = 0;
    final picked = <String>[];
    await pumpField(
      tester,
      value: 'Ubuntu Sans',
      locked: true,
      onLockedTap: () => duplicated++,
      onChanged: picked.add,
    );

    await tester.tap(find.text('Ubuntu Sans'));
    await tester.pump();

    expect(duplicated, 1);
    expect(_listOpen(), isFalse);
    expect(picked, isEmpty);
  });

  testWidgets('a theme switch closes an open list', (tester) async {
    final selected =
        await pumpField(tester, value: 'Ubuntu Sans', onChanged: (_) {});
    await openList(tester);
    expect(_listOpen(), isTrue);

    // The new theme's family arrives under the open list.
    selected.value = 'Cantarell';
    await tester.pump();
    // OverlayEntry.remove() called from didUpdateWidget lands after the frame.
    await tester.pump();

    expect(_listOpen(), isFalse);
    expect(find.text('Cantarell'), findsOneWidget);
  });

  testWidgets('renders each row in its own family', (tester) async {
    await pumpField(tester, value: 'Ubuntu Sans', onChanged: (_) {});
    await openList(tester);

    final row = tester.widget<Text>(find.text('JetBrains Mono'));
    expect(row.style?.fontFamily, 'JetBrains Mono');
  });
}
