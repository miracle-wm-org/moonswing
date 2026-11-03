import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/background.dart';
import 'package:moonswing/background_transition.dart';
import 'package:moonswing/config.dart';

/// Whether [layer] paints anything at all at the screen's [point].
bool paintsAt(WallpaperLayer layer, Offset point, Size size) {
  if (layer.opacity <= 0) return false;
  final clip = layer.clip;
  if (clip != null && !clip.contains(point)) return false;
  final transform = layer.transform;
  if (transform == null) return true;
  // Where the point came from in the layer's own space.
  final inverse = Matrix4.tryInvert(transform);
  if (inverse == null) return false;
  final source = MatrixUtils.transformPoint(inverse, point);
  return (Offset.zero & size).contains(source);
}

void main() {
  const size = Size(1920, 1080);
  final samples = [
    for (var x = 5.0; x < size.width; x += 97)
      for (var y = 5.0; y < size.height; y += 89) Offset(x, y),
  ];

  group('WallpaperTransition', () {
    test('every member round-trips through its slug', () {
      for (final t in WallpaperTransition.values) {
        expect(WallpaperTransition.fromSlug(t.slug), t);
      }
    });

    test('an unknown or absent slug is null, so the caller falls back', () {
      expect(WallpaperTransition.fromSlug('spiral'), isNull);
      expect(WallpaperTransition.fromSlug(null), isNull);
    });

    test('random draws from every effect but itself and none', () {
      expect(WallpaperTransition.effects, isNot(contains(WallpaperTransition.random)));
      expect(WallpaperTransition.effects, isNot(contains(WallpaperTransition.none)));
      expect(WallpaperTransition.effects, containsAll([
        WallpaperTransition.fade,
        WallpaperTransition.checkerboard,
        WallpaperTransition.circle,
        WallpaperTransition.flip,
        WallpaperTransition.slide,
      ]));
    });
  });

  group('WallpaperTransitionPlan.choose', () {
    test('a fixed setting is played as itself', () {
      final random = math.Random(1);
      for (final t in WallpaperTransition.effects) {
        expect(WallpaperTransitionPlan.choose(t, random).effect, t);
      }
    });

    test('random never repeats the previous effect, and reaches them all', () {
      final random = math.Random(7);
      WallpaperTransition? previous;
      final seen = <WallpaperTransition>{};
      for (var i = 0; i < 400; i++) {
        final plan = WallpaperTransitionPlan.choose(
          WallpaperTransition.random,
          random,
          previous: previous,
        );
        expect(plan.effect, isNot(previous));
        expect(WallpaperTransition.effects, contains(plan.effect));
        seen.add(plan.effect);
        previous = plan.effect;
      }
      expect(seen, WallpaperTransition.effects.toSet());
    });

    test('a slide comes from every edge in time', () {
      final random = math.Random(3);
      final edges = {
        for (var i = 0; i < 100; i++)
          WallpaperTransitionPlan.choose(WallpaperTransition.slide, random).edge,
      };
      expect(edges, WallpaperEdge.values.toSet());
    });
  });

  group('wallpaperFrame', () {
    for (final effect in WallpaperTransition.effects) {
      for (final edge in WallpaperEdge.values) {
        if (!effect.directional && edge != WallpaperEdge.right) continue;
        final plan = WallpaperTransitionPlan(effect, edge: edge, seed: 42);
        final name = effect.directional ? '${effect.slug} from $edge' : effect.slug;

        test('$name starts on the old wallpaper', () {
          final frame = wallpaperFrame(plan, 0, size);
          for (final p in samples) {
            expect(paintsAt(frame.incoming, p, size), isFalse,
                reason: 'the new wallpaper shows at $p before it began');
            expect(paintsAt(frame.outgoing, p, size), isTrue,
                reason: 'the old wallpaper is missing at $p before it began');
          }
        });

        test('$name ends on the new wallpaper, untouched', () {
          final frame = wallpaperFrame(plan, 1, size);
          expect(frame.incoming.opacity, 1);
          expect(frame.incoming.clip, isNull);
          expect(frame.incoming.transform, isNull);
          expect(frame.backdrop, isFalse);
        });

        test('$name is between the two part-way', () {
          // Not 0.5 exactly: a flip is edge-on there and shows neither face.
          final frame = wallpaperFrame(plan, 0.6, size);
          final shown = samples.where((p) => paintsAt(frame.incoming, p, size));
          // Something of the new wallpaper is on screen, and every point shows
          // one of the two or the backdrop.
          expect(shown, isNotEmpty);
          for (final p in samples) {
            final covered = paintsAt(frame.incoming, p, size) ||
                paintsAt(frame.outgoing, p, size);
            expect(covered || frame.backdrop, isTrue,
                reason: 'nothing at all is painted at $p');
          }
        });
      }
    }

    test('a reveal keeps the old wallpaper whole beneath it', () {
      for (final effect in [
        WallpaperTransition.checkerboard,
        WallpaperTransition.circle,
        WallpaperTransition.wipe,
        WallpaperTransition.blinds,
        WallpaperTransition.dissolve,
      ]) {
        final frame = wallpaperFrame(WallpaperTransitionPlan(effect), 0.4, size);
        expect(frame.outgoing.opacity, 1, reason: effect.slug);
        expect(frame.outgoing.clip, isNull, reason: effect.slug);
        expect(frame.outgoing.transform, isNull, reason: effect.slug);
      }
    });

    test('a flip shows one face at a time, over the backdrop', () {
      const plan = WallpaperTransitionPlan(WallpaperTransition.flip);
      final early = wallpaperFrame(plan, 0.25, size);
      expect(early.backdrop, isTrue);
      expect(early.incoming.opacity, 0);
      expect(early.outgoing.opacity, 1);
      final late = wallpaperFrame(plan, 0.75, size);
      expect(late.outgoing.opacity, 0);
      expect(late.incoming.opacity, 1);
    });

    test('a dissolve is the same scatter for the same seed', () {
      const plan = WallpaperTransitionPlan(WallpaperTransition.dissolve, seed: 9);
      final a = wallpaperFrame(plan, 0.5, size).incoming.clip!;
      final b = wallpaperFrame(plan, 0.5, size).incoming.clip!;
      for (final p in samples) {
        expect(a.contains(p), b.contains(p));
      }
    });
  });

  group('BackgroundConfig transition keys', () {
    test('default to the crossfade every change used to play', () {
      final cfg = BackgroundConfig.fromMap({});
      expect(cfg.transition, WallpaperTransition.fade);
      expect(cfg.transitionMillis, 1500);
    });

    test('parse, and a bad value costs only its own key', () {
      final cfg = BackgroundConfig.fromMap({
        'transition': 'random',
        'transition_duration': 800,
      });
      expect(cfg.transition, WallpaperTransition.random);
      expect(cfg.transitionDuration, const Duration(milliseconds: 800));

      final bad = BackgroundConfig.fromMap({
        'transition': 'spiral',
        'transition_duration': 'slow',
        'interval_minutes': 3,
      });
      expect(bad.transition, WallpaperTransition.fade);
      expect(bad.transitionMillis, 1500);
      expect(bad.intervalMinutes, 3);
    });

    test('the duration is clamped', () {
      expect(
        BackgroundConfig.fromMap({'transition_duration': -5}).transitionMillis,
        0,
      );
      expect(
        BackgroundConfig.fromMap({'transition_duration': 99999})
            .transitionMillis,
        BackgroundConfig.maxTransitionMillis,
      );
    });

    test('take part in equality', () {
      expect(
        const BackgroundConfig(transition: WallpaperTransition.flip),
        isNot(const BackgroundConfig()),
      );
      expect(
        const BackgroundConfig(transitionMillis: 10),
        isNot(const BackgroundConfig()),
      );
      expect(
        const BackgroundConfig(transition: WallpaperTransition.flip),
        const BackgroundConfig(transition: WallpaperTransition.flip),
      );
    });
  });

  group('BackgroundWindow transitions', () {
    late Directory dir;
    late File first;
    late File second;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('gs_bg_transition_test');
      first = File('${dir.path}/a.png')..writeAsBytesSync([1]);
      second = File('${dir.path}/b.png')..writeAsBytesSync([2]);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    BackgroundConfig cfg(
      List<File> files, {
      WallpaperTransition transition = WallpaperTransition.fade,
      int millis = 1000,
    }) =>
        BackgroundConfig(
          transition: transition,
          transitionMillis: millis,
          entries: [for (final f in files) BackgroundEntry(path: f.path)],
        );

    List<String> paths(WidgetTester tester) => [
          for (final image in tester.widgetList<Image>(find.byType(Image)))
            (image.image as FileImage).file.path,
        ];

    for (final transition in [
      ...WallpaperTransition.effects,
      WallpaperTransition.random,
    ]) {
      testWidgets('${transition.slug} plays both, then leaves only the new one',
          (tester) async {
        await tester.pumpWidget(
          BackgroundWindow(
            config: cfg([first], transition: transition),
            random: math.Random(5),
          ),
        );
        expect(paths(tester), [first.path]);

        await tester.pumpWidget(
          BackgroundWindow(
            config: cfg([second], transition: transition),
            random: math.Random(5),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(paths(tester), [first.path, second.path]);

        await tester.pumpAndSettle();
        expect(paths(tester), [second.path]);
        expect(tester.binding.transientCallbackCount, 0);
      });
    }

    testWidgets('none cuts straight to the new wallpaper', (tester) async {
      await tester.pumpWidget(BackgroundWindow(
        config: cfg([first], transition: WallpaperTransition.none),
      ));
      await tester.pumpWidget(BackgroundWindow(
        config: cfg([second], transition: WallpaperTransition.none),
      ));
      expect(paths(tester), [second.path]);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a zero duration is a cut too', (tester) async {
      await tester.pumpWidget(BackgroundWindow(config: cfg([first], millis: 0)));
      await tester.pumpWidget(BackgroundWindow(config: cfg([second], millis: 0)));
      expect(paths(tester), [second.path]);
    });

    testWidgets('the staying wallpaper is never remounted', (tester) async {
      await tester.pumpWidget(BackgroundWindow(config: cfg([first])));
      final before = tester.element(find.byType(Image));

      // A change starts: the leaving wallpaper keeps its element.
      await tester.pumpWidget(BackgroundWindow(config: cfg([second])));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.element(find.byType(Image).first), same(before));
      final arriving = tester.element(find.byType(Image).last);

      // And when it ends, the one that arrived keeps its own.
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(Image)), same(arriving));
    });

    testWidgets('editing the transition plays nothing by itself',
        (tester) async {
      await tester.pumpWidget(BackgroundWindow(config: cfg([first])));
      await tester.pumpWidget(BackgroundWindow(
        config: cfg([first], transition: WallpaperTransition.flip),
      ));
      expect(tester.binding.transientCallbackCount, 0);
      expect(paths(tester), [first.path]);
    });
  });
}
