import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/notification_panel_controller.dart';

void main() {
  group('NotificationPanelController', () {
    test('toggle notifies the root', () {
      final controller = NotificationPanelController.forTesting();
      addTearDown(controller.dispose);
      var signals = 0;
      controller.addListener(() => signals++);

      controller.toggle();
      controller.toggle();

      expect(signals, 2);
      expect(controller.signalCount, 2);
    });

    // The load-bearing separation. The root *listens* to this controller for
    // the toggle, so if the open flag were published through the same notifier
    // the root's own write on opening would come straight back in as a second
    // toggle and close the panel it had just opened.
    test('the open flag is not a toggle', () {
      final controller = NotificationPanelController.forTesting();
      addTearDown(controller.dispose);
      var signals = 0;
      controller.addListener(() => signals++);

      controller.setOpen(true);
      controller.setOpen(false);

      expect(signals, 0);
    });

    test('the open flag is what the triggers draw themselves from', () {
      final controller = NotificationPanelController.forTesting();
      addTearDown(controller.dispose);
      var flags = <bool>[];
      controller.isOpen.addListener(() => flags.add(controller.isOpen.value));

      controller.setOpen(true);
      // Idempotent: the root calls this from both the open and the teardown
      // path, and a repeat must not re-lay every bell in the shell.
      controller.setOpen(true);
      controller.setOpen(false);

      expect(flags, [true, false]);
      expect(controller.isOpen.value, isFalse);
    });

    test('a toggle does not move the open flag', () {
      final controller = NotificationPanelController.forTesting();
      addTearDown(controller.dispose);

      controller.toggle();

      expect(controller.isOpen.value, isFalse);
    });
  });
}
