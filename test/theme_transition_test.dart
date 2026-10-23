import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/icon_pack.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/theme_store.dart';
import 'package:moonswing/theme/theme_transition.dart';
import 'package:moonswing/theme/tokens.dart';

/// A theme *switch* blends the palette into the new one; an *edit* to the
/// active theme does not, or a colour picker would trail the pointer.
void main() {
  group('ThemeConfig.blend', () {
    const from = ThemeConfig(
      accent: Color(0xFF000000),
      fontSize: 10.0,
      fontFamily: 'From',
      iconPack: IconPack.fontAwesome,
      panelOverhang: 0,
      foliageColor: Color(0xFF000000),
    );
    const to = ThemeConfig(
      accent: Color(0xFFFFFFFF),
      fontSize: 20.0,
      fontFamily: 'To',
      iconPack: IconPack.lucide,
      panelOverhang: 40,
      foliageColor: Color(0xFFFFFFFF),
    );

    test('moves the palette and the font size part of the way', () {
      final half = ThemeConfig.blend(from, to, 0.5);
      expect(half.accent, Color.lerp(from.accent, to.accent, 0.5));
      expect(half.fontSize, 15.0);
    });

    test('takes everything else from the new theme at once', () {
      // Geometry sizes native surfaces and has to land with the store's other
      // readers; a family or a pack has no halfway.
      final start = ThemeConfig.blend(from, to, 0);
      expect(start.accent, from.accent);
      expect(start.fontFamily, 'To');
      expect(start.iconPack, IconPack.lucide);
      expect(start.panelOverhang, 40);
    });

    test('never blends a tint a tile or plant is generated in', () {
      expect(ThemeConfig.blend(from, to, 0.5).foliageColor, to.foliageColor);
    });

    test('is the new theme itself at the end', () {
      expect(identical(ThemeConfig.blend(from, to, 1), to), isTrue);
    });
  });

  group('ThemeTransition', () {
    late Directory tempDir;
    late ThemeStore themes;
    late ThemeTransition transition;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('gs_theme_transition');
      themes = ThemeStore.forTesting(directory: '${tempDir.path}/themes');
      themes.start();
      transition = ThemeTransition.ofStore(themes);
    });

    tearDown(() async {
      transition.dispose();
      themes.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    const glassy = Color(0xFF7FB6FF);
    const dracula = Color(0xFFBD93F9);
    const forest = Color(0xFF2E8B57);

    Color painted(WidgetTester tester) =>
        tester.widget<ColoredBox>(find.byType(ColoredBox)).color;

    Future<void> mount(WidgetTester tester) => tester.pumpWidget(
          ThemeProvider(theme: transition, child: const _AccentBox()),
        );

    final half = Duration(
        microseconds: ShellDurations.themeSwitch.inMicroseconds ~/ 2);

    testWidgets('a switch blends into the new palette, then stops',
        (tester) async {
      await mount(tester);
      expect(painted(tester), glassy);

      themes.select('dracula');
      await tester.pump();
      // The ticker's first frame is elapsed zero: still the old colour.
      expect(painted(tester), glassy);

      await tester.pump(half);
      final midway = painted(tester);
      expect(midway, isNot(glassy));
      expect(midway, isNot(dracula));

      await tester.pump(ShellDurations.themeSwitch);
      expect(painted(tester), dracula);
      expect(transition.isBlending, isFalse);
      // Nothing animates at rest.
      expect(tester.binding.transientCallbackCount, 0);

      themes.flush();
    });

    testWidgets('an edit to the active theme lands at once', (tester) async {
      themes.create('Mine');
      await mount(tester);
      await tester.pumpAndSettle();

      themes.edit('accent', '#00FF00');
      await tester.pump();
      expect(painted(tester), const Color(0xFF00FF00));
      expect(transition.isBlending, isFalse);
      expect(tester.binding.transientCallbackCount, 0);

      themes.flush();
    });

    testWidgets('a second switch starts from what is on screen',
        (tester) async {
      await mount(tester);

      themes.select('dracula');
      await tester.pump();
      await tester.pump(half);
      final midway = painted(tester);

      themes.select('forest');
      await tester.pump();
      // No jump back to either end: the new blend starts where the old one was.
      expect(painted(tester), midway);

      await tester.pump(half);
      expect(painted(tester), isNot(midway));
      expect(painted(tester), isNot(forest));

      await tester.pump(ShellDurations.themeSwitch);
      expect(painted(tester), forest);
      expect(tester.binding.transientCallbackCount, 0);

      themes.flush();
    });

    testWidgets('an edit mid-switch retargets the blend', (tester) async {
      themes.create('Mine');
      themes.select('dracula');
      await mount(tester);
      await tester.pumpAndSettle();

      themes.select('mine');
      await tester.pump();
      await tester.pump(half);
      themes.edit('accent', '#00FF00');
      await tester.pump();
      // Still playing, toward the edited colour.
      expect(transition.isBlending, isTrue);
      expect(painted(tester), isNot(const Color(0xFF00FF00)));

      await tester.pump(ShellDurations.themeSwitch);
      expect(painted(tester), const Color(0xFF00FF00));
      expect(tester.binding.transientCallbackCount, 0);

      themes.flush();
    });

    testWidgets('a switch to an identical palette plays nothing',
        (tester) async {
      await mount(tester);

      // A fork is a new name with the same contents.
      themes.duplicateActive();
      await tester.pump();
      expect(transition.isBlending, isFalse);
      expect(tester.binding.transientCallbackCount, 0);

      themes.flush();
    });
  });
}

/// Reads the accent from the enclosing scope. `const`, so the only thing that
/// can repaint it is the [ThemeScope] above it changing.
class _AccentBox extends StatelessWidget {
  const _AccentBox();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: ThemeScope.of(context).accent);
}
