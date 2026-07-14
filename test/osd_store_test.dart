import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/osd/osd_store.dart';

void main() {
  const short = Duration(milliseconds: 30);

  test('shows the requested kind and level', () {
    final store = OsdStore.forTesting(hideDelay: short);

    store.show(OsdKind.volume, 0.4);

    expect(store.visible, isTrue);
    expect(store.current?.kind, OsdKind.volume);
    expect(store.current?.value, 0.4);
    expect(store.current?.muted, isFalse);
  });

  test('a new kind replaces the one on screen rather than stacking', () {
    final store = OsdStore.forTesting(hideDelay: short);

    store.show(OsdKind.volume, 0.4);
    store.show(OsdKind.brightness, 0.9);

    expect(store.current?.kind, OsdKind.brightness);
    expect(store.current?.value, 0.9);
  });

  test('levels outside 0..1 are clamped', () {
    final store = OsdStore.forTesting(hideDelay: short);

    store.show(OsdKind.volume, 1.4);
    expect(store.current?.value, 1.0);

    store.show(OsdKind.volume, -0.2);
    expect(store.current?.value, 0.0);
  });

  test('hides after the delay, and the fade-out drops the request', () async {
    final store = OsdStore.forTesting(hideDelay: short);
    store.show(OsdKind.microphone, 0.5, muted: true);

    await Future<void>.delayed(short * 2);

    // Still current, so the window survives long enough to animate out.
    expect(store.visible, isFalse);
    expect(store.current, isNotNull);

    store.onFadeOutComplete();
    expect(store.current, isNull);
  });

  test('a later change restarts the hide timer', () async {
    final store = OsdStore.forTesting(hideDelay: short);
    store.show(OsdKind.volume, 0.2);

    await Future<void>.delayed(short ~/ 2);
    store.show(OsdKind.volume, 0.3);
    await Future<void>.delayed(short ~/ 2);

    // The first timer's deadline has passed, but the second change reset it.
    expect(store.visible, isTrue);

    await Future<void>.delayed(short);
    expect(store.visible, isFalse);
  });

  test('a change during the fade-out brings the indicator back', () async {
    final store = OsdStore.forTesting(hideDelay: short);
    store.show(OsdKind.volume, 0.2);
    await Future<void>.delayed(short * 2);
    expect(store.visible, isFalse);

    store.show(OsdKind.brightness, 0.6);

    expect(store.visible, isTrue);
    // The fade-out that was in flight must not tear down the revived window.
    store.onFadeOutComplete();
    expect(store.current?.kind, OsdKind.brightness);
  });

  test('notifies on show and on hide', () async {
    final store = OsdStore.forTesting(hideDelay: short);
    var notifications = 0;
    store.addListener(() => notifications++);

    store.show(OsdKind.volume, 0.2);
    expect(notifications, 1);

    await Future<void>.delayed(short * 2);
    expect(notifications, 2);
  });
}
