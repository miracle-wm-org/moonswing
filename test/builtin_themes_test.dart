import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/panel_background.dart';
import 'package:moonswing/panel_rim.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/theme/builtin_themes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The shipped theme [slug], parsed the way the store parses it off disk.
ThemeConfig _shipped(String slug) =>
    ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes[slug]!).toMap());

/// The WCAG contrast ratio between two colours, spelled out here rather than
/// reached for in the library: a test that measured contrast with the same
/// expression the code does could only ever agree with itself.
double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}

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
      'popup_animation_duration',
      'overlay_animation',
      'overlay_animation_duration',
      'overlay_animation_exit_ratio',
      'overlay_animation_curve',
    };
    for (final entry in kBuiltInThemes.entries) {
      final map = TomlDocument.parse(entry.value).toMap();
      expect(map.keys, containsAll(expected), reason: 'in ${entry.key}');
    }
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
    // Dracula is a flat palette and should never have moved off the screen
    // edge.
    for (final slug in const ['dracula']) {
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
    // *saturated* one. `muted` reusing the accent — which is what moonswing
    // used to do, at 1.8:1 on its own card — would put the theme's one vivid
    // green on its least important text, so it is pinned apart from it.
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
    expect(attach,
        EdgeInsets.symmetric(horizontal: carbon.popupAttachRadius));
    expect(
        popupSurfaceInsets(
            popupShadowInsets(carbon, attachEdge: 'top'), attach),
        attach);
  });

  test('carbon runs one rim off the bar and round its menus', () {
    final carbon = _shipped('carbon');
    // The bar is rimmed, and a panel's rim is drawn along its *inner* edge too
    // — the edge every menu comes out of — so the card has to cover that band
    // or the theme's one line runs straight across the mouth of every popup.
    expect(carbon.panelBorderWidth, greaterThan(0));
    expect(carbon.popupGap, 0.0);

    // One line, so it cannot step where the bar's outline hands over to the
    // card's: equal widths lay the card's stroke over the very band the bar's
    // rim occupies.
    expect(carbon.panelBorder, carbon.popupBorder);
    expect(carbon.panelBorderWidth, carbon.popupBorderWidth);
    expect(carbon.panelBorder.a, greaterThan(0),
        reason: 'a rim with a transparent colour draws nothing');

    // And the covering is the *bar's* job, not the card's: the compositor
    // places the popup below the panel, so the panel paints its own rim and
    // leaves out the stretch the mouth covers. The card's surface margin is
    // therefore the flare's alone.
    expect(panelPaintsOwnRim(carbon), isTrue);
    expect(popupAttachInsets(carbon, attachEdge: 'top').top, 0.0,
        reason: 'the card reaches nowhere near the bar');
    expect(
        panelBackgroundDecoration(anchor: 'top', theme: carbon, includeRim: false)
            .border,
        isNull,
        reason: 'the decoration leaves the rim to the painter');
  });

  test('carbon draws its popups out of the same graphite as its bar', () {
    final carbon = _shipped('carbon');
    // The join carries this theme, and a colour step across it is the one thing
    // that would still read as two surfaces meeting after the gap, the shadow and
    // the rim have all been taken away. panelBackgroundDecoration paints
    // panel_background verbatim under panel_gradient = false.
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

  test('a shipped theme rims its bar only if its join can carry the line', () {
    // panel_border_width above zero draws the bar's rim along its *inner* edge
    // too, which is the edge an attached popup meets. A *flared* join takes that
    // over: the card reaches one rim-width into the panel and the arcs carry the
    // line down the card. A square butt join has nothing to carry it with, so for
    // those the two keys are still a pair — which is where moonswing and dracula
    // sit.
    for (final slug in kBuiltInThemes.keys) {
      final theme = _shipped(slug);
      if (theme.popupGap > 0 || theme.popupAttachRadius > 0) continue;
      expect(theme.panelBorderWidth, 0.0, reason: 'in $slug');
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
    // font_size is the body tier and every other size is a fixed ratio to it, so
    // this is the whole shell set one rung up rather than a larger label here and
    // there. It is also the only shipped theme that moves the scale at all, which
    // makes it the only one pinning that a theme *can*.
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
    // A shipped theme may turn its bar's rounding off — moonswing and dracula
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

  test('every shipped theme can be read on its own popup', () {
    // The reported bug, pinned for every shipped theme. One palette's `muted`
    // was its accent verbatim — a fill colour, chosen dark enough to carry
    // white — which put every menu header, timestamp, unit and greyed row on
    // its own card at 1.8:1. A popup is where the shell does its reading, so
    // the three colours it reads in are held to a floor here rather than to an
    // eye.
    for (final slug in kBuiltInThemes.keys) {
      final theme = _shipped(slug);
      expect(_contrast(theme.popupForeground, theme.popupBackground),
          greaterThanOrEqualTo(kTextContrast),
          reason: 'popup_foreground in $slug');
      expect(_contrast(theme.accentText, theme.popupBackground),
          greaterThanOrEqualTo(kTextContrast),
          reason: 'accentText in $slug');
      // Secondary text is held to the large-text floor rather than AA's body
      // ratio. It is the tier that is *meant* to recede, and dracula's `muted`
      // is Dracula's own comment colour — authentic to the palette it is taken
      // from, and a shade the theme would not be itself without. What the floor
      // rules out is the tier vanishing altogether, which is where moonswing had
      // it.
      expect(_contrast(theme.muted, theme.popupBackground),
          greaterThanOrEqualTo(3.0),
          reason: 'muted in $slug');
      expect(theme.muted, isNot(theme.accent),
          reason: 'secondary text in $slug is a fill colour');
    }
  });

  test('accentText lifts an accent only as far as reading it needs', () {
    // The accent stays the accent: whatever a theme fills with is what gets
    // filled, and only the *writing* moves.
    for (final slug in kBuiltInThemes.keys) {
      final theme = _shipped(slug);
      final reads =
          _contrast(theme.accent, theme.popupBackground) >= kTextContrast;
      expect(theme.accentText == theme.accent, reads,
          reason: 'an accent that already reads is handed back untouched, and '
              'one that does not is not — in $slug');
    }

    // moonswing is the case this exists for, and the one that cannot be fixed
    // by choosing a better accent: nothing that holds kOnAccent's white on a
    // button also clears 4.5:1 as text on a #2C2C2C card.
    const moonswing = ThemeConfig();
    expect(_contrast(moonswing.accent, moonswing.popupBackground), lessThan(2.0));
    expect(_contrast(moonswing.accentText, moonswing.popupBackground),
        greaterThanOrEqualTo(kTextContrast));
    // The same colour read louder, not a different one: hue and saturation are
    // held, so a maroon theme is still lettered in maroon.
    final accent = HSLColor.fromColor(moonswing.accent);
    final lifted = HSLColor.fromColor(moonswing.accentText);
    expect(lifted.hue, closeTo(accent.hue, 1.0));
    expect(lifted.saturation, closeTo(accent.saturation, 0.01));
    expect(lifted.lightness, greaterThan(accent.lightness));
  });

  test('accentText darkens instead when the card is a pale one', () {
    // No shipped theme is light, and the day somebody writes one the rule has
    // to still be "away from the surface" rather than "upwards".
    const pale = ThemeConfig(
      accent: Color(0xFFFFE08A),
      popupBackground: Color(0xFFFAFAFA),
    );
    expect(_contrast(pale.accent, pale.popupBackground),
        lessThan(kTextContrast));
    expect(_contrast(pale.accentText, pale.popupBackground),
        greaterThanOrEqualTo(kTextContrast));
    expect(HSLColor.fromColor(pale.accentText).lightness,
        lessThan(HSLColor.fromColor(pale.accent).lightness));
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
