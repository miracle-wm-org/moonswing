// The brightness module's store: what it reads off sysfs, what it hands
// logind, and that a write logind refuses is a visible state.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/modules/brightness.dart';

import 'brightness_monitor_test.dart' show writeDevice;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('backlight_store'));
  tearDown(() => root.deleteSync(recursive: true));

  group('backlightRawFor', () {
    test('scales a fraction to the device range', () {
      expect(backlightRawFor(0.5, 1200), 600);
      expect(backlightRawFor(1.0, 1200), 1200);
    });

    test('never writes zero, which switches some panels off', () {
      expect(backlightRawFor(0.0, 1200), 12);
      expect(backlightRawFor(0.0, 7), 1);
      expect(backlightRawFor(-1.0, 1), 1);
    });

    test('clamps past full scale', () {
      expect(backlightRawFor(2.0, 255), 255);
    });
  });

  test('a lease reads the level; no backlight reads as null', () {
    final empty = BacklightStore.forTesting(
      sysfsRoot: root.path,
      writer: (_, _) async {},
    );
    empty.acquire();
    addTearDown(empty.release);
    expect(empty.level, isNull);

    writeDevice(root, 'intel_backlight', 300, 1200);
    final store = BacklightStore.forTesting(
      sysfsRoot: root.path,
      writer: (_, _) async {},
    );
    store.acquire();
    addTearDown(store.release);
    expect(store.level, 0.25);
  });

  test('setLevel writes the raw value to the named device', () async {
    writeDevice(root, 'amdgpu_bl0', 100, 200);
    final writes = <(String, int)>[];
    final store = BacklightStore.forTesting(
      sysfsRoot: root.path,
      writer: (device, raw) async => writes.add((device, raw)),
    );
    store.acquire();
    addTearDown(store.release);

    await store.setLevel(0.75);
    expect(writes, [('amdgpu_bl0', 150)]);
    expect(store.level, 0.75);
    expect(store.error, isNull);
  });

  test('scrolling steps on the shared 5% grid', () async {
    writeDevice(root, 'intel_backlight', 500, 1000);
    final writes = <int>[];
    final store = BacklightStore.forTesting(
      sysfsRoot: root.path,
      writer: (_, raw) async => writes.add(raw),
    );
    store.acquire();
    addTearDown(store.release);

    store.step(1);
    await Future<void>.delayed(Duration.zero);
    expect(writes, [550]);
  });

  test('a refused write is reported, and cleared by the next one', () async {
    writeDevice(root, 'intel_backlight', 500, 1000);
    var fail = true;
    final store = BacklightStore.forTesting(
      sysfsRoot: root.path,
      writer: (_, _) async {
        if (fail) throw StateError('access denied');
      },
    );
    store.acquire();
    addTearDown(store.release);

    await store.setLevel(0.2);
    expect(store.error, isNotNull);
    expect(store.level, 0.2, reason: 'the level stays on screen');

    fail = false;
    await store.setLevel(0.3);
    expect(store.error, isNull);
  });
}
