import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/notification_badge.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/scopes.dart';

/// The badge as the root hosts it: inside its own layer-shell window, whose
/// size the root reads off [kNotificationBadgeWindowSize].
Widget _badge({VoidCallback? onTap}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(
      theme: const ThemeConfig(),
      child: Center(
        child: SizedBox.fromSize(
          size: kNotificationBadgeWindowSize,
          child: NotificationBadge(onTap: onTap ?? () {}),
        ),
      ),
    ),
  );
}

void _seed(int count) {
  final store = NotificationStore.instance;
  for (var i = 0; i < count; i++) {
    store.addOrReplace(NotificationItem(
      id: store.allocateId(),
      appName: 'App',
      summary: 'Summary $i',
      body: '',
      actions: const [],
      expireTimeout: 0,
      arrivedAt: DateTime(2026, 1, 1),
    ));
  }
}

void main() {
  tearDown(() => NotificationStore.instance.dismissAll());

  group('notificationBadgeLabel', () {
    test('shows the count up to 99', () {
      expect(notificationBadgeLabel(1), '1');
      expect(notificationBadgeLabel(99), '99');
    });

    // Three characters at the most: the surface is sized once, by the root,
    // and a four-digit count would be drawn outside it.
    test('clamps past that', () {
      expect(notificationBadgeLabel(100), '99+');
      expect(notificationBadgeLabel(4321), '99+');
    });
  });

  group('NotificationBadge', () {
    testWidgets('fits the window the root sizes for it', (tester) async {
      _seed(1);
      await tester.pumpWidget(_badge());
      await tester.pumpAndSettle();

      // The button, its shadow room and the bubble's overhang add up to
      // exactly the surface the root creates — the two constants are used at
      // opposite ends of the shell with no compiler link between them.
      expect(
        tester.getSize(find.byType(NotificationBadge)),
        kNotificationBadgeWindowSize,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the number of notifications waiting', (tester) async {
      _seed(3);
      await tester.pumpWidget(_badge());
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);

      _seed(1);
      await tester.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);
      expect(find.text('3'), findsNothing);
    });

    testWidgets('asks for the panel when tapped', (tester) async {
      _seed(1);
      var taps = 0;
      await tester.pumpWidget(_badge(onTap: () => taps++));
      await tester.pumpAndSettle();

      // A corner of the button, not its centre: `HoverRegion` emits the opaque
      // detector around the whole 48px circle, and a centre tap would pass on
      // a badge whose only hit-testable child was the glyph.
      final rect = tester.getRect(find.byType(NotificationBadge));
      await tester.tapAt(Offset(
        rect.left + kNotificationBadgeShadowInset + 4,
        rect.bottom - kNotificationBadgeShadowInset - 4,
      ));
      await tester.pump();

      expect(taps, 1);
    });

    // The entrance plays once and the bump plays on an arrival; neither leaves
    // anything running. This surface can be on screen for hours.
    testWidgets('settles, and stays settled after an arrival',
        (tester) async {
      _seed(1);
      await tester.pumpWidget(_badge());
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);

      _seed(1);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
