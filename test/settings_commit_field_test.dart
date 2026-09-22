import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

/// Pumps [field] beside a second focusable field, so focus has somewhere to go.
Future<void> pump(WidgetTester tester, Widget field) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: const ThemeConfig(),
          // EditableText needs an Overlay for its selection handles.
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      field,
                      const SizedBox(height: 40),
                      SettingsTextField(onChanged: (_) {}),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a number field reports nothing until Enter', (tester) async {
    final reported = <num>[];
    await pump(
      tester,
      SettingsNumberField(value: 32, isInt: true, onChanged: reported.add),
    );

    final field = find.byType(EditableText).first;
    await tester.tap(field);
    await tester.enterText(field, '2');
    await tester.enterText(field, '24');
    await tester.pump();
    expect(reported, isEmpty);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(reported, [24]);
  });

  testWidgets('focus moving away commits, once', (tester) async {
    final reported = <String>[];
    await pump(
      tester,
      SettingsCommitField(initial: 'foot', onCommitted: reported.add),
    );

    final field = find.byType(EditableText).first;
    await tester.tap(field);
    await tester.enterText(field, 'kitty');
    await tester.pump();
    expect(reported, isEmpty);

    await tester.tap(find.byType(EditableText).last);
    await tester.pump();
    expect(reported, ['kitty']);

    // Back and away again with nothing typed: not a second commit.
    await tester.tap(field);
    await tester.pump();
    await tester.tap(find.byType(EditableText).last);
    await tester.pump();
    expect(reported, ['kitty']);
  });

  testWidgets('a click outside the field commits', (tester) async {
    final reported = <String>[];
    await pump(
      tester,
      SettingsCommitField(initial: 'a', onCommitted: reported.add),
    );

    final field = find.byType(EditableText).first;
    await tester.tap(field);
    await tester.enterText(field, 'b');
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();
    expect(reported, ['b']);
  });

  testWidgets('an unparseable number reverts instead of committing', (
    tester,
  ) async {
    final reported = <num>[];
    await pump(
      tester,
      SettingsNumberField(
        value: 4,
        isInt: true,
        allowNegative: true,
        onChanged: reported.add,
      ),
    );

    final field = find.byType(EditableText).first;
    await tester.tap(field);
    await tester.enterText(field, '-');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(reported, isEmpty);
    expect(tester.widget<EditableText>(field).controller.text, '4');
  });

  testWidgets('an unfocused field follows its value', (tester) async {
    final value = ValueNotifier<String>('one');
    await pump(
      tester,
      ValueListenableBuilder<String>(
        valueListenable: value,
        builder: (_, v, _) =>
            SettingsCommitField(initial: v, onCommitted: (_) {}),
      ),
    );

    value.value = 'two';
    await tester.pump();
    final field = find.byType(EditableText).first;
    expect(tester.widget<EditableText>(field).controller.text, 'two');
  });
}
