import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';
import 'package:graceful_shell/settings/config_store.dart';

/// End-to-end test of the settings write layer against a real temp file.
///
/// Uses [ConfigStore.loadFrom] with an isolated temp directory so it never
/// touches the user's real `~/.config/graceful-shell/config.toml`.
void main() {
  late Directory tempDir;
  late String path;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gs_config_store_test');
    path = '${tempDir.path}/config.toml';
    await File(path).writeAsString('''
[theme]
accent = "#853953"

[modules.weather]
unit = "fahrenheit"
refresh_minutes = 10

[panels.top.layout]
right = ["battery", "clock"]
''');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('loads, mutates nested keys and lists, and writes back atomically',
      () async {
    final store = await ConfigStore.loadFrom(path);

    // Reads existing values.
    expect(store.get<String>(['theme', 'accent']), '#853953');
    expect(store.get<num>(['modules', 'weather', 'refresh_minutes']), 10);
    expect(store.getList<String>(['panels', 'top', 'layout', 'right']),
        ['battery', 'clock']);

    // Mutates a scalar, creates a brand-new nested key, and replaces a list.
    store.set(['theme', 'accent'], '#123456');
    store.set(['modules', 'weather', 'unit'], 'celsius');
    store.set(['modules', 'clock', 'show_date'], true); // new table
    store.set(['panels', 'top', 'layout', 'right'], ['clock', 'battery']);

    await store.save();

    // Re-read the file fresh from disk.
    final reparsed = (await TomlDocument.load(path)).toMap();
    expect(reparsed['theme']['accent'], '#123456');
    expect(reparsed['modules']['weather']['unit'], 'celsius');
    expect(reparsed['modules']['clock']['show_date'], true);
    expect(reparsed['panels']['top']['layout']['right'], ['clock', 'battery']);

    // Atomic write leaves no temp file behind.
    expect(await File('$path.tmp').exists(), isFalse);

    // A second store instance sees the persisted changes (round-trip).
    final reopened = await ConfigStore.loadFrom(path);
    expect(reopened.get<String>(['theme', 'accent']), '#123456');

    store.dispose();
    reopened.dispose();
  });

  test('remove deletes a key and persists', () async {
    final store = await ConfigStore.loadFrom(path);
    store.remove(['modules', 'weather', 'refresh_minutes']);
    await store.save();
    final reparsed = (await TomlDocument.load(path)).toMap();
    expect(
        (reparsed['modules']['weather'] as Map).containsKey('refresh_minutes'),
        isFalse);
    store.dispose();
  });
}
