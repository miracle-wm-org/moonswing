import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/launcher/launcher_controller.dart';

void main() {
  group('LauncherController', () {
    test('each toggle notifies exactly once', () {
      final controller = LauncherController.forTesting();
      var fires = 0;
      controller.addListener(() => fires++);

      controller.toggle();
      controller.toggle();

      expect(fires, 2);
      expect(controller.signalCount, 2);
    });

    test('the controller carries no window state of its own', () {
      // The root decides whether a toggle opens or closes; repeated requests
      // must therefore keep arriving rather than being coalesced here.
      final controller = LauncherController.forTesting();
      var fires = 0;
      controller.addListener(() => fires++);

      for (var i = 0; i < 5; i++) {
        controller.toggle();
      }

      expect(fires, 5);
    });
  });
}
