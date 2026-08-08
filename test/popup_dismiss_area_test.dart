import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_coordinator.dart';

/// [PopupDismissArea] talks to the process-wide singleton — that is the point
/// of it — so each test registers into that instance and unregisters after.
void main() {
  final registered = <TransientHandle>[];

  TransientHandle register({
    required Object owner,
    required VoidCallback onDismiss,
    TransientPolicy policy = TransientPolicy.menu,
  }) {
    final handle = PopupCoordinator.instance
        .open(owner: owner, policy: policy, onDismiss: onDismiss);
    registered.add(handle);
    return handle;
  }

  tearDown(() {
    for (final handle in registered) {
      PopupCoordinator.instance.close(handle);
    }
    registered.clear();
    // Drops any reopen-guard entry the test armed, so the next one starts clean.
    PopupCoordinator.instance
        .dismissFromPointerDown(const PointerDownEvent());
  });

  Future<void> pumpArea(WidgetTester tester, {Widget? child}) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PopupDismissArea(
          child: child ?? const SizedBox(width: 200, height: 60),
        ),
      ),
    );
  }

  testWidgets('a press dismisses an open surface', (tester) async {
    var dismissed = 0;
    register(owner: Object(), onDismiss: () => dismissed++);
    await pumpArea(tester);

    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump();

    expect(dismissed, 1);
    await gesture.up();
  });

  testWidgets('a primary press arms the reopen guard', (tester) async {
    final owner = Object();
    register(owner: owner, onDismiss: () {});
    await pumpArea(tester);

    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump();

    expect(PopupCoordinator.instance.consumeReopenGuard(owner), isTrue);
    await gesture.up();
  });

  testWidgets('a secondary press dismisses but arms nothing', (tester) async {
    final owner = Object();
    var dismissed = 0;
    register(owner: owner, onDismiss: () => dismissed++);
    await pumpArea(tester);

    final gesture = await tester.startGesture(
      const Offset(400, 300),
      buttons: kSecondaryButton,
    );
    await tester.pump();

    expect(dismissed, 1);
    expect(PopupCoordinator.instance.consumeReopenGuard(owner), isFalse);
    await gesture.up();
  });

  testWidgets('it sees a press that a descendant handles', (tester) async {
    // The bar buttons are GestureDetectors, and a click on one has to dismiss
    // the *other* modules' popups. A Listener above them on the hit-test path
    // is what guarantees it, so this pins the ordering rather than the widget.
    var dismissed = 0;
    var tapped = 0;
    register(owner: Object(), onDismiss: () => dismissed++);
    await pumpArea(
      tester,
      child: GestureDetector(
        // Opaque: the point is that even a descendant that claims the hit
        // does not stop the area above it from seeing the pointer-down.
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => tapped++,
        child: const SizedBox(width: 200, height: 60),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(dismissed, 1);
    expect(tapped, 1);
  });

  testWidgets('a press on empty space still dismisses', (tester) async {
    // Translucent behaviour: a panel is mostly padding, and clicking it must
    // work the same as clicking an icon.
    var dismissed = 0;
    register(owner: Object(), onDismiss: () => dismissed++);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PopupDismissArea(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(width: 10, height: 10, color: const Color(0xFF00FF00)),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump();

    expect(dismissed, 1);
    await gesture.up();
  });
}
