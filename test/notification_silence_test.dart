import 'dart:io';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/modules/notifications.dart';
import 'package:moonswing/notification_service.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

/// [FaIcon.icon] answers the wrapped [IconData], not the [FaIconData] the
/// call site named, so the two are compared unwrapped.
Finder _icon(FaIconData icon) =>
    find.byWidgetPredicate((w) => w is FaIcon && w.icon == icon.data);

/// The bar module, as `test/notification_daemon_test.dart` hosts it: a
/// [ThemeScope] and nothing else. Nothing here clicks the bell's own popup,
/// which is the one thing that would need a layer-shell window.
Widget _bell() {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(
      theme: const ThemeConfig(),
      child: const Center(child: Notifications()),
    ),
  );
}

/// The panel's silence row on its own, under the store listener the real panel
/// rebuilds it from — `_NotificationPanelState` holds the only one, so the row
/// itself has none.
Widget _row() {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(
      theme: const ThemeConfig(),
      child: Center(
        child: SizedBox(
          width: 420,
          child: ListenableBuilder(
            listenable: NotificationStore.instance,
            // Deliberately not const, `test/notification_daemon_test.dart`'s
            // reason: a const child is the same widget instance every build,
            // and the element would short-circuit the rebuild this listener
            // exists to cause. The panel passes a runtime `theme`, so it never
            // hits that.
            builder: (_, _) => NotificationSilenceRow(
              theme: const ThemeConfig(),
            ),
          ),
        ),
      ),
    ),
  );
}

NotificationItem _item(int id) => NotificationItem(
      id: id,
      appName: 'App',
      summary: 'Hello',
      body: '',
      actions: const [],
      expireTimeout: 0,
      arrivedAt: DateTime(2026, 1, 1),
    );

void main() {
  final store = NotificationStore.instance;

  // Unbound from any config: a widget test that wrote through one would leave
  // the store's debounced save timer pending past the end of the test.
  setUp(store.resetSilencedState);
  tearDown(() {
    store.resetSilencedState();
    store.dismissAll();
  });

  group('NotificationStore.silenced', () {
    test('starts out unsilenced and toggles either way', () {
      var notifies = 0;
      void listener() => notifies++;
      store.addListener(listener);
      addTearDown(() => store.removeListener(listener));

      expect(store.silenced, isFalse);

      store.toggleSilenced();
      expect(store.silenced, isTrue);
      expect(notifies, 1);

      store.toggleSilenced();
      expect(store.silenced, isFalse);
      expect(notifies, 2);
    });

    test('setting what is already set is not news', () {
      var notifies = 0;
      void listener() => notifies++;
      store.addListener(listener);
      addTearDown(() => store.removeListener(listener));

      store.setSilenced(false);
      expect(notifies, 0);

      store.setSilenced(true);
      store.setSilenced(true);
      expect(notifies, 1);
    });

    test('silencing keeps collecting; it is delivery that is untouched', () {
      store.setSilenced(true);
      store.addOrReplace(_item(1));
      store.addOrReplace(_item(2));

      // The whole promise of the switch: the panel still fills up, so nothing
      // arriving while the user is heads-down is lost.
      expect(store.items.length, 2);
    });
  });

  group('the silenced flag in config.toml', () {
    late Directory tempDir;
    late String path;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('gs_notif_silence');
      path = '${tempDir.path}/config.toml';
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('a flag left over from the last session is read back', () async {
      await File(path).writeAsString('''
[notifications]
silenced = true
''');
      store.resetSilencedState(configStore: await ConfigStore.loadFrom(path));

      // The point of persisting it at all: a restart must not quietly start
      // interrupting somebody who asked not to be.
      expect(store.silenced, isTrue);
    });

    test('a wrongly-typed flag costs the key, not the session', () async {
      await File(path).writeAsString('''
[notifications]
silenced = "yes"
''');
      store.resetSilencedState(configStore: await ConfigStore.loadFrom(path));

      expect(store.silenced, isFalse);
    });

    test('flipping it survives a round trip through the file', () async {
      final config = await ConfigStore.loadFrom(path);
      store.resetSilencedState(configStore: config);

      store.setSilenced(true);
      // The store's own write is debounced; a test has no reason to wait it
      // out when the same write is what `save()` does.
      await config.save();

      final reloaded = await ConfigStore.loadFrom(path);
      expect(reloaded.get<bool>(kNotificationSilencedPath), isTrue);

      store.resetSilencedState(configStore: reloaded);
      expect(store.silenced, isTrue);
    });
  });

  group('the bell', () {
    testWidgets('wears a crossed-out bell while silenced', (tester) async {
      await tester.pumpWidget(_bell());
      expect(_icon(FontAwesomeIcons.bell), findsOneWidget);
      expect(_icon(FontAwesomeIcons.bellSlash), findsNothing);

      // Live, on the store's notify: the flag can be flipped from the panel on
      // another output, or from the bell on another monitor entirely.
      store.setSilenced(true);
      await tester.pump();
      expect(_icon(FontAwesomeIcons.bellSlash), findsOneWidget);
      expect(_icon(FontAwesomeIcons.bell), findsNothing);
    });

    testWidgets('right-click silences and unsilences it', (tester) async {
      await tester.pumpWidget(_bell());

      Future<void> rightClick() async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Notifications)),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.up();
        await tester.pump();
      }

      await rightClick();
      expect(store.silenced, isTrue);

      await rightClick();
      expect(store.silenced, isFalse);
    });

    testWidgets('a notification arriving while silenced does not shake it',
        (tester) async {
      store.setSilenced(true);
      await tester.pumpWidget(_bell());
      await tester.pumpAndSettle();

      store.addOrReplace(_item(1));
      await tester.pump();
      // Nothing animates at rest, and a silenced bell is at rest by
      // definition: the shake is the shell tapping the user on the shoulder.
      expect(tester.hasRunningAnimations, isFalse);

      store.setSilenced(false);
      await tester.pump();
      store.addOrReplace(_item(2));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('still counts what it is not announcing', (tester) async {
      store.setSilenced(true);
      store.addOrReplace(_item(1));
      await tester.pumpWidget(_bell());

      expect(find.text('1'), findsOneWidget);
    });
  });

  group('the panel row', () {
    testWidgets('says what silencing does, and what it does not',
        (tester) async {
      await tester.pumpWidget(_row());
      expect(find.text('Silence notifications'), findsOneWidget);
      expect(find.textContaining('announce themselves'), findsOneWidget);

      store.setSilenced(true);
      await tester.pump();
      // The sentence a user needs before flipping a switch called "silence".
      expect(find.textContaining('Nothing is lost'), findsOneWidget);
    });

    testWidgets('the switch follows the store both ways', (tester) async {
      await tester.pumpWidget(_row());
      expect(tester.widget<SettingsToggle>(find.byType(SettingsToggle)).value,
          isFalse);

      await tester.tap(find.byType(SettingsToggle));
      await tester.pump();
      expect(store.silenced, isTrue);
      expect(tester.widget<SettingsToggle>(find.byType(SettingsToggle)).value,
          isTrue);

      // Flipped from somewhere else — the bell's right-click — the switch
      // still moves, because the row renders the store rather than a copy.
      store.setSilenced(false);
      await tester.pump();
      expect(tester.widget<SettingsToggle>(find.byType(SettingsToggle)).value,
          isFalse);
    });

    testWidgets('a tap on the row toggles exactly once', (tester) async {
      await tester.pumpWidget(_row());

      // The row and the switch are both tappable and both toggle, so the
      // arena resolving to the wrong one — or to both — would flip the flag
      // twice and look like the tap doing nothing at all.
      await tester.tap(find.text('Silence notifications'));
      await tester.pump();
      expect(store.silenced, isTrue);

      await tester.tap(find.byType(SettingsToggle));
      await tester.pump();
      expect(store.silenced, isFalse);
    });

    testWidgets('the row fires from its corners, not just its middle',
        (tester) async {
      await tester.pumpWidget(_row());

      // `test/tap_target_test.dart`'s rule: a centre tap passes on every
      // hit-test bug there is, because the glyph and the label accept hits of
      // their own. The row's box is the `HoverRegion`'s opaque detector or the
      // padding around the text is dead.
      final rect = tester.getRect(find.byType(NotificationSilenceRow));
      await tester.tapAt(rect.topLeft + const Offset(2, 2));
      await tester.pump();
      expect(store.silenced, isTrue);

      await tester.tapAt(rect.bottomLeft + const Offset(2, -2));
      await tester.pump();
      expect(store.silenced, isFalse);
    });

    testWidgets('the row carries the glyph the bell wears', (tester) async {
      await tester.pumpWidget(_row());
      expect(
        find.descendant(
          of: find.byType(NotificationSilenceRow),
          matching: _icon(FontAwesomeIcons.bell),
        ),
        findsOneWidget,
      );

      store.setSilenced(true);
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(NotificationSilenceRow),
          matching: _icon(FontAwesomeIcons.bellSlash),
        ),
        findsOneWidget,
      );
    });
  });
}
