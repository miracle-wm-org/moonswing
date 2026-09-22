import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/switcher/open_window.dart';
import 'package:moonswing/switcher/switcher_overlay.dart';

/// The Alt+Tab surface. The gesture it is drawn for cannot be reproduced here —
/// the presses that cycle it are consumed by the compositor and arrive as a
/// global shortcut — so what is pinned is the other half: the release that
/// commits, the ways out, and that the title under the grid follows the
/// highlight.
///
/// Every window is given an empty `app_id`, so the icon resolves to the
/// first-letter fallback rather than reaching the machine's icon theme —
/// `launcher_overlay_test.dart`'s rule.
void main() {
  late ValueNotifier<bool> closing;
  late ValueNotifier<int> selection;
  late int closed;
  late int committed;
  late int cancelled;
  late List<int> selected;

  setUp(() {
    closing = ValueNotifier(false);
    selection = ValueNotifier(0);
    closed = 0;
    committed = 0;
    cancelled = 0;
    selected = [];
  });

  tearDown(() {
    closing.dispose();
    selection.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    List<OpenWindow> windows = const [],
    bool takesKeyboard = true,
    bool available = true,
  }) async {
    await tester.pumpWidget(ThemeScope(
      theme: const ThemeConfig(),
      child: WindowSwitcherOverlay(
        windows: windows,
        selection: selection,
        closingNotifier: closing,
        onClosed: () => closed++,
        onSelect: (index) {
          selected.add(index);
          selection.value = index;
        },
        onCommit: () => committed++,
        onCancel: () => cancelled++,
        takesKeyboard: takesKeyboard,
        available: available,
      ),
    ));
    await tester.pumpAndSettle();
  }

  List<OpenWindow> makeWindows(int count) => [
    for (var i = 0; i < count; i++)
      OpenWindow(identifier: 'w$i', appId: '', title: 'Window $i'),
  ];

  testWidgets('writes the full title of the highlighted window', (
    tester,
  ) async {
    await pump(tester, windows: makeWindows(3));
    expect(find.text('Window 0'), findsOneWidget);
    expect(find.text('Window 1'), findsNothing);

    selection.value = 2;
    await tester.pumpAndSettle();
    expect(find.text('Window 2'), findsOneWidget);
    expect(find.text('Window 0'), findsNothing);
  });

  testWidgets('letting go of Alt commits', (tester) async {
    await pump(tester, windows: makeWindows(3));
    // The surface takes focus while Alt is already held; the release is the
    // one signal the compositor's trigger cannot report.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(committed, 0);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(committed, 1);
    expect(cancelled, 0);
  });

  testWidgets('letting go of Shift while Alt is held is not letting go', (
    tester,
  ) async {
    // Alt+Shift+Tab, one key at a time. What ends the gesture is the last
    // modifier, not the first.
    await pump(tester, windows: makeWindows(3));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(committed, 0);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(committed, 1);
  });

  testWidgets('Escape switches to nothing', (tester) async {
    await pump(tester, windows: makeWindows(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(cancelled, 1);
    expect(committed, 0);
  });

  testWidgets('the arrows move the highlight and wrap', (tester) async {
    await pump(tester, windows: makeWindows(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(selection.value, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(selection.value, 0);
    expect(committed, 0);
  });

  testWidgets('a click on an icon picks it and switches', (tester) async {
    await pump(tester, windows: makeWindows(3));
    // Each cell is keyed on its toplevel identifier, which is the one field of
    // the three that is stable and unique.
    await tester.tap(find.byKey(const ValueKey('w1')));
    await tester.pumpAndSettle();

    expect(selected, [1]);
    expect(committed, 1);
  });

  testWidgets('a click on the backdrop switches to nothing', (tester) async {
    // The shell has no input-region support, so this surface eats every click
    // on the output: without this a mouse-only user could not answer it.
    await pump(tester, windows: makeWindows(3));
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(cancelled, 1);
    expect(committed, 0);
  });

  testWidgets('the surface without the keyboard answers no key', (
    tester,
  ) async {
    await pump(tester, windows: makeWindows(3), takesKeyboard: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(cancelled, 0);
  });

  testWidgets('nothing open and nothing readable are different sentences', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('No open windows'), findsOneWidget);

    await pump(tester, available: false);
    expect(find.text('No open windows'), findsNothing);
    expect(find.textContaining('cannot read'), findsOneWidget);
  });

  testWidgets('the closing handshake ends in onClosed', (tester) async {
    await pump(tester, windows: makeWindows(3));
    closing.value = true;
    await tester.pumpAndSettle();
    // Nothing tears the window down directly: the root flips the notifier, the
    // surface plays its exit, and this is the cue that it is safe.
    expect(closed, 1);
  });
}
