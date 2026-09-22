import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/modules/notifications.dart';
import 'package:moonswing/notification_service.dart';
import 'package:moonswing/notification_sound.dart';
import 'package:moonswing/scopes.dart';

/// Finds a rendered FontAwesome glyph.
///
/// By code point, not by icon: `FaIcon` unwraps the [FaIconData] it is given
/// into a plain `IconData`, which never compares equal to the catalogue entry
/// it came from. The code point is what actually reaches the font.
Finder _glyph(FaIconData icon) => find.byWidgetPredicate(
      (w) => w is FaIcon && w.icon?.codePoint == icon.codePoint,
    );

/// Read and dismissed are different acts, and the whole of this file is about
/// keeping them different: marking everything read stops the shell *asking*
/// about a notification without removing it, which is what makes it something
/// other than a second Clear all.
void main() {
  final store = NotificationStore.instance;

  tearDown(() {
    store.dismissAll();
    store.resetDaemonState();
    NotificationSoundStore.instance.resetForTesting();
  });

  int seed({String app = 'App', String summary = 'Hello', String body = ''}) {
    final id = store.allocateId();
    store.addOrReplace(NotificationItem(
      id: id,
      appName: app,
      summary: summary,
      body: body,
      actions: const [],
      expireTimeout: 0,
      arrivedAt: DateTime(2026, 1, 1),
    ));
    return id;
  }

  group('NotificationStore read state', () {
    test('a notification arrives unread', () {
      seed();
      seed();
      expect(store.items.every((item) => !item.read), isTrue);
      expect(store.unreadCount, 2);
      expect(store.hasUnread, isTrue);
    });

    test('marking all read keeps every message on the list', () {
      seed();
      seed();
      store.markAllRead();

      expect(store.unreadCount, 0);
      expect(store.hasUnread, isFalse);
      // The point of the button: nothing is gone, so the panel still has
      // something to show and Clear all still has something to do.
      expect(store.items, hasLength(2));
      expect(store.items.every((item) => item.read), isTrue);
    });

    test('marking all read twice costs one notification, not two', () {
      seed();
      var notifies = 0;
      void count() => notifies++;
      store.addListener(count);
      addTearDown(() => store.removeListener(count));

      store.markAllRead();
      expect(notifies, 1);
      store.markAllRead();
      expect(notifies, 1);
    });

    test('one can be marked read on its own', () {
      final first = seed();
      seed();
      store.markRead(first);

      expect(store.unreadCount, 1);
      expect(store.items.firstWhere((i) => i.id == first).read, isTrue);
      // An id that is not on the list, and one already read, are both no-ops.
      store.markRead(first);
      store.markRead(999999);
      expect(store.unreadCount, 1);
    });

    // An application that rewrites a notification under an id it is reusing has
    // said something the user has not seen.
    test('a replacement arrives unread again', () {
      final id = seed(summary: 'Downloading');
      store.markAllRead();
      expect(store.unreadCount, 0);

      store.addOrReplace(NotificationItem(
        id: id,
        appName: 'App',
        summary: 'Download finished',
        body: '',
        actions: const [],
        expireTimeout: 0,
        arrivedAt: DateTime(2026, 1, 1),
      ));
      expect(store.unreadCount, 1);
      expect(store.items.single.summary, 'Download finished');
    });

    test('dismissing a read one leaves the unread count alone', () {
      final first = seed();
      seed();
      store.markRead(first);
      store.dismiss(first);

      expect(store.items, hasLength(1));
      expect(store.unreadCount, 1);
    });
  });

  group('the panel header', () {
    Widget panel(ValueNotifier<bool> closing) => ThemeScope(
          theme: const ThemeConfig(),
          child: NotificationPanel(
            closingNotifier: closing,
            onClosed: () {},
          ),
        );

    testWidgets('the check-all button marks everything read and stays put',
        (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      seed();
      seed();

      await tester.pumpWidget(panel(closing));
      await tester.pumpAndSettle();

      final check = _glyph(FontAwesomeIcons.checkDouble);
      expect(check, findsOneWidget);
      await tester.tap(check);
      await tester.pumpAndSettle();

      expect(store.unreadCount, 0);
      expect(store.items, hasLength(2));
      // And the button goes with the thing it acted on: a control that stays
      // and does nothing is how a user learns not to trust it.
      expect(check, findsNothing);
      // The list did not: Clear all is the button that empties it.
      expect(find.text('Clear all'), findsOneWidget);
    });

    testWidgets('the way out is a drawer closing, not an X', (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);

      await tester.pumpWidget(panel(closing));
      await tester.pumpAndSettle();

      final close = _glyph(FontAwesomeIcons.arrowRightToBracket);
      expect(close, findsOneWidget);
      // The panel leaves by sliding back into the edge it is anchored to, and
      // this is the arrow that says so. An X says the thing under it is being
      // thrown away, which is what Clear all does.
      expect(_glyph(FontAwesomeIcons.xmark), findsNothing);

      await tester.tap(close);
      await tester.pump();
      expect(closing.value, isTrue);
    });

    testWidgets('the sound row reports what is set, and what is wrong',
        (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      final sound = NotificationSoundStore.instance;
      var plays = 0;
      sound.play = (_, _) async => plays++;
      sound.materialise = (voice) => '/cache/${voice.slug}.wav';
      sound.resolve = (_) => const NotificationSoundChoice.missing('nonesuch');

      await tester.pumpWidget(panel(closing));
      await tester.pumpAndSettle();

      expect(find.text('Notification sound'), findsOneWidget);
      // A name that resolves to nothing is the user having asked for a sound
      // and not got one. It is not silence, and the row says which.
      expect(find.textContaining('nonesuch'), findsOneWidget);

      sound.resolve = (_) => const NotificationSoundChoice.silent();
      sound.configure(const NotificationSoundConfig(sound: 'none'));
      await tester.pumpAndSettle();
      expect(find.textContaining('without a sound'), findsOneWidget);

      sound.resolve = (_) => NotificationSoundChoice.shipped(
            notificationVoice('bell')!,
          );
      sound.configure(const NotificationSoundConfig(sound: 'bell'));
      await tester.pumpAndSettle();
      // Nothing is holding the chime open in a test, and the row says that
      // too rather than claiming a sound that would never play.
      expect(find.textContaining('no notifications module'), findsOneWidget);

      // The preview plays whatever is configured, every time it is pressed.
      await tester.tap(_glyph(FontAwesomeIcons.play));
      await tester.pump();
      await tester.tap(_glyph(FontAwesomeIcons.play));
      await tester.pump();
      expect(plays, 2);
    });

    testWidgets('the count line says how much of the list is still asking',
        (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      final first = seed();
      seed();
      seed();

      await tester.pumpWidget(panel(closing));
      await tester.pumpAndSettle();
      // All three unread: the total on its own, because "3 unread" of three is
      // the same sentence twice.
      expect(find.text('3 notifications'), findsOneWidget);

      store.markRead(first);
      await tester.pumpAndSettle();
      expect(find.text('3 notifications, 2 unread'), findsOneWidget);

      store.markAllRead();
      await tester.pumpAndSettle();
      // Not "0 unread": a panel that reported a zero over three cards would
      // read as the button having emptied something.
      expect(find.text('3 notifications, all read'), findsOneWidget);
    });
  });
}
