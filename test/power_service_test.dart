import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/power/power_controller.dart';
import 'package:graceful_shell/power/power_inhibitor.dart';
import 'package:graceful_shell/power/power_service.dart';

/// A [PowerInhibitor] that records rather than talks to logind — the whole
/// reason the interface exists: a unit test must never change what the machine
/// running it does when somebody presses its power button.
class FakeInhibitor implements PowerInhibitor {
  int takes = 0;
  int releases = 0;
  bool failNextTake = false;

  bool _held = false;

  @override
  bool get isHeld => _held;

  @override
  Future<void> take() async {
    takes++;
    if (failNextTake) {
      failNextTake = false;
      throw StateError('no logind here');
    }
    _held = true;
  }

  @override
  Future<void> release() async {
    releases++;
    _held = false;
  }
}

void main() {
  group('PowerKeyService', () {
    test('holds nothing until the compositor confirms the key', () async {
      final fake = FakeInhibitor();
      final service = PowerKeyService.forTesting(inhibitor: fake);

      await service.setConfig(const PowerConfig());
      // The config wants the key intercepted, but nothing has said the press
      // will ever arrive — and inhibiting a key nobody answers is a power
      // button that does nothing.
      expect(service.wantsInhibitor, isFalse);
      expect(fake.isHeld, isFalse);
      expect(fake.takes, 0);

      await service.setKeyOwned(true);
      expect(service.wantsInhibitor, isTrue);
      expect(service.isInhibiting, isTrue);
      expect(fake.takes, 1);
    });

    test('a refused registration gives the lock back', () async {
      final fake = FakeInhibitor();
      final service = PowerKeyService.forTesting(inhibitor: fake);
      await service.setConfig(const PowerConfig());
      await service.setKeyOwned(true);
      expect(fake.isHeld, isTrue);

      // The combination became unavailable, or another client took it.
      await service.setKeyOwned(false);
      expect(fake.isHeld, isFalse);
      expect(fake.releases, 1);
    });

    test('key_action = "none" releases without waiting for a restart',
        () async {
      final fake = FakeInhibitor();
      final service = PowerKeyService.forTesting(inhibitor: fake);
      await service.setKeyOwned(true);
      await service.setConfig(const PowerConfig());
      expect(fake.isHeld, isTrue);

      await service.setConfig(
          const PowerConfig(keyAction: PowerKeyAction.none));
      expect(fake.isHeld, isFalse);

      // And back on again, live.
      await service.setConfig(const PowerConfig());
      expect(fake.isHeld, isTrue);
      expect(fake.takes, 2);
    });

    test('inhibit_logind = false keeps the key but drops the lock', () async {
      final fake = FakeInhibitor();
      final service = PowerKeyService.forTesting(inhibitor: fake);
      await service.setKeyOwned(true);
      await service.setConfig(const PowerConfig(inhibitLogind: false));

      expect(service.config.handlesKey, isTrue);
      expect(fake.isHeld, isFalse);
      expect(fake.takes, 0);
    });

    // ConfigStore notifies on every keystroke anywhere in the settings UI, and
    // the root forwards every one of those; a round trip to logind per
    // keystroke is what the comparison prevents.
    test('an unchanged config does not touch the lock again', () async {
      final fake = FakeInhibitor();
      final service = PowerKeyService.forTesting(inhibitor: fake);
      await service.setKeyOwned(true);
      await service.setConfig(const PowerConfig());
      await service.setConfig(const PowerConfig());
      await service.setConfig(const PowerConfig());

      expect(fake.takes, 1);
      expect(fake.releases, 0);
    });

    test('a failed take is recorded rather than thrown, and retried later',
        () async {
      final fake = FakeInhibitor()..failNextTake = true;
      final service = PowerKeyService.forTesting(inhibitor: fake);
      await service.setKeyOwned(true);
      await service.setConfig(const PowerConfig());

      expect(fake.isHeld, isFalse);
      expect(service.lastError, contains('no logind here'));

      // The chain is not poisoned: the next transition still runs.
      await service.setConfig(
          const PowerConfig(keyAction: PowerKeyAction.lock));
      expect(fake.isHeld, isTrue);
      expect(service.lastError, isNull);
    });

    test('shutdown gives the lock back whatever the config says', () async {
      final fake = FakeInhibitor();
      final service = PowerKeyService.forTesting(inhibitor: fake);
      await service.setKeyOwned(true);
      await service.setConfig(const PowerConfig());
      expect(fake.isHeld, isTrue);

      await service.shutdown();
      expect(fake.isHeld, isFalse);
    });
  });

  group('PowerController', () {
    test('a press notifies and counts', () {
      final controller = PowerController.forTesting();
      addTearDown(controller.dispose);
      var presses = 0;
      controller.addListener(() => presses++);

      controller.pressPowerKey();
      controller.pressPowerKey();

      expect(presses, 2);
      expect(controller.signalCount, 2);
    });
  });
}
