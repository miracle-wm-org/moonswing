import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miracle/miracle.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/keybinds/keybind_cheatsheet_controller.dart';
import 'package:graceful_shell/keybinds/keybind_cheatsheet_overlay.dart';
import 'package:graceful_shell/keybinds/keybind_store.dart';
import 'package:graceful_shell/modules/keybinds.dart';
import 'package:graceful_shell/scopes.dart';

Keybind _bind({
  BuiltInKeyCommand? action,
  String? command,
  List<Modifier> modifiers = const [Modifier.meta],
  String key = 'x',
}) => Keybind(
  action: action,
  actionName: action?.wireName,
  command: command,
  keyboardAction: KeyboardAction.down,
  modifiers: KeybindModifiers(
    modifiers: modifiers,
    mask: modifiers.fold(0, (mask, modifier) => mask | modifier.value),
  ),
  configuredModifiers: modifiers,
  xkbKeysym: 0,
  xkbKeysymName: key,
);

final _keybinds = KeybindsResult(
  primaryModifier: KeybindModifiers(
    modifiers: const [Modifier.meta],
    mask: Modifier.meta.value,
  ),
  keybinds: [
    _bind(action: BuiltInKeyCommand.quitActiveWindow, key: 'q'),
    _bind(action: BuiltInKeyCommand.selectWorkspace1, key: '1'),
    _bind(command: 'ptyxis', key: 'Return'),
  ],
);

/// A source with no socket behind it, which is the whole reason
/// [KeybindSource] is an interface.
class FakeKeybindSource implements KeybindSource {
  FakeKeybindSource({this.result, this.failure});

  KeybindsResult? result;
  String? failure;
  int reads = 0;

  @override
  Future<KeybindsResult> read() async {
    reads++;
    final message = failure;
    if (message != null) throw KeybindUnavailable(message);
    return result!;
  }
}

void main() {
  group('the store', () {
    test('the first lease reads, and a later one does not read again', () async {
      final source = FakeKeybindSource(result: _keybinds);
      final store = KeybindStore.forTesting(source: source);

      store.acquire();
      // Nothing synchronous: `acquire` runs inside a widget's `initState`.
      expect(store.status, KeybindStatus.loading);
      await Future<void>.delayed(Duration.zero);

      expect(store.status, KeybindStatus.ready);
      expect(store.result, same(_keybinds));
      expect(source.reads, 1);

      store.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(source.reads, 1, reason: 'the second lease rides the first');
    });

    /// Miracle re-reads its configuration on `reload_config` and the sheet
    /// exists to answer what a key does *now*, so a reopen is a re-read.
    test('reopening after the last release reads again', () async {
      final source = FakeKeybindSource(result: _keybinds);
      final store = KeybindStore.forTesting(source: source);

      store.acquire();
      await Future<void>.delayed(Duration.zero);
      store.release();
      expect(store.leaseCount, 0);

      store.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(source.reads, 2);
    });

    test('a failure is a visible reason, and the last good list survives it',
        () async {
      final source = FakeKeybindSource(result: _keybinds);
      final store = KeybindStore.forTesting(source: source);

      store.acquire();
      await Future<void>.delayed(Duration.zero);
      store.release();

      source.failure = 'Miracle is not running.';
      store.acquire();
      await Future<void>.delayed(Duration.zero);

      expect(store.status, KeybindStatus.unavailable);
      expect(store.error, 'Miracle is not running.');
      // An empty sheet would be indistinguishable from a machine with no
      // bindings at all; the last good answer stays on screen behind the
      // reason.
      expect(store.result, same(_keybinds));
    });

    test('retry clears the reason once it lands', () async {
      final source = FakeKeybindSource(failure: 'no socket');
      final store = KeybindStore.forTesting(source: source);

      store.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(store.error, 'no socket');

      source
        ..failure = null
        ..result = _keybinds;
      await store.retry();

      expect(store.error, isEmpty);
      expect(store.status, KeybindStatus.ready);
    });

    /// A module built alone, with no `main()` behind it to `bind` the store: a
    /// stated reason, never a silently empty sheet.
    test('an unbound store says so rather than showing nothing', () async {
      final store = KeybindStore.forTesting();
      store.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(store.status, KeybindStatus.unavailable);
      expect(store.error, isNotEmpty);
    });
  });

  group('the sheet', () {
    late ValueNotifier<bool> closing;
    late int closed;

    setUp(() {
      closing = ValueNotifier(false);
      closed = 0;
    });

    tearDown(() => closing.dispose());

    Future<KeybindStore> pump(
      WidgetTester tester, {
      KeybindStore? store,
    }) async {
      final resolved =
          store ??
          KeybindStore.forTesting(source: FakeKeybindSource(result: _keybinds));
      await tester.pumpWidget(
        ThemeScope(
          theme: const ThemeConfig(),
          child: Center(
            child: SizedBox(
              width: 1000,
              height: 700,
              child: KeybindCheatsheetOverlay(
                closingNotifier: closing,
                onClosed: () => closed++,
                store: resolved,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return resolved;
    }

    testWidgets('draws every binding under its own section', (tester) async {
      await pump(tester);

      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(find.text('WINDOWS'), findsOneWidget);
      expect(find.text('WORKSPACES'), findsOneWidget);
      expect(find.text('APPLICATIONS & COMMANDS'), findsOneWidget);
      expect(find.text('Close the focused window'), findsOneWidget);
      expect(find.text('Go to workspace 1'), findsOneWidget);
      expect(find.text('ptyxis'), findsOneWidget);
    });

    testWidgets('draws the keys as caps', (tester) async {
      await pump(tester);
      // Two rows carry Super, and the header names it as the Action Key.
      expect(find.text('Super'), findsNWidgets(4));
      expect(find.text('Q'), findsOneWidget);
      expect(find.text('Action Key'), findsOneWidget);
      // Enter is drawn as its glyph, so its label is not on screen.
      expect(find.text('Enter'), findsNothing);
      expect(find.byType(KeyCapChip), findsWidgets);
    });

    testWidgets('Escape plays the exit and hands the window back',
        (tester) async {
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('a click on the backdrop closes it', (tester) async {
      await pump(tester);
      // No input-region support means this surface eats every click on the
      // output; the backdrop is a mouse-only user's way out.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('a click on the card does not', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Close the focused window'));
      await tester.pumpAndSettle();
      expect(closed, 0);
    });

    testWidgets('shows why it is empty, and offers to ask again',
        (tester) async {
      final source = FakeKeybindSource(failure: 'Miracle is not running.');
      final store = KeybindStore.forTesting(source: source);
      await pump(tester, store: store);

      expect(find.text('Could not read the key bindings'), findsOneWidget);
      expect(find.text('Miracle is not running.'), findsOneWidget);

      source
        ..failure = null
        ..result = _keybinds;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(source.reads, 2);
      expect(find.text('Close the focused window'), findsOneWidget);
    });

    testWidgets('releases its lease when the window goes', (tester) async {
      final store = await pump(tester);
      expect(store.leaseCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(store.leaseCount, 0);
    });

    testWidgets('nothing animates once it has settled', (tester) async {
      await pump(tester);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('the bar module', () {
    testWidgets('the keyboard icon asks the root for the sheet',
        (tester) async {
      final controller = KeybindCheatsheetController.forTesting();
      var signals = 0;
      controller.addListener(() => signals++);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ThemeScope(
          theme: const ThemeConfig(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: KeybindsButton(controller: controller)),
          ),
        ),
      );

      // The corner, not the centre: a tap target that only answers over its
      // glyph passes a centre tap and fails a real one.
      final box = tester.getRect(find.byType(KeybindsButton));
      await tester.tapAt(box.topLeft + const Offset(1, 1));
      await tester.pump();

      expect(signals, 1);
    });
  });
}
