import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/request_controller.dart';

class _TestController extends RequestController<String, int> {}

class _TestSignal extends SignalController {
  void poke() => signal();
}

void main() {
  group('RequestController', () {
    test('declines immediately when nothing is listening', () async {
      final controller = _TestController();
      expect(await controller.pick('a'), isNull);
      expect(controller.pending, isNull);
    });

    test('resolves with the completed result', () async {
      final controller = _TestController();
      controller.addListener(() {});
      final future = controller.pick('a');
      expect(controller.pending, 'a');
      controller.complete(42);
      expect(await future, 42);
      expect(controller.pending, isNull);
    });

    test('a second request supersedes the first as declined', () async {
      final controller = _TestController();
      controller.addListener(() {});
      final first = controller.pick('a');
      final second = controller.pick('b');
      expect(await first, isNull);
      expect(controller.pending, 'b');
      controller.complete(7);
      expect(await second, 7);
    });

    test('complete on an idle controller neither throws nor notifies', () {
      final controller = _TestController();
      var notifies = 0;
      controller.addListener(() => notifies++);
      controller.complete(1);
      expect(notifies, 0);
    });

    test('dispose answers the awaiting caller', () async {
      final controller = _TestController();
      controller.addListener(() {});
      final future = controller.pick('a');
      controller.dispose();
      // The future must resolve — a teardown that strands an awaiting D-Bus
      // Start call hangs the portal client forever.
      expect(await future, isNull);
    });

    test('pending clears before the future resolves', () async {
      // The awaiting caller may re-read `pending` in its continuation; a
      // stale request there would re-open the window that just closed.
      final controller = _TestController();
      controller.addListener(() {});
      final future = controller.pick('a').then((r) {
        expect(controller.pending, isNull);
        return r;
      });
      controller.complete(3);
      await future;
    });
  });

  group('SignalController', () {
    test('counts and notifies', () {
      final controller = _TestSignal();
      var notifies = 0;
      controller.addListener(() => notifies++);
      controller.poke();
      controller.poke();
      expect(controller.signalCount, 2);
      expect(notifies, 2);
    });
  });
}
