import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/modules/notifications.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/scopes.dart';

/// The panel as the module hosts it, minus the layer-shell window it really
/// lives in. The module wraps it in a `ThemeProvider`, which resolves to the
/// [ThemeScope] below — all the panel itself reads — and the surface is
/// whatever size the test view is.
Widget _panel({
  required ValueNotifier<bool> closing,
  required VoidCallback onClosed,
}) {
  return ThemeScope(
    theme: const ThemeConfig(),
    child: NotificationPanel(closingNotifier: closing, onClosed: onClosed),
  );
}

void main() {
  final store = NotificationStore.instance;

  tearDown(() {
    store.resetDaemonState();
    store.dismissAll();
  });

  group('NotificationPanel dismissal', () {
    testWidgets('Escape asks for the exit rather than closing outright',
        (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      var closed = 0;

      await tester.pumpWidget(
        _panel(closing: closing, onClosed: () => closed++),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // The window is not torn down under the animation: the key flips the
      // notifier, and `onClosed` only lands once the panel has left.
      expect(closing.value, isTrue);
      expect(closed, 0);

      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('a key that is not Escape is left alone', (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);

      await tester.pumpWidget(_panel(closing: closing, onClosed: () {}));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(closing.value, isFalse);
    });

    testWidgets('a second dismissal mid-exit does not close twice',
        (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      var closed = 0;

      await tester.pumpWidget(
        _panel(closing: closing, onClosed: () => closed++),
      );
      await tester.pumpAndSettle();

      closing.value = true;
      await tester.pump();
      await tester.pump(kNotificationPanelExit ~/ 2);
      // Escape while the panel is already on its way out: the notifier is
      // already true, and even a fresh flip must not queue a second teardown.
      closing.value = false;
      closing.value = true;
      await tester.pumpAndSettle();

      expect(closed, 1);
    });

    testWidgets('the exit is quicker than the entrance', (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      var closed = 0;

      await tester.pumpWidget(
        _panel(closing: closing, onClosed: () => closed++),
      );
      await tester.pumpAndSettle();

      closing.value = true;
      await tester.pump();
      // One frame short of the exit's own duration, it is still going.
      await tester.pump(
        kNotificationPanelExit - const Duration(milliseconds: 16),
      );
      expect(closed, 0);

      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(kNotificationPanelExit, lessThan(kNotificationPanelEnter));
    });
  });

  group('NotificationPanel exit geometry', () {
    testWidgets('never pulls away from the edge it is anchored to',
        (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);

      await tester.pumpWidget(_panel(closing: closing, onClosed: () {}));
      await tester.pumpAndSettle();

      // The one FadeTransition in an idle panel is the exit's own, and its
      // box is the whole surface — so its global rect is the panel as
      // painted, ancestor transforms included.
      final panel = find.byType(FadeTransition);
      expect(panel, findsOneWidget);

      final surfaceRight = tester.getRect(panel).right;

      closing.value = true;
      await tester.pump();
      for (var elapsed = Duration.zero;
          elapsed < kNotificationPanelExit + const Duration(milliseconds: 32);
          elapsed += const Duration(milliseconds: 8)) {
        // Every part of the exit either scales towards the right edge or moves
        // the panel further off it. Anything that moved it left would open a
        // transparent strip along the screen edge — the reason the entrance
        // refuses PopupBounceIn.
        expect(
          tester.getRect(panel).right,
          greaterThanOrEqualTo(surfaceRight - 0.01),
          reason: 'panel detached from the screen edge at $elapsed',
        );
        await tester.pump(const Duration(milliseconds: 8));
      }
    });
  });

  group('notificationPanelWidth', () {
    // A quarter of the output, which on the common sizes is where a column of
    // prose reads comfortably against a bar module's popup.
    test('is a fraction of the output', () {
      expect(notificationPanelWidth(1920), 480);
      expect(notificationPanelWidth(1600), 400);
    });

    // The floor is what the card's own type needs; a fifth of a 1366px laptop
    // was 273, which wrapped two-word summaries.
    test('has a floor a small display cannot go under', () {
      expect(notificationPanelWidth(1366), 360);
      expect(notificationPanelWidth(800), 360);
    });

    // The ceiling stops a quarter of an ultrawide from covering what the user
    // was reading.
    test('has a ceiling a wide one cannot go over', () {
      expect(notificationPanelWidth(3440), 560);
      expect(notificationPanelWidth(5120), 560);
    });
  });

  group('NotificationPanel content', () {
    testWidgets('says how much is waiting, not just what it is called',
        (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);

      await tester.pumpWidget(_panel(closing: closing, onClosed: () {}));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Nothing waiting'), findsOneWidget);

      store.addOrReplace(NotificationItem(
        id: store.allocateId(),
        appName: 'App',
        summary: 'Hello',
        body: '',
        actions: const [],
        expireTimeout: 0,
        arrivedAt: DateTime(2026, 1, 1),
      ));
      await tester.pumpAndSettle();

      // Singular, because "1 notifications" is the thing that makes a panel
      // read as generated rather than written.
      expect(find.text('1 notification'), findsOneWidget);
    });

    // An empty panel is the one the user sees most often, so it says what the
    // surface is for rather than reporting that it has nothing.
    testWidgets('the empty state explains itself', (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);

      await tester.pumpWidget(_panel(closing: closing, onClosed: () {}));
      await tester.pumpAndSettle();

      expect(find.text('You are all caught up'), findsOneWidget);
      expect(
        find.textContaining('appear here', findRichText: true),
        findsOneWidget,
      );
      // Nothing to clear, so nothing offering to.
      expect(find.text('Clear all'), findsNothing);
    });
  });
}
