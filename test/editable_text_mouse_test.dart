import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/editable_text_mouse.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

void main() {
  group('lineAround', () {
    test('is the line holding the offset, without its break', () {
      const text = 'one\ntwo three\nfour';
      expect(
        lineAround(text, 6),
        const TextSelection(baseOffset: 4, extentOffset: 13),
      );
      expect(
        lineAround(text, 0),
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      expect(
        lineAround(text, 3),
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      expect(
        lineAround(text, text.length),
        const TextSelection(baseOffset: 14, extentOffset: 18),
      );
    });

    test('an empty line is an empty selection on it', () {
      expect(
        lineAround('a\n\nb', 2),
        const TextSelection(baseOffset: 2, extentOffset: 2),
      );
      expect(
        lineAround('', 0),
        const TextSelection(baseOffset: 0, extentOffset: 0),
      );
    });
  });

  group('a SettingsTextField under the mouse', () {
    late TextEditingController controller;

    setUp(() => controller = TextEditingController());
    tearDown(() => controller.dispose());

    Future<void> pump(
      WidgetTester tester,
      String text, {
      int? maxLines = 1,
    }) async {
      controller.text = text;
      await tester.pumpWidget(
        ThemeScope(
          theme: const ThemeConfig(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextEditingShortcuts(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  child: SettingsTextField(
                    controller: controller,
                    maxLines: maxLines,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// Where the [offset]th character of the field starts, on screen.
    Offset charAt(WidgetTester tester, int offset) {
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
      return editable.localToGlobal(caret.center + const Offset(1, 0));
    }

    Future<void> click(WidgetTester tester, Offset at, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        final gesture = await tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('a drag selects what it crosses', (tester) async {
      await pump(tester, 'hello brave world');
      final gesture = await tester.startGesture(
        charAt(tester, 6),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(charAt(tester, 9));
      await tester.pump();
      await gesture.moveTo(charAt(tester, 11));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 6, extentOffset: 11),
      );
      expect(controller.selection.textInside(controller.text), 'brave');
      expect(
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .widget
            .focusNode
            .hasFocus,
        isTrue,
      );
    });

    testWidgets('a click places the caret, Shift+click extends from it', (
      tester,
    ) async {
      await pump(tester, 'hello brave world');
      await click(tester, charAt(tester, 2));
      expect(controller.selection, const TextSelection.collapsed(offset: 2));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await click(tester, charAt(tester, 8));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 8),
      );
    });

    testWidgets('a double click selects the word', (tester) async {
      await pump(tester, 'hello brave world');
      await click(tester, charAt(tester, 8), times: 2);
      expect(controller.selection.textInside(controller.text), 'brave');
    });

    testWidgets('a triple click selects the line of a multi-line field', (
      tester,
    ) async {
      await pump(tester, 'first line\nsecond line\nthird', maxLines: 4);
      await click(tester, charAt(tester, 14), times: 3);
      expect(controller.selection.textInside(controller.text), 'second line');
    });

    testWidgets('a triple click selects all of a one-line field', (
      tester,
    ) async {
      await pump(tester, 'hello brave world');
      await click(tester, charAt(tester, 8), times: 3);
      expect(
        controller.selection.textInside(controller.text),
        'hello brave world',
      );
    });
  });
}
