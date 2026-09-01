import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/panel_background.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/theme/builtin_themes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The shipped theme [slug], parsed the way the store parses it off disk.
ThemeConfig _shipped(String slug) =>
    ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes[slug]!).toMap());

void main() {
  test('the default theme ships', () {
    expect(kBuiltInThemes.keys, contains(kDefaultThemeName));
  });

  test('every shipped theme parses and names itself', () {
    for (final entry in kBuiltInThemes.entries) {
      final map = TomlDocument.parse(entry.value).toMap();
      expect(map['name'], isA<String>(),
          reason: '${entry.key} needs a display name');
      expect(() => ThemeConfig.fromMap(map), returnsNormally);
    }
  });

  test('every shipped theme spells out every key', () {
    // A shipped theme must not lean on a ThemeConfig default: changing a
    // default would then silently restyle it.
    final expected = {
      ...ThemeConfig.colorKeys,
      'font',
      'font_size',
      'panel_gradient',
      'panel_margin',
      'panel_radius',
      'panel_border_width',
      'popup_radius',
      'popup_gap',
      'popup_attach_radius',
      'popup_border_width',
      'popup_shadow_blur',
      'popup_shadow_spread',
      'popup_shadow_offset_x',
      'popup_shadow_offset_y',
    };
    for (final entry in kBuiltInThemes.entries) {
      final map = TomlDocument.parse(entry.value).toMap();
      expect(map.keys, containsAll(expected), reason: 'in ${entry.key}');
    }
  });

  test('graceful reproduces the palette that used to be the default', () {
    final graceful =
        ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes['graceful']!).toMap());
    // Every colour matches the ThemeConfig defaults, so seeding the themes
    // directory cannot change how an existing install looks.
    const defaults = ThemeConfig();
    expect(graceful, defaults);
  });

  test('a shipped theme that keeps the gradient is opaque enough to read', () {
    // Nothing forces a bar to be translucent, but a gradient one puts the
    // accent against the screen edge — so a theme either commits to the fade
    // or turns it off, which is the choice glassy makes.
    for (final entry in kBuiltInThemes.entries) {
      final theme =
          ThemeConfig.fromMap(TomlDocument.parse(entry.value).toMap());
      if (!theme.panelGradient) continue;
      expect(theme.panelBackground.a, greaterThan(0.5), reason: 'in ${entry.key}');
    }
  });

  test('the flush themes keep the geometry the bar always had', () {
    // graceful is pinned to the ThemeConfig defaults by the test above, but
    // dracula is not — and neither should have moved off the screen edge.
    for (final slug in const ['graceful', 'dracula']) {
      final theme =
          ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes[slug]!).toMap());
      expect(theme.panelMargin, 0, reason: 'in $slug');
      expect(theme.panelRadius, 0.0, reason: 'in $slug');
      expect(theme.panelBorderWidth, 0.0, reason: 'in $slug');
    }
  });

  test('glassy floats, rounds, and has a visible rim', () {
    // The theme this feature exists for: alpha alone made the bar see-through,
    // but it still read as a strip of tint rather than a pane of glass.
    final glassy =
        ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes['glassy']!).toMap());
    expect(glassy.panelMargin, greaterThan(0));
    expect(glassy.panelRadius, greaterThan(0));
    expect(glassy.panelBorderWidth, greaterThan(0));
    expect(glassy.panelBorder.a, greaterThan(0),
        reason: 'a rim with a transparent colour draws nothing');
    // Floating means all four corners round.
    expect(panelCornerRadius(theme: glassy),
        BorderRadius.circular(glassy.panelRadius));
  });

  test('glassy popups are made of the same material as its bar', () {
    // The reported bug: glassy's bar was rounded and rimmed while its popups
    // were flat rectangles. A menu should read as a pane dropped out of the
    // pane it came from, so the two shapes are pinned to each other.
    final glassy =
        ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes['glassy']!).toMap());
    expect(glassy.popupRadius, glassy.panelRadius);
    expect(glassy.popupBorder, glassy.panelBorder);
    expect(glassy.popupBorderWidth, greaterThan(0));
    expect(glassy.popupBorder.a, greaterThan(0),
        reason: 'a rim with a transparent colour draws nothing');
  });

  test('forest floats on a lit rim, and spends its hue once', () {
    final forest =
        ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes['forest']!).toMap());
    // Like glassy it floats — but for the opposite reason. Glassy needs a rim
    // because a translucent bar has no edge of its own; this one is nearly
    // opaque and the rim is the picture, so it has to be visible on both the
    // bar and the cards, and the two have to be the same rim.
    expect(forest.panelMargin, greaterThan(0));
    expect(forest.panelRadius, greaterThan(0));
    expect(forest.panelBorderWidth, greaterThan(0));
    expect(forest.panelBorder.a, greaterThan(0),
        reason: 'a rim with a transparent colour draws nothing');
    expect(forest.popupBorder, forest.panelBorder);
    expect(forest.popupRadius, forest.panelRadius);
    // Floating means all four corners round.
    expect(panelCornerRadius(theme: forest),
        BorderRadius.circular(forest.panelRadius));

    // The single-hue rule: every surface is green, and the accent is the only
    // *saturated* one. `muted` reusing the accent — which is what graceful
    // does — would put the theme's one vivid green on its least important
    // text, so it is pinned apart from it.
    for (final surface in [
      forest.workspaceBackground,
      forest.popupBackground,
      forest.controlSurface,
      forest.surfaceHover,
      forest.surfacePressed,
    ]) {
      expect(surface.g, greaterThan(surface.r), reason: 'a forest surface');
      expect(surface.g, greaterThan(surface.b), reason: 'a forest surface');
    }
    expect(forest.muted, isNot(forest.accent));
  });

  test('carbon is flat: no fade, no lift, and no shadow at all', () {
    final carbon = _shipped('carbon');
    // Flat is the whole brief, and it is spelled on every key that could
    // contradict it — including the one no other shipped theme touches.
    expect(carbon.panelGradient, isFalse);
    expect(carbon.panelBackground.a, 1.0,
        reason: 'a translucent bar lets the wallpaper decide what colour the '
            'flattest surface in the theme is');
    expect(carbon.panelMargin, 0);
    expect(carbon.panelRadius, 0.0);
    // popup_shadow_color's alpha is the documented off switch, and switching
    // it off has to give back the geometry of a shell built before shadows
    // existed: an off shadow that still grew every popup's window would be
    // the margin without the paint.
    expect(popupShadow(carbon), isNull);
    expect(popupShadowInsets(carbon), EdgeInsets.zero);
  });

  test('carbon spends its one piece of shaping on the join', () {
    final carbon = _shipped('carbon');
    expect(carbon.popupGap, 0.0,
        reason: 'the flare is unread at any gap above zero');
    expect(carbon.popupAttachRadius, greaterThan(0));

    // Attached: the two corners on the join square off and only the far pair
    // take popup_radius.
    final r = Radius.circular(carbon.popupRadius);
    expect(popupCornerRadius(carbon, attach: 'top'),
        BorderRadius.only(bottomLeft: r, bottomRight: r));

    // The flare paints outside the card, so the popup's own surface has to
    // carry it — and with no shadow to take the larger of, it carries the flare
    // and nothing else: the two sides that meet the join, and nothing past the
    // join itself, which is what leaves the surface flush with the bar.
    final attach = popupAttachInsets(carbon, attachEdge: 'top');
    expect(
        attach,
        EdgeInsets.symmetric(horizontal: carbon.popupAttachRadius));
    expect(
        popupSurfaceInsets(
            popupShadowInsets(carbon, attachEdge: 'top'), attach),
        attach);
  });

  test('carbon rims its bar everywhere but the edge its menus come out of',
      () {
    final carbon = _shipped('carbon');
    // The bar is rimmed, and the one edge it leaves open is the inner one — the
    // edge every attached card is joined to. That line is on the panel's own
    // surface, so nothing the card draws can take it out; the bar has to
    // decline to draw it, which it can, because attaching is a property of the
    // theme rather than of any popup that happens to be open.
    expect(carbon.panelBorderWidth, greaterThan(0));
    expect(carbon.popupGap, 0.0);
    for (final anchor in ['top', 'bottom', 'left', 'right']) {
      final border =
          panelBackgroundDecoration(anchor: anchor, theme: carbon).border!
              as Border;
      final inner = switch (anchor) {
        'top' => border.bottom,
        'bottom' => border.top,
        'left' => border.right,
        _ => border.left,
      };
      expect(inner.style, BorderStyle.none, reason: anchor);
      // And exactly that one side: the other three are against the screen edge
      // and still carry the rim the theme asked for.
      expect(
          [border.top, border.bottom, border.left, border.right]
              .where((s) => s.style == BorderStyle.none),
          hasLength(1),
          reason: anchor);
    }

    // One line, of one colour and one width, so it cannot step where the bar's
    // outline breaks off and the card's picks up.
    expect(carbon.panelBorder, carbon.popupBorder);
    expect(carbon.panelBorderWidth, carbon.popupBorderWidth);
    expect(carbon.panelBorder.a, greaterThan(0),
        reason: 'a rim with a transparent colour draws nothing');
  });

  test('carbon draws its popups out of the same graphite as its bar', () {
    final carbon = _shipped('carbon');
    // The join carries this theme, and a colour step across it is the one
    // thing that would still read as two surfaces meeting after the gap, the
    // shadow and the rim have all been taken away. panelBackgroundDecoration
    // paints panel_background verbatim under panel_gradient = false, so the
    // fill either side of the join is this one value.
    expect(carbon.popupBackground, carbon.panelBackground,
        reason: 'a card that grows out of the bar is made of the bar');
    expect(carbon.panelGradient, isFalse,
        reason: 'a fade would step across the join the flare exists to erase');
    expect(carbon.popupBackground.a, 1.0,
        reason: 'a translucent card would let the wallpaper decide which half '
            'of the join is which');
    // With no step in the fill, the rim is the only thing drawing the flare's
    // sweep — so it has to be distinguishable from both surfaces it separates.
    expect(carbon.popupBorderWidth, greaterThan(0));
    expect(carbon.popupBorder, isNot(carbon.popupBackground));
    // And a control still has to lift off the card it sits on, which it now
    // does by two of Carbon's steps rather than one.
    expect(carbon.controlSurface, isNot(carbon.popupBackground));
  });

  test('no shipped theme puts a line across the mouth of its own menus', () {
    // The one seam attaching exists to remove, checked over every shipped
    // theme rather than over carbon alone: an attached bar (popup_gap = 0)
    // leaves its inner edge unrimmed whatever its flare, so there is nothing
    // between it and the card it opens. A theme with a gap has genuinely
    // floating cards and keeps all four sides.
    for (final slug in kBuiltInThemes.keys) {
      final theme = _shipped(slug);
      for (final anchor in const ['top', 'bottom', 'left', 'right']) {
        final border =
            panelBackgroundDecoration(anchor: anchor, theme: theme).border
                as Border?;
        if (border == null) continue; // panel_border_width = 0: no rim at all.
        final inner = switch (anchor) {
          'top' => border.bottom,
          'bottom' => border.top,
          'left' => border.right,
          _ => border.left,
        };
        expect(
            inner.style,
            theme.popupGap > 0 ? BorderStyle.solid : BorderStyle.none,
            reason: '$slug on a $anchor bar');
      }
    }
  });

  test('midnight glows rather than casting a shadow', () {
    final midnight = _shipped('midnight');
    final glow = popupShadow(midnight)!;
    // Three things separate a bloom from a shadow, and this theme is the only
    // shipped one that does any of them.
    expect(glow.offset, Offset.zero,
        reason: 'a glow surrounds the card; a shadow falls away from it');
    expect(glow.spreadRadius, greaterThan(0));
    expect(glow.color.b, greaterThan(glow.color.r));
    expect(glow.color.b, greaterThan(glow.color.g),
        reason: 'the glow takes the accent hue, not a neutral black');

    // Zero offset is a geometric statement as much as a visual one: the shell
    // grows a floating popup's window by the shadow's reach per side, and with
    // no displacement all four sides come out equal.
    final insets = popupShadowInsets(midnight);
    expect(insets.left, insets.right);
    expect(insets.top, insets.bottom);
    expect(insets.top, insets.left);

    for (final slug in kBuiltInThemes.keys) {
      if (slug == 'midnight') continue;
      expect(popupShadow(_shipped(slug))?.spreadRadius ?? 0.0,
          lessThanOrEqualTo(0.0),
          reason: 'in $slug');
    }
  });

  test('midnight treats the type scale as part of the palette', () {
    // font_size is the body tier and every other size in the shell is a fixed
    // ratio to it, so this is the whole shell set one rung up rather than a
    // larger label here and there. It is also the only shipped theme that
    // moves the scale at all, which makes it the only one pinning that a
    // theme *can*.
    final midnight = _shipped('midnight');
    expect(midnight.fontSize, greaterThan(ShellFontSizes.body));
    expect(midnight.textScale, greaterThan(1.0));
    for (final slug in kBuiltInThemes.keys) {
      if (slug == 'midnight') continue;
      expect(_shipped(slug).textScale, 1.0, reason: 'in $slug');
    }
  });

  test('midnight floats, and its popups are made of the bar', () {
    // glassy's and forest's rule: a bar lifted off the screen edge cannot open
    // a menu glued to it, and a menu should read as a pane dropped out of the
    // pane it came from — same gap, same corner, same rim, same weight of rim.
    final midnight = _shipped('midnight');
    expect(midnight.panelMargin, greaterThan(0));
    expect(midnight.popupGap, midnight.panelMargin.toDouble());
    expect(midnight.popupRadius, midnight.panelRadius);
    expect(midnight.popupBorder, midnight.panelBorder);
    expect(midnight.popupBorderWidth, midnight.panelBorderWidth);
    expect(midnight.panelBorderWidth, greaterThan(1.0),
        reason: 'a hairline thins out visibly around a corner this round');
    expect(midnight.panelBorder.a, greaterThan(0),
        reason: 'a rim with a transparent colour draws nothing');
    // Floating means all four corners round.
    expect(panelCornerRadius(theme: midnight),
        BorderRadius.circular(midnight.panelRadius));
  });

  test('every shipped theme gives its popups a shape', () {
    // A shipped theme may turn its bar's rounding off — graceful and dracula
    // both do — but a popup has no screen edge to sit flush against, so a
    // square shipped card would only ever be an oversight.
    for (final entry in kBuiltInThemes.entries) {
      final theme =
          ThemeConfig.fromMap(TomlDocument.parse(entry.value).toMap());
      expect(theme.popupRadius, greaterThan(0), reason: 'in ${entry.key}');
      expect(theme.popupBorderWidth, greaterThan(0), reason: 'in ${entry.key}');
      expect(theme.popupBorder.a, greaterThan(0), reason: 'in ${entry.key}');
    }
  });

  test('toMap round-trips through TOML unchanged', () {
    for (final entry in kBuiltInThemes.entries) {
      final parsed =
          ThemeConfig.fromMap(TomlDocument.parse(entry.value).toMap());
      final written = TomlDocument.fromMap(parsed.toMap()).toString();
      expect(ThemeConfig.fromMap(TomlDocument.parse(written).toMap()), parsed,
          reason: '${entry.key} did not survive a save/load cycle');
    }
  });
}
