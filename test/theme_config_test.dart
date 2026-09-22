import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/theme/overlay_effect.dart';
import 'package:moonswing/theme/popup_effect.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/theme/tokens.dart';

void main() {
  group('a hand-edited theme cannot crash the shell', () {
    // Theme files are edited by hand, so every numeric key has to survive
    // whatever is typed into it. The clamps live in ThemeConfig.fromMap rather
    // than at each painter, so one bad value costs that key and nothing else.

    test('a non-numeric value falls back', () {
      final theme = ThemeConfig.fromMap({
        'panel_margin': 'lots',
        'panel_radius': true,
        'panel_border_width': [1, 2],
        'popup_radius': 'round',
        'popup_border_width': {'a': 1},
      });
      expect(theme.panelMargin, 0);
      expect(theme.panelRadius, 0.0);
      expect(theme.panelBorderWidth, 0.0);
      // The popup fallbacks are not zero, so a garbled value must land on the
      // shipped card shape rather than on the panel's flush-and-square one.
      expect(theme.popupRadius, 8.0);
      expect(theme.popupBorderWidth, 1.0);
    });

    test('a negative value clamps to zero', () {
      final theme = ThemeConfig.fromMap({
        'panel_margin': -5,
        'panel_radius': -1.0,
        'panel_border_width': -0.5,
        'popup_radius': -1.0,
        'popup_border_width': -0.5,
      });
      expect(theme.panelMargin, 0);
      expect(theme.panelRadius, 0.0);
      expect(theme.panelBorderWidth, 0.0);
      // Clamped, not fallen back: zero is a legitimate popup shape — a square
      // card with no rim — and a negative one is the nearest thing to it.
      expect(theme.popupRadius, 0.0);
      expect(theme.popupBorderWidth, 0.0);
    });

    test('an absurd value clamps to the ceiling', () {
      final theme = ThemeConfig.fromMap({
        'panel_margin': 100000,
        'panel_radius': 1e9,
        'panel_border_width': 999,
        'popup_radius': 1e9,
        'popup_border_width': 999,
      });
      expect(theme.panelMargin, 256);
      expect(theme.panelRadius, 64.0);
      expect(theme.panelBorderWidth, 16.0);
      expect(theme.popupRadius, 64.0);
      expect(theme.popupBorderWidth, 16.0);
    });

    test('NaN falls back rather than propagating', () {
      // The margin is the sharp edge here: double.nan.toInt() throws
      // UnsupportedError, so a NaN that reached the int conversion would take
      // down the whole theme rather than one key.
      final theme = ThemeConfig.fromMap({
        'panel_margin': double.nan,
        'panel_radius': double.nan,
        'panel_border_width': double.nan,
        'popup_radius': double.nan,
        'popup_border_width': double.nan,
      });
      expect(theme.panelMargin, 0);
      expect(theme.panelRadius, 0.0);
      expect(theme.panelBorderWidth, 0.0);
      expect(theme.popupRadius, 8.0);
      expect(theme.popupBorderWidth, 1.0);
    });

    test('infinity falls back rather than clamping', () {
      // clamp() lets infinity through as the upper bound, which would be a
      // silently absurd value instead of an obviously ignored one.
      final theme = ThemeConfig.fromMap({
        'panel_margin': double.infinity,
        'panel_radius': double.negativeInfinity,
        'popup_radius': double.infinity,
        'popup_border_width': double.negativeInfinity,
      });
      expect(theme.panelMargin, 0);
      expect(theme.panelRadius, 0.0);
      expect(theme.popupRadius, 8.0);
      expect(theme.popupBorderWidth, 1.0);
    });

    test('a malformed border colour costs only that key', () {
      final theme = ThemeConfig.fromMap({
        'panel_border': 'not a colour',
        'panel_border_width': 2.0,
      });
      expect(theme.panelBorder, const ThemeConfig().panelBorder);
      expect(theme.panelBorderWidth, 2.0);
    });

    test('a malformed popup rim colour costs only that key', () {
      final theme = ThemeConfig.fromMap({
        'popup_border': 'not a colour',
        'popup_border_width': 2.0,
      });
      expect(theme.popupBorder, const ThemeConfig().popupBorder);
      expect(theme.popupBorderWidth, 2.0);
    });
  });

  group('the new keys take part in equality', () {
    // ThemeScope.updateShouldNotify is `old != new`, so a field missing from
    // == means changing it in the settings UI repaints nothing — a failure
    // that reads like a Flutter bug rather than a missing comparison.
    const base = ThemeConfig();

    test('panel_margin', () {
      expect(base, isNot(const ThemeConfig(panelMargin: 8)));
    });

    test('panel_radius', () {
      expect(base, isNot(const ThemeConfig(panelRadius: 12.0)));
    });

    test('panel_border', () {
      expect(base, isNot(const ThemeConfig(panelBorder: Color(0xFFFF0000))));
    });

    test('panel_border_width', () {
      expect(base, isNot(const ThemeConfig(panelBorderWidth: 1.0)));
    });

    test('popup_radius', () {
      expect(base, isNot(const ThemeConfig(popupRadius: 12.0)));
    });

    test('popup_border', () {
      expect(base, isNot(const ThemeConfig(popupBorder: Color(0xFFFF0000))));
    });

    test('popup_border_width', () {
      expect(base, isNot(const ThemeConfig(popupBorderWidth: 2.0)));
    });

    test('popup_animation', () {
      expect(base, isNot(const ThemeConfig(popupEffect: PopupEffect.fade)));
    });

    test('and hashCode moves with them', () {
      final hashes = {
        base.hashCode,
        const ThemeConfig(panelMargin: 8).hashCode,
        const ThemeConfig(panelRadius: 12.0).hashCode,
        const ThemeConfig(panelBorder: Color(0xFFFF0000)).hashCode,
        const ThemeConfig(panelBorderWidth: 1.0).hashCode,
        const ThemeConfig(popupRadius: 12.0).hashCode,
        const ThemeConfig(popupBorder: Color(0xFFFF0000)).hashCode,
        const ThemeConfig(popupBorderWidth: 2.0).hashCode,
      };
      expect(hashes, hasLength(8));
    });
  });

  group('the default font size', () {
    test('is the body tier, so an unset key scales nothing', () {
      // The whole guarantee of this key: a theme that does not spell it — every
      // theme written before it existed — renders exactly as it did, because
      // TextScaler.linear(1.0) is TextScaler.noScaling.
      const theme = ThemeConfig();
      expect(theme.fontSize, ShellFontSizes.body);
      expect(theme.textScale, 1.0);
      expect(ThemeConfig.fromMap({}).textScale, 1.0);
    });

    test('the scale is the ratio to the body tier', () {
      final theme = ThemeConfig.fromMap({'font_size': 26.0});
      expect(theme.fontSize, 26.0);
      expect(theme.textScale, closeTo(2.0, 1e-9));
    });

    test('a TOML integer coerces rather than falling back', () {
      // `font_size = 16` is what a hand-written theme file looks like.
      expect(ThemeConfig.fromMap({'font_size': 16}).fontSize, 16.0);
    });

    test('a garbled value costs that key alone', () {
      final theme = ThemeConfig.fromMap({
        'font_size': 'large',
        'font': 'Cantarell',
      });
      expect(theme.fontSize, ShellFontSizes.body);
      expect(theme.fontFamily, 'Cantarell');
    });

    test('clamps at both ends rather than laying out nothing', () {
      // Zero lays every string in the shell out as an empty box, and a few
      // hundred leaves one letter on the screen; both are recoverable only by
      // editing the file back, so neither is allowed through.
      expect(ThemeConfig.fromMap({'font_size': 0}).fontSize, 6.0);
      expect(ThemeConfig.fromMap({'font_size': -20.0}).fontSize, 6.0);
      expect(ThemeConfig.fromMap({'font_size': 400.0}).fontSize, 32.0);
    });

    test('NaN and infinity fall back', () {
      expect(ThemeConfig.fromMap({'font_size': double.nan}).fontSize,
          ShellFontSizes.body);
      expect(ThemeConfig.fromMap({'font_size': double.infinity}).fontSize,
          ShellFontSizes.body);
    });

    test('takes part in equality, and round-trips', () {
      const base = ThemeConfig();
      const bigger = ThemeConfig(fontSize: 18.0);
      expect(base, isNot(bigger));
      expect(base.hashCode, isNot(bigger.hashCode));
      expect(ThemeConfig.fromMap(bigger.toMap()), bigger);
      expect(bigger.toMap()['font_size'], 18.0);
    });
  });

  test('the defaults are the geometry the bar has always had', () {
    // Every install that has never opened the theme editor resolves to these,
    // so they are what guarantee this feature changes nothing until asked for.
    const theme = ThemeConfig();
    expect(theme.panelMargin, 0);
    expect(theme.panelRadius, 0.0);
    expect(theme.panelBorderWidth, 0.0);
  });

  test('the popup defaults are the card shape the menus already drew', () {
    // These are not the panel's flush-and-square defaults, and deliberately
    // so. The shell's menus have always been rounded with a hairline rim; a
    // zero default would have made every one of them square the moment they
    // started reading the theme. It is also what a user theme forked before
    // these keys existed resolves to, since its file has none of them.
    const theme = ThemeConfig();
    expect(theme.popupRadius, 8.0);
    expect(theme.popupBorderWidth, 1.0);
    expect(theme.popupBorder, theme.divider);
  });

  group('popup_animation', () {
    test('defaults to the quick slide-and-fade', () {
      // The elastic bounce this replaced was 500ms and had no exit at all, so
      // every popup in the shell blinked out of existence. A theme file
      // written before the key existed resolves to this.
      expect(const ThemeConfig().popupEffect, PopupEffect.slide);
    });

    test('parses a slug and writes it back', () {
      final theme = ThemeConfig.fromMap({'popup_animation': 'flip'});
      expect(theme.popupEffect, PopupEffect.flip);
      expect(theme.toMap()['popup_animation'], 'flip');
    });

    test('a slug this build does not know costs the key, not the theme', () {
      // TomlReader's rule, applied to a closed set: an effect added in a later
      // release must not take down a shell reading the file back.
      final theme = ThemeConfig.fromMap({
        'popup_animation': 'kaleidoscope',
        'popup_radius': 12.0,
      });
      expect(theme.popupEffect, PopupEffect.slide);
      expect(theme.popupRadius, 12.0);
    });

    test('a wrongly-typed value falls back too', () {
      expect(ThemeConfig.fromMap({'popup_animation': 3}).popupEffect,
          PopupEffect.slide);
      expect(ThemeConfig.fromMap({'popup_animation': true}).popupEffect,
          PopupEffect.slide);
    });
  });

  group('popup_animation_duration', () {
    test('defaults to the pace every popup already played', () {
      // The key's whole guarantee, as with font_size: a theme written before it
      // existed animates exactly as it did.
      const theme = ThemeConfig();
      expect(theme.popupInDuration, ShellDurations.popupIn);
      expect(theme.popupOutDuration, ShellDurations.popupOut);
    });

    test('the exit is shorter than the entrance, at any length', () {
      for (final ms in const [40, 140, 600, 2000]) {
        final theme = ThemeConfig.fromMap({'popup_animation_duration': ms});
        expect(theme.popupInDuration.inMilliseconds, ms);
        expect(theme.popupOutDuration, lessThan(theme.popupInDuration),
            reason: 'at ${ms}ms');
      }
    });

    test('a TOML float coerces and a garbled value costs the key alone', () {
      expect(
          ThemeConfig.fromMap({'popup_animation_duration': 240.0})
              .popupAnimationDuration,
          240);
      final theme = ThemeConfig.fromMap({
        'popup_animation_duration': 'quick',
        'popup_radius': 12.0,
      });
      expect(theme.popupAnimationDuration,
          const ThemeConfig().popupAnimationDuration);
      expect(theme.popupRadius, 12.0);
    });

    test('the clamps hold at both ends', () {
      // 0 is a real value — the effect played instantly — so the floor is not
      // an off switch; `popup_animation = "none"` is. The ceiling is a menu the
      // user would be waiting out.
      expect(
          ThemeConfig.fromMap({'popup_animation_duration': -50})
              .popupAnimationDuration,
          0);
      expect(
          ThemeConfig.fromMap({'popup_animation_duration': 99999})
              .popupAnimationDuration,
          2000);
    });
  });

  group('the overlay animation keys', () {
    test('the defaults are the entrance every overlay already played', () {
      // The same guarantee popup_animation_duration makes: a theme file written
      // before these four keys existed renders exactly as it did.
      const theme = ThemeConfig();
      expect(theme.overlayEffect, OverlayEffect.scale);
      expect(theme.overlayCurve, OverlayCurve.easeOut);
      expect(theme.overlayInDuration, ShellDurations.overlayFade);
      expect(theme.overlayExitRatio, 1.0);
      expect(theme.overlayOutDuration, theme.overlayInDuration);
    });

    test('each of the four parses and writes itself back', () {
      final theme = ThemeConfig.fromMap({
        'overlay_animation': 'swing',
        'overlay_animation_duration': 320,
        'overlay_animation_exit_ratio': 0.6,
        'overlay_animation_curve': 'elastic',
      });
      expect(theme.overlayEffect, OverlayEffect.swing);
      expect(theme.overlayAnimationDuration, 320);
      expect(theme.overlayExitRatio, 0.6);
      expect(theme.overlayCurve, OverlayCurve.elastic);

      final map = theme.toMap();
      expect(map['overlay_animation'], 'swing');
      expect(map['overlay_animation_duration'], 320);
      expect(map['overlay_animation_exit_ratio'], 0.6);
      expect(map['overlay_animation_curve'], 'elastic');
      expect(ThemeConfig.fromMap(map), theme, reason: 'round trip');
    });

    test('an unknown slug or a wrong type costs its key, not the theme', () {
      // TomlReader's rule on two closed sets and two numbers at once: an effect
      // or a curve added in a later release must not take down a shell reading
      // the file back.
      final theme = ThemeConfig.fromMap({
        'overlay_animation': 'kaleidoscope',
        'overlay_animation_curve': 'parabolic',
        'overlay_animation_duration': 'brisk',
        'overlay_animation_exit_ratio': true,
        'popup_radius': 12.0,
      });
      const defaults = ThemeConfig();
      expect(theme.overlayEffect, defaults.overlayEffect);
      expect(theme.overlayCurve, defaults.overlayCurve);
      expect(theme.overlayAnimationDuration, defaults.overlayAnimationDuration);
      expect(theme.overlayExitRatio, defaults.overlayExitRatio);
      expect(theme.popupRadius, 12.0);
    });

    test('a TOML float coerces into the duration', () {
      expect(
          ThemeConfig.fromMap({'overlay_animation_duration': 320.0})
              .overlayAnimationDuration,
          320);
    });

    test('the clamps hold at both ends', () {
      // 0 is a real value at both keys — an entrance played instantly, and an
      // exit that is — so neither floor is an off switch; `overlay_animation =
      // "none"` is. The duration's ceiling is wider than a popup's because an
      // overlay is a surface the user asked for rather than one they are
      // already reaching past, and the ratio's is above 1 because an overlay
      // that leaves more slowly than it arrived is a legitimate theme.
      expect(
          ThemeConfig.fromMap({'overlay_animation_duration': -50})
              .overlayAnimationDuration,
          0);
      expect(
          ThemeConfig.fromMap({'overlay_animation_duration': 99999})
              .overlayAnimationDuration,
          4000);
      expect(
          ThemeConfig.fromMap({'overlay_animation_exit_ratio': -1.0})
              .overlayExitRatio,
          0.0);
      expect(
          ThemeConfig.fromMap({'overlay_animation_exit_ratio': 9.0})
              .overlayExitRatio,
          2.0);
    });

    test('the exit follows the entrance through the ratio', () {
      for (final ms in const [40, 160, 600, 4000]) {
        final theme = ThemeConfig.fromMap({
          'overlay_animation_duration': ms,
          'overlay_animation_exit_ratio': 0.5,
        });
        expect(theme.overlayOutDuration.inMilliseconds, (ms * 0.5).round(),
            reason: 'at ${ms}ms');
      }
    });

    test('an overlay key is not a popup key', () {
      // Two surfaces, two decisions: a theme that wants motion in its menus and
      // none in its panels has to be able to say so.
      final theme = ThemeConfig.fromMap({
        'popup_animation': 'none',
        'overlay_animation': 'flip',
        'overlay_animation_duration': 500,
      });
      expect(theme.popupEffect, PopupEffect.none);
      expect(theme.popupAnimationDuration, 140);
      expect(theme.overlayEffect, OverlayEffect.flip);
      expect(theme.overlayAnimationDuration, 500);
    });
  });

  group('the popup shadow', () {
    test('its defaults are the lift the shipped themes draw', () {
      const theme = ThemeConfig();
      expect(theme.popupShadowColor, const Color(0x66000000));
      expect(theme.popupShadowBlur, 16.0);
      expect(theme.popupShadowSpread, 0.0);
      expect(theme.popupShadowOffset, const Offset(0, 6));
    });

    test('a garbled value costs that key alone', () {
      final theme = ThemeConfig.fromMap({
        'popup_shadow_color': 'not a colour',
        'popup_shadow_blur': 'lots',
        'popup_shadow_spread': [1],
        'popup_shadow_offset_x': true,
        'popup_shadow_offset_y': {'a': 1},
        'popup_radius': 12.0,
      });
      const defaults = ThemeConfig();
      expect(theme.popupShadowColor, defaults.popupShadowColor);
      expect(theme.popupShadowBlur, defaults.popupShadowBlur);
      expect(theme.popupShadowSpread, defaults.popupShadowSpread);
      expect(theme.popupShadowOffset, defaults.popupShadowOffset);
      // The one well-formed key still lands.
      expect(theme.popupRadius, 12.0);
    });

    test('blur clamps non-negative, spread and the offsets do not', () {
      // A negative blur is meaningless and would throw inside BoxShadow, but a
      // negative spread shrinks the shape before blurring and a negative offset
      // casts the shadow up or to the left — both are CSS, and both are what a
      // theme author reaches for.
      final theme = ThemeConfig.fromMap({
        'popup_shadow_blur': -4.0,
        'popup_shadow_spread': -2.0,
        'popup_shadow_offset_x': -3.0,
        'popup_shadow_offset_y': -5.0,
      });
      expect(theme.popupShadowBlur, 0.0);
      expect(theme.popupShadowSpread, -2.0);
      expect(theme.popupShadowOffset, const Offset(-3, -5));
    });

    test('the clamps hold at both ends', () {
      final theme = ThemeConfig.fromMap({
        'popup_shadow_blur': 1000.0,
        'popup_shadow_spread': -1000.0,
        'popup_shadow_offset_x': 1000.0,
        'popup_shadow_offset_y': -1000.0,
      });
      expect(theme.popupShadowBlur, 64.0);
      expect(theme.popupShadowSpread, -32.0);
      expect(theme.popupShadowOffset, const Offset(64, -64));
    });

    test('a TOML integer coerces rather than falling back', () {
      // `popup_shadow_blur = 20` is what a hand-written theme file looks like.
      final theme = ThemeConfig.fromMap({'popup_shadow_blur': 20});
      expect(theme.popupShadowBlur, 20.0);
    });

    test('an alpha channel survives the colour round-trip', () {
      final theme = ThemeConfig.fromMap({'popup_shadow_color': '#59102030'});
      expect(theme.popupShadowColor, const Color(0x59102030));
      expect(theme.toMap()['popup_shadow_color'], '#59102030');
    });
  });

  test('the new keys round-trip through toMap', () {
    const theme = ThemeConfig(
      panelMargin: 8,
      panelRadius: 12.0,
      panelBorder: Color(0x40FFFFFF),
      panelBorderWidth: 1.5,
      popupRadius: 10.0,
      popupBorder: Color(0x40FFFFFF),
      popupBorderWidth: 2.0,
      popupShadowColor: Color(0x59000000),
      popupShadowBlur: 28.0,
      popupShadowSpread: -2.0,
      popupShadowOffsetX: -3.0,
      popupShadowOffsetY: 10.0,
    );
    expect(ThemeConfig.fromMap(theme.toMap()), theme);
  });
}
