import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';

import 'package:moonswing/decor/foliage.dart';
import 'package:moonswing/decor/material_decoration.dart';
import 'package:moonswing/decor/material_textures.dart';
import 'package:moonswing/decor/material_tiles.dart';
import 'package:moonswing/decor/panel_decor.dart';
import 'package:moonswing/decor/seeded_random.dart';
import 'package:moonswing/native/input_region.dart';
import 'package:moonswing/panel_rim.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/popup_transition.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/builtin_themes.dart';
import 'package:moonswing/theme/popup_effect.dart';
import 'package:moonswing/theme/surface_material.dart';
import 'package:moonswing/theme/theme_config.dart';

import 'paint_counter.dart';

ThemeConfig _shipped(String slug) =>
    ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes[slug]!).toMap());

void main() {
  group('the closed sets', () {
    test('every material and foliage style round-trips through its slug', () {
      for (final m in SurfaceMaterial.values) {
        expect(SurfaceMaterial.fromSlug(m.slug), m);
      }
      for (final f in FoliageStyle.values) {
        expect(FoliageStyle.fromSlug(f.slug), f);
      }
      expect(PopupEffect.fromSlug('sprout'), PopupEffect.sprout);
      expect(SurfaceMaterial.fromSlug('marble'), isNull);
      expect(FoliageStyle.fromSlug(null), isNull);
    });

    test('none is a real off switch', () {
      expect(SurfaceMaterial.none.paints, isFalse);
      expect(FoliageStyle.none.grows, isFalse);
      for (final m in SurfaceMaterial.values.skip(1)) {
        expect(m.paints, isTrue);
      }
    });
  });

  group('theme keys', () {
    test('a theme that names none of them is painted as it always was', () {
      const plain = ThemeConfig();
      expect(plain.panelHasDecor, isFalse);
      expect(plain.popupHasMaterial, isFalse);
      expect(plain.panelReach, 0);
      expect(popupDecoration(theme: plain), isA<BoxDecoration>());
    });

    test('a wrongly-typed value costs that key and nothing else', () {
      final theme = ThemeConfig.fromMap({
        'panel_texture': 3,
        'panel_foliage': 'jungle',
        'panel_overhang': 9999,
        'foliage_density': double.nan,
        'popup_roots': -4,
        'popup_border_texture': 'bark',
        'panel_image': '  wood.png  ',
      });
      expect(theme.panelTexture, SurfaceMaterial.none);
      expect(theme.panelFoliage, FoliageStyle.none);
      expect(theme.panelOverhang, 160);
      expect(theme.foliageDensity, 1.0);
      expect(theme.popupRoots, 0.0);
      expect(theme.popupBorderTexture, SurfaceMaterial.bark);
      expect(theme.panelImage, 'wood.png');
    });

    test('the new keys round-trip', () {
      final forest = _shipped('forest');
      expect(ThemeConfig.fromMap(forest.toMap()), forest);
    });

    test('an overhang with nothing growing in it reaches nowhere', () {
      final theme = ThemeConfig.fromMap({'panel_overhang': 40});
      expect(theme.panelReach, 0);
      final grown = ThemeConfig.fromMap(
          {'panel_overhang': 40, 'panel_foliage': 'ivy'});
      expect(grown.panelReach, 40);
    });
  });

  group('SeededRandom', () {
    test('is the same sequence for the same seed, and only for it', () {
      final a = SeededRandom(42);
      final b = SeededRandom(42);
      final c = SeededRandom(43);
      final xs = [for (var i = 0; i < 8; i++) a.nextUint32()];
      expect([for (var i = 0; i < 8; i++) b.nextUint32()], xs);
      expect([for (var i = 0; i < 8; i++) c.nextUint32()], isNot(xs));
      for (final x in xs) {
        expect(x, inInclusiveRange(0, 0xFFFFFFFF));
      }
    });

    test('periodic noise joins itself at the period', () {
      final n = PeriodicNoise1D(7, 12);
      expect(n.at(0), closeTo(n.at(12), 1e-12));
      expect(n.fbm(0.5), closeTo(n.fbm(12.5), 1e-12));
    });
  });

  group('foliage', () {
    FoliagePlan grow(String anchor, {FoliageStyle style = FoliageStyle.wildwood}) =>
        growFoliage(
          style: style,
          length: 900,
          thickness: 32,
          reach: 64,
          anchor: anchor,
          leaf: const Color(0xFF3F7D38),
          bloom: const Color(0xFFE8A33C),
          endCaps: 50,
        );

    test('nothing grows with no style, no room or no density', () {
      expect(grow('top', style: FoliageStyle.none).sprigs, isEmpty);
      expect(
        growFoliage(
          style: FoliageStyle.ivy,
          length: 900,
          thickness: 32,
          reach: 0,
          anchor: 'top',
          leaf: const Color(0xFF00FF00),
          bloom: const Color(0xFFFF0000),
        ).sprigs,
        isEmpty,
      );
    });

    test('the same bar grows the same plants', () {
      final a = grow('top');
      final b = grow('top');
      expect(a.sprigs.length, b.sprigs.length);
      for (var i = 0; i < a.sprigs.length; i++) {
        expect(a.sprigs[i].root, b.sprigs[i].root);
        expect(a.sprigs[i].leaves.length, b.sprigs[i].leaves.length);
      }
    });

    test('every stem stays in the room it has', () {
      for (final anchor in ['top', 'bottom', 'left', 'right']) {
        final plan = grow(anchor);
        expect(plan.sprigs, isNotEmpty, reason: anchor);
        for (final s in plan.sprigs) {
          expect(s.root.dx, inInclusiveRange(0, 900), reason: anchor);
          for (final stem in s.stems) {
            for (final p in stem) {
              final q = s.root + p;
              // Over the overhang, and onto the bar only as a fringe.
              expect(q.dy, lessThanOrEqualTo(64), reason: anchor);
              expect(q.dy, greaterThanOrEqualTo(-32 * 0.33), reason: anchor);
            }
          }
        }
      }
    });

    test('gravity is the anchor: a top bar hangs, a bottom bar stands', () {
      expect(foliageGravity('top'), const Offset(0, 1));
      expect(foliageGravity('bottom'), const Offset(0, -1));
      expect(foliageGravity('left'), const Offset(1, 0));
      double meanTip(FoliagePlan plan) {
        final vines = plan.sprigs.where((s) => s.kind == SprigKind.vine);
        var sum = 0.0;
        for (final v in vines) {
          sum += v.stems.first.last.dy;
        }
        return sum / vines.length;
      }

      // Both reach outward; the hanging ones further, because gravity helps.
      expect(meanTip(grow('top')), greaterThan(meanTip(grow('bottom'))));
    });

    test('back to front', () {
      final plan = grow('top');
      for (var i = 1; i < plan.sprigs.length; i++) {
        expect(plan.sprigs[i].depth,
            lessThanOrEqualTo(plan.sprigs[i - 1].depth));
      }
    });

    group('harvest', () {
      FoliagePlan harvest(String anchor, {double length = 1400}) =>
          growFoliage(
            style: FoliageStyle.harvest,
            length: length,
            thickness: 32,
            reach: 72,
            anchor: anchor,
            leaf: const Color(0xFF6B8A35),
            bloom: const Color(0xFFE2731E),
            endCaps: 44,
          );

      test('a top bar turns in its corners and is bare in the middle', () {
        final plan = harvest('top');
        expect(plan.sprigs, isNotEmpty);
        expect(plan.sprigs.expand((s) => s.gourds), isEmpty,
            reason: 'nothing hangs a pumpkin');
        for (final s in plan.sprigs) {
          final reach = s.bounds.shift(s.root);
          expect(reach.left < 1400 * 0.3 || reach.right > 1400 * 0.7, isTrue,
              reason: 'every plant roots in a corner: $reach');
        }
        final leaves = plan.sprigs.expand((s) => s.leaves).toList();
        expect(leaves.where((l) => l.shape == LeafShape.maple), isNotEmpty);
        expect(leaves.where((l) => l.shape == LeafShape.oak), isNotEmpty);
        // A motley: the leaves are many colours, not one jittered.
        final hues = {
          for (final l in leaves) (HSLColor.fromColor(l.color).hue / 15).floor(),
        };
        expect(hues.length, greaterThanOrEqualTo(4));
      });

      test('a bottom bar grows pumpkin patches, at both ends and between', () {
        final plan = harvest('bottom');
        final pumpkins = [
          for (final s in plan.sprigs)
            for (final g in s.gourds) (s.root + g.at, g),
        ];
        expect(pumpkins.length, greaterThanOrEqualTo(4));
        final xs = [for (final (at, _) in pumpkins) at.dx];
        expect(xs.any((x) => x < 160), isTrue, reason: 'a patch in each corner');
        expect(xs.any((x) => x > 1400 - 160), isTrue);
        expect(xs.any((x) => x > 400 && x < 1000), isTrue,
            reason: 'and one between');
        for (final (at, g) in pumpkins) {
          // Standing on the bar's edge, upright, inside the room it has.
          expect(at.dy, inInclusiveRange(-3, 3));
          expect(g.down, const Offset(0, -1));
          expect(at.dy + g.height + g.stalk, lessThanOrEqualTo(72));
          expect(at.dx - g.width / 2, greaterThanOrEqualTo(0));
          expect(at.dx + g.width / 2, lessThanOrEqualTo(1400));
        }
        // A pumpkin is too heavy to rustle.
        for (final s in plan.sprigs.where((s) => s.gourds.isNotEmpty)) {
          expect(s.kind.sway, 0);
        }
      });

      test('a short bottom bar still gets its patch', () {
        final plan = harvest('bottom', length: 240);
        expect(plan.sprigs.expand((s) => s.gourds), isNotEmpty);
      });

      test('every stem stays in the room it has', () {
        for (final anchor in ['top', 'bottom', 'left', 'right']) {
          for (final s in harvest(anchor).sprigs) {
            for (final stem in s.stems) {
              for (final p in stem) {
                final q = s.root + p;
                expect(q.dy, lessThanOrEqualTo(72), reason: anchor);
                expect(q.dy, greaterThanOrEqualTo(-32 * 0.33), reason: anchor);
                expect(q.dx, inInclusiveRange(0, 1400), reason: anchor);
              }
            }
          }
        }
      });

      test('the same bar grows the same harvest', () {
        final a = harvest('bottom');
        final b = harvest('bottom');
        expect([for (final s in a.sprigs) s.root],
            [for (final s in b.sprigs) s.root]);
      });

      test('every plant paints, pumpkins and all', () {
        for (final anchor in ['top', 'bottom']) {
          for (final s in harvest(anchor).sprigs) {
            recordSprig(s).dispose();
          }
        }
      });
    });
  });

  group('the overhang', () {
    test('the input region is the bar, against its screen edge', () {
      expect(panelInputRect(anchor: 'top', thickness: 32, reach: 64).top, 0);
      expect(
          panelInputRect(anchor: 'top', thickness: 32, reach: 64).height, 32);
      final bottom = panelInputRect(anchor: 'bottom', thickness: 32, reach: 64);
      expect(bottom.top, 64);
      expect(bottom.height, 32);
      final right = panelInputRect(anchor: 'right', thickness: 40, reach: 20);
      expect(right.left, 20);
      expect(right.width, 40);
    });

    test('the bar is laid out where the input region is', () {
      const surface = Size(1000, 96);
      expect(
          panelBarRect(surface: surface, anchor: 'top', thickness: 32),
          const Rect.fromLTWH(0, 0, 1000, 32));
      expect(
          panelBarRect(surface: surface, anchor: 'bottom', thickness: 32),
          const Rect.fromLTWH(0, 64, 1000, 32));
      expect(
          panelBarRect(
              surface: const Size(96, 800), anchor: 'right', thickness: 32),
          const Rect.fromLTWH(64, 0, 32, 800));
      // A surface no deeper than the bar is all bar.
      expect(
          panelBarRect(
              surface: const Size(1000, 32), anchor: 'bottom', thickness: 32),
          const Rect.fromLTWH(0, 0, 1000, 32));
    });

    test('a popup opens at the bar, over the leaves', () {
      const module = Rect.fromLTWH(100, 4, 30, 24);
      // A top bar's popup hangs from the bar's edge, not the surface's.
      expect(
          barAnchorRect(module, const Size(1000, 96), 'top', thickness: 32),
          const Rect.fromLTRB(100, 0, 130, 32));
      expect(
          barAnchorRect(const Rect.fromLTWH(100, 68, 30, 24),
              const Size(1000, 96), 'bottom',
              thickness: 32),
          const Rect.fromLTRB(100, 64, 130, 96));
      // With no thickness, the surface is the bar, as it always was.
      expect(barAnchorRect(module, const Size(1000, 32), 'top'),
          const Rect.fromLTRB(100, 0, 130, 32));
    });
  });

  group('textures', () {
    setUp(MaterialTextures.instance.reset);

    // Asked for, a tile is null until it has been rasterized; then it lands,
    // notifies, and is the same image for every later ask.
    Future<ui.Image?> drawn(
        WidgetTester tester, SurfaceMaterial m, Color tint, double dpr) async {
      final textures = MaterialTextures.instance;
      var landed = textures.tile(m, tint, dpr);
      if (landed != null || !m.paints) return landed;
      await tester.runAsync(() async {
        for (var i = 0; i < 200 && landed == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          landed = textures.tile(m, tint, dpr);
        }
      });
      return landed;
    }

    testWidgets('a tile is drawn once and shared', (tester) async {
      var notified = 0;
      void count() => notified++;
      MaterialTextures.instance.addListener(count);
      addTearDown(() => MaterialTextures.instance.removeListener(count));
      expect(
          MaterialTextures.instance
              .tile(SurfaceMaterial.wood, const Color(0xFF6E4A2A), 2.0),
          isNull,
          reason: 'never drawn synchronously');
      final a = (await drawn(tester, SurfaceMaterial.wood,
          const Color(0xFF6E4A2A), 2.0))!;
      expect(notified, 1);
      final size = materialTileSize(SurfaceMaterial.wood);
      expect(a.width, (size.width * 2).round());
      expect(a.height, (size.height * 2).round());
      final b = MaterialTextures.instance
          .tile(SurfaceMaterial.wood, const Color(0xFF6E4A2A), 2.0)!;
      expect(identical(a, b), isTrue);
      expect(MaterialTextures.instance.tileCount, 1);
      // The alpha is the strength, not part of the tile.
      expect(
          MaterialTextures.instance
              .tile(SurfaceMaterial.wood, const Color(0x206E4A2A), 2.0),
          same(a));
      expect(MaterialTextures.instance.tileCount, 1);
      expect(
          MaterialTextures.instance
              .tile(SurfaceMaterial.none, const Color(0xFF000000), 1.0),
          isNull);
    });

    testWidgets('every material draws', (tester) async {
      for (final m in SurfaceMaterial.values.where((m) => m.paints)) {
        expect(await drawn(tester, m, const Color(0xFF6B5340), 1.0),
            isNotNull,
            reason: m.slug);
      }
    });

    test('a picture resolves beside its theme', () {
      expect(resolvePicturePath('/abs/bark.png', '/themes'), '/abs/bark.png');
      expect(resolvePicturePath('bark.png', '/themes'), '/themes/bark.png');
      expect(resolvePicturePath('bark.png', '/themes/'), '/themes/bark.png');
      expect(resolvePicturePath('~/p/bark.png', '/themes'),
          endsWith('/p/bark.png'));
    });

    testWidgets('a picture that will not load says why, and can be retried',
        (tester) async {
      MaterialTextures.instance.baseDirectory = '/nonexistent-moonswing';
      await tester.runAsync(() async {
        expect(MaterialTextures.instance.picture('missing.png'), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(MaterialTextures.instance.failureFor('missing.png'),
          contains('missing.png'));
      MaterialTextures.instance.retryFailed();
      expect(MaterialTextures.instance.failureFor('missing.png'), isNull);
      MaterialTextures.instance.baseDirectory = null;
    });

    test('the shader turns the grain a quarter for a trunk across', () {
      final m = materialShaderTransform(across: true, pixelScale: 2);
      // Column-major: the tile's x axis lands on the canvas's y.
      expect(m[0], closeTo(0, 1e-9));
      expect(m[1], closeTo(0.5, 1e-9));
      final flat = materialShaderTransform(pixelScale: 2, origin: const Offset(3, 4));
      expect(flat[0], 0.5);
      expect(flat[12], 3);
      expect(flat[13], 4);
    });
  });

  group('the trunk', () {
    test('a card with a material rim pads exactly as a flat rim would', () {
      final forest = _shipped('forest');
      final plain = popupDecoration(
          theme: ThemeConfig.fromMap(
              {...forest.toMap(), 'popup_border_texture': 'none', 'popup_texture': 'none'}),
          attach: 'top');
      final textured = popupDecoration(theme: forest, attach: 'top');
      expect(textured, isA<MaterialCardDecoration>());
      expect(textured.padding, plain.padding);
      expect(decorationClips(textured), isTrue);
    });

    test('a rim that carries meaning stays plain', () {
      final forest = _shipped('forest');
      final d = popupDecoration(
        theme: forest,
        border: Border.all(color: const Color(0xFFFF0000), width: 2),
      );
      expect(d, isNot(isA<MaterialCardDecoration>()));
    });

    test('a full-grown sprout is the whole card', () {
      for (final edge in ['top', 'bottom', 'left', 'right']) {
        final path = SproutClipper(edge: edge, length: 1, girth: 1)
            .getClip(const Size(200, 120));
        for (final p in const [
          Offset(1, 1),
          Offset(199, 1),
          Offset(1, 119),
          Offset(199, 119),
          Offset(100, 60),
        ]) {
          expect(path.contains(p), isTrue, reason: '$edge at $p');
        }
      }
    });

    test('a young sprout is narrow, and grows from its join', () {
      final path = SproutClipper(edge: 'top', length: 0.3, girth: 0.3)
          .getClip(const Size(200, 120));
      expect(path.contains(const Offset(100, 4)), isTrue);
      expect(path.contains(const Offset(10, 60)), isFalse);
      expect(path.contains(const Offset(100, 115)), isFalse);
      final up = SproutClipper(edge: 'bottom', length: 0.3, girth: 0.3)
          .getClip(const Size(200, 120));
      expect(up.contains(const Offset(100, 116)), isTrue);
      expect(up.contains(const Offset(100, 5)), isFalse);
    });

    testWidgets('a sprouting popup settles with nothing left animating',
        (tester) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: _shipped('forest'),
          child: const Center(
            child: PopupTransition(
              effect: PopupEffect.sprout,
              duration: Duration(milliseconds: 300),
              edge: 'top',
              child: SizedBox(width: 120, height: 80),
            ),
          ),
        ),
      ));
      expect(find.byType(ClipPath), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(ClipPath), findsNothing,
          reason: 'no clip layer at rest');
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('the bar', () {
    setUp(PanelRimBreaks.instance.clearAll);

    Widget bar(ThemeConfig theme, {Object? panel, Listenable? rustle,
        VoidCallback? onTap}) {
      const thickness = 32.0;
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            height: thickness + theme.panelReach,
            child: Stack(children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: thickness,
                child: PanelSurfaceDecor(
                  theme: theme,
                  anchor: 'top',
                  radius: BorderRadius.zero,
                  panel: panel,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      child: const SizedBox(width: 40, height: 32),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: PanelFoliage(
                  theme: theme,
                  anchor: 'top',
                  thickness: thickness,
                  panel: panel,
                  rustle: rustle,
                ),
              ),
            ]),
          ),
        ),
      );
    }

    CustomPaint decorPaint(WidgetTester tester) => tester.widget<CustomPaint>(
        find.descendant(
            of: find.byType(PanelSurfaceDecor),
            matching: find.byType(CustomPaint)).first);

    testWidgets('a plain theme builds no painter and grows nothing',
        (tester) async {
      await tester.pumpWidget(bar(const ThemeConfig()));
      expect(decorPaint(tester).painter, isNull);
      expect(
          find.descendant(
              of: find.byType(PanelFoliage), matching: find.byType(CustomPaint)),
          findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    });

    for (final slug in ['forest', 'autumn']) {
      testWidgets('$slug paints, rests, rustles and rests again',
          (tester) async {
        final rustle = ValueNotifier(0);
        addTearDown(rustle.dispose);
        await tester.pumpWidget(bar(_shipped(slug), rustle: rustle));
        expect(decorPaint(tester).painter, isNotNull);
        expect(
            find.descendant(
                of: find.byType(PanelFoliage),
                matching: find.byType(CustomPaint)),
            findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0,
            reason: 'nothing animates at rest');

        rustle.value++;
        await tester.pump();
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      });
    }

    testWidgets('roots grow when a popup opens and go when it closes',
        (tester) async {
      final panel = Object();
      await tester.pumpWidget(bar(_shipped('forest'), panel: panel));
      await tester.pumpAndSettle();
      PanelRimBreaks.instance.set(panel, (300, 420));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpAndSettle();
      PanelRimBreaks.instance.clear(panel);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    // Every plant becomes an image laid on the device-pixel grid, and the
    // canopy drawn from them is the canopy its vector pictures drew.
    testWidgets('the leaves are rasterized once, and look the same',
        (tester) async {
      final forest = _shipped('forest');
      final rustle = ValueNotifier(0);
      addTearDown(rustle.dispose);
      await tester.pumpWidget(bar(forest, rustle: rustle));
      final state = tester.state<State<PanelFoliage>>(find.byType(PanelFoliage));
      await tester.runAsync(() async {
        for (var i = 0;
            i < 200 && PanelFoliage.debugRasterized(state) == null;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      // The same plan, painted the way it was before it was rasterized.
      const size = Size(800, 32.0 + 64);
      expect(forest.panelReach, 64);
      final plan = growFoliage(
        style: forest.panelFoliage,
        length: size.width,
        thickness: 32,
        reach: size.height - 32,
        anchor: 'top',
        leaf: forest.foliageColor,
        bloom: forest.foliageBloom,
        density: forest.foliageDensity,
        endCaps: forest.panelEndLength,
      );
      expect(PanelFoliage.debugRasterized(state), plan.sprigs.length);
      expect(plan.sprigs.length, greaterThan(20));
      final dpr = tester.view.devicePixelRatio;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..scale(dpr)
        ..transform(foliageFrame(anchor: 'top', surface: size, thickness: 32)
            .storage);
      for (final s in plan.sprigs) {
        canvas
          ..save()
          ..translate(s.root.dx, s.root.dy);
        paintSprig(canvas, s);
        canvas.restore();
      }
      final reference = recorder.endRecording();
      addTearDown(reference.dispose);
      final boundary = tester.renderObject<RenderRepaintBoundary>(find
          .descendant(
              of: find.byType(PanelFoliage),
              matching: find.byType(RepaintBoundary))
          .first);

      late ByteData before;
      late ByteData after;
      await tester.runAsync(() async {
        Future<ByteData> bytes(ui.Image image) async {
          final data = (await image.toByteData())!;
          image.dispose();
          return data;
        }

        before = await bytes(await reference.toImage(
            (size.width * dpr).round(), (size.height * dpr).round()));
        after = await bytes(await boundary.toImage(pixelRatio: dpr));
      });
      expect(after.lengthInBytes, before.lengthInBytes);
      var drawn = 0;
      var off = 0;
      for (var i = 0; i < before.lengthInBytes; i++) {
        final a = before.getUint8(i);
        if (a != 0) drawn++;
        if ((a - after.getUint8(i)).abs() > 8) off++;
      }
      expect(drawn, greaterThan(1000), reason: 'the canopy painted at all');
      expect(off / drawn, lessThan(0.01));

      // And a rustle swings the images about their roots, then rests.
      rustle.value++;
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a module repainting re-records none of the decor under it',
        (tester) async {
      final tick = ValueNotifier(0);
      addTearDown(tick.dispose);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          child: PaintCounter(
            child: SizedBox(
              width: 800,
              height: 32,
              child: PanelSurfaceDecor(
                theme: _shipped('forest'),
                anchor: 'top',
                radius: BorderRadius.zero,
                panel: null,
                child: CustomPaint(painter: _Ticking(tick)),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final counter =
          tester.renderObject<RenderPaintCounter>(find.byType(PaintCounter));
      final painted = counter.paints;
      tick.value++;
      await tester.pump();
      expect(_Ticking.paints, greaterThan(1), reason: 'the module repainted');
      expect(counter.paints, painted);
    });

    testWidgets('a module under the leaves still takes the click',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(bar(_shipped('forest'), onTap: () => taps++));
      await tester.pumpAndSettle();
      // The bottom corner of the module, where the fringe of leaves is.
      await tester.tapAt(const Offset(400 - 19, 31));
      expect(taps, 1);
    });

    test('the rim breaks for the roots as well as the mouth', () {
      final forest = _shipped('forest');
      expect(themeGrowsRoots(forest), isTrue);
      final panel = Object();
      PanelRimBreaks.instance.set(panel, (300, 420));
      final w = panelWithRim(
          theme: forest,
          anchor: 'top',
          panel: panel,
          content: const SizedBox()) as ListenableBuilder;
      final paint = w.builder(_FakeContext(), const SizedBox()) as CustomPaint;
      final painter = paint.foregroundPainter! as PanelRimPainter;
      expect(painter.gap, (300 - forest.popupRoots, 420 + forest.popupRoots));
    });
  });
}

/// A module that repaints, as a clock does once a second.
class _Ticking extends CustomPainter {
  _Ticking(Listenable tick) : super(repaint: tick);

  static int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(_Ticking old) => false;
}

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
