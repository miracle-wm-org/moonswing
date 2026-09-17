import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/modules/system.dart';
import 'package:graceful_shell/power/power_actions.dart';
import 'package:graceful_shell/power/power_menu_controller.dart';
import 'package:graceful_shell/power/power_menu_overlay.dart';
import 'package:graceful_shell/scopes.dart';

void main() {
  late ValueNotifier<bool> closing;
  late List<PowerAction> performed;
  late int closed;

  setUp(() {
    closing = ValueNotifier(false);
    performed = [];
    closed = 0;
  });

  tearDown(() => closing.dispose());

  Future<void> pump(WidgetTester tester,
      {PowerAction initial = PowerAction.shutdown}) async {
    await tester.pumpWidget(ThemeScope(
      theme: const ThemeConfig(),
      child: PowerMenuOverlay(
        closingNotifier: closing,
        onClosed: () => closed++,
        onAction: performed.add,
        initialAction: initial,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('offers every power action', (tester) async {
    await pump(tester);
    for (final action in PowerAction.values) {
      expect(find.text(action.label), findsOneWidget, reason: action.label);
    }
  });

  testWidgets('a tile runs its action and dismisses', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();

    expect(performed, [PowerAction.suspend]);
    // The overlay asks for its own fade-out; the root tears the window down
    // once it finishes, which is what `onClosed` is.
    expect(closed, 1);
  });

  // Unlike the bar popup, which routes the same verbs through a confirmation:
  // this menu appears *because* the power button was pressed, so answering it
  // is already the second deliberate act.
  testWidgets('acts on the press with no confirmation of its own',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Shut Down'));
    await tester.pump();
    expect(performed, [PowerAction.shutdown]);
  });

  testWidgets('Escape cancels without running anything', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(performed, isEmpty);
    expect(closed, 1);
  });

  testWidgets('a click on the backdrop cancels', (tester) async {
    await pump(tester);
    // The shell has no input-region support, so this surface eats every click
    // on the output: a mouse-only user's way out is the backdrop.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(performed, isEmpty);
    expect(closed, 1);
  });

  testWidgets('a click on the card is not a dismissal', (tester) async {
    await pump(tester);
    // Between the title and the tiles: inside the card, on no control.
    await tester.tapAt(tester.getCenter(find.text('Power')));
    await tester.pumpAndSettle();

    expect(performed, isEmpty);
    expect(closed, 0);
  });

  // The fast path a physical button wants: press, glance, Enter.
  testWidgets('Enter answers with Shut Down before the user has moved',
      (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(performed, [PowerAction.shutdown]);
  });

  testWidgets('the arrow keys move the selection, and it wraps',
      (tester) async {
    await pump(tester);
    // Shut Down is last, so one step right wraps to the first action.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(performed, [PowerAction.values.first]);
  });

  testWidgets('arrow-left from the default steps back one', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(performed, [PowerAction.reboot]);
  });

  // `lock` and `logout` leave the shell running, so the surface is still on
  // screen — fading out — when the verb has already been handed off.
  testWidgets('a second answer during the fade-out is ignored', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Lock'));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.text('Log Out'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(performed, [PowerAction.lock]);
    expect(closed, 1);
  });

  testWidgets('the owner can ask for the fade-out itself', (tester) async {
    await pump(tester);
    closing.value = true;
    await tester.pumpAndSettle();

    expect(closed, 1);
    expect(performed, isEmpty);
  });

  // The bar's power icon opens this same menu. It used to open a popup of its
  // own, with a confirmation dialog behind each destructive verb; it now creates
  // no window at all and asks the root for the menu, exactly as the keyboard
  // icon asks for the cheat sheet.
  group('the bar module', () {
    testWidgets('the power icon asks the root for the menu', (tester) async {
      final controller = PowerMenuController.forTesting();
      var signals = 0;
      controller.addListener(() => signals++);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ThemeScope(
          theme: const ThemeConfig(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: System(controller: controller)),
          ),
        ),
      );

      // The corner, not the centre: a tap target that only answers over its
      // glyph passes a centre tap and fails a real one.
      final box = tester.getRect(find.byType(System));
      await tester.tapAt(box.topLeft + const Offset(1, 1));
      await tester.pump();

      expect(signals, 1);
    });

    testWidgets('it opens no popup of its own', (tester) async {
      final controller = PowerMenuController.forTesting();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ThemeScope(
          theme: const ThemeConfig(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: System(controller: controller)),
          ),
        ),
      );
      await tester.tap(find.byType(System));
      await tester.pumpAndSettle();

      // No window registry is in play here, so a module that still built its
      // own menu would throw rather than quietly draw one — but the verbs are
      // what a regression would put back on screen, so look for those.
      for (final action in PowerAction.values) {
        expect(find.text(action.label), findsNothing, reason: action.label);
      }
    });
  });
}
