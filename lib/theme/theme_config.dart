/// The resolved palette — [ThemeConfig] — and the key table that drives its
/// parsing, serialization, and equality.
library;

import 'dart:ui';

import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/theme/popup_effect.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The theme selected when `config.toml` names none, and the one every
/// failure path falls back to. Matches `lib/theme/builtin_themes.dart`.
const String kDefaultThemeName = 'graceful';

/// How a theme key parses and encodes.
///
/// [color] goes through [ThemeConfig.formatColor] and its inverse; [number]
/// is a clamped double; [integer] is read as a double and rounded, so a TOML
/// float coerces rather than falling back; [flag] and [text] are verbatim.
/// [effect] is a [PopupEffect] spelled by its slug — a closed set, so a slug
/// this build does not know falls back like any other wrongly-typed value
/// rather than costing the theme.
enum _ThemeKeyKind { color, number, integer, flag, text, effect }

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
      case _ThemeKeyKind.effect:
        return PopupEffect.fromSlug(map.stringOrNull(key)) ??
            fallback as PopupEffect;
    }
  }

  /// The value as [ThemeConfig.toMap] writes it.
  Object encode(ThemeConfig theme) {
    final value = get(theme);
    switch (kind) {
      case _ThemeKeyKind.color:
        return ThemeConfig.formatColor(value as Color);
      case _ThemeKeyKind.effect:
        return (value as PopupEffect).slug;
      default:
        return value;
    }
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
  /// All four corners for a popup that floats: it sits over a transparent
  /// surface with nothing behind it to cut into, unlike a flush bar, which
  /// spares the pair against the screen edge where rounding would cut wallpaper
  /// wedges out of the display's own corners. A bar popup at [popupGap] 0 is
  /// the exception — it is *attached* to the bar, so the two corners on the
  /// join are squared off and only the far pair take this. See
  /// `popupCornerRadius` (`popup_surface.dart`).
  final double popupRadius;

  /// How far a bar popup's card sits off the inner edge of its panel.
  ///
  /// The popup analogue of [panelMargin], one layer up: that floats the bar off
  /// the screen edge, this floats a popup off the bar. A bar popup is anchored
  /// to the panel's inner edge, centred on the module that opened it, so this
  /// is the whole distance between the two surfaces.
  ///
  /// **0 is the attached mode**, not merely a small gap: the card is flush with
  /// the bar, the two corners touching it are squared off and flared out by
  /// [popupAttachRadius], the rim on that edge is dropped and the shadow is cut
  /// at the join — so the popup reads as growing out of the panel rather than
  /// floating over it. There is no separate flag; this key is the switch.
  ///
  /// Only bar popups are affected. A menu anchored to the pointer — the
  /// desktop's context menu, the dock's unpin menu — has no panel edge to sit
  /// off and keeps the geometry it always had.
  final double popupGap;

  /// How far an attached popup **flares outward** into the bar it is joined to.
  ///
  /// Reads as a corner radius and is the inverse of one, which is the whole
  /// point. A convex corner curves *away* from the surface behind it and leaves
  /// two transparent wedges where the card meets the bar, so the card reads as
  /// resting against it. This sweeps each side *outward* instead, as it reaches
  /// the panel, the way a branch runs into a trunk — so the card is wider than
  /// itself exactly where it meets the bar and the two look like one surface.
  ///
  /// Being a concave fillet, it is no [BorderRadius] and cannot be one: it is
  /// drawn by `AttachedPopupBorder` (`popup_surface.dart`), which is why an
  /// attached card with a flare is the one card in the shell whose decoration
  /// is a `ShapeDecoration`. It also paints *outside* the card's own box, so
  /// the popup's surface is grown by `popupAttachInsets` the way it already is
  /// for the shadow.
  ///
  /// Read only at [popupGap] 0; with a gap there is no join to flare into. 0,
  /// the default, is a square butt join — the card's sides continue the bar's
  /// with no flare at all.
  final double popupAttachRadius;

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

  /// Which animation a popup plays as it opens, and — reversed — as it closes.
  ///
  /// Shape and colour are what a theme decides, and a card's *arrival* is part
  /// of its shape: a menu that unrolls out of the bar and one that fades in
  /// place belong to different themes even when every colour matches. Hence a
  /// theme key rather than a `config.toml` one, alongside [popupGap] and
  /// [popupRadius], which decide the same card's other two dimensions.
  ///
  /// The exit is the entrance played backwards, always — see
  /// `lib/popup_transition.dart`. [PopupEffect.none] is a real off switch:
  /// nothing is wrapped, no controller is created, and the window is destroyed
  /// on the frame it is closed, exactly as it was before this key existed.
  final PopupEffect popupEffect;

  /// [popupShadowOffsetX] and [popupShadowOffsetY] as one offset.
  ///
  /// The two are separate fields because a [_ThemeKey] maps one TOML scalar to
  /// one accessor; this is what every painter actually wants.
  Offset get popupShadowOffset =>
      Offset(popupShadowOffsetX, popupShadowOffsetY);

  /// The wash painted over the screen behind a full-screen overlay (the
  /// settings panel, the launcher card).
  final Color scrim;

  // There is no `blur` key. A `BackdropFilter` reaches only what Flutter has
  // already painted beneath it, and the overlay scaffold is the first thing
  // painted into its own window — under it is a transparent layer-shell
  // surface whose contents belong to the compositor, and Mir exposes no blur
  // protocol. So the filter had an empty backdrop and changed no pixel, while
  // every animated frame paid for a full-output Gaussian. Translucency over
  // the desktop comes from alpha in the colours above.

  final String fontFamily;

  /// The shell's body text size, and through it every other size in the shell.
  ///
  /// This is the size [ShellFontSizes.body] names — the tier most of the shell
  /// is set in — so the shipped default is that constant and a theme that
  /// spells no `font_size` renders exactly as it did before the key existed.
  ///
  /// It is a *default* in the strong sense: the rest of the type scale is a
  /// fixed ratio to it rather than a set of independent numbers. A theme that
  /// could only move the text no `TextStyle` had sized would move almost
  /// nothing — nearly every string in the shell names its tier explicitly —
  /// which is the setting that appears to do nothing. See [textScale] for how
  /// the ratio is applied.
  final double fontSize;

  /// How far every size in the shell is scaled, as a plain factor.
  ///
  /// `ThemeProvider` turns this into the `TextScaler` on the `MediaQuery` it
  /// puts above every themed tree, which is what reaches the three hundred-odd
  /// explicit `fontSize:` values as well as the text that names none. 1.0 —
  /// the default — is `TextScaler.noScaling`, so an unset key costs nothing at
  /// all.
  ///
  /// Sizes in *pixels* are not scaled: a panel's `height`, the grid's cell
  /// size and [ShellSizes] are config or layout, not type, and growing the
  /// text is not an instruction to grow the bar. A large enough font in a bar
  /// left at its default height will crop, and the answer is the panel's own
  /// `height` key.
  double get textScale => fontSize / ShellFontSizes.body;

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
    this.popupGap = 0.0,
    this.popupAttachRadius = 0.0,
    this.popupBorder = const Color(0x33F3F4F4),
    this.popupBorderWidth = 1.0,
    this.popupShadowColor = const Color(0x66000000),
    this.popupShadowBlur = 16.0,
    this.popupShadowSpread = 0.0,
    this.popupShadowOffsetX = 0.0,
    this.popupShadowOffsetY = 6.0,
    this.popupEffect = PopupEffect.slide,
    this.scrim = const Color(0x882C2C2C),
    this.fontFamily = 'Ubuntu Sans',
    this.fontSize = ShellFontSizes.body,
  });

  /// Every theme key, in the order [toMap] writes them; the colour
  /// subsequence is the order the settings editor lists ([colorKeys]).
  ///
  /// `static final` rather than `const` only because each row carries a field
  /// accessor and a function literal is not a constant expression; the list is
  /// built once and never mutated.
  static final List<_ThemeKey> _keys = [
    _ThemeKey('font', _ThemeKeyKind.text, (t) => t.fontFamily),
    // A theme file is hand-edited, and the two ends of this key are not
    // symmetrical failures of degree: 0 lays every string in the shell out as
    // nothing, and a few hundred leaves one letter on the screen. Either is
    // recoverable only by editing the file back with the shell unusable, so
    // neither is allowed through. The ceiling is well above any size the bars
    // can hold at their default height, which is the panel's problem to solve
    // and not this key's.
    _ThemeKey('font_size', _ThemeKeyKind.number, (t) => t.fontSize,
        min: 6.0, max: 32.0),
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
    _ThemeKey('popup_gap', _ThemeKeyKind.number, (t) => t.popupGap,
        min: 0.0, max: 64.0),
    _ThemeKey('popup_attach_radius', _ThemeKeyKind.number,
        (t) => t.popupAttachRadius,
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
    _ThemeKey('popup_animation', _ThemeKeyKind.effect, (t) => t.popupEffect),
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
      fontSize: v('font_size'),
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
      popupGap: v('popup_gap'),
      popupAttachRadius: v('popup_attach_radius'),
      popupBorder: v('popup_border'),
      popupBorderWidth: v('popup_border_width'),
      popupShadowColor: v('popup_shadow_color'),
      popupShadowBlur: v('popup_shadow_blur'),
      popupShadowSpread: v('popup_shadow_spread'),
      popupShadowOffsetX: v('popup_shadow_offset_x'),
      popupShadowOffsetY: v('popup_shadow_offset_y'),
      popupEffect: v('popup_animation'),
      scrim: v('scrim'),
    );
  }

  /// The theme's key/value pairs, ready to hand to `TomlDocument.fromMap`.
  /// Every key is written explicitly so a saved theme never depends on a
  /// default that a later release might change.
  Map<String, dynamic> toMap() =>
      {for (final k in _keys) k.key: k.encode(this)};

  /// The TOML keys [toMap] writes, colours only, in the order the settings
  /// editor lists them — `font` and `font_size` have their own controls.
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
