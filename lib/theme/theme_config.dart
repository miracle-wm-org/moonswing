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

/// The shipped `popup_animation_duration`, in milliseconds.
///
/// [ShellDurations.popupIn] read as a number, so a theme spelling no duration
/// plays exactly what every popup played before the key existed — the same
/// guarantee `font_size` makes against [ShellFontSizes.body]. A const `int`
/// rather than the token itself because `Duration.inMilliseconds` is a getter,
/// and a field default has to be a constant expression.
const int _kDefaultPopupDurationMs = 140;

/// How a theme key parses and encodes.
///
/// [color] goes through [ThemeConfig.formatColor] and its inverse; [number] is a
/// clamped double; [integer] is read as a double and rounded, so a TOML float
/// coerces; [flag] and [text] are verbatim. [effect] is a [PopupEffect] spelled
/// by its slug — a closed set, so an unknown slug falls back like any other
/// wrongly-typed value.
enum _ThemeKeyKind { color, number, integer, flag, text, effect }

/// One TOML theme key: its spelling, its kind, its clamp range, and where it
/// lives on a [ThemeConfig].
///
/// [ThemeConfig._keys] is the single place a key is described: `fromMap`'s parse
/// rules, `toMap`, [ThemeConfig.colorKeys], `==` and `hashCode` are all derived
/// from it. Adding a key means declaring the field, giving the constructor its
/// default, adding one row, and linking key to parameter in `fromMap`. A key
/// cannot be *partially* added — the built-in themes' round-trip test fails on
/// any row `fromMap` forgets, and `fromMap` throws on a key the table lacks.
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
/// Each theme is its own file under `~/.config/graceful-shell/themes/`, with
/// `config.toml` naming the active one. The file *is* this table, flat, so
/// [fromMap] parses a whole theme document. See `lib/theme/theme_store.dart`.
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
  /// The one surface that had no colour of its own — the panel used to be painted
  /// from [workspaceBackground] at a hardcoded 93% opacity, so a translucent theme
  /// could not see through the surface sitting on the desktop. Its alpha is
  /// honoured verbatim and sets the whole bar's opacity: see [panelGradient].
  final Color panelBackground;

  /// Whether the bar fades from [accent] across to [panelBackground].
  ///
  /// False gives a flat [panelBackground]. When true every gradient stop takes
  /// its alpha from [panelBackground], so the bar has exactly one opacity and
  /// cannot band partway across.
  final bool panelGradient;

  /// How far each bar floats off the screen edges it is anchored to.
  ///
  /// A *native* `gtk_layer_set_margin`, never a Flutter `Padding`: with no
  /// input-region support, an inset inside a full-size surface would swallow
  /// every click in the gap.
  ///
  /// The exclusive zone is left at the panel's thickness. Per wlr-layer-shell,
  /// "the exclusive zone includes the margin", so reserving `height + margin`
  /// would reserve it twice.
  final int panelMargin;

  /// The bar's corner rounding.
  ///
  /// A floating bar ([panelMargin] > 0) rounds all four corners. A flush one
  /// rounds only the two facing the screen's interior, because rounding the pair
  /// against the screen edge cuts wallpaper wedges out of the display's corners.
  final double panelRadius;

  /// The colour of the bar's rim. Only drawn when [panelBorderWidth] > 0.
  final Color panelBorder;

  /// The bar's rim thickness, or 0 for no rim.
  ///
  /// Width, not alpha, is the off switch: at 0 no `Border` is built at all.
  ///
  /// The rim is drawn round the whole bar, its **inner** edge included — the edge
  /// an attached popup meets. Any attached card ([popupGap] 0) therefore reaches
  /// this far back into the panel so its own fill takes that hairline out across
  /// the mouth; see `popupAttachCollar`. [popupAttachRadius] decides only how the
  /// line resumes at either end.
  final double panelBorderWidth;

  /// A popup card's corner rounding.
  ///
  /// All four corners for a popup that floats. A bar popup at [popupGap] 0 is the
  /// exception — it is *attached*, so the two corners on the join are squared off
  /// and only the far pair take this. See `popupCornerRadius`.
  final double popupRadius;

  /// How far a bar popup's card sits off the inner edge of its panel.
  ///
  /// The popup analogue of [panelMargin], one layer up: that floats the bar off
  /// the screen edge, this floats a popup off the bar.
  ///
  /// **0 is the attached mode**, not merely a small gap: the card is flush with
  /// the bar, the two corners touching it are squared off and flared out by
  /// [popupAttachRadius], the rim on that edge is dropped and the shadow is cut
  /// at the join. There is no separate flag; this key is the switch.
  ///
  /// Only bar popups are affected. A menu anchored to the pointer has no panel
  /// edge to sit off and keeps the geometry it always had.
  final double popupGap;

  /// How far an attached popup **flares outward** into the bar it is joined to.
  ///
  /// Reads as a corner radius and is the inverse of one. A convex corner curves
  /// *away* from the surface behind it, leaving transparent wedges where the card
  /// meets the bar; this sweeps each side *outward* as it reaches the panel, so
  /// the card is widest exactly where the two meet and they read as one surface.
  ///
  /// Being a concave fillet it is no [BorderRadius]: it is drawn by
  /// `AttachedPopupBorder`, which is why an attached card with a flare is the one
  /// card whose decoration is a `ShapeDecoration`. It paints *outside* the card's
  /// box, so the surface is grown by `popupAttachInsets`.
  ///
  /// It does *not* decide whether a bar may carry a rim: every attached card
  /// reaches [panelBorderWidth] back into the panel (`popupAttachCollar`) and
  /// takes the bar's inner hairline out with its own fill. A flare only decides
  /// how the line resumes at either end.
  ///
  /// Read only at [popupGap] 0. The default of 0 is a square butt join.
  final double popupAttachRadius;

  /// The colour of a popup card's rim. Only drawn when [popupBorderWidth] > 0.
  final Color popupBorder;

  /// A popup card's rim thickness, or 0 for no rim.
  ///
  /// Width, not alpha, is the off switch, for [panelBorderWidth]'s reason: at 0
  /// no `Border` is built at all, and a `Border` carries a
  /// [BoxDecoration.padding] a `Container` silently adds to its child's.
  final double popupBorderWidth;

  /// The colour of a popup card's shadow.
  ///
  /// Alpha *is* the off switch here, unlike [popupBorderWidth]: a shadow carries
  /// no [BoxDecoration.padding] to shift. At alpha 0 — or with
  /// [popupShadowBlur], [popupShadowSpread] and both offsets at 0 —
  /// `popupDecoration` builds no `boxShadow` at all.
  final Color popupShadowColor;

  /// The shadow's blur radius, in the CSS sense: how far the falloff reaches past
  /// the card's edge.
  ///
  /// Flutter's [BoxShadow.blurRadius] maps to a sigma the way CSS does, so this
  /// doubles as the extent `popupShadowInsets` grows the popup's window by.
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
  /// A card's *arrival* is part of its shape: a menu that unrolls out of the bar
  /// and one that fades in place belong to different themes even when every
  /// colour matches. Hence a theme key, alongside [popupGap] and [popupRadius].
  ///
  /// The exit is the entrance played backwards, always — see
  /// `lib/popup_transition.dart`. [PopupEffect.none] is a real off switch: nothing
  /// is wrapped, no controller is created, and the window is destroyed on the
  /// frame it is closed.
  final PopupEffect popupEffect;

  /// How long that animation lasts on the way in, in milliseconds.
  ///
  /// Pace is part of an entrance the same way its shape is: the same slide read
  /// at 60ms and at 400ms is a different theme. Ignored entirely under
  /// [PopupEffect.none], which builds no controller at all.
  ///
  /// The ceiling is well short of anything usable as a menu — a popup the user
  /// has to wait out is a broken bar, and a theme file is hand-edited — while
  /// the floor is 0, which is the animation played instantly rather than a
  /// controller that never completes.
  final int popupAnimationDuration;

  /// [popupAnimationDuration] as the entrance [Duration] a controller takes.
  Duration get popupInDuration =>
      Duration(milliseconds: popupAnimationDuration);

  /// The exit: the entrance reversed and shortened by
  /// [ShellDurations.popupExitFraction], which is where that trade is
  /// explained.
  Duration get popupOutDuration => Duration(
      milliseconds:
          (popupAnimationDuration * ShellDurations.popupExitFraction).round());

  /// [popupShadowOffsetX] and [popupShadowOffsetY] as one offset.
  ///
  /// The two are separate fields because a [_ThemeKey] maps one TOML scalar to one
  /// accessor; this is what every painter actually wants.
  Offset get popupShadowOffset =>
      Offset(popupShadowOffsetX, popupShadowOffsetY);

  /// The wash painted over the screen behind a full-screen overlay (the
  /// settings panel, the launcher card).
  final Color scrim;

  // There is no `blur` key. A `BackdropFilter` reaches only what Flutter has
  // already painted beneath it, and the overlay scaffold is the first thing
  // painted into its own window — under it is a transparent layer-shell surface
  // whose contents belong to the compositor, and Mir exposes no blur protocol. So
  // the filter had an empty backdrop and changed no pixel while every animated
  // frame paid for a full-output Gaussian. Translucency comes from alpha instead.

  final String fontFamily;

  /// The shell's body text size, and through it every other size in the shell.
  ///
  /// The size [ShellFontSizes.body] names, so the shipped default is that constant
  /// and a theme spelling no `font_size` renders exactly as before the key existed.
  ///
  /// A *default* in the strong sense: the rest of the type scale is a fixed ratio
  /// to it. A theme that could only move the text no `TextStyle` had sized would
  /// move almost nothing. See [textScale].
  final double fontSize;

  /// How far every size in the shell is scaled, as a plain factor.
  ///
  /// `ThemeProvider` turns this into the `TextScaler` on the `MediaQuery` above
  /// every themed tree, which reaches the three hundred-odd explicit `fontSize:`
  /// values as well as the text that names none. 1.0 is `TextScaler.noScaling`,
  /// so an unset key costs nothing.
  ///
  /// Sizes in *pixels* are not scaled: a panel's `height`, the grid's cell size
  /// and [ShellSizes] are layout, not type. A large font in a bar left at its
  /// default height will crop, and the answer is that panel's `height` key.
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
    this.popupAnimationDuration = _kDefaultPopupDurationMs,
    this.scrim = const Color(0x882C2C2C),
    this.fontFamily = 'Ubuntu Sans',
    this.fontSize = ShellFontSizes.body,
  });

  /// Every theme key, in the order [toMap] writes them; the colour subsequence is
  /// the order the settings editor lists ([colorKeys]).
  ///
  /// `static final` rather than `const` only because each row carries a field
  /// accessor and a function literal is not a constant expression.
  static final List<_ThemeKey> _keys = [
    _ThemeKey('font', _ThemeKeyKind.text, (t) => t.fontFamily),
    // A theme file is hand-edited, and the two ends of this key are not
    // symmetrical failures of degree: 0 lays every string out as nothing, and a
    // few hundred leaves one letter on the screen. Either is recoverable only by
    // editing the file back with the shell unusable. The ceiling is well above
    // any size the bars can hold at their default height, which is the panel's
    // problem rather than this key's.
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
    _ThemeKey('popup_animation_duration', _ThemeKeyKind.integer,
        (t) => t.popupAnimationDuration,
        min: 0.0, max: 2000.0),
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
    // A theme file is hand-editable, so every read goes through TomlReader — a
    // wrongly-typed value costs that one key, not the theme — and every number is
    // clamped into a range that cannot crash a painter. Kind, clamp and default
    // come from [_keys]; the constructor call below only links each TOML key to
    // its named parameter, which Dart cannot do dynamically.
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
      popupAnimationDuration: v('popup_animation_duration'),
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
