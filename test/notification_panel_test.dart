import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/modules/notifications.dart';
import 'package:moonswing/notification_service.dart';
import 'package:moonswing/scopes.dart';

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

  _activationTests(store);

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

  group('NotificationPanel animation geometry', () {
    // The one FadeTransition in the panel is the animation's own, and its box
    // is the whole surface — so its global rect is the panel as painted,
    // ancestor transforms included.
    Finder panelSurface() {
      final panel = find.byType(FadeTransition);
      expect(panel, findsOneWidget);
      return panel;
    }

    testWidgets('the exit never pulls away from the edge it is anchored to',
        (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);

      await tester.pumpWidget(_panel(closing: closing, onClosed: () {}));
      await tester.pumpAndSettle();

      final panel = panelSurface();
      final surfaceRight = tester.getRect(panel).right;

      closing.value = true;
      await tester.pump();
      for (var elapsed = Duration.zero;
          elapsed < kNotificationPanelExit + const Duration(milliseconds: 32);
          elapsed += const Duration(milliseconds: 8)) {
        // Every part of the exit either scales towards the right edge or moves
        // the panel further off it. Anything that moved it left would open a
        // transparent strip along the screen edge.
        expect(
          tester.getRect(panel).right,
          greaterThanOrEqualTo(surfaceRight - 0.01),
          reason: 'panel detached from the screen edge at $elapsed',
        );
        await tester.pump(const Duration(milliseconds: 8));
      }
    });

    testWidgets('the entrance never pulls away from it either', (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);

      await tester.pumpWidget(_panel(closing: closing, onClosed: () {}));
      final panel = panelSurface();
      await tester.pump();

      // The entrance is the exit backwards, so it inherits the exit's one
      // rule: a centre-pivoted scale or a dip to the left here would open a
      // gap along the screen edge that closes as the panel settles.
      final seen = <Duration, double>{};
      for (var elapsed = Duration.zero;
          elapsed < kNotificationPanelEnter + const Duration(milliseconds: 32);
          elapsed += const Duration(milliseconds: 8)) {
        seen[elapsed] = tester.getRect(panel).right;
        await tester.pump(const Duration(milliseconds: 8));
      }

      await tester.pumpAndSettle();
      final surfaceRight = tester.getRect(panel).right;
      seen.forEach((elapsed, right) {
        expect(
          right,
          greaterThanOrEqualTo(surfaceRight - 0.01),
          reason: 'panel detached from the screen edge at $elapsed',
        );
      });

      // The entrance plays once: nothing about it is still ticking at rest.
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });

    testWidgets('the entrance is the exit played backwards', (tester) async {
      // A quarter, half and three quarters of the way in, the panel is where
      // the exit has it at the mirrored point of its own — shorter — run. One
      // animation played both ways is what makes this hold; two that merely
      // resembled each other would drift.
      const progress = <double>[0.25, 0.5, 0.75];

      // Keyed apart, or the second `pumpWidget` would update the first panel's
      // State in place and leave it listening to a disposed notifier.
      Future<Map<double, Rect>> run(String phase, bool leaving) async {
        final closing = ValueNotifier(false);
        addTearDown(closing.dispose);
        await tester.pumpWidget(KeyedSubtree(
          key: ValueKey(phase),
          child: _panel(closing: closing, onClosed: () {}),
        ));
        final panel = panelSurface();

        if (leaving) {
          await tester.pumpAndSettle();
          closing.value = true;
        }
        // The frame the ticker starts on: it elapses nothing, so the pumps
        // below are measured from here.
        await tester.pump();

        final rects = <double, Rect>{};
        var elapsed = Duration.zero;
        // A quarter of the way in is three quarters of the way out, so the
        // leaving half walks the same points in the opposite order.
        for (final p in leaving ? progress.reversed : progress) {
          final at = leaving
              ? kNotificationPanelExit * (1 - p)
              : kNotificationPanelEnter * p;
          await tester.pump(at - elapsed);
          elapsed = at;
          rects[p] = tester.getRect(panel);
        }
        await tester.pumpAndSettle();
        return rects;
      }

      final arriving = await run('entering', false);
      final departing = await run('leaving', true);

      for (final p in progress) {
        expect(
          arriving[p]!,
          _rectCloseTo(departing[p]!),
          reason: 'the panel is elsewhere at $p of the way in',
        );
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

  // Every chip in the panel is lettered in the accent, so none of them may be
  // *filled* with it: `surface_hover` is the accent itself in the shipped
  // palette, and a label drawn in the colour it sits on is not a label.
  group('NotificationPanel highlights', () {
    Future<void> pumpPanel(WidgetTester tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      await tester.pumpWidget(_panel(closing: closing, onClosed: () {}));
      await tester.pumpAndSettle();
    }

    void expectTint(WidgetTester tester, String label) {
      final container = tester.widget<Container>(find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first);
      final fill = (container.decoration! as BoxDecoration).color;
      final ink = tester.widget<Text>(find.text(label)).style!.color!;
      if (fill == null) return;
      // A tint the card reads through, never the letters' own colour.
      expect(fill, isNot(ink));
      expect(fill.a, lessThan(0.5));
    }

    testWidgets('an action chip is a tint of the accent it is lettered in',
        (tester) async {
      store.addOrReplace(NotificationItem(
        id: store.allocateId(),
        appName: 'Mail',
        summary: 'Hello',
        body: '',
        actions: const ['reply', 'Reply'],
        expireTimeout: 0,
        arrivedAt: DateTime(2026, 1, 1),
      ));
      await pumpPanel(tester);

      // At rest, which is where the old fill made it unreadable: the resting
      // chip wore `surface_hover` and only the *hovered* one was tinted.
      expectTint(tester, 'Reply');

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Reply')));
      await tester.pumpAndSettle();

      expectTint(tester, 'Reply');
    });

    testWidgets('so is a hovered "Clear all"', (tester) async {
      store.addOrReplace(NotificationItem(
        id: store.allocateId(),
        appName: 'Mail',
        summary: 'Hello',
        body: '',
        actions: const [],
        expireTimeout: 0,
        arrivedAt: DateTime(2026, 1, 1),
      ));
      await pumpPanel(tester);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Clear all')));
      await tester.pumpAndSettle();

      expectTint(tester, 'Clear all');
    });
  });
}

/// The two halves are the same animation, not the same arithmetic: a rect a
/// hundredth of a pixel out is the same frame.
Matcher _rectCloseTo(Rect expected) => _RectCloseTo(expected);

class _RectCloseTo extends Matcher {
  const _RectCloseTo(this.expected);

  final Rect expected;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is Rect &&
      (item.left - expected.left).abs() < 0.01 &&
      (item.top - expected.top).abs() < 0.01 &&
      (item.right - expected.right).abs() < 0.01 &&
      (item.bottom - expected.bottom).abs() < 0.01;

  @override
  Description describe(Description description) =>
      description.add('within 0.01 of $expected');

}

/// Clicking a notification is clicking the thing it is about.
void _activationTests(NotificationStore store) {
  group('NotificationPanel activation', () {
    int seed({List<String> actions = const [], String desktopEntry = ''}) {
      return store.addOrReplace(NotificationItem(
        id: store.allocateId(),
        appName: 'Chat',
        summary: 'Somebody said hi',
        body: '',
        actions: actions,
        expireTimeout: 0,
        arrivedAt: DateTime(2026, 1, 1),
        desktopEntry: desktopEntry,
      ));
    }

    final invoked = <(int, String)>[];
    final launched = <String>[];
    setUp(() {
      invoked.clear();
      launched.clear();
      store.setActionInvokedCallback((id, key) => invoked.add((id, key)));
      store.appLauncher = (entry) {
        launched.add(entry);
        return true;
      };
    });

    Future<ValueNotifier<bool>> pumpPanel(WidgetTester tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      await tester.pumpWidget(_panel(closing: closing, onClosed: () {}));
      await tester.pumpAndSettle();
      return closing;
    }

    testWidgets('a click on the card takes its default action and closes',
        (tester) async {
      final id = seed(actions: ['default', 'Open', 'reply', 'Reply']);
      final closing = await pumpPanel(tester);

      await tester.tap(find.text('Somebody said hi'));
      await tester.pump();

      expect(invoked, [(id, 'default')]);
      expect(launched, isEmpty);
      expect(store.items, isEmpty);
      expect(closing.value, isTrue);
    });

    testWidgets('an action button does only its own action', (tester) async {
      final id = seed(actions: ['default', 'Open', 'reply', 'Reply']);
      await pumpPanel(tester);

      await tester.tap(find.text('Reply'));
      await tester.pump();

      expect(invoked, [(id, 'reply')]);
    });

    testWidgets('with no default action it opens the sending application',
        (tester) async {
      seed(desktopEntry: 'discord');
      final closing = await pumpPanel(tester);

      await tester.tap(find.text('Somebody said hi'));
      await tester.pump();

      expect(invoked, isEmpty);
      expect(launched, ['discord']);
      expect(store.items, isEmpty);
      expect(closing.value, isTrue);
    });

    testWidgets('with nothing to open it is only marked read', (tester) async {
      seed();
      final closing = await pumpPanel(tester);

      await tester.tap(find.text('Somebody said hi'));
      await tester.pump();

      expect(invoked, isEmpty);
      expect(store.items, hasLength(1));
      expect(store.items.single.read, isTrue);
      expect(closing.value, isFalse);
    });
  });
}
