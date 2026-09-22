import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/lock/lock_controller.dart';

void main() {
  final controller = LockController.instance;

  setUp(() => controller.clear());
  tearDown(() => controller.clear());

  test('starts idle', () {
    expect(controller.isRequested, isFalse);
    expect(controller.isActive, isFalse);
  });

  test('lock() requests a lock and notifies once', () {
    var notifications = 0;
    void listener() => notifications++;
    controller.addListener(listener);
    addTearDown(() => controller.removeListener(listener));

    controller.lock();

    expect(controller.isRequested, isTrue);
    expect(controller.isActive, isFalse);
    expect(notifications, 1);
  });

  test('a second lock() while already requested is ignored', () {
    // The shell root creates the lock windows in response to the first
    // notification; a repeat must not build a second set.
    var notifications = 0;
    void listener() => notifications++;
    controller.lock();
    controller.addListener(listener);
    addTearDown(() => controller.removeListener(listener));

    controller.lock();

    expect(notifications, 0);
  });

  test('markActive() reports the lock as up', () {
    controller.lock();
    controller.markActive();
    expect(controller.isRequested, isTrue);
    expect(controller.isActive, isTrue);
  });

  test('clear() returns to idle', () {
    controller.lock();
    controller.markActive();

    controller.clear();

    expect(controller.isRequested, isFalse);
    expect(controller.isActive, isFalse);
  });

  test('clear() from idle does not notify', () {
    // Teardown calls clear() unconditionally; if that notified while idle the
    // root would re-enter its lock handler for no reason.
    var notifications = 0;
    void listener() => notifications++;
    controller.addListener(listener);
    addTearDown(() => controller.removeListener(listener));

    controller.clear();

    expect(notifications, 0);
  });

  test('the state after clear() allows locking again', () {
    controller.lock();
    controller.markActive();
    controller.clear();

    controller.lock();

    expect(controller.isRequested, isTrue);
  });

  test('markFailed() records the reason and leaves the lock down', () {
    controller.lock();

    controller.markFailed('no ext-session-lock-v1');

    expect(controller.isRequested, isFalse);
    expect(controller.isActive, isFalse);
    expect(controller.lastError, 'no ext-session-lock-v1');
  });

  test('a new lock() clears the previous error', () {
    controller.lock();
    controller.markFailed('boom');

    controller.lock();

    expect(controller.lastError, isNull);
  });
}
