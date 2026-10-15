import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/docked_panel.dart';
import 'package:moonswing/modules/notifications.dart';
import 'package:moonswing/notification_panel_controller.dart';
import 'package:moonswing/notification_service.dart';
import 'package:moonswing/scopes.dart';

/// The panel as the module hosts it, minus the layer-shell window it really
/// lives in. The module wraps it in a `ThemeProvider`, which resolves to the
/// [ThemeScope] below — all the panel itself reads — and the surface is
/// whatever size the test view is.
Widget _panel({
  required ValueNotifier<bool> closing,
  required VoidCallback onClosed,
  DockSide side = DockSide.right,
}) {
  return ThemeScope(
    theme: const ThemeConfig(),
    child: NotificationPanel(
      side: side,
      closingNotifier: closing,
      onClosed: onClosed,
    ),
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
    testWidgets('the close button asks for the exit rather than closing '
        'outright', (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      var closed = 0;

      await tester.pumpWidget(
        _panel(closing: closing, onClosed: () => closed++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(FontAwesomeIcons.xmark.data));
      await tester.pump();

      // The window is not torn down under the animation: the button flips the
      // notifier, and `onClosed` only lands once the panel has left.
      expect(closing.value, isTrue);
      expect(closed, 0);

      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    // A docked panel takes no keyboard, so nothing on it may wait for a key:
    // Escape would never arrive.
    testWidgets('it takes no focus of its own', (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);

      await tester.pumpWidget(_panel(closing: closing, onClosed: () {}));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(NotificationPanel),
          matching: find.byWidgetPredicate((w) => w is Focus && w.autofocus),
        ),
        findsNothing,
      );
      expect(find.textContaining('Escape'), findsNothing);
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
      await tester.pump(kDockedPanelExit ~/ 2);
      // Asked again while the panel is already on its way out: even a fresh
      // flip must not queue a second teardown.
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
      await tester.pump(kDockedPanelExit - const Duration(milliseconds: 16));
      expect(closed, 0);

      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(kDockedPanelExit, lessThan(kDockedPanelEnter));
    });
  });

  group('NotificationPanel animation geometry', () {
    // The one SlideTransition in the panel is the docked frame's own, and its
    // box is the whole surface — so its global rect is the panel as painted.
    Finder panelSurface() {
      final panel = find.byType(SlideTransition);
      expect(panel, findsOneWidget);
      return panel;
    }

    for (final side in DockSide.values) {
      // The edge the surface is butted against: the right edge of a panel on
      // the right never comes in from it, and the left edge of one on the left
      // never comes in from that. Anything moving the panel inwards opens a
      // strip between it and the screen edge.
      double outer(Rect rect) =>
          side == DockSide.right ? rect.right : -rect.left;

      testWidgets('docked ${side.name}, the exit never pulls away from its '
          'edge', (tester) async {
        final closing = ValueNotifier(false);
        addTearDown(closing.dispose);

        await tester.pumpWidget(
          _panel(closing: closing, onClosed: () {}, side: side),
        );
        await tester.pumpAndSettle();

        final panel = panelSurface();
        final rest = outer(tester.getRect(panel));

        closing.value = true;
        await tester.pump();
        for (var elapsed = Duration.zero;
            elapsed < kDockedPanelExit + const Duration(milliseconds: 32);
            elapsed += const Duration(milliseconds: 8)) {
          expect(
            outer(tester.getRect(panel)),
            greaterThanOrEqualTo(rest - 0.01),
            reason: 'panel detached from the screen edge at $elapsed',
          );
          await tester.pump(const Duration(milliseconds: 8));
        }
      });

      testWidgets('docked ${side.name}, the entrance never pulls away from '
          'it either', (tester) async {
        final closing = ValueNotifier(false);
        addTearDown(closing.dispose);

        await tester.pumpWidget(
          _panel(closing: closing, onClosed: () {}, side: side),
        );
        final panel = panelSurface();
        await tester.pump();

        final seen = <Duration, double>{};
        for (var elapsed = Duration.zero;
            elapsed < kDockedPanelEnter + const Duration(milliseconds: 32);
            elapsed += const Duration(milliseconds: 8)) {
          seen[elapsed] = outer(tester.getRect(panel));
          await tester.pump(const Duration(milliseconds: 8));
        }

        await tester.pumpAndSettle();
        final rest = outer(tester.getRect(panel));
        seen.forEach((elapsed, edge) {
          expect(
            edge,
            greaterThanOrEqualTo(rest - 0.01),
            reason: 'panel detached from the screen edge at $elapsed',
          );
        });

        // The entrance plays once: nothing about it is still ticking at rest.
        expect(SchedulerBinding.instance.transientCallbackCount, 0);
      });
    }
  });

  group('NotificationsConfig panel keys', () {
    test('docks on the right at the default width when nothing is said', () {
      const config = NotificationsConfig();
      expect(NotificationsConfig.fromMap(null), config);
      expect(config.side, DockSide.right);
      expect(config.width, kDefaultNotificationPanelWidth);
    });

    test('reads a side and a width', () {
      final config = NotificationsConfig.fromMap(const {
        'side': 'left',
        'width': 480,
      });
      expect(config.side, DockSide.left);
      expect(config.width, 480);
    });

    // A typo costs the key, never the table — and the fallback is this
    // panel's own default, not the clipboard's.
    test('an unknown side keeps the right', () {
      expect(
        NotificationsConfig.fromMap(const {'side': 'top'}).side,
        DockSide.right,
      );
    });

    test('a width is clamped, and a float is taken', () {
      expect(
        NotificationsConfig.fromMap(const {'width': 10}).width,
        kDockedPanelMinWidth,
      );
      expect(
        NotificationsConfig.fromMap(const {'width': 99999}).width,
        kDockedPanelMaxWidth,
      );
      expect(NotificationsConfig.fromMap(const {'width': 420.0}).width, 420);
    });

    test('the side and width take part in equality', () {
      expect(
        const NotificationsConfig(side: DockSide.left),
        isNot(const NotificationsConfig()),
      );
      expect(
        const NotificationsConfig(width: 500),
        isNot(const NotificationsConfig()),
      );
    });

    test('loading the module tells the root where the panel docks', () {
      final controller = NotificationPanelController.instance;
      addTearDown(() => controller.configure(
            side: kDefaultNotificationPanelSide,
            width: kDefaultNotificationPanelWidth,
          ));
      notificationsModule.loadConfig(const {'side': 'left', 'width': 300});
      expect(controller.side, DockSide.left);
      expect(controller.width, 300);
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
