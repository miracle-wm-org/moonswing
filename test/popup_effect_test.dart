// The popup animation table, and the widget that plays it.
//
// Two properties matter above the rest, because losing either is what the
// feature exists to prevent: **the exit is the entrance reversed** — there is
// no second definition of an effect, so a card cannot leave by a route it
// never arrived by — and **`none` is a real off switch**, answering its owner
// on the spot, which is what lets `PopupHost` destroy a window in the frame it
// was closed exactly as it did before there was an exit at all.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/popup_transition.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/popup_effect.dart';
import 'package:graceful_shell/theme/tokens.dart';

Widget _host({
  Key? key,
  PopupEffect? effect,
  String? edge,
  ValueListenable<bool>? closing,
  VoidCallback? onClosed,
  ThemeConfig? theme,
}) {
  final Widget transition = PopupTransition(
    key: key,
    effect: effect,
    edge: edge,
    closing: closing,
    onClosed: onClosed,
    child: const SizedBox(width: 120, height: 60),
  );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: theme == null
        ? transition
        : ThemeScope(theme: theme, child: transition),
  );
}

double _opacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byType(Opacity).first).opacity;

Offset _translation(WidgetTester tester) {
  final t = tester.widget<Transform>(find.byType(Transform).first);
  return Offset(t.transform.storage[12], t.transform.storage[13]);
}

void main() {
  group('the effect table', () {
    test('every slug is unique, and round-trips', () {
      final slugs = <String>{};
      for (final effect in PopupEffect.values) {
        expect(slugs.add(effect.slug), isTrue,
            reason: 'duplicate ${effect.slug}');
        expect(PopupEffect.fromSlug(effect.slug), effect);
      }
    });

    test('an unknown or absent slug answers null, never a throw', () {
      // The caller is ThemeConfig.fromMap, whose whole discipline is that a
      // bad value costs its own key; it holds the fallback, not this.
      expect(PopupEffect.fromSlug(null), isNull);
      expect(PopupEffect.fromSlug('kaleidoscope'), isNull);
      expect(PopupEffect.fromSlug(''), isNull);
    });

    test('only `none` claims not to animate', () {
      for (final effect in PopupEffect.values) {
        expect(effect.animates, effect != PopupEffect.none,
            reason: effect.slug);
      }
    });

    test('every row carries a label and a sentence for the settings UI', () {
      for (final effect in PopupEffect.values) {
        expect(effect.label, isNotEmpty);
        expect(effect.description, endsWith('.'));
      }
    });
  });

  group('PopupTransition', () {
    testWidgets('none wraps nothing at all', (tester) async {
      final closing = ValueNotifier<bool>(false);
      var closed = false;
      await tester.pumpWidget(_host(
        effect: PopupEffect.none,
        closing: closing,
        onClosed: () => closed = true,
      ));

      // Not merely a zero-length animation: no Opacity and no Transform is
      // what keeps a popup's whole card out of a save layer it gains nothing
      // from.
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(Transform), findsNothing);

      closing.value = true;
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('an animated effect starts invisible and settles opaque',
        (tester) async {
      await tester.pumpWidget(_host(effect: PopupEffect.fade));
      expect(_opacity(tester), 0.0);

      await tester.pump(ShellDurations.popupIn ~/ 2);
      final mid = _opacity(tester);
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(1.0));

      await tester.pumpAndSettle();
      expect(_opacity(tester), 1.0);
    });

    testWidgets('the exit is the entrance reversed', (tester) async {
      final closing = ValueNotifier<bool>(false);
      var closed = false;
      await tester.pumpWidget(_host(
        effect: PopupEffect.fade,
        closing: closing,
        onClosed: () => closed = true,
      ));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1.0);

      closing.value = true;
      await tester.pump();
      await tester.pump(ShellDurations.popupOut ~/ 3);
      final first = _opacity(tester);
      expect(first, lessThan(1.0));
      // The owner destroys the window on this callback, so it must not arrive
      // while the card is still on screen.
      expect(closed, isFalse);

      await tester.pump(ShellDurations.popupOut ~/ 3);
      expect(_opacity(tester), lessThan(first));

      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });

    testWidgets('the theme paces the animation', (tester) async {
      // `popup_animation_duration`, the one number behind both directions: a
      // theme that lengthens the entrance lengthens the exit with it.
      const slow = ThemeConfig(popupAnimationDuration: 600);
      await tester.pumpWidget(_host(effect: PopupEffect.fade, theme: slow));

      // Still mid-fade well past the default 140ms entrance, which is what says
      // the theme's number is the one being played.
      await tester.pump(ShellDurations.popupIn * 2);
      expect(_opacity(tester), lessThan(1.0));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1.0);
    });

    testWidgets('a second dismissal mid-exit does not restart it',
        (tester) async {
      final closing = ValueNotifier<bool>(false);
      var closes = 0;
      await tester.pumpWidget(_host(
        effect: PopupEffect.scale,
        closing: closing,
        onClosed: () => closes++,
      ));
      await tester.pumpAndSettle();

      closing.value = true;
      await tester.pump(ShellDurations.popupOut ~/ 3);
      // The coordinator's `closing` flag flipping again mid-fade — a second
      // surface opening over one already on its way out.
      closing.value = false;
      closing.value = true;
      await tester.pumpAndSettle();
      expect(closes, 1);
    });

    testWidgets('a close requested before the first frame is still answered',
        (tester) async {
      // A popup displaced in the same turn it opened: the coordinator's
      // dismissal can land before this widget has ever built.
      final closing = ValueNotifier<bool>(true);
      var closed = false;
      await tester.pumpWidget(_host(
        effect: PopupEffect.slide,
        closing: closing,
        onClosed: () => closed = true,
      ));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });

    testWidgets('slide travels out of the bar it is anchored to',
        (tester) async {
      const cases = <(String?, Offset)>[
        ('top', Offset(0, -1)),
        ('bottom', Offset(0, 1)),
        ('left', Offset(-1, 0)),
        ('right', Offset(1, 0)),
        // A menu at the pointer has no bar to travel out of, and the
        // compositor hangs it below its anchor — so it arrives the way a top
        // bar's popup does.
        (null, Offset(0, -1)),
      ];
      for (final (edge, sign) in cases) {
        // Keyed per case so each one gets a fresh State and replays from zero
        // rather than being updated in place.
        await tester.pumpWidget(_host(
          key: ValueKey<String>('slide-$edge'),
          effect: PopupEffect.slide,
          edge: edge,
        ));
        expect(
          _translation(tester),
          Offset(sign.dx * kPopupSlideDistance, sign.dy * kPopupSlideDistance),
          reason: 'edge $edge starts on the bar\'s side',
        );

        await tester.pumpAndSettle();
        expect(_translation(tester), Offset.zero,
            reason: 'edge $edge settles flush');
      }
    });

    testWidgets("with no effect given it plays the theme's", (tester) async {
      await tester.pumpWidget(_host(
        key: const ValueKey<String>('themed-none'),
        theme: const ThemeConfig(popupEffect: PopupEffect.none),
      ));
      expect(find.byType(Opacity), findsNothing);

      await tester.pumpWidget(_host(
        key: const ValueKey<String>('themed-fade'),
        theme: const ThemeConfig(popupEffect: PopupEffect.fade),
      ));
      expect(find.byType(Opacity), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('and falls back to the default with no theme above it',
        (tester) async {
      // A card built alone in a widget test has no ThemeProvider behind it; one
      // that refused to animate there would be exercising a path the shell
      // itself never takes.
      await tester.pumpWidget(_host());
      expect(find.byType(Transform), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('nothing is left ticking once it has settled', (tester) async {
      await tester.pumpWidget(_host(effect: PopupEffect.spin));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
