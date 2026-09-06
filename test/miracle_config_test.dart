// The Window Manager pane's testable half.
//
// Almost none of `settings/miracle/` can be exercised here: every value it
// renders comes out of `libmiracle-wm-c`, which is not installed on a test
// machine and has no in-process fake — the package's own configuration tests
// skip for exactly that reason. So what is pinned is the part that is *not*
// FFI, and it is the part that is easy to get quietly wrong:
//
//  * the evdev table, where a wrong code silently rebinds somebody's shortcut;
//  * the colour conversion, where an off-by-one repaints every border a shade
//    darker each time the page is opened;
//  * the shortcut formatting, which is what the save notice tells the user to
//    press;
//  * and the store's no-configuration states, which are the whole of the pane
//    on a machine with no miracle-wm.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miracle/miracle.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/miracle_config/miracle_color.dart';
import 'package:graceful_shell/miracle_config/miracle_config_store.dart';
import 'package:graceful_shell/miracle_config/miracle_key_codes.dart';
import 'package:graceful_shell/miracle_config/miracle_labels.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/settings/miracle.dart';
import 'package:graceful_shell/scopes.dart';

void main() {
  group('evdev key table', () {
    test('is one row per code, ascending', () {
      final codes = [for (final key in kMiracleKeys) key.code];
      expect(codes.toSet(), hasLength(codes.length));
      final sorted = [...codes]..sort();
      expect(codes, sorted);
    });

    // Spot checks against `input-event-codes.h`. A shifted table would still
    // look plausible everywhere — every label would simply name the key next
    // to the right one — so the anchors have to be spelled out.
    test('the anchors are where the kernel puts them', () {
      expect(miracleKeyForCode(1)?.name, 'KEY_ESC');
      expect(miracleKeyForCode(19)?.name, 'KEY_R');
      expect(miracleKeyForCode(28)?.name, 'KEY_ENTER');
      expect(miracleKeyForCode(57)?.name, 'KEY_SPACE');
      expect(miracleKeyForCode(59)?.name, 'KEY_F1');
      expect(miracleKeyForCode(125)?.name, 'KEY_LEFTMETA');
    });

    test('every row says what it is, and says it once', () {
      final labels = <String, String>{};
      for (final key in kMiracleKeys) {
        expect(key.name, startsWith('KEY_'));
        expect(key.label, isNotEmpty);
        expect(
          labels.containsKey(key.label),
          isFalse,
          reason:
              'two keys both read as "${key.label}": ${labels[key.label]} '
              'and ${key.name}',
        );
        labels[key.label] = key.name;
      }
    });

    // A configuration written against a newer kernel, or a vendor key. The
    // binding stays editable and, crucially, stays saveable as authored.
    test('a code the table does not name still has a label', () {
      expect(miracleKeyForCode(99999), isNull);
      expect(miracleKeyLabel(99999), 'Key code 99999');
      expect(miracleKeyLabel(19), 'R');
    });
  });

  group('labels', () {
    test('a shortcut is written in the conventional order', () {
      expect(
        describeShortcut({
          Modifier.shift,
          Modifier.primary,
          Modifier.ctrl,
        }, 'R'),
        'Action Key + Ctrl + Shift + R',
      );
      expect(describeShortcut(const {}, 'F1'), 'F1');
    });

    test('the sentinel modifier is called what the wiki calls it', () {
      expect(modifierLabel(Modifier.primary), 'Action Key');
      expect(modifierLabel(Modifier.meta), 'Super');
      expect(modifierLabel(Modifier.ctrlLeft), 'Left Ctrl');
    });

    test('every modifier is offered exactly once, generic bits first', () {
      expect(kModifiersInDisplayOrder.toSet(), Modifier.values.toSet());
      expect(kModifiersInDisplayOrder.first, Modifier.primary);
      expect(
        kModifiersInDisplayOrder.indexOf(Modifier.ctrl),
        lessThan(kModifiersInDisplayOrder.indexOf(Modifier.ctrlLeft)),
      );
    });

    test('the reload shortcut is miracle\'s default when nothing rebinds it', () {
      expect(
        reloadShortcutLabel(const <KeyCommandOverride>[], miracleKeyLabel),
        'Action Key + Shift + R',
      );
    });

    // The reason it is read off the configuration at all: telling somebody to
    // press a combination they have taken away is worse than saying nothing.
    test('the reload shortcut follows an override', () {
      expect(
        reloadShortcutLabel(const [
          KeyCommandOverride(
            key: 59, // KEY_F1
            command: BuiltInKeyCommand.reloadConfig,
            modifiers: {Modifier.ctrl, Modifier.alt},
          ),
        ], miracleKeyLabel),
        'Ctrl + Alt + F1',
      );
    });

    test('an override of some other command is not the reload shortcut', () {
      expect(
        reloadShortcutLabel(const [
          KeyCommandOverride(
            key: 59,
            command: BuiltInKeyCommand.fullscreen,
            modifiers: {Modifier.ctrl},
          ),
        ], miracleKeyLabel),
        kDefaultReloadShortcut,
      );
    });

    test('every enum has a label, and no two share one', () {
      void unique<T>(List<T> values, String Function(T) label) {
        final seen = <String>{};
        for (final value in values) {
          final text = label(value);
          expect(text, isNotEmpty, reason: '$value');
          expect(seen.add(text), isTrue, reason: 'duplicate label "$text"');
        }
      }

      unique(Modifier.values, modifierLabel);
      unique(MouseButton.values, mouseButtonLabel);
      unique(KeyboardAction.values, keyboardActionLabel);
      unique(BuiltInKeyCommand.values, builtInCommandLabel);
      unique(AnimationType.values, animationTypeLabel);
      unique(EaseFunction.values, easeFunctionLabel);
      unique(Handedness.values, handednessLabel);
      unique(Acceleration.values, accelerationLabel);
      unique(TouchpadClickMode.values, touchpadClickModeLabel);
      unique(TouchpadScrollMode.values, touchpadScrollModeLabel);
      unique(CursorFocusMode.values, cursorFocusModeLabel);
    });

    test('easing names are the ones easings.net uses', () {
      expect(easeFunctionLabel(EaseFunction.linear), 'Linear');
      expect(easeFunctionLabel(EaseFunction.easeInOutSine), 'Ease In Out Sine');
    });

    // The event names are miracle's, not the configuration's, so a compositor
    // that grows one must render it rather than drop it.
    test('an unknown animateable event still gets a name', () {
      expect(animateableEventLabel('window_open'), 'A window opens');
      expect(animateableEventLabel('portal_open'), 'Portal open');
    });
  });

  group('colours', () {
    test('a hex round-trips through miracle components', () {
      const hex = '#80336699';
      final colour = rgbaFromHex(hex);
      expect(colour, isNotNull);
      expect(rgbaToHex(colour!), hex);
    });

    test('a six-digit hex is opaque', () {
      final colour = rgbaFromHex('336699');
      expect(colour!.alpha, 1.0);
      expect(rgbaToHex(colour, includeAlpha: false), '#336699');
    });

    test('the byte conversion is stable across a re-read', () {
      // The failure this guards: a colour that shifts by one every time the
      // page is opened, because rounding down on the way out and up on the way
      // in never reaches a fixed point.
      for (final start in ['#FF000000', '#FFFFFFFF', '#0A0B0C0D', '#7F7F7F7F']) {
        var hex = start;
        for (var i = 0; i < 5; i++) {
          hex = rgbaToHex(rgbaFromHex(hex)!);
        }
        expect(hex, start);
      }
    });

    test('a half-typed hex is not a colour', () {
      expect(rgbaFromHex(''), isNull);
      expect(rgbaFromHex('#33'), isNull);
      expect(rgbaFromHex('#3366990'), isNull);
      expect(rgbaFromHex('#zzzzzz'), isNull);
    });

    test('components outside the range are clamped rather than wrapped', () {
      expect(
        rgbaToHex(const RgbaColor(red: 2, green: -1, blue: 0.5, alpha: 1)),
        '#FFFF0080',
      );
      expect(
        rgbaToHex(const RgbaColor(red: double.nan, green: 0, blue: 0)),
        '#FF000000',
      );
    });
  });

  group('MiracleConfigStore with no library', () {
    MiracleConfigStore unavailable() => MiracleConfigStore.forTesting(
      isAvailable: () => false,
      path: () => '/home/somebody/.config/miracle-wm/config.yaml',
    );

    test('settles unavailable, and holds no configuration', () {
      final store = unavailable();
      addTearDown(store.dispose);
      expect(store.status, MiracleConfigStatus.idle);

      store.acquire();
      expect(store.status, MiracleConfigStatus.unavailable);
      expect(store.config, isNull);
      expect(store.dirty, isFalse);
      expect(store.showReloadNotice, isFalse);
    });

    // `acquire` runs inside the acquirer's `initState`, which is the rule every
    // lease in this shell keeps.
    test('acquire does not notify', () {
      final store = unavailable();
      addTearDown(store.dispose);
      var notifications = 0;
      store.addListener(() => notifications++);
      store.acquire();
      expect(notifications, 0);
    });

    test('editing and saving without a configuration do nothing', () {
      final store = unavailable();
      addTearDown(store.dispose);
      store.acquire();
      var notifications = 0;
      store.addListener(() => notifications++);

      store.edit((config) => config.innerGapsX = 10);
      expect(notifications, 0);
      expect(store.dirty, isFalse);
      expect(store.save(), isFalse);
      expect(notifications, 0);
    });

    test('an unbalanced release is not an underflow', () {
      final store = unavailable();
      addTearDown(store.dispose);
      store.release();
      store.acquire();
      store.release();
      store.release();
      expect(store.status, MiracleConfigStatus.idle);
    });

    test('the path is still reportable', () {
      final store = unavailable();
      addTearDown(store.dispose);
      expect(store.path, endsWith('miracle-wm/config.yaml'));
    });
  });

  group('MiracleSettingsPage', () {
    Future<void> pump(WidgetTester tester, MiracleConfigStore store) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: Overlay(
              key: ObjectKey(store),
              initialEntries: [
                OverlayEntry(
                  builder: (_) => SizedBox(
                    width: 620,
                    height: 560,
                    child: MiracleSettingsPage(store: store),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // The state a machine without miracle-wm lands in. An empty form here
    // would read as a compositor with no settings.
    testWidgets('says so when the library is missing, and offers a retry', (
      tester,
    ) async {
      var probes = 0;
      final store = MiracleConfigStore.forTesting(
        isAvailable: () {
          probes++;
          return false;
        },
        path: () => '/tmp/miracle/config.yaml',
      );
      addTearDown(store.dispose);

      await pump(tester, store);

      expect(find.text('miracle-wm is not installed here'), findsOneWidget);
      expect(find.byType(SettingsRescanButton), findsOneWidget);
      // No Save or Reset: there is nothing loaded for either to act on.
      expect(find.text('Save'), findsNothing);
      expect(find.text('Reset'), findsNothing);

      final before = probes;
      await tester.tap(find.byType(SettingsRescanButton));
      await tester.pumpAndSettle();
      expect(probes, greaterThan(before));
    });

  });
}
