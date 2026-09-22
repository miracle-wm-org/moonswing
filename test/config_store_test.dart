import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';
import 'package:moonswing/config_store.dart';

/// End-to-end test of the settings write layer against a real temp file.
///
/// Uses [ConfigStore.loadFrom] with an isolated temp directory so it never
/// touches the user's real `~/.config/moonswing/config.toml`.
void main() {
  late Directory tempDir;
  late String path;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gs_config_store_test');
    path = '${tempDir.path}/config.toml';
    await File(path).writeAsString('''
theme = "dracula"

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
    expect(store.get<String>(['theme']), 'dracula');
    expect(store.get<num>(['modules', 'weather', 'refresh_minutes']), 10);
    expect(store.getList<String>(['panels', 'top', 'layout', 'right']),
        ['battery', 'clock']);

    // Mutates a scalar, creates a brand-new nested key, and replaces a list.
    // A top-level scalar beside the tables: TOML requires it be emitted
    // before them, so this also guards the writer's key ordering.
    store.set(['theme'], 'glassy');
    store.set(['modules', 'weather', 'unit'], 'celsius');
    store.set(['modules', 'clock', 'show_date'], true); // new table
    store.set(['panels', 'top', 'layout', 'right'], ['clock', 'battery']);

    await store.save();

    // Re-read the file fresh from disk.
    final reparsed = (await TomlDocument.load(path)).toMap();
    expect(reparsed['theme'], 'glassy');
    expect(reparsed['modules']['weather']['unit'], 'celsius');
    expect(reparsed['modules']['clock']['show_date'], true);
    expect(reparsed['panels']['top']['layout']['right'], ['clock', 'battery']);

    // Atomic write leaves no temp file behind.
    expect(await File('$path.tmp').exists(), isFalse);

    // A second store instance sees the persisted changes (round-trip).
    final reopened = await ConfigStore.loadFrom(path);
    expect(reopened.get<String>(['theme']), 'glassy');

    store.dispose();
    reopened.dispose();
  });

  test('appConfig derives a typed config from the live in-memory map',
      () async {
    final store = await ConfigStore.loadFrom(path);

    expect(store.appConfig.themeName, 'dracula');
    expect(store.appConfig.panels['top']?.layout.right, ['battery', 'clock']);

    // A live edit is reflected immediately, without touching disk.
    store.set(['theme'], 'glassy');
    store.set(['panels', 'top', 'layout', 'right'], ['clock']);

    expect(store.appConfig.themeName, 'glassy');
    expect(store.appConfig.panels['top']?.layout.right, ['clock']);

    store.dispose();
  });

  test('needsRestart tracks only window-geometry / panel-set / background '
      'changes', () async {
    final store = await ConfigStore.loadFrom(path);
    expect(store.needsRestart, isFalse);

    // Live-updatable fields never require a restart.
    store.set(['theme'], 'glassy');
    store.set(['panels', 'top', 'layout', 'right'], ['clock']);
    store.set(['panels', 'top', 'padding_horizontal'], 20);
    expect(store.needsRestart, isFalse);

    // A restart-only field flips it.
    store.set(['panels', 'top', 'anchor'], 'bottom');
    expect(store.needsRestart, isTrue);

    store.dispose();
  });

  test('needsRestart flags added panels and background-layer presence',
      () async {
    final store = await ConfigStore.loadFrom(path);
    expect(store.needsRestart, isFalse);

    store.set(['panels', 'bottom', 'height'], 40);
    expect(store.needsRestart, isTrue);
    store.dispose();

    // The wallpaper half needs a config that has *no* background surface yet,
    // and since the desktop grid is on by default that means saying so: a
    // config silent about `[desktop]` already has the surface, and adding a
    // wallpaper to one that exists is live (see the builder in main.dart,
    // which follows `LiveConfigScope` for everything but the surface itself).
    final gridless = '${tempDir.path}/gridless.toml';
    await File(gridless).writeAsString('''
[panels.top]
anchor = "top"
height = 32

[desktop]
enabled = false
''');
    final store2 = await ConfigStore.loadFrom(gridless);
    expect(store2.needsRestart, isFalse);
    store2.set(['background', 'entries'], [
      {'path': '/tmp/w.jpg', 'shown': true}
    ]);
    expect(store2.needsRestart, isTrue);
    store2.dispose();
  });

  // The signature encodes whether the background *surface* exists, not the two
  // inputs to that decision, so enabling the grid on a config that already has
  // a wallpaper must not demand a restart.
  test('needsRestart tracks the background surface, not its two causes',
      () async {
    final bare = Directory.systemTemp.createTempSync('gs_config_store_desktop');
    final barePath = '${bare.path}/config.toml';
    File(barePath).writeAsStringSync('''
[panels.top]
anchor = "top"
height = 32

[desktop]
enabled = false
''');

    // No wallpaper, no grid -> enabling the grid creates the surface.
    final store = await ConfigStore.loadFrom(barePath);
    expect(store.needsRestart, isFalse);
    store.set(['desktop', 'enabled'], true);
    expect(store.needsRestart, isTrue);
    // ...and turning it back off destroys it again.
    store.set(['desktop', 'enabled'], false);
    expect(store.needsRestart, isFalse);
    store.dispose();

    // The grid is on by default, so a config that names no `[desktop]` section
    // already has the surface: the signature must agree with the typed config
    // main() built it from, or the first unrelated edit raises the banner.
    File(barePath).writeAsStringSync('''
[panels.top]
anchor = "top"
height = 32
''');
    final implicit = await ConfigStore.loadFrom(barePath);
    implicit.set(['desktop', 'enabled'], true);
    expect(implicit.needsRestart, isFalse);
    implicit.set(['desktop', 'enabled'], false);
    expect(implicit.needsRestart, isTrue);
    implicit.dispose();

    // A wallpaper already forces the surface, so the grid is free.
    File(barePath).writeAsStringSync('''
[panels.top]
anchor = "top"
height = 32

[[background.entries]]
path = "/tmp/w.jpg"
shown = true
''');
    final withWallpaper = await ConfigStore.loadFrom(barePath);
    withWallpaper.set(['desktop', 'enabled'], true);
    expect(withWallpaper.needsRestart, isFalse);

    // Grid geometry and the item list are live, never restart-only.
    withWallpaper.set(['desktop', 'cell_width'], 120);
    withWallpaper.set(['desktop', 'items'], [
      {'kind': 'file', 'target': '/tmp/a.txt', 'column': 0, 'row': 0}
    ]);
    expect(withWallpaper.needsRestart, isFalse);
    withWallpaper.dispose();

    bare.deleteSync(recursive: true);
  });

  // What the Panels & Layout remove button does: one call drops the whole
  // `[panels.<name>]` sub-table, and the panel set is restart-only, so the
  // banner comes up without the settings UI wiring anything.
  test('removing a panel drops its whole table and demands a restart',
      () async {
    // Two panels on disk, so the removal is of a panel that was there at load
    // — adding one and taking it away again returns to the startup signature,
    // which is correct and would prove nothing.
    final seed = await ConfigStore.loadFrom(path);
    seed.set(['panels', 'bottom', 'anchor'], 'bottom');
    await seed.save();
    seed.dispose();

    final store = await ConfigStore.loadFrom(path);
    expect(store.panelNames, containsAll(<String>['top', 'bottom']));
    expect(store.needsRestart, isFalse);

    // One call takes the whole sub-table, `[panels.top.layout]` included.
    store.remove(['panels', 'top']);
    expect(store.panelNames, ['bottom']);
    expect(store.needsRestart, isTrue);

    await store.save();
    final reparsed = (await TomlDocument.load(path)).toMap();
    expect((reparsed['panels'] as Map).containsKey('top'), isFalse);
    expect((reparsed['panels'] as Map).containsKey('bottom'), isTrue);
    store.dispose();
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
