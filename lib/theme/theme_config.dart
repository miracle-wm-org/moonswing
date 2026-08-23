/// The resolved palette — [ThemeConfig] — and the key table that drives its
/// parsing, serialization, and equality.
library;

import 'dart:ui';

import 'package:graceful_shell/config_reader.dart';

/// The theme selected when `config.toml` names none, and the one every
/// failure path falls back to. Matches `lib/theme/builtin_themes.dart`.
const String kDefaultThemeName = 'graceful';

/// How a theme key parses and encodes.
///
/// [color] goes through [ThemeConfig.formatColor] and its inverse; [number]
/// is a clamped double; [integer] is read as a double and rounded, so a TOML
/// float coerces rather than falling back; [flag] and [text] are verbatim.
enum _ThemeKeyKind { color, number, integer, flag, text }

/// One TOML theme key: its spelling, its kind, its clamp range, and where it
/// lives on a [ThemeConfig].
///
/// [ThemeConfig._keys] is the single place a key is described. `fromMap`'s
/// parse rules (kind, clamps, and the default — read off `const ThemeConfig()`
/// through [get]), `toMap`, [ThemeConfig.colorKeys], `==` and `hashCode` are
/// all derived from that table, so adding a key means declaring the field,
/// giving the constructor its default, adding one row to the table, and
/// linking key to constructor parameter in `fromMap`. A key cannot be
/// *partially* added: the built-in themes' lossless round-trip test fails on
/// any row `fromMap` forgets, and `fromMap` throws in any test on a key the
/// table does not carry.
class _ThemeKey {
  const _ThemeKey(this.key, this.kind, this.get, {this.min, this.max});

  final String key;
  final _ThemeKeyKind kind;

  /// Reads this key's field off a theme. Doubles as the source of the per-key
  /// default — `get(const ThemeConfig())` — so defaults are spelled once, in
  /// the constructor.
  final Object Function(ThemeConfig) get;

  /// Clamp range for the numeric kinds; see [ThemeConfig.fromMap] for why
  /// every number is clamped.
  final double? min;
  final double? max;

  /// Parses this key out of [map] with the TomlReader discipline: a
  /// wrongly-typed value costs this one key, never the theme.
  Object parse(Map<String, dynamic> map, Object fallback) {
    switch (kind) {
      case _ThemeKeyKind.color:
        return ThemeConfig._parseColor(
            map.stringOrNull(key), fallback as Color);
      case _ThemeKeyKind.number:
        return map.doubleOr(key, fallback as double, min: min, max: max);
      case _ThemeKeyKind.integer:
        // Via doubleOr so a TOML float coerces; NaN and the infinities fall
        // back inside it, which is what keeps `.round()` from throwing.
        return map
            .doubleOr(key, (fallback as int).toDouble(), min: min, max: max)
            .round();
      case _ThemeKeyKind.flag:
        return map.boolOr(key, fallback as bool);
      case _ThemeKeyKind.text:
        return map.stringOrNull(key) ?? fallback;
    }
  }

  /// The value as [ThemeConfig.toMap] writes it.
  Object encode(ThemeConfig theme) {
    final value = get(theme);
    return kind == _ThemeKeyKind.color
        ? ThemeConfig.formatColor(value as Color)
        : value;
  }
}

/// A resolved palette.
///
/// Themes are no longer part of `config.toml` — each one is its own file under
/// `~/.config/graceful-shell/themes/` and `config.toml` names the active one.
/// The file *is* this table, flat, so [fromMap] parses a whole theme document.
/// See `lib/theme/theme_store.dart`.
class ThemeConfig {
  final Color foreground;
  final Color accent;
  final Color surfaceHover;
  final Color surfacePressed;
  final Color workspaceBackground;
  final Color popupBackground;
  final Color popupForeground;
  final Color controlSurface;
  final Color sliderTrack;
  final Color muted;
  final Color divider;

  /// The bar's own background.
  ///
  /// The one surface that had no colour of its own — the panel used to be
  /// painted from [workspaceBackground] at a hardcoded 93% opacity, so a
  /// translucent theme could not see through the very surface that sits on top
  /// of the desktop. Its alpha is honoured verbatim, and it also sets the
  /// opacity of the whole bar: see [panelGradient].
  final Color panelBackground;

  /// Whether the bar fades from [accent] across to [panelBackground].
  ///
  /// A theme that wants a plain sheet of glass sets this false and gets a flat
  /// [panelBackground]. When true the gradient's stops all take their alpha
  /// from [panelBackground], so the bar has exactly one opacity and cannot
  /// band partway across.
  final bool panelGradient;

  /// How far each bar floats off the screen edges it is anchored to.
  ///
  /// This is a *native* `gtk_layer_set_margin` applied in `main.dart`, never a
  /// Flutter `Padding`: the shell has no input-region support, so an inset
  /// inside a full-size surface would swallow every click in the gap instead of
  /// letting it reach the desktop.
  ///
  /// The exclusive zone is deliberately left at the panel's thickness. Per
  /// wlr-layer-shell's `set_margin`, "the exclusive zone includes the margin",
  /// so the compositor already keeps windows out of the gap; reserving
  /// `height + margin` ourselves would reserve it twice.
  final int panelMargin;

  /// The bar's corner rounding.
  ///
  /// A floating bar ([panelMargin] > 0) rounds all four corners. A flush one
  /// rounds only the two corners facing the screen's interior, because
  /// rounding the pair against the screen edge cuts wallpaper wedges out of
  /// the display's own corners.
  final double panelRadius;

  /// The colour of the bar's rim. Only drawn when [panelBorderWidth] > 0.
  final Color panelBorder;

  /// The bar's rim thickness, or 0 for no rim.
  ///
  /// Width, not alpha, is the off switch: at 0 no `Border` is built at all, so
  /// the default decoration stays exactly what it was before rims existed.
  final double panelBorderWidth;

  /// A popup card's corner rounding.
  ///
  /// Unlike [panelRadius] this rounds all four corners unconditionally. The
  /// pair a flush bar spares are the ones against the screen edge, where
  /// rounding would cut wallpaper wedges out of the display's own corners; a
  /// popup floats over a transparent surface with nothing behind it to cut
  /// into, so it has no such pair.
  final double popupRadius;

  /// The colour of a popup card's rim. Only drawn when [popupBorderWidth] > 0.
  final Color popupBorder;

  /// A popup card's rim thickness, or 0 for no rim.
  ///
  /// Width, not alpha, is the off switch, for the same reason as
  /// [panelBorderWidth]: at 0 no `Border` is built at all, and a `Border` in a
  /// decoration carries a [BoxDecoration.padding] that a `Container` silently
  /// adds to its child's.
  final double popupBorderWidth;

  /// The colour of a popup card's shadow.
  ///
  /// Alpha *is* the off switch here, unlike [popupBorderWidth]: a shadow
  /// carries no [BoxDecoration.padding] for a `Container` to silently apply,
  /// so there is nothing a zero-alpha shadow can shift. At alpha 0 — or with
  /// [popupShadowBlur], [popupShadowSpread] and both offsets at 0 —
  /// `popupDecoration` builds no `boxShadow` at all.
  final Color popupShadowColor;

  /// The shadow's blur radius, in the CSS sense: the distance the falloff
  /// reaches past the card's edge.
  ///
  /// Flutter's [BoxShadow.blurRadius] maps to a sigma the same way CSS does,
  /// so this doubles as the extent `popupShadowInsets` grows the popup's own
  /// window by. See `lib/popup_surface.dart`.
  final double popupShadowBlur;

  /// How far the shadow's shape is grown (or, negative, shrunk) before it is
  /// blurred. CSS's third length.
  final double popupShadowSpread;

  /// The shadow's horizontal displacement. Positive is right.
  final double popupShadowOffsetX;

  /// The shadow's vertical displacement. Positive is down.
  final double popupShadowOffsetY;

  /// [popupShadowOffsetX] and [popupShadowOffsetY] as one offset.
  ///
  /// The two are separate fields because a [_ThemeKey] maps one TOML scalar to
  /// one accessor; this is what every painter actually wants.
  Offset get popupShadowOffset =>
      Offset(popupShadowOffsetX, popupShadowOffsetY);

  /// The wash painted over the screen behind a full-screen overlay (the
  /// settings panel, the launcher card).
  final Color scrim;

  /// Gaussian sigma for the overlay backdrops, or 0 to skip the filter.
  ///
  /// This blurs what *Flutter* has composited behind the filter, not the
  /// desktop: a layer-shell surface is transparent and the compositor owns
  /// everything under it, and Mir exposes no blur protocol. Translucency over
  /// the desktop comes from alpha in the colours above.
  final double blur;

  final String fontFamily;

  const ThemeConfig({
    this.foreground = const Color(0xFFF3F4F4),
    this.accent = const Color(0xFF853953),
    this.surfaceHover = const Color(0xFF853953),
    this.surfacePressed = const Color(0xFF612D53),
    this.workspaceBackground = const Color(0xFF2C2C2C),
    this.popupBackground = const Color(0xFF2C2C2C),
    this.popupForeground = const Color(0xFFF3F4F4),
    this.controlSurface = const Color(0xFF39393D),
    this.sliderTrack = const Color(0xFF612D53),
    this.muted = const Color(0xFF853953),
    this.divider = const Color(0x33F3F4F4),
    this.panelBackground = const Color(0xEE2C2C2C),
    this.panelGradient = true,
    this.panelMargin = 0,
    this.panelRadius = 0.0,
    this.panelBorder = const Color(0x33F3F4F4),
    this.panelBorderWidth = 0.0,
    this.popupRadius = 8.0,
    this.popupBorder = const Color(0x33F3F4F4),
    this.popupBorderWidth = 1.0,
    this.popupShadowColor = const Color(0x66000000),
    this.popupShadowBlur = 16.0,
    this.popupShadowSpread = 0.0,
    this.popupShadowOffsetX = 0.0,
    this.popupShadowOffsetY = 6.0,
    this.scrim = const Color(0x882C2C2C),
    this.blur = 24.0,
    this.fontFamily = 'Ubuntu Sans',
  });

  /// Every theme key, in the order [toMap] writes them; the colour
  /// subsequence is the order the settings editor lists ([colorKeys]).
  ///
  /// `static final` rather than `const` only because each row carries a field
  /// accessor and a function literal is not a constant expression; the list is
  /// built once and never mutated.
  static final List<_ThemeKey> _keys = [
    _ThemeKey('font', _ThemeKeyKind.text, (t) => t.fontFamily),
    _ThemeKey('blur', _ThemeKeyKind.number, (t) => t.blur,
        min: 0.0, max: 100.0),
    _ThemeKey('accent', _ThemeKeyKind.color, (t) => t.accent),
    _ThemeKey('foreground', _ThemeKeyKind.color, (t) => t.foreground),
    _ThemeKey('surface_hover', _ThemeKeyKind.color, (t) => t.surfaceHover),
    _ThemeKey('surface_pressed', _ThemeKeyKind.color, (t) => t.surfacePressed),
    _ThemeKey(
        'workspace_background', _ThemeKeyKind.color, (t) => t.workspaceBackground),
    _ThemeKey('popup_background', _ThemeKeyKind.color, (t) => t.popupBackground),
    _ThemeKey('popup_foreground', _ThemeKeyKind.color, (t) => t.popupForeground),
    _ThemeKey('control_surface', _ThemeKeyKind.color, (t) => t.controlSurface),
    _ThemeKey('slider_track', _ThemeKeyKind.color, (t) => t.sliderTrack),
    _ThemeKey('muted', _ThemeKeyKind.color, (t) => t.muted),
    _ThemeKey('divider', _ThemeKeyKind.color, (t) => t.divider),
    _ThemeKey('panel_background', _ThemeKeyKind.color, (t) => t.panelBackground),
    _ThemeKey('panel_gradient', _ThemeKeyKind.flag, (t) => t.panelGradient),
    _ThemeKey('panel_margin', _ThemeKeyKind.integer, (t) => t.panelMargin,
        min: 0.0, max: 256.0),
    _ThemeKey('panel_radius', _ThemeKeyKind.number, (t) => t.panelRadius,
        min: 0.0, max: 64.0),
    _ThemeKey('panel_border', _ThemeKeyKind.color, (t) => t.panelBorder),
    _ThemeKey(
        'panel_border_width', _ThemeKeyKind.number, (t) => t.panelBorderWidth,
        min: 0.0, max: 16.0),
    _ThemeKey('popup_radius', _ThemeKeyKind.number, (t) => t.popupRadius,
        min: 0.0, max: 64.0),
    _ThemeKey('popup_border', _ThemeKeyKind.color, (t) => t.popupBorder),
    _ThemeKey(
        'popup_border_width', _ThemeKeyKind.number, (t) => t.popupBorderWidth,
        min: 0.0, max: 16.0),
    _ThemeKey(
        'popup_shadow_color', _ThemeKeyKind.color, (t) => t.popupShadowColor),
    _ThemeKey('popup_shadow_blur', _ThemeKeyKind.number, (t) => t.popupShadowBlur,
        min: 0.0, max: 64.0),
    // Spread and the offsets take negative floors: CSS allows a shadow that is
    // shrunk before blurring, and one cast upward or to the left.
    _ThemeKey(
        'popup_shadow_spread', _ThemeKeyKind.number, (t) => t.popupShadowSpread,
        min: -32.0, max: 32.0),
    _ThemeKey('popup_shadow_offset_x', _ThemeKeyKind.number,
        (t) => t.popupShadowOffsetX,
        min: -64.0, max: 64.0),
    _ThemeKey('popup_shadow_offset_y', _ThemeKeyKind.number,
        (t) => t.popupShadowOffsetY,
        min: -64.0, max: 64.0),
    _ThemeKey('scrim', _ThemeKeyKind.color, (t) => t.scrim),
  ];

  static Color _parseColor(String? hex, Color fallback) {
    if (hex == null) return fallback;
    final s = hex.startsWith('#') ? hex.substring(1) : hex;
    final value = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
    return value != null ? Color(value) : fallback;
  }

  /// Renders [color] the way theme files spell it: `#RRGGBB` when opaque,
  /// `#AARRGGBB` otherwise. The inverse of [_parseColor].
  static String formatColor(Color color) {
    String hex(double c) =>
        (c * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final rgb = '${hex(color.r)}${hex(color.g)}${hex(color.b)}'.toUpperCase();
    if (color.a >= 1.0) return '#$rgb';
    return '#${hex(color.a).toUpperCase()}$rgb';
  }

  factory ThemeConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ThemeConfig();
    // A theme file is hand-editable, so every read goes through TomlReader —
    // a wrongly-typed value costs that one key, not the theme — and every
    // number is clamped into a range that cannot crash a painter. Kind, clamp
    // and default all come from [_keys]; the constructor call below only links
    // each TOML key to its named parameter, which Dart cannot do dynamically.
    const defaults = ThemeConfig();
    final parsed = <String, Object>{
      for (final k in _keys) k.key: k.parse(map, k.get(defaults)),
    };
    T v<T>(String key) => parsed[key] as T;

    return ThemeConfig(
      fontFamily: v('font'),
      blur: v('blur'),
      accent: v('accent'),
      foreground: v('foreground'),
      surfaceHover: v('surface_hover'),
      surfacePressed: v('surface_pressed'),
      workspaceBackground: v('workspace_background'),
      popupBackground: v('popup_background'),
      popupForeground: v('popup_foreground'),
      controlSurface: v('control_surface'),
      sliderTrack: v('slider_track'),
      muted: v('muted'),
      divider: v('divider'),
      panelBackground: v('panel_background'),
      panelGradient: v('panel_gradient'),
      panelMargin: v('panel_margin'),
      panelRadius: v('panel_radius'),
      panelBorder: v('panel_border'),
      panelBorderWidth: v('panel_border_width'),
      popupRadius: v('popup_radius'),
      popupBorder: v('popup_border'),
      popupBorderWidth: v('popup_border_width'),
      popupShadowColor: v('popup_shadow_color'),
      popupShadowBlur: v('popup_shadow_blur'),
      popupShadowSpread: v('popup_shadow_spread'),
      popupShadowOffsetX: v('popup_shadow_offset_x'),
      popupShadowOffsetY: v('popup_shadow_offset_y'),
      scrim: v('scrim'),
    );
  }

  /// The theme's key/value pairs, ready to hand to `TomlDocument.fromMap`.
  /// Every key is written explicitly so a saved theme never depends on a
  /// default that a later release might change.
  Map<String, dynamic> toMap() =>
      {for (final k in _keys) k.key: k.encode(this)};

  /// The TOML keys [toMap] writes, colours only, in the order the settings
  /// editor lists them — `font` and `blur` have their own controls.
  static final List<String> colorKeys = List<String>.unmodifiable([
    for (final k in _keys)
      if (k.kind == _ThemeKeyKind.color) k.key,
  ]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeConfig && _keys.every((k) => k.get(other) == k.get(this));

  @override
  int get hashCode => Object.hashAll([for (final k in _keys) k.get(this)]);
}
