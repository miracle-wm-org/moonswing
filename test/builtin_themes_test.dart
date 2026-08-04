import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/panel_background.dart';
import 'package:graceful_shell/theme/builtin_themes.dart';

void main() {
  test('the default theme ships', () {
    expect(kBuiltInThemes.keys, contains(kDefaultThemeName));
  });

  test('every shipped theme parses and names itself', () {
    for (final entry in kBuiltInThemes.entries) {
      final map = TomlDocument.parse(entry.value).toMap();
      expect(map['name'], isA<String>(),
          reason: '${entry.key} needs a display name');
      expect(() => ThemeConfig.fromMap(map), returnsNormally);
    }
  });

  test('every shipped theme spells out every key', () {
    // A shipped theme must not lean on a ThemeConfig default: changing a
    // default would then silently restyle it.
    final expected = {
      ...ThemeConfig.colorKeys,
      'font',
      'blur',
      'panel_gradient',
      'panel_margin',
      'panel_radius',
      'panel_border_width',
    };
    for (final entry in kBuiltInThemes.entries) {
      final map = TomlDocument.parse(entry.value).toMap();
      expect(map.keys, containsAll(expected), reason: 'in ${entry.key}');
    }
  });

  test('graceful reproduces the palette that used to be the default', () {
    final graceful =
        ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes['graceful']!).toMap());
    // Every colour matches the ThemeConfig defaults, so seeding the themes
    // directory cannot change how an existing install looks.
    const defaults = ThemeConfig();
    expect(graceful, defaults);
  });

  test('a shipped theme that keeps the gradient is opaque enough to read', () {
    // Nothing forces a bar to be translucent, but a gradient one puts the
    // accent against the screen edge — so a theme either commits to the fade
    // or turns it off, which is the choice glassy makes.
    for (final entry in kBuiltInThemes.entries) {
      final theme =
          ThemeConfig.fromMap(TomlDocument.parse(entry.value).toMap());
      if (!theme.panelGradient) continue;
      expect(theme.panelBackground.a, greaterThan(0.5), reason: 'in ${entry.key}');
    }
  });

  test('the flush themes keep the geometry the bar always had', () {
    // graceful is pinned to the ThemeConfig defaults by the test above, but
    // dracula is not — and neither should have moved off the screen edge.
    for (final slug in const ['graceful', 'dracula']) {
      final theme =
          ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes[slug]!).toMap());
      expect(theme.panelMargin, 0, reason: 'in $slug');
      expect(theme.panelRadius, 0.0, reason: 'in $slug');
      expect(theme.panelBorderWidth, 0.0, reason: 'in $slug');
    }
  });

  test('glassy floats, rounds, and has a visible rim', () {
    // The theme this feature exists for: alpha alone made the bar see-through,
    // but it still read as a strip of tint rather than a pane of glass.
    final glassy =
        ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes['glassy']!).toMap());
    expect(glassy.panelMargin, greaterThan(0));
    expect(glassy.panelRadius, greaterThan(0));
    expect(glassy.panelBorderWidth, greaterThan(0));
    expect(glassy.panelBorder.a, greaterThan(0),
        reason: 'a rim with a transparent colour draws nothing');
    // Floating means all four corners round.
    expect(panelCornerRadius(theme: glassy),
        BorderRadius.circular(glassy.panelRadius));
  });

  test('toMap round-trips through TOML unchanged', () {
    for (final entry in kBuiltInThemes.entries) {
      final parsed =
          ThemeConfig.fromMap(TomlDocument.parse(entry.value).toMap());
      final written = TomlDocument.fromMap(parsed.toMap()).toString();
      expect(ThemeConfig.fromMap(TomlDocument.parse(written).toMap()), parsed,
          reason: '${entry.key} did not survive a save/load cycle');
    }
  });
}
