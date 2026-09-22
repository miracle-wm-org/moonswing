import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/osd/brightness_monitor.dart';

/// Writes a fake `/sys/class/backlight` device into [root].
void writeDevice(Directory root, String name, int brightness, int max) {
  final device = Directory('${root.path}/$name')..createSync(recursive: true);
  File('${device.path}/brightness').writeAsStringSync('$brightness\n');
  File('${device.path}/max_brightness').writeAsStringSync('$max\n');
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('backlight_test'));
  tearDown(() => root.deleteSync(recursive: true));

  test('reads the level as a fraction of max_brightness', () {
    writeDevice(root, 'intel_backlight', 300, 1200);
    final monitor = BrightnessMonitor(sysfsRoot: root.path)..start();
    addTearDown(monitor.dispose);

    expect(monitor.current, 0.25);
  });

  test('start-up does not report a level, so no indicator flashes', () async {
    writeDevice(root, 'intel_backlight', 600, 1200);
    final monitor = BrightnessMonitor(sysfsRoot: root.path);
    addTearDown(monitor.dispose);

    final seen = <double>[];
    monitor.onChanged.listen(seen.add);
    monitor.start();
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
    expect(monitor.current, 0.5);
  });

  test('a machine with no backlight stays silent', () {
    final monitor = BrightnessMonitor(sysfsRoot: root.path)..start();
    addTearDown(monitor.dispose);

    expect(monitor.current, isNull);
  });

  test('a device with a zero max_brightness is ignored', () {
    writeDevice(root, 'broken', 0, 0);
    final monitor = BrightnessMonitor(sysfsRoot: root.path)..start();
    addTearDown(monitor.dispose);

    expect(monitor.current, isNull);
  });

  test('skips entries that are not backlight devices', () {
    Directory('${root.path}/not_a_device').createSync();
    writeDevice(root, 'real', 900, 1200);
    final monitor = BrightnessMonitor(sysfsRoot: root.path)..start();
    addTearDown(monitor.dispose);

    expect(monitor.current, 0.75);
  });
}
