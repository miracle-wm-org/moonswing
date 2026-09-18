import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:miracle/miracle.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/input_trigger/keysym.dart';
import 'package:graceful_shell/keybinds/keybind_cheatsheet_controller.dart';
import 'package:graceful_shell/keybinds/keybind_cheatsheet_overlay.dart';
import 'package:graceful_shell/keybinds/keybind_store.dart';
import 'package:graceful_shell/keybinds/shell_keybind_store.dart';
import 'package:graceful_shell/keybinds/shell_keybinds.dart';
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

/// Font Awesome icons are [FaIconData], which `find.byIcon` cannot take; the
/// plain [IconData] inside one is what reaches the widget tree.
Finder _faIcon(FaIconData icon) => find.byIcon(icon.data);

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
      ShellKeybindStore? shellStore,
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
                // Unbound unless a test asks otherwise: the sheet then draws
                // the shell's own rows on their defaults and offers no
                // editing, which is what a widget test with no config file
                // behind it has to get.
                shellStore: shellStore ?? ShellKeybindStore.forTesting(),
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
      // Every compositor row in the fixture carries Super, the header names it
      // as the Action Key, and five of the shell's own defaults are on it too
      // — the launcher, settings, the notification panel, the power menu
      // and the recorder.
      expect(find.text('Super'), findsNWidgets(9));
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

  group("the shell's own shortcuts", () {
    late ValueNotifier<bool> closing;
    late Directory tempDir;
    late String path;

    // Synchronously, deliberately: a widget test's fake clock does not complete
    // real asynchronous file I/O, and an `await` here hangs the whole file
    // rather than failing it.
    setUp(() {
      closing = ValueNotifier(false);
      tempDir = Directory.systemTemp.createTempSync('gs_sheet_shortcuts');
      path = '${tempDir.path}/config.toml';
      File(path).writeAsStringSync('theme = "dracula"\n');
    });

    tearDown(() {
      closing.dispose();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    /// The sheet with a shell store that has no config file behind it — the
    /// read-only shape, and the one a widget test gets by default.
    Future<void> pumpReadOnly(WidgetTester tester) async {
      final shellStore = ShellKeybindStore.forTesting();
      addTearDown(shellStore.dispose);
      await tester.pumpWidget(
        ThemeScope(
          theme: const ThemeConfig(),
          child: Center(
            child: SizedBox(
              width: 1000,
              height: 700,
              child: KeybindCheatsheetOverlay(
                closingNotifier: closing,
                onClosed: () {},
                store: KeybindStore.forTesting(
                  source: FakeKeybindSource(result: _keybinds),
                ),
                shellStore: shellStore,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The sheet over a real config file, so an edit goes the whole way.
    Future<ShellKeybindStore> pumpEditable(WidgetTester tester) async {
      // Through `runAsync`: loading the store is real file I/O, and a widget
      // test's fake clock never completes one.
      final config = (await tester.runAsync(() => ConfigStore.loadFrom(path)))!;
      addTearDown(config.dispose);
      final shellStore = ShellKeybindStore.forTesting(config: config);
      addTearDown(shellStore.dispose);
      await tester.pumpWidget(
        ThemeScope(
          theme: const ThemeConfig(),
          child: Center(
            child: SizedBox(
              width: 1000,
              height: 700,
              child: KeybindCheatsheetOverlay(
                closingNotifier: closing,
                onClosed: () {},
                store: KeybindStore.forTesting(
                  source: FakeKeybindSource(result: _keybinds),
                ),
                shellStore: shellStore,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return shellStore;
    }

    /// Past [ConfigStore]'s save debounce. The write is the point of the
    /// editor, and a widget test that ends with one still queued fails on the
    /// timer it left behind.
    Future<void> letTheWriteLand(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 1));

    /// Clicks a row and presses Ctrl+Shift+J into it.
    Future<void> rebind(WidgetTester tester, String row) async {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await letTheWriteLand(tester);
    }

    testWidgets('are listed beside the compositor\'s, with their own heading',
        (tester) async {
      await pumpReadOnly(tester);

      expect(find.text('SHELL'), findsOneWidget);
      expect(find.text('Open the application launcher'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Open the emoji picker'), findsOneWidget);
      expect(find.text('Open the notification panel'), findsOneWidget);
      expect(find.text('Screenshot an area'), findsOneWidget);
      expect(find.text('Record the current screen'), findsOneWidget);
      expect(find.text('The power button'), findsOneWidget);
      // Drawn as caps, exactly as the compositor's rows are: Print is the
      // screenshot shortcut's default and Super+Print the recorder's.
      expect(find.text('Print'), findsNWidgets(2));
      // And Ctrl is the emoji picker's alone — every other default is on
      // Super, which is what a cap count notices and a row label does not.
      expect(find.text('Ctrl'), findsOneWidget);
      // And the compositor's own bindings are still there, under theirs.
      expect(find.text('Close the focused window'), findsOneWidget);
    });

    testWidgets('a click and a combination rebinds one', (tester) async {
      final store = await pumpEditable(tester);
      await rebind(tester, 'Open the emoji picker');

      expect(
        store.specFor(ShellShortcut.openEmoji),
        parseShortcut('ctrl+shift+j'),
      );
      expect(find.text('J'), findsOneWidget);
      // Registration latches at start-up, so the row says what it is waiting
      // for rather than pretending the keyboard has changed.
      expect(find.text('Takes effect when the shell restarts'), findsOneWidget);
      expect(find.textContaining('Restart the shell'), findsOneWidget);
    });

    testWidgets('the row says it is listening, and Escape only stops that',
        (tester) async {
      final store = await pumpEditable(tester);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(find.text('Press keys…'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // The sheet is still up: while a row is listening, Escape is the way out
      // of the capture, not out of the sheet.
      expect(find.text('Press keys…'), findsNothing);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(store.specFor(ShellShortcut.openSettings), kDefaultOpenSettings);
      expect(closing.value, isFalse);

      // And once nothing is listening, Escape closes it again.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(closing.value, isTrue);
    });

    testWidgets('Backspace switches one off, and it can be switched back on',
        (tester) async {
      final store = await pumpEditable(tester);
      await tester.tap(find.text('Open the emoji picker'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      await letTheWriteLand(tester);

      expect(store.specFor(ShellShortcut.openEmoji), isNull);
      // The row stays — it is where the shortcut is turned back on.
      expect(find.text('Disabled'), findsOneWidget);

      await rebind(tester, 'Open the emoji picker');
      expect(
        store.specFor(ShellShortcut.openEmoji),
        parseShortcut('ctrl+shift+j'),
      );
    });

    testWidgets('two of them on one combination is refused, with the reason',
        (tester) async {
      final store = await pumpEditable(tester);
      await tester.tap(find.text('Open the emoji picker'));
      await tester.pumpAndSettle();
      // Super+D is the launcher's.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      // The later of two registrations silently never happens, so this is
      // refused rather than warned about — and the row keeps listening.
      expect(store.specFor(ShellShortcut.openEmoji), kDefaultOpenEmoji);
      expect(
        find.text('Super + D is already "Open the application launcher".'),
        findsOneWidget,
      );
      expect(find.text('Press keys…'), findsOneWidget);
    });

    testWidgets("a combination the compositor uses is a warning, not a refusal",
        (tester) async {
      final store = await pumpEditable(tester);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      // Super+Q is `quit_active_window` in the fake result above.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      await letTheWriteLand(tester);

      expect(store.specFor(ShellShortcut.openSettings), parseShortcut('super+q'));
      expect(
        find.text(
          'The window manager also uses this for "Close the focused window".',
        ),
        findsOneWidget,
      );
    });

    testWidgets('putting one back drops the key it was given', (tester) async {
      final store = await pumpEditable(tester);
      await rebind(tester, 'Open the emoji picker');
      expect(store.isDefault(ShellShortcut.openEmoji), isFalse);

      // The undo only exists on a row that has something to go back to.
      await tester.tap(_faIcon(FontAwesomeIcons.arrowRotateLeft).first);
      await tester.pumpAndSettle();
      await letTheWriteLand(tester);

      expect(store.specFor(ShellShortcut.openEmoji), kDefaultOpenEmoji);
      expect(store.needsRestart, isFalse);
    });

    testWidgets('a row answers a click at its corner, not only over its label',
        (tester) async {
      await pumpEditable(tester);
      // The house rule: a control's hover box and its tap box are one rect. A
      // centre tap passes on the bug this is here for, because the label is the
      // only render object at the centre that accepts a hit.
      final row = tester.getRect(
        find
            .ancestor(
              of: find.text('Open settings'),
              matching: find.byType(HoverRegion),
            )
            .first,
      );
      await tester.tapAt(row.topLeft + const Offset(2, 2));
      await tester.pumpAndSettle();

      expect(find.text('Press keys…'), findsOneWidget);
    });

    testWidgets('the compositor\'s rows cannot be edited from here',
        (tester) async {
      await pumpEditable(tester);
      // Miracle's bindings are miracle's own configuration; the sheet reads
      // them and offers nothing that would write them.
      await tester.tap(find.text('Close the focused window'));
      await tester.pumpAndSettle();
      expect(find.text('Press keys…'), findsNothing);

      await tester.tap(find.text('Go to workspace 1'));
      await tester.pumpAndSettle();
      expect(find.text('Press keys…'), findsNothing);
    });

    testWidgets('an unbound store draws them and offers no editing',
        (tester) async {
      // No `bind` — a sheet pumped with no config file behind it. The rows are
      // still the truth about what the shell binds; an editor whose writes go
      // nowhere is what would be a lie.
      await pumpReadOnly(tester);
      await tester.tap(find.text('Open the emoji picker'));
      await tester.pumpAndSettle();

      expect(find.text('Press keys…'), findsNothing);
      expect(_faIcon(FontAwesomeIcons.pen), findsNothing);
      expect(find.textContaining('config.toml'), findsOneWidget);
    });

    testWidgets('nothing animates while a row is listening', (tester) async {
      await pumpEditable(tester);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
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
