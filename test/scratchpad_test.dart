import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miracle/miracle.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/input_trigger/keysym.dart';
import 'package:moonswing/keybinds/shell_keybinds.dart';
import 'package:moonswing/modules/scratchpad.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/scratchpad/scratchpad_store.dart';

import 'tap_target.dart';

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: const ThemeConfig(),
        child: Center(child: child),
      ),
    );

void main() {
  group('ScratchpadStore', () {
    test('sends miracle\'s own two commands', () async {
      final sent = <String>[];
      final store = ScratchpadStore.forTesting(
        (command) async => sent.add(command.toCommandString()),
      );

      await store.toggle();
      await store.moveFocusedWindow();

      expect(sent, ['scratchpad show', 'move scratchpad']);
      expect(store.error, isNull);
    });

    test('a failure is recorded, and the next success clears it', () async {
      var fail = true;
      final store = ScratchpadStore.forTesting((command) async {
        if (fail) throw MiracleConnectionException('the socket closed');
      });
      var notifications = 0;
      store.addListener(() => notifications++);

      await store.toggle();
      expect(store.error, 'the socket closed');
      expect(notifications, 1);

      // The same failure again is nothing new to draw.
      await store.toggle();
      expect(notifications, 1);

      fail = false;
      await store.toggle();
      expect(store.error, isNull);
      expect(notifications, 2);

      // Nor is a success after a success.
      await store.moveFocusedWindow();
      expect(notifications, 2);
    });

    test('miracle\'s own refusal is what the label says', () async {
      final store = ScratchpadStore.forTesting((command) async {
        throw MiracleCommandException(command.toCommandString(), [
          CommandResult(success: false, error: 'No such window'),
        ]);
      });
      await store.moveFocusedWindow();
      expect(store.error, 'No such window');
    });
  });

  group('the hover label', () {
    test('names both shortcuts the shell registered', () {
      final text = scratchpadTooltip(const ShortcutsConfig());
      expect(text, contains('Super + Z  show or hide'));
      expect(
        text,
        contains('Shift + Super + Z  move the focused window here'),
      );
    });

    test('follows a rebinding, says when one is off, and carries the error',
        () {
      final text = scratchpadTooltip(
        ShortcutsConfig.fromMap({
          'toggle_scratchpad': 'super+grave',
          'move_to_scratchpad': '',
        }),
        error: 'the socket closed',
      );
      final grave = shortcutLabel(parseShortcut('super+grave')!);
      expect(text, contains('$grave  show or hide'));
      expect(text, contains('Disabled  move the focused window here'));
      expect(text.split('\n').last, 'the socket closed');
    });
  });

  testWidgets('a click on the button is one toggle, from any corner',
      (tester) async {
    final sent = <String>[];
    final store = ScratchpadStore.forTesting(
      (command) async => sent.add(command.toCommandString()),
    );
    await tester.pumpWidget(_host(ScratchpadButton(
      store: store,
      shortcuts: const ShortcutsConfig(),
    )));

    await tapEveryCorner(tester, find.byType(ScratchpadButton));

    expect(sent, List.filled(4, 'scratchpad show'));
  });
}
