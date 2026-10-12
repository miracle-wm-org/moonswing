// Keyboard movement between the settings fields: Tab and Shift+Tab, which no
// WidgetsApp supplies here, and Ctrl+A inside a field.
//
// Pumped under the chrome the settings overlay gives its panes —
// `DefaultTextEditingShortcuts` and `TabFocusTraversal` over an `Overlay` — on
// Linux, since the editing shortcuts are chosen per platform.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_search_bar.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/tab_focus_traversal.dart';

final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

Future<void> _pump(WidgetTester tester, List<Widget> fields) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextEditingShortcuts(
        child: TabFocusTraversal(
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 14),
            child: ThemeScope(
              theme: const ThemeConfig(),
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => Align(
                      alignment: Alignment.topLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final field in fields)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: field,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

EditableTextState _field(WidgetTester tester, int index) =>
    tester.state<EditableTextState>(find.byType(EditableText).at(index));

bool _focused(WidgetTester tester, int index) =>
    _field(tester, index).widget.focusNode.hasPrimaryFocus;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Future<void> _withHeld(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  testWidgets('Tab and Shift+Tab walk the fields in order', variant: _linux, (
    tester,
  ) async {
    await _pump(tester, [
      SettingsCommitField(initial: 'foot', onCommitted: (_) {}),
      SettingsNumberField(value: 32, isInt: true, onChanged: (_) {}),
      SettingsTextField(initial: 'third', onChanged: (_) {}),
    ]);

    await tester.tap(find.byType(EditableText).first);
    await tester.pump();
    expect(_focused(tester, 0), isTrue);

    await _press(tester, LogicalKeyboardKey.tab);
    expect(_focused(tester, 1), isTrue);
    await _press(tester, LogicalKeyboardKey.tab);
    expect(_focused(tester, 2), isTrue);

    await _withHeld(
      tester,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.tab,
    );
    expect(_focused(tester, 1), isTrue);
    await _withHeld(
      tester,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.tab,
    );
    expect(_focused(tester, 0), isTrue);
  });

  testWidgets('a field tabbed into has its text selected', variant: _linux, (
    tester,
  ) async {
    await _pump(tester, [
      SettingsCommitField(initial: 'foot', onCommitted: (_) {}),
      SettingsNumberField(value: 32, isInt: true, onChanged: (_) {}),
    ]);

    await tester.tap(find.byType(EditableText).first);
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.tab);

    // Typing replaces the number rather than appending to it.
    expect(
      _field(tester, 1).textEditingValue.selection,
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
  });

  testWidgets('tabbing out of a field commits it', variant: _linux, (
    tester,
  ) async {
    final reported = <String>[];
    await _pump(tester, [
      SettingsCommitField(initial: 'foot', onCommitted: reported.add),
      SettingsTextField(onChanged: (_) {}),
    ]);

    final field = find.byType(EditableText).first;
    await tester.tap(field);
    await tester.enterText(field, 'kitty');
    await tester.pump();
    expect(reported, isEmpty);

    await _press(tester, LogicalKeyboardKey.tab);
    expect(reported, ['kitty']);
  });

  testWidgets(
    'Ctrl+A selects everything in a settings field',
    variant: _linux,
    (tester) async {
      await _pump(tester, [
        SettingsCommitField(initial: 'alacritty', onCommitted: (_) {}),
        SettingsNumberField(value: 1280, isInt: true, onChanged: (_) {}),
      ]);

      for (final (index, length) in [(0, 9), (1, 4)]) {
        await tester.tap(find.byType(EditableText).at(index));
        await tester.pump();
        // Collapse whatever focusing selected, so the shortcut has work to do.
        _field(tester, index).userUpdateTextEditingValue(
          _field(tester, index).textEditingValue.copyWith(
            selection: const TextSelection.collapsed(offset: 1),
          ),
          SelectionChangedCause.tap,
        );
        await tester.pump();

        await _withHeld(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.keyA,
        );
        expect(
          _field(tester, index).textEditingValue.selection,
          TextSelection(baseOffset: 0, extentOffset: length),
        );
      }
    },
  );

  testWidgets('the search bar is one Tab stop, not two', variant: _linux, (
    tester,
  ) async {
    final search = FocusNode();
    addTearDown(search.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextEditingShortcuts(
          child: TabFocusTraversal(
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 14),
              child: ThemeScope(
                theme: const ThemeConfig(),
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 200,
                            width: 300,
                            child: SettingsTextField(onChanged: (_) {}),
                          ),
                          Positioned.fill(
                            child: SettingsSearchBar(
                              focusNode: search,
                              onJump: (_) {},
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    search.requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.tab);
    // The pane's field, not the key listener wrapped around the search field.
    expect(_focused(tester, 0), isTrue);
    expect(search.hasPrimaryFocus, isFalse);

    await _press(tester, LogicalKeyboardKey.tab);
    expect(search.hasPrimaryFocus, isTrue);
  });
}
