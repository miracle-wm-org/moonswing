import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/shell/appearance.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/font_catalog.dart';
import 'package:moonswing/theme/overlay_effect.dart';
import 'package:moonswing/theme/popup_effect.dart';
import 'package:moonswing/theme/surface_material.dart';
import 'package:moonswing/theme/theme_store.dart';

/// The Theme editor's dropdowns render the value they select, so each has to
/// follow the store: the section reads its seed values only when the *active
/// theme* changes, and a dropdown seeded from them went on showing the old
/// value after a pick on the user's own theme until the page was reopened.
void main() {
  late Directory tempDir;
  late ConfigStore config;
  late ThemeStore themes;
  late String slug;

  // Read once outside the fake clock: the section starts `fc-list` as it is
  // created, and the catalogue caches the answer for every test after.
  setUpAll(() => FontCatalog.instance.list());

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gs_appearance_test');
    final configPath = '${tempDir.path}/config.toml';
    await File(configPath).writeAsString('');
    config = await ConfigStore.loadFrom(configPath);
    themes = ThemeStore.forTesting(directory: '${tempDir.path}/themes');
    themes.start();
    // A theme of the user's own: an edit to a built-in forks it, and the
    // switch to the fork rebuilt every row — which is what hid the bug there.
    slug = themes.create('Mine')!;
  });

  tearDown(() async {
    themes.dispose();
    config.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => CustomScrollView(
                  slivers: [AppearanceSection(store: config, themes: themes)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the editor is one section per thing a key paints', (
    tester,
  ) async {
    await pump(tester);
    // Section headings are drawn upper-case.
    expect(find.text('EDIT MINE'), findsOneWidget);
    for (final group in ThemeGroup.values.skip(1)) {
      expect(find.text(group.label.toUpperCase()), findsOneWidget);
    }
    // Every colour is drawn, once, whichever section it is in.
    for (final colour in SettingsCatalog.themeColors) {
      expect(find.byKey(ValueKey('${colour.key}-$slug')), findsOneWidget);
    }
    // And a row sits in its own item's section: the bar's corners come
    // after the Bar heading and before the Popups one.
    double top(Finder f) => tester.getTopLeft(f).dy;
    final bar = top(find.text(ThemeGroup.bar.label.toUpperCase()));
    final popups = top(find.text(ThemeGroup.popup.label.toUpperCase()));
    final radius = top(find.byKey(ValueKey('panel_radius-$slug')));
    expect(radius, greaterThan(bar));
    expect(radius, lessThan(popups));
  });

  /// The label the dropdown keyed [key] currently shows.
  Finder shown(String key, String label) => find.descendant(
    of: find.byKey(ValueKey('$key-$slug')),
    matching: find.text(label),
  );

  /// Each dropdown's key, what it shows for the resolved theme, and two
  /// values to pick between — whichever is not already showing.
  final cases =
      <(String, String Function(ThemeConfig), List<(String, String)>)>[
        for (final key in [
          'panel_texture',
          'panel_end_texture',
          'popup_texture',
          'popup_border_texture',
        ])
          (
            key,
            (t) => SurfaceMaterial.fromSlug(t.toMap()[key] as String?)!.label,
            [
              (SurfaceMaterial.wood.slug, SurfaceMaterial.wood.label),
              (SurfaceMaterial.stone.slug, SurfaceMaterial.stone.label),
            ],
          ),
        (
          'panel_foliage',
          (t) => t.panelFoliage.label,
          [
            (FoliageStyle.ivy.slug, FoliageStyle.ivy.label),
            (FoliageStyle.moss.slug, FoliageStyle.moss.label),
          ],
        ),
        (
          'popup_animation',
          (t) => t.popupEffect.label,
          [
            (PopupEffect.none.slug, PopupEffect.none.label),
            (PopupEffect.slide.slug, PopupEffect.slide.label),
          ],
        ),
        (
          'overlay_animation',
          (t) => t.overlayEffect.label,
          [
            (OverlayEffect.none.slug, OverlayEffect.none.label),
            (OverlayEffect.scale.slug, OverlayEffect.scale.label),
          ],
        ),
        (
          'overlay_animation_curve',
          (t) => t.overlayCurve.label,
          [
            (OverlayCurve.linear.slug, OverlayCurve.linear.label),
            (OverlayCurve.easeOut.slug, OverlayCurve.easeOut.label),
          ],
        ),
      ];

  for (final (key, read, options) in cases) {
    testWidgets('the $key dropdown shows a pick at once', (tester) async {
      await pump(tester);
      final before = read(themes.theme);
      expect(shown(key, before), findsOneWidget);
      final (value, after) = options.firstWhere((o) => o.$2 != before);

      themes.edit(key, value);
      await tester.pump();

      expect(themes.activeName, slug, reason: 'the edit must not fork');
      expect(shown(key, after), findsOneWidget);
      expect(shown(key, before), findsNothing);
      await themes.flush();
    });
  }
}
