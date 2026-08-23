import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';

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
        'blur': -10.0,
      });
      expect(theme.panelMargin, 0);
      expect(theme.panelRadius, 0.0);
      expect(theme.panelBorderWidth, 0.0);
      // Clamped, not fallen back: zero is a legitimate popup shape — a square
      // card with no rim — and a negative one is the nearest thing to it.
      expect(theme.popupRadius, 0.0);
      expect(theme.popupBorderWidth, 0.0);
      expect(theme.blur, 0.0);
    });

    test('an absurd value clamps to the ceiling', () {
      final theme = ThemeConfig.fromMap({
        'panel_margin': 100000,
        'panel_radius': 1e9,
        'panel_border_width': 999,
        'popup_radius': 1e9,
        'popup_border_width': 999,
        'blur': 5000.0,
      });
      expect(theme.panelMargin, 256);
      expect(theme.panelRadius, 64.0);
      expect(theme.panelBorderWidth, 16.0);
      expect(theme.popupRadius, 64.0);
      expect(theme.popupBorderWidth, 16.0);
      expect(theme.blur, 100.0);
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
        'blur': double.nan,
      });
      expect(theme.panelMargin, 0);
      expect(theme.panelRadius, 0.0);
      expect(theme.panelBorderWidth, 0.0);
      expect(theme.popupRadius, 8.0);
      expect(theme.popupBorderWidth, 1.0);
      expect(theme.blur, 24.0);
    });

    test('infinity falls back rather than clamping', () {
      // clamp() lets infinity through as the upper bound, which would be a
      // silently absurd value instead of an obviously ignored one.
      final theme = ThemeConfig.fromMap({
        'panel_margin': double.infinity,
        'panel_radius': double.negativeInfinity,
        'popup_radius': double.infinity,
        'popup_border_width': double.negativeInfinity,
        'blur': double.infinity,
      });
      expect(theme.panelMargin, 0);
      expect(theme.panelRadius, 0.0);
      expect(theme.popupRadius, 8.0);
      expect(theme.popupBorderWidth, 1.0);
      expect(theme.blur, 24.0);
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
