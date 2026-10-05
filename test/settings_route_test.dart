import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/overlay/settings/shell.dart';
import 'package:moonswing/overlay/settings_route.dart';

void main() {
  group('SettingsController', () {
    test('open notifies and holds the route until consumed', () {
      final controller = SettingsController.forTesting();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.pending, isNull);
      controller.open(SettingsRoute.background);

      expect(notifications, 1);
      expect(controller.signalCount, 1);
      expect(controller.pending, SettingsRoute.background);

      controller.consume();
      expect(controller.pending, isNull);
    });

    test('defaults to the settings tab when no route is given', () {
      final controller = SettingsController.forTesting();
      addTearDown(controller.dispose);
      controller.open();
      expect(controller.pending, const SettingsRoute());
      expect(controller.pending?.tab, 'settings');
      expect(controller.pending?.category, 'shell');
      expect(controller.pending?.shellCategory, isNull);
    });

    // The root compares the incoming route against the open one, so routes must
    // compare by value rather than by identity.
    test('routes have value equality', () {
      expect(
        const SettingsRoute(shellCategory: 'Background'),
        SettingsRoute.background,
      );
      expect(SettingsRoute.background, isNot(SettingsRoute.desktop));
      expect(
        const SettingsRoute(shellCategory: 'Background').hashCode,
        SettingsRoute.background.hashCode,
      );
    });

    // Unlike LauncherController.toggle, this never asks to close: the request
    // names a destination, and dismissing the settings in response to "show me
    // the background settings" would be nonsense.
    test('a second open replaces the pending route rather than cancelling', () {
      final controller = SettingsController.forTesting();
      addTearDown(controller.dispose);
      controller.open(SettingsRoute.background);
      controller.open(SettingsRoute.desktop);
      expect(controller.pending, SettingsRoute.desktop);
      expect(controller.signalCount, 2);
    });
  });

  // The route titles are plain strings; this is what stops one going stale when
  // a category is renamed.
  group('shell category titles', () {
    test('every route the shell can emit lands on a real category', () {
      expect(isShellCategory(SettingsRoute.background.shellCategory!), isTrue);
      expect(isShellCategory(SettingsRoute.desktop.shellCategory!), isTrue);
      expect(isShellCategory(SettingsRoute.modules.shellCategory!), isTrue);
    });

    test('an unknown title is not a category', () {
      expect(isShellCategory('Nonexistent'), isFalse);
    });
  });
}
