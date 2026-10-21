import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/clipboard/clipboard_config.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/docked_panel.dart';
import 'package:moonswing/modules/notifications.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/overlay_effect.dart';

const _content = Key('content');

/// A bare docked panel whose content fills it, so the content's rect is the
/// panel as laid out — transforms included.
Widget _panel({
  required ValueNotifier<bool> closing,
  required VoidCallback onClosed,
  required DockSide side,
  required DockedPanelAnimation animation,
}) {
  return ThemeScope(
    theme: const ThemeConfig(),
    child: DockedPanel(
      side: side,
      animation: animation,
      closingNotifier: closing,
      onClosed: onClosed,
      child: const SizedBox.expand(key: _content),
    ),
  );
}

void main() {
  group('DockedPanelAnimation.fromMap', () {
    test('says what both panels did before the keys existed', () {
      const defaults = DockedPanelAnimation();
      expect(DockedPanelAnimation.fromMap(null), defaults);
      expect(DockedPanelAnimation.fromMap(const {}), defaults);
      expect(defaults.effect, DockedPanelEffect.slide);
      expect(defaults.curve, OverlayCurve.easeOut);
      expect(defaults.enter, const Duration(milliseconds: 180));
      expect(defaults.exit, lessThan(defaults.enter));
      expect(defaults.travel, 1.0);
      expect(defaults.fade, isFalse);
      expect(defaults.animates, isTrue);
    });

    test('reads every key', () {
      final animation = DockedPanelAnimation.fromMap(const {
        'animation': 'stretch',
        'animation_curve': 'elastic',
        'animation_duration': 400,
        'animation_exit_ratio': 0.5,
        'animation_travel': 0.25,
        'animation_fade': true,
      });
      expect(animation.effect, DockedPanelEffect.stretch);
      expect(animation.curve, OverlayCurve.elastic);
      expect(animation.enter, const Duration(milliseconds: 400));
      expect(animation.exit, const Duration(milliseconds: 200));
      expect(animation.travel, 0.25);
      expect(animation.fade, isTrue);
    });

    test('spellings are forgiving of case and spaces', () {
      final animation = DockedPanelAnimation.fromMap(const {
        'animation': ' Reveal ',
        'animation_curve': 'EASE_IN_OUT',
      });
      expect(animation.effect, DockedPanelEffect.reveal);
      expect(animation.curve, OverlayCurve.easeInOut);
    });

    // A typo costs that key, never its neighbours or the table.
    test('a bad value costs its own key only', () {
      final animation = DockedPanelAnimation.fromMap(const {
        'animation': 'wobble',
        'animation_curve': 3,
        'animation_duration': 'slow',
        'animation_fade': 'yes',
        'animation_travel': 0.5,
      });
      expect(animation.effect, DockedPanelEffect.slide);
      expect(animation.curve, OverlayCurve.easeOut);
      expect(animation.durationMs, kDockedPanelEnterMs);
      expect(animation.fade, isFalse);
      expect(animation.travel, 0.5);
    });

    test('numbers are clamped', () {
      final high = DockedPanelAnimation.fromMap(const {
        'animation_duration': 99999,
        'animation_exit_ratio': 9.0,
        'animation_travel': 4.0,
      });
      expect(high.durationMs, kDockedPanelMaxDurationMs);
      expect(high.exitRatio, 2.0);
      expect(high.travel, 1.0);

      final low = DockedPanelAnimation.fromMap(const {
        'animation_duration': -5,
        'animation_exit_ratio': -1.0,
        'animation_travel': 0.0,
      });
      expect(low.durationMs, 0);
      expect(low.exitRatio, 0.0);
      expect(low.travel, 0.05);
    });

    test('a zero duration is no animation at all', () {
      expect(
        DockedPanelAnimation.fromMap(const {'animation_duration': 0}).animates,
        isFalse,
      );
      expect(
        const DockedPanelAnimation(effect: DockedPanelEffect.none).animates,
        isFalse,
      );
    });

    // The config objects carry value equality, or the live-config notifier
    // could never refuse a keystroke that changed nothing.
    test('takes part in both modules\' equality', () {
      const fading = DockedPanelAnimation(effect: DockedPanelEffect.fade);
      expect(
        const NotificationsConfig(animation: fading),
        isNot(const NotificationsConfig()),
      );
      expect(
        const ClipboardConfig(animation: fading),
        isNot(const ClipboardConfig()),
      );
      expect(
        NotificationsConfig.fromMap(const {'animation': 'fade'}),
        const NotificationsConfig(animation: fading),
      );
      expect(
        ClipboardConfig.fromMap(const {'animation': 'fade'}),
        const ClipboardConfig(animation: fading),
      );
    });
  });

  group('DockedPanel effects', () {
    // The curves most likely to break the rule: the plain default, and the
    // three that leave the unit interval or come back on themselves.
    const curves = [
      OverlayCurve.easeOut,
      OverlayCurve.overshoot,
      OverlayCurve.bounce,
      OverlayCurve.elastic,
    ];

    for (final effect in DockedPanelEffect.values.where((e) => e != DockedPanelEffect.none)) {
      for (final side in DockSide.values) {
        for (final curve in curves) {
          for (final fade in [false, true]) {
            final animation = DockedPanelAnimation(
              effect: effect,
              curve: curve,
              fade: fade,
              travel: 0.6,
            );
            testWidgets(
                '${effect.slug} on ${curve.slug}${fade ? ' with a fade' : ''}, '
                'docked ${side.name}, never leaves its edge', (tester) async {
              final closing = ValueNotifier(false);
              addTearDown(closing.dispose);
              var closed = 0;

              // How far the panel's screen-edge side is from that edge:
              // positive when it has come away from it, which is the bug.
              final view = tester.view.physicalSize / tester.view.devicePixelRatio;
              double gap() {
                final rect = tester.getRect(find.byKey(_content));
                return side == DockSide.left
                    ? rect.left
                    : view.width - rect.right;
              }

              await tester.pumpWidget(
                _panel(
                  closing: closing,
                  onClosed: () => closed++,
                  side: side,
                  animation: animation,
                ),
              );
              const step = Duration(milliseconds: 8);
              for (var t = Duration.zero;
                  t < animation.enter + step * 4;
                  t += step) {
                expect(gap(), lessThanOrEqualTo(0.01),
                    reason: 'entrance pulled away from the edge at $t');
                await tester.pump(step);
              }
              await tester.pumpAndSettle();
              expect(gap(), closeTo(0, 0.01));
              // Nothing is still ticking at rest.
              expect(SchedulerBinding.instance.transientCallbackCount, 0);

              closing.value = true;
              await tester.pump();
              for (var t = Duration.zero;
                  t < animation.exit + step * 4;
                  t += step) {
                expect(gap(), lessThanOrEqualTo(0.01),
                    reason: 'exit pulled away from the edge at $t');
                await tester.pump(step);
              }
              await tester.pumpAndSettle();
              expect(closed, 1);
            });
          }
        }
      }
    }

    // A reveal leaves the content where it stands; what moves is the clip, and
    // the visible strip is always the one against the screen edge.
    for (final side in DockSide.values) {
      testWidgets('reveal uncovers from the ${side.name} edge', (tester) async {
        final closing = ValueNotifier(false);
        addTearDown(closing.dispose);
        const animation = DockedPanelAnimation(
          effect: DockedPanelEffect.reveal,
          curve: OverlayCurve.linear,
        );
        await tester.pumpWidget(
          _panel(
            closing: closing,
            onClosed: () {},
            side: side,
            animation: animation,
          ),
        );
        await tester.pump(animation.enter ~/ 2);

        final clip = tester.widget<ClipRect>(
          find
              .ancestor(of: find.byKey(_content), matching: find.byType(ClipRect))
              .first,
        );
        final size = tester.getSize(find.byKey(_content));
        final visible = clip.clipper!.getClip(size);
        expect(visible.width, closeTo(size.width / 2, 2));
        if (side == DockSide.left) {
          expect(visible.left, 0);
        } else {
          expect(visible.right, size.width);
        }
        await tester.pumpAndSettle();
      });
    }

    testWidgets('fade alone moves nothing and fades', (tester) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      await tester.pumpWidget(
        _panel(
          closing: closing,
          onClosed: () {},
          side: DockSide.left,
          animation: const DockedPanelAnimation(
            effect: DockedPanelEffect.fade,
          ),
        ),
      );
      expect(find.byType(SlideTransition), findsNothing);
      expect(find.byType(FadeTransition), findsOneWidget);
      await tester.pumpAndSettle();
    });

    for (final animation in const [
      DockedPanelAnimation(effect: DockedPanelEffect.none),
      DockedPanelAnimation(durationMs: 0),
    ]) {
      testWidgets(
          'with no animation (${animation.effect.slug}, '
          '${animation.durationMs}ms) nothing ticks and a close is immediate',
          (tester) async {
        final closing = ValueNotifier(false);
        addTearDown(closing.dispose);
        var closed = 0;

        await tester.pumpWidget(
          _panel(
            closing: closing,
            onClosed: () => closed++,
            side: DockSide.right,
            animation: animation,
          ),
        );
        expect(SchedulerBinding.instance.transientCallbackCount, 0);
        expect(find.byType(SlideTransition), findsNothing);
        expect(find.byType(FadeTransition), findsNothing);

        closing.value = true;
        // Not from inside the notifier's own dispatch...
        expect(closed, 0);
        // ...but without waiting for a frame either: an idle shell has none.
        await tester.idle();
        expect(closed, 1);

        // And only once, however often it is asked.
        closing.value = false;
        closing.value = true;
        await tester.idle();
        expect(closed, 1);
      });
    }
  });
}
