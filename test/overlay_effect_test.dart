// The overlay animation tables, and the scaffold that plays them.
//
// Three properties matter above the rest, because losing any of them is what
// this feature exists to prevent: **the exit is the entrance reversed**, so an
// overlay cannot leave by a route it never arrived by; **`none` is a real off
// switch**, answering its owner on the spot so the window is torn down in the
// frame it was closed; and **an overshooting curve never reaches an alpha**,
// because `Opacity` asserts on a value outside `0..1` and a theme file is
// hand-edited.
//
// The fourth is quieter and pinned at the bottom: whatever an effect does on the
// way in, it ends with the card exactly where an unanimated one would have been.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay_fade_scaffold.dart';
import 'package:graceful_shell/overlay_transition.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/overlay_effect.dart';

const double _kCardWidth = 120;
const double _kCardHeight = 80;
const Size _kCard = Size(_kCardWidth, _kCardHeight);

Widget _host({
  required ThemeConfig theme,
  required ValueNotifier<bool> closing,
  VoidCallback? onClosed,
  double durationScale = 1.0,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(
      theme: theme,
      child: FadeOverlayScaffold(
        // A fresh State per pump, deliberately. Without it a test that pumps a
        // second theme reuses the first one's State — and the scaffold
        // snapshots its effect, curve and pace when it opens, exactly as
        // `PopupTransition` does, so the second theme would never be read.
        key: UniqueKey(),
        closing: closing,
        onClosed: onClosed ?? () {},
        durationScale: durationScale,
        child: const SizedBox(width: _kCardWidth, height: _kCardHeight),
      ),
    ),
  );
}

double _cardOpacity(WidgetTester tester) =>
    tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;

/// The card's own transform, in the effect's units: `storage[0]` is the x
/// scale, `storage[5]` the y scale, and `[12]`/`[13]` the translation.
Matrix4 _cardTransform(WidgetTester tester) =>
    tester.widget<Transform>(find.byType(Transform).first).transform;

/// The scrim's alpha as a fraction of the theme's own.
double _scrimFraction(WidgetTester tester, ThemeConfig theme) {
  final painted = tester
      .widget<ColoredBox>(
        find.descendant(
          of: find.byType(FadeOverlayScaffold),
          matching: find.byType(ColoredBox),
        ),
      )
      .color;
  return painted.a / theme.scrim.a;
}

void main() {
  group('the effect table', () {
    test('every slug is unique, and round-trips', () {
      final slugs = <String>{};
      for (final effect in OverlayEffect.values) {
        expect(slugs.add(effect.slug), isTrue,
            reason: 'duplicate ${effect.slug}');
        expect(OverlayEffect.fromSlug(effect.slug), effect);
      }
    });

    test('an unknown or absent slug answers null, never a throw', () {
      // The caller is ThemeConfig.fromMap, whose whole discipline is that a bad
      // value costs its own key; it holds the fallback, not this.
      expect(OverlayEffect.fromSlug(null), isNull);
      expect(OverlayEffect.fromSlug('kaleidoscope'), isNull);
      expect(OverlayEffect.fromSlug(''), isNull);
    });

    test('only `none` claims not to animate', () {
      for (final effect in OverlayEffect.values) {
        expect(effect.animates, effect != OverlayEffect.none,
            reason: effect.slug);
      }
    });

    test('every row carries a label and a sentence for the settings UI', () {
      for (final effect in OverlayEffect.values) {
        expect(effect.label, isNotEmpty);
        expect(effect.description, endsWith('.'));
      }
    });
  });

  group('the curve table', () {
    test('every slug is unique, and round-trips', () {
      final slugs = <String>{};
      for (final curve in OverlayCurve.values) {
        expect(slugs.add(curve.slug), isTrue, reason: 'duplicate ${curve.slug}');
        expect(OverlayCurve.fromSlug(curve.slug), curve);
      }
    });

    test('an unknown or absent slug answers null', () {
      expect(OverlayCurve.fromSlug(null), isNull);
      expect(OverlayCurve.fromSlug('parabolic'), isNull);
    });

    test('every row carries a label and a sentence', () {
      for (final curve in OverlayCurve.values) {
        expect(curve.label, isNotEmpty);
        expect(curve.description, endsWith('.'));
      }
    });

    test('every curve resolves, and starts and ends where it must', () {
      for (final curve in OverlayCurve.values) {
        final resolved = flutterCurve(curve);
        expect(resolved.transform(0.0), 0.0, reason: curve.slug);
        expect(resolved.transform(1.0), 1.0, reason: curve.slug);
      }
    });

    test('ClampedCurve holds an overshoot inside the unit interval', () {
      // The property `FadeTransition` needs and three of these curves break:
      // easeOutBack goes above 1, and read backwards it dips below 0.
      final raw = flutterCurve(OverlayCurve.overshoot);
      var sawOvershoot = false;
      const clamped = ClampedCurve(Curves.easeOutBack);
      for (var i = 1; i < 100; i++) {
        final t = i / 100;
        if (raw.transform(t) > 1.0) sawOvershoot = true;
        final v = clamped.transform(t);
        expect(v, inInclusiveRange(0.0, 1.0), reason: 't=$t');
      }
      expect(sawOvershoot, isTrue,
          reason: 'overshoot that never overshoots is not one');
    });
  });

  group('FadeOverlayScaffold', () {
    testWidgets('none wraps nothing and answers its owner on the spot',
        (tester) async {
      const theme = ThemeConfig(overlayEffect: OverlayEffect.none);
      final closing = ValueNotifier<bool>(false);
      var closed = 0;
      await tester.pumpWidget(
          _host(theme: theme, closing: closing, onClosed: () => closed++));

      // Not merely a zero-length animation: no controller is built at all, so
      // there is no layer over the card and no ticker in an idle shell.
      expect(find.byType(FadeTransition), findsNothing);
      expect(find.byType(Transform), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      // And the scrim is simply there, at the theme's own alpha.
      expect(_scrimFraction(tester, theme), 1.0);

      closing.value = true;
      expect(closed, 1, reason: 'the window may be destroyed this frame');
      closing.dispose();
    });

    testWidgets('a close asked for before the first build is still answered',
        (tester) async {
      // An overlay superseded in the turn it opened. Whoever asked is waiting on
      // `onClosed` to tear the window down, and under `none` that answer is
      // immediate — which is why it is given at the end of the frame rather than
      // inside the build it would be tearing down.
      for (final effect in const [OverlayEffect.none, OverlayEffect.fade]) {
        final closing = ValueNotifier<bool>(true);
        var closed = 0;
        await tester.pumpWidget(_host(
          theme: ThemeConfig(overlayEffect: effect),
          closing: closing,
          onClosed: () => closed++,
        ));
        await tester.pumpAndSettle();
        expect(closed, 1, reason: effect.slug);
        closing.dispose();
      }
    });

    testWidgets('the default is the entrance every overlay used to play',
        (tester) async {
      // A theme that says nothing about overlays must render exactly as the
      // shell did before the key existed: a scale from 0.96 under a fade, at
      // 160ms — the same guarantee `font_size` makes.
      const theme = ThemeConfig();
      expect(theme.overlayEffect, OverlayEffect.scale);
      expect(theme.overlayCurve, OverlayCurve.easeOut);
      expect(theme.overlayInDuration, const Duration(milliseconds: 160));
      expect(theme.overlayOutDuration, theme.overlayInDuration);

      final closing = ValueNotifier<bool>(false);
      await tester.pumpWidget(_host(theme: theme, closing: closing));
      expect(_cardOpacity(tester), 0.0);
      expect(_cardTransform(tester).storage[0], closeTo(kOverlayScaleFrom, 1e-6));

      await tester.pumpAndSettle();
      expect(_cardOpacity(tester), 1.0);
      expect(_cardTransform(tester).storage[0], closeTo(1.0, 1e-6));
      expect(_scrimFraction(tester, theme), 1.0);
      closing.dispose();
    });

    testWidgets('the duration is the theme\'s, and durationScale a ratio of it',
        (tester) async {
      const theme = ThemeConfig(overlayAnimationDuration: 400);
      final closing = ValueNotifier<bool>(false);
      await tester.pumpWidget(_host(theme: theme, closing: closing));

      await tester.pump(const Duration(milliseconds: 200));
      expect(_cardOpacity(tester), lessThan(1.0),
          reason: 'halfway through a 400ms entrance');
      await tester.pump(const Duration(milliseconds: 220));
      expect(_cardOpacity(tester), 1.0);

      // The same theme at half the pace is still animating where the first was
      // done: the scale multiplies the theme's number rather than replacing it.
      final second = ValueNotifier<bool>(false);
      await tester.pumpWidget(
          _host(theme: theme, closing: second, durationScale: 2.0));
      await tester.pump(const Duration(milliseconds: 420));
      expect(_cardOpacity(tester), lessThan(1.0));
      await tester.pumpAndSettle();
      expect(_cardOpacity(tester), 1.0);
      closing.dispose();
      second.dispose();
    });

    testWidgets('the exit is the entrance reversed, at the ratio\'s pace',
        (tester) async {
      const theme = ThemeConfig(
        overlayAnimationDuration: 200,
        overlayExitRatio: 0.5,
      );
      expect(theme.overlayOutDuration, const Duration(milliseconds: 100));

      final closing = ValueNotifier<bool>(false);
      var closed = 0;
      await tester.pumpWidget(
          _host(theme: theme, closing: closing, onClosed: () => closed++));
      await tester.pumpAndSettle();

      closing.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Mid-exit: the card is on its way back to where it came from, and the
      // teardown must not have happened — onClosed destroys the window.
      expect(closed, 0);
      expect(_cardOpacity(tester), lessThan(1.0));
      expect(_cardTransform(tester).storage[0], lessThan(1.0),
          reason: 'the shape of the exit is the entrance, backwards');

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(closed, 1);
      closing.dispose();
    });

    testWidgets('a ratio above 1 leaves more slowly than it arrived',
        (tester) async {
      const theme = ThemeConfig(
        overlayAnimationDuration: 100,
        overlayExitRatio: 2.0,
      );
      final closing = ValueNotifier<bool>(false);
      var closed = 0;
      await tester.pumpWidget(
          _host(theme: theme, closing: closing, onClosed: () => closed++));
      await tester.pumpAndSettle();

      closing.value = true;
      await tester.pump();
      // Past the whole entrance, and still going.
      await tester.pump(const Duration(milliseconds: 140));
      expect(closed, 0);
      await tester.pumpAndSettle();
      expect(closed, 1);
      closing.dispose();
    });

    testWidgets('the curve is the theme\'s', (tester) async {
      const linear = ThemeConfig(
        overlayAnimationDuration: 400,
        overlayCurve: OverlayCurve.linear,
      );
      final a = ValueNotifier<bool>(false);
      await tester.pumpWidget(_host(theme: linear, closing: a));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_cardOpacity(tester), closeTo(0.5, 0.02));

      const eased = ThemeConfig(
        overlayAnimationDuration: 400,
        overlayCurve: OverlayCurve.easeOut,
      );
      final b = ValueNotifier<bool>(false);
      await tester.pumpWidget(_host(theme: eased, closing: b));
      await tester.pump(const Duration(milliseconds: 200));
      // Halfway through the clock, an ease-out is well past halfway through
      // the journey. That difference is the whole key.
      expect(_cardOpacity(tester), greaterThan(0.6));
      a.dispose();
      b.dispose();
    });

    testWidgets('an overshoot reaches the geometry but never the alpha',
        (tester) async {
      // The one combination that can abort the shell rather than look wrong:
      // `Opacity` asserts on an argument outside 0..1, and easeOutBack is above
      // 1 for most of the second half of its run.
      const theme = ThemeConfig(
        overlayAnimationDuration: 400,
        overlayCurve: OverlayCurve.overshoot,
      );
      final closing = ValueNotifier<bool>(false);
      await tester.pumpWidget(_host(theme: theme, closing: closing));

      var sawOvershoot = false;
      for (var elapsed = 0; elapsed < 400; elapsed += 20) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(_cardOpacity(tester), inInclusiveRange(0.0, 1.0));
        if (_cardTransform(tester).storage[0] > 1.0) sawOvershoot = true;
      }
      expect(sawOvershoot, isTrue,
          reason: 'the card should pass its resting size and come back');
      await tester.pumpAndSettle();
      expect(_cardTransform(tester).storage[0], closeTo(1.0, 1e-6));
      closing.dispose();
    });

    testWidgets('a travelling effect starts displaced and lands square',
        (tester) async {
      const theme = ThemeConfig(overlayEffect: OverlayEffect.rise);
      final closing = ValueNotifier<bool>(false);
      await tester.pumpWidget(_host(theme: theme, closing: closing));
      expect(_cardTransform(tester).storage[13], closeTo(kOverlayTravel, 1e-6),
          reason: 'rise comes up from below');

      const drop = ThemeConfig(overlayEffect: OverlayEffect.drop);
      final other = ValueNotifier<bool>(false);
      await tester.pumpWidget(_host(theme: drop, closing: other));
      expect(_cardTransform(tester).storage[13], closeTo(-kOverlayTravel, 1e-6),
          reason: 'drop comes down from above');
      closing.dispose();
      other.dispose();
    });

    testWidgets('every effect settles with the card exactly where it belongs',
        (tester) async {
      // Whatever an effect does on the way in, an overlay at rest is an overlay
      // at rest: the same rect, fully opaque, and nothing still ticking.
      Rect? resting;
      for (final effect in OverlayEffect.values) {
        final closing = ValueNotifier<bool>(false);
        await tester.pumpWidget(_host(
          theme: ThemeConfig(overlayEffect: effect),
          closing: closing,
        ));
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.byType(SizedBox).first);
        expect(rect.size, _kCard, reason: effect.slug);
        resting ??= rect;
        expect(rect, resting, reason: effect.slug);
        expect(tester.binding.transientCallbackCount, 0,
            reason: 'nothing animates at rest (${effect.slug})');
        if (effect.animates) expect(_cardOpacity(tester), 1.0);
        closing.dispose();
      }
    });

    testWidgets('the scrim fades by alpha and is never transformed',
        (tester) async {
      // The scrim is the size of the output, so anything moving or fading it
      // through a layer is a full-output offscreen every frame. Only the card
      // is allowed either.
      const theme = ThemeConfig(
        overlayEffect: OverlayEffect.swing,
        overlayAnimationDuration: 400,
      );
      final closing = ValueNotifier<bool>(false);
      await tester.pumpWidget(_host(theme: theme, closing: closing));
      await tester.pump(const Duration(milliseconds: 200));

      final fraction = _scrimFraction(tester, theme);
      expect(fraction, greaterThan(0.0));
      expect(fraction, lessThan(1.0));
      expect(find.byType(Opacity), findsNothing);
      // One transform in the tree, and it is the card's.
      expect(find.byType(Transform), findsOneWidget);
      expect(
        tester.renderObject<RenderBox>(find.byType(FadeTransition)).size,
        _kCard,
      );
      closing.dispose();
    });
  });
}
