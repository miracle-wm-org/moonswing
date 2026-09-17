import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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

void _seed(int count, {String app = 'App', String body = ''}) {
  final store = NotificationStore.instance;
  for (var i = 0; i < count; i++) {
    store.addOrReplace(NotificationItem(
      id: store.allocateId(),
      appName: app,
      summary: 'Summary $i',
      body: body,
      actions: const [],
      expireTimeout: 0,
      arrivedAt: DateTime(2026, 1, 1),
    ));
  }
}

/// Where the card actually is inside its surface, in the frame it is asked for.
///
/// The surface is bigger than the card — shadow room on every side, and the
/// slide's room on the right — so a rect read off [NotificationBadge] is the
/// window rather than the thing being animated.
Rect _cardRect(WidgetTester tester) =>
    tester.getRect(find.byType(FaIcon).first);

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

    // The whole reason the badge is a rectangle now: a circle with a number in
    // it says only that *something* arrived, which on a machine the user has
    // walked back to is the question rather than the answer.
    testWidgets('says what the newest one was', (tester) async {
      _seed(1, app: 'Mail', body: 'from somebody');
      await tester.pumpWidget(_badge());
      await tester.pumpAndSettle();

      expect(find.text('Mail'), findsOneWidget);
      expect(find.text('Summary 0'), findsOneWidget);
      expect(find.text('from somebody'), findsOneWidget);
      // One notification, so no count: a "1" beside a card that already says
      // what it is is a number nobody needed.
      expect(find.text('1'), findsNothing);
    });

    // A body arrives as free text from any application on the machine, so its
    // newlines are flattened rather than showing the first line of a paragraph
    // — which for a message that opens with a blank one is nothing at all.
    testWidgets('flattens the body it quotes', (tester) async {
      _seed(1, body: '\n  two   lines\nhere ');
      await tester.pumpWidget(_badge());
      await tester.pumpAndSettle();

      expect(find.text('two lines here'), findsOneWidget);
    });

    testWidgets('says how much else is waiting once there is more',
        (tester) async {
      _seed(2);
      await tester.pumpWidget(_badge());
      await tester.pumpAndSettle();
      expect(find.text('1 more notification'), findsOneWidget);

      _seed(2);
      await tester.pumpAndSettle();
      expect(find.text('3 more notifications'), findsOneWidget);
    });

    // The card is about what is still *asking*, not about what is on the list:
    // the panel's check-all button is what takes it away without emptying it.
    testWidgets('follows the unread count, not the list', (tester) async {
      _seed(3);
      await tester.pumpWidget(_badge());
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);

      NotificationStore.instance.markRead(
        NotificationStore.instance.items.first.id,
      );
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      // And the message it quotes is the newest one still unread.
      expect(find.text('Summary 1'), findsOneWidget);
    });

    // The card arrives out of the edge it is anchored to. Read off the glyph
    // rather than the widget, whose box is the whole surface and does not move.
    testWidgets('slides in, and settles where it will stay', (tester) async {
      _seed(1);
      await tester.pumpWidget(_badge());
      await tester.pump();
      final start = _cardRect(tester).left;

      await tester.pump(kNotificationBadgeEnter ~/ 3);
      final moving = _cardRect(tester).left;
      expect(moving, lessThan(start));

      await tester.pumpAndSettle();
      final settled = _cardRect(tester).left;
      expect(settled, lessThan(moving));
      // It came from the right by exactly the slide it is given room for.
      expect(start - settled, closeTo(kNotificationBadgeSlide, 0.5));
    });

    // And bounces when something lands in it — vertically, off the top edge it
    // hangs from, and back to exactly where it was.
    testWidgets('bounces on an arrival', (tester) async {
      _seed(1);
      await tester.pumpWidget(_badge());
      await tester.pumpAndSettle();
      final resting = _cardRect(tester).top;

      _seed(1);
      await tester.pump();
      await tester.pump(kNotificationBadgeBump ~/ 4);
      expect(_cardRect(tester).top, greaterThan(resting));

      await tester.pumpAndSettle();
      expect(_cardRect(tester).top, closeTo(resting, 0.01));
    });

    testWidgets('asks for the panel when tapped', (tester) async {
      _seed(1);
      var taps = 0;
      await tester.pumpWidget(_badge(onTap: () => taps++));
      await tester.pumpAndSettle();

      // A corner of the card, not its centre: `HoverRegion` emits the opaque
      // detector around the whole rectangle, and a centre tap would pass on a
      // badge whose only hit-testable child was the glyph.
      final rect = tester.getRect(find.byType(NotificationBadge));
      await tester.tapAt(Offset(
        rect.right - kNotificationBadgeShadowInset - kNotificationBadgeSlide - 4,
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
