import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/theme/builtin_themes.dart';
import 'package:moonswing/theme/theme_store.dart';

/// Every store here is rooted at a temp directory — never the user's real
/// `~/.config/moonswing/themes`.
void main() {
  late Directory tempDir;
  late String themesDir;
  late String configPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gs_theme_store_test');
    themesDir = '${tempDir.path}/themes';
    configPath = '${tempDir.path}/config.toml';
    await File(configPath).writeAsString('theme = "forest"\n');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<(ThemeStore, ConfigStore)> open() async {
    final config = await ConfigStore.loadFrom(configPath);
    final themes = ThemeStore.forTesting(directory: themesDir);
    themes.start(config: config);
    return (themes, config);
  }

  test('seeds the shipped themes into an empty directory', () async {
    expect(Directory(themesDir).existsSync(), isFalse);
    final (themes, config) = await open();

    for (final slug in kBuiltInThemes.keys) {
      expect(File('$themesDir/$slug.toml').existsSync(), isTrue,
          reason: '$slug should have been seeded');
    }
    expect(themes.themes.map((t) => t.slug), containsAll(kBuiltInThemes.keys));
    // Built-ins sort first, and the display name comes from the file's `name`.
    expect(themes.themes.first.builtIn, isTrue);
    expect(themes.themes.firstWhere((t) => t.slug == 'dracula').displayName,
        'Dracula');

    themes.dispose();
    config.dispose();
  });

  test('resolves the theme config.toml names, and follows a change to it',
      () async {
    final (themes, config) = await open();
    expect(themes.activeName, 'forest');
    expect(themes.theme.accent, const Color(0xFF2E8B57));

    config.set(['theme'], 'dracula');
    expect(themes.activeName, 'dracula');
    expect(themes.theme.accent, const Color(0xFFBD93F9));
    expect(themes.theme.workspaceBackground, const Color(0xFF282A36));

    themes.dispose();
    config.dispose();
  });

  test('select writes the name back to config.toml', () async {
    final (themes, config) = await open();
    themes.select('glassy');

    expect(config.get<String>(['theme']), 'glassy');
    expect(themes.activeName, 'glassy');

    themes.dispose();
    config.dispose();
  });

  test('an unknown, missing or corrupt theme falls back to the default',
      () async {
    // A file that is not TOML at all, plus a name nothing on disk answers to.
    await Directory(themesDir).create(recursive: true);
    await File('$themesDir/broken.toml').writeAsString('this is not = = toml');
    await File(configPath).writeAsString('theme = "nope"\n');

    final (themes, config) = await open();

    expect(themes.activeName, 'nope');
    // Falls back to the built-in default (glassy) rather than an unstyled
    // shell.
    expect(themes.theme.accent, const Color(0xFF7FB6FF));
    // The unparseable file is simply absent from the picker.
    expect(themes.themes.map((t) => t.slug), isNot(contains('broken')));

    themes.dispose();
    config.dispose();
  });

  test('create slugifies, de-duplicates, and selects the new theme', () async {
    final (themes, config) = await open();

    final slug = themes.create('My Theme!');
    expect(slug, 'my-theme');
    expect(themes.activeName, 'my-theme');
    expect(config.get<String>(['theme']), 'my-theme');
    expect(File('$themesDir/my-theme.toml').existsSync(), isTrue);
    expect(themes.themes.firstWhere((t) => t.slug == slug).displayName,
        'My Theme!');

    // A colliding name gets a suffix rather than overwriting.
    expect(themes.create('My Theme!'), 'my-theme-2');
    // A name that slugifies to nothing is refused.
    expect(themes.create('!!!'), isNull);

    themes.dispose();
    config.dispose();
  });

  test('create copies the active theme, not the defaults', () async {
    final (themes, config) = await open();
    themes.select('dracula');
    themes.create('Mine');

    expect(themes.theme.accent, const Color(0xFFBD93F9));

    themes.dispose();
    config.dispose();
  });

  test('editing a built-in forks it and leaves the shipped file untouched',
      () async {
    final (themes, config) = await open();
    themes.select('dracula');
    final shipped = await File('$themesDir/dracula.toml').readAsString();

    themes.edit('accent', '#123456');
    await themes.flush();

    // The active theme is now a user copy, carrying the edit.
    expect(themes.activeName, isNot('dracula'));
    expect(themes.activeIsBuiltIn, isFalse);
    expect(themes.theme.accent, const Color(0xFF123456));
    // ...and the rest of Dracula came along.
    expect(themes.theme.workspaceBackground, const Color(0xFF282A36));

    expect(await File('$themesDir/dracula.toml').readAsString(), shipped);

    themes.dispose();
    config.dispose();
  });

  test('edits to a user theme round-trip through disk', () async {
    final (themes, config) = await open();
    themes.create('Mine');
    themes.edit('accent', '#00FF00');
    themes.edit('font', 'Cantarell');
    // The bar's geometry writes an int beside two doubles, so this also covers
    // the TOML encoder keeping the types apart.
    themes.edit('panel_margin', 12);
    themes.edit('panel_radius', 10.0);
    themes.edit('panel_border_width', 1.5);
    await themes.flush();

    final map = (await TomlDocument.load('$themesDir/mine.toml')).toMap();
    final reparsed = ThemeConfig.fromMap(map);
    expect(reparsed.accent, const Color(0xFF00FF00));
    expect(reparsed.fontFamily, 'Cantarell');
    expect(reparsed.panelMargin, 12);
    expect(reparsed.panelRadius, 10.0);
    expect(reparsed.panelBorderWidth, 1.5);
    expect(reparsed, themes.theme);
    // The display name survives a write.
    expect(map['name'], 'Mine');

    themes.dispose();
    config.dispose();
  });

  test('rename changes a user theme\'s display name and keeps its file',
      () async {
    final (themes, config) = await open();
    final slug = themes.create('Mine')!;

    themes.rename('  Evening  ');
    await themes.flush();

    expect(themes.activeName, slug);
    expect(config.get<String>(['theme']), slug);
    expect(themes.themes.firstWhere((t) => t.slug == slug).displayName,
        'Evening');
    final map = (await TomlDocument.load('$themesDir/$slug.toml')).toMap();
    expect(map['name'], 'Evening');

    // A blank name is refused rather than written.
    themes.rename('   ');
    expect(themes.themes.firstWhere((t) => t.slug == slug).displayName,
        'Evening');

    themes.dispose();
    config.dispose();
  });

  test('renaming a built-in forks it under the new name', () async {
    final (themes, config) = await open();
    themes.select('dracula');
    final shipped = await File('$themesDir/dracula.toml').readAsString();

    themes.rename('Night Owl');
    await themes.flush();

    expect(themes.activeName, 'night-owl');
    expect(themes.activeIsBuiltIn, isFalse);
    expect(themes.theme.accent, const Color(0xFFBD93F9));
    expect(themes.themes.firstWhere((t) => t.slug == 'night-owl').displayName,
        'Night Owl');
    expect(await File('$themesDir/dracula.toml').readAsString(), shipped);

    themes.dispose();
    config.dispose();
  });

  test('delete removes a user theme and refuses a built-in', () async {
    final (themes, config) = await open();
    final slug = themes.create('Mine')!;

    expect(themes.delete('dracula'), isFalse);
    expect(File('$themesDir/dracula.toml').existsSync(), isTrue);

    // Deleting the active theme falls back to the default.
    expect(themes.delete(slug), isTrue);
    expect(File('$themesDir/$slug.toml').existsSync(), isFalse);
    expect(themes.activeName, kDefaultThemeName);
    expect(themes.themes.map((t) => t.slug), isNot(contains(slug)));

    themes.dispose();
    config.dispose();
  });

  test('a stale shipped theme is rewritten at start-up', () async {
    // The shell owns these files, so a palette fix has to reach an install
    // that has already run once. Leaving the old copy in place is how a
    // shipped theme silently keeps rendering last release's colours.
    await Directory(themesDir).create(recursive: true);
    await File('$themesDir/dracula.toml')
        .writeAsString('name = "Stale"\naccent = "#ABCDEF"\n');

    final (themes, config) = await open();
    themes.select('dracula');

    expect(await File('$themesDir/dracula.toml').readAsString(),
        kBuiltInThemes['dracula']);
    expect(themes.theme.accent, const Color(0xFFBD93F9));

    themes.dispose();
    config.dispose();
  });

  test('a user theme is left alone at start-up', () async {
    await Directory(themesDir).create(recursive: true);
    const mine = 'name = "Mine"\naccent = "#ABCDEF"\n';
    await File('$themesDir/mine.toml').writeAsString(mine);

    final (themes, config) = await open();
    themes.select('mine');

    expect(await File('$themesDir/mine.toml').readAsString(), mine);
    expect(themes.theme.accent, const Color(0xFFABCDEF));

    themes.dispose();
    config.dispose();
  });

  test('notifies listeners when the palette changes, and only then', () async {
    final (themes, config) = await open();
    var notifications = 0;
    themes.addListener(() => notifications++);

    config.set(['theme'], 'dracula');
    expect(notifications, 1);

    // An unrelated config edit must not churn every ThemeProvider in the shell.
    config.set(['modules', 'clock', 'show_date'], false);
    expect(notifications, 1);

    themes.dispose();
    config.dispose();
  });
}
