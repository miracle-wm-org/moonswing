import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:toml/toml.dart';
import 'package:graceful_shell/input_trigger/keysym.dart';
import 'package:graceful_shell/module.dart';

enum BackgroundFit {
  fill,
  contain,
  natural;

  static BackgroundFit fromString(String s) {
    switch (s) {
      case 'contain':
        return BackgroundFit.contain;
      case 'natural':
        return BackgroundFit.natural;
      default:
        return BackgroundFit.fill;
    }
  }
}

/// The theme selected when `config.toml` names none, and the one every
/// failure path falls back to. Matches `lib/theme/builtin_themes.dart`.
const String kDefaultThemeName = 'graceful';

/// Resolves [name] against the directories the shell's shipped data files
/// (the wallpapers) can live in, returning the first that exists.
///
/// The snap's own copy comes first, because it cannot write into the user's
/// data dir; `make install` puts them in the XDG data dir instead. Returns null
/// when neither has the file — the callers all treat a missing wallpaper as
/// "draw the fallback", never as an error.
///
/// Under the snap this deliberately resolves through `/snap/<name>/current`
/// rather than `$SNAP`, which is `/snap/<name>/<revision>`: the result is baked
/// into the generated `config.toml` and a revisioned path would go dead on the
/// next `snap refresh`.
String? shippedDataFile(String name) {
  final env = Platform.environment;
  final roots = <String>[];

  final snap = env['SNAP'] ?? '';
  if (snap.isNotEmpty) {
    final snapName = env['SNAP_NAME'] ?? '';
    if (snapName.isNotEmpty) {
      roots.add('/snap/$snapName/current/share/graceful-shell');
    }
    roots.add('$snap/share/graceful-shell');
  }

  final dataHome = env['XDG_DATA_HOME'] ?? '';
  if (dataHome.isNotEmpty) {
    roots.add('$dataHome/graceful-shell');
  } else {
    final home = env['HOME'] ?? '';
    if (home.isNotEmpty) roots.add('$home/.local/share/graceful-shell');
  }

  for (final root in roots) {
    final path = '$root/$name';
    if (File(path).existsSync()) return path;
  }
  return null;
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
    this.scrim = const Color(0x882C2C2C),
    this.blur = 24.0,
    this.fontFamily = 'Ubuntu Sans',
  });

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
    // Every read is type-tested rather than cast: a theme file is hand-editable
    // and a wrongly-typed value should cost that one key, not the theme.
    String? str(String key) {
      final raw = map[key];
      return raw is String ? raw : null;
    }

    // A theme file is hand-editable, so every number is clamped into a range
    // that cannot crash a painter. NaN and ±Infinity both fall back rather than
    // clamp: infinity survives clamp(), and `double.nan.toInt()` throws.
    double num_(String key, double fallback, double max) {
      final raw = map[key];
      if (raw is! num) return fallback;
      final value = raw.toDouble();
      if (!value.isFinite) return fallback;
      return value.clamp(0.0, max);
    }

    return ThemeConfig(
      foreground: _parseColor(str('foreground'), const Color(0xFFF3F4F4)),
      accent: _parseColor(str('accent'), const Color(0xFF853953)),
      surfaceHover: _parseColor(str('surface_hover'), const Color(0xFF853953)),
      surfacePressed:
          _parseColor(str('surface_pressed'), const Color(0xFF612D53)),
      workspaceBackground:
          _parseColor(str('workspace_background'), const Color(0xFF2C2C2C)),
      popupBackground:
          _parseColor(str('popup_background'), const Color(0xFF2C2C2C)),
      popupForeground:
          _parseColor(str('popup_foreground'), const Color(0xFFF3F4F4)),
      controlSurface:
          _parseColor(str('control_surface'), const Color(0xFF39393D)),
      sliderTrack: _parseColor(str('slider_track'), const Color(0xFF612D53)),
      muted: _parseColor(str('muted'), const Color(0xFF853953)),
      divider: _parseColor(str('divider'), const Color(0x33F3F4F4)),
      panelBackground:
          _parseColor(str('panel_background'), const Color(0xEE2C2C2C)),
      panelGradient: map['panel_gradient'] is bool
          ? map['panel_gradient'] as bool
          : true,
      panelMargin: num_('panel_margin', 0.0, 256.0).round(),
      panelRadius: num_('panel_radius', 0.0, 64.0),
      panelBorder: _parseColor(str('panel_border'), const Color(0x33F3F4F4)),
      panelBorderWidth: num_('panel_border_width', 0.0, 16.0),
      scrim: _parseColor(str('scrim'), const Color(0x882C2C2C)),
      // A negative or NaN sigma throws inside ImageFilter.blur.
      blur: num_('blur', 24.0, 100.0),
      fontFamily: str('font') ?? 'Ubuntu Sans',
    );
  }

  /// The theme's key/value pairs, ready to hand to `TomlDocument.fromMap`.
  /// Every key is written explicitly so a saved theme never depends on a
  /// default that a later release might change.
  Map<String, dynamic> toMap() => {
        'font': fontFamily,
        'blur': blur,
        'foreground': formatColor(foreground),
        'accent': formatColor(accent),
        'surface_hover': formatColor(surfaceHover),
        'surface_pressed': formatColor(surfacePressed),
        'workspace_background': formatColor(workspaceBackground),
        'popup_background': formatColor(popupBackground),
        'popup_foreground': formatColor(popupForeground),
        'control_surface': formatColor(controlSurface),
        'slider_track': formatColor(sliderTrack),
        'muted': formatColor(muted),
        'divider': formatColor(divider),
        'panel_background': formatColor(panelBackground),
        'panel_gradient': panelGradient,
        'panel_margin': panelMargin,
        'panel_radius': panelRadius,
        'panel_border': formatColor(panelBorder),
        'panel_border_width': panelBorderWidth,
        'scrim': formatColor(scrim),
      };

  /// The TOML keys [toMap] writes, in the order the settings editor lists
  /// them. Colours only — `font` and `blur` have their own controls.
  static const List<String> colorKeys = [
    'accent',
    'foreground',
    'surface_hover',
    'surface_pressed',
    'workspace_background',
    'popup_background',
    'popup_foreground',
    'control_surface',
    'slider_track',
    'muted',
    'divider',
    'panel_background',
    'panel_border',
    'scrim',
  ];

  @override
  bool operator ==(Object other) =>
      other is ThemeConfig &&
      other.foreground == foreground &&
      other.accent == accent &&
      other.surfaceHover == surfaceHover &&
      other.surfacePressed == surfacePressed &&
      other.workspaceBackground == workspaceBackground &&
      other.popupBackground == popupBackground &&
      other.popupForeground == popupForeground &&
      other.controlSurface == controlSurface &&
      other.sliderTrack == sliderTrack &&
      other.muted == muted &&
      other.divider == divider &&
      other.panelBackground == panelBackground &&
      other.panelGradient == panelGradient &&
      other.panelMargin == panelMargin &&
      other.panelRadius == panelRadius &&
      other.panelBorder == panelBorder &&
      other.panelBorderWidth == panelBorderWidth &&
      other.scrim == scrim &&
      other.blur == blur &&
      other.fontFamily == fontFamily;

  // hashAll rather than Object.hash: the field list is already at that
  // function's 20-argument ceiling, so the next key added would not compile.
  @override
  int get hashCode => Object.hashAll([
        foreground,
        accent,
        surfaceHover,
        surfacePressed,
        workspaceBackground,
        popupBackground,
        popupForeground,
        controlSurface,
        sliderTrack,
        muted,
        divider,
        panelBackground,
        panelGradient,
        panelMargin,
        panelRadius,
        panelBorder,
        panelBorderWidth,
        scrim,
        blur,
        fontFamily,
      ]);
}

/// File extensions considered valid image wallpapers. Paths with any other
/// extension (or none) are treated as invalid and auto-pruned by the selector.
const Set<String> imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
};

/// File extensions rendered with the video backend rather than as a still.
const Set<String> videoExtensions = {
  '.mp4',
  '.mkv',
  '.webm',
  '.mov',
  '.avi',
  '.m4v',
};

/// Whether [path] points at a supported image file, judged purely by its
/// extension. Existence is checked separately at call sites so this stays a
/// pure, unit-testable predicate.
bool isImagePath(String path) {
  final lower = path.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0) return false;
  return imageExtensions.contains(lower.substring(dot));
}

class BackgroundEntry {
  final String path;
  final bool shown;

  const BackgroundEntry({required this.path, this.shown = true});

  factory BackgroundEntry.fromMap(Map<String, dynamic> map) {
    final path = map['path'] as String? ?? '';
    final shown = map['shown'] as bool? ?? true;
    return BackgroundEntry(path: path, shown: shown);
  }
}

class BackgroundConfig {
  final BackgroundFit fit;
  final int intervalMinutes;
  final List<BackgroundEntry> entries;

  const BackgroundConfig({
    this.fit = BackgroundFit.fill,
    this.intervalMinutes = 5,
    this.entries = const [],
  });

  factory BackgroundConfig.fromMap(Map<String, dynamic> map) {
    final fitStr = map['fit'] as String? ?? 'fill';
    final rawInterval = map['interval_minutes'];
    final interval = rawInterval is num ? rawInterval.toInt() : 5;
    final rawEntries = map['entries'] as List<dynamic>? ?? [];
    // List order is the canonical presentation order — do not sort.
    final entries = rawEntries
        .whereType<Map<String, dynamic>>()
        .map(BackgroundEntry.fromMap)
        .toList();
    return BackgroundConfig(
      fit: BackgroundFit.fromString(fitStr),
      intervalMinutes: interval < 1 ? 1 : interval,
      entries: entries,
    );
  }
}

/// What a desktop grid item points at, which decides how it opens.
///
/// The distinction between [file] and [folder] is not cosmetic: it picks the
/// icon and decides whether "Open with…" is offered, and a folder cannot be
/// content-sniffed from its name alone (see `iconNameForPath`).
enum DesktopItemKind {
  app,
  file,
  folder;

  static DesktopItemKind fromString(String s) {
    switch (s) {
      case 'app':
        return DesktopItemKind.app;
      case 'folder':
        return DesktopItemKind.folder;
      default:
        return DesktopItemKind.file;
    }
  }
}

/// Infers an item's kind from its target, used when the stored `kind` is
/// missing or has gone stale (a path that was a file and is now a directory).
///
/// A `.desktop` file is an application even though it is also a file on disk —
/// that is the whole point of pinning one.
DesktopItemKind inferDesktopItemKind(String target) {
  if (target.toLowerCase().endsWith('.desktop')) return DesktopItemKind.app;
  if (Directory(target).existsSync()) return DesktopItemKind.folder;
  return DesktopItemKind.file;
}

/// One icon pinned to the desktop grid.
///
/// [target] is the identity: an absolute path in every case, including for
/// applications. A desktop *id* (what `[modules.dock].apps` stores) is
/// deliberately not used — the item is added through the file picker, which
/// yields a path, and `g_desktop_app_info_new` cannot resolve a `.desktop`
/// living outside `XDG_DATA_DIRS`.
class DesktopItem {
  final DesktopItemKind kind;
  final String target;

  /// The user's rename, or null to derive the label from the desktop entry's
  /// name (for [DesktopItemKind.app]) or the path's basename.
  final String? label;

  final int column;
  final int row;

  const DesktopItem({
    required this.kind,
    required this.target,
    this.label,
    this.column = 0,
    this.row = 0,
  });

  DesktopItem copyWith({
    DesktopItemKind? kind,
    String? label,
    bool clearLabel = false,
    int? column,
    int? row,
  }) {
    return DesktopItem(
      kind: kind ?? this.kind,
      target: target,
      label: clearLabel ? null : (label ?? this.label),
      column: column ?? this.column,
      row: row ?? this.row,
    );
  }

  /// Parses one `[[desktop.items]]` table, or null when it names no target.
  ///
  /// Type-tested rather than cast throughout: a throw here would be caught by
  /// [AppConfig.fromMap] and discard the user's *whole* config.
  static DesktopItem? fromMap(Map<String, dynamic> map) {
    final target = map['target'];
    if (target is! String || target.trim().isEmpty) return null;

    final rawKind = map['kind'];
    // A stored kind is trusted only when it still matches reality; `app` is the
    // exception, since a `.desktop` file is legitimately both.
    var kind = rawKind is String
        ? DesktopItemKind.fromString(rawKind)
        : inferDesktopItemKind(target);
    if (kind != DesktopItemKind.app) kind = inferDesktopItemKind(target);

    final rawLabel = map['label'];
    final label =
        rawLabel is String && rawLabel.trim().isNotEmpty ? rawLabel : null;

    final rawColumn = map['column'];
    final rawRow = map['row'];
    return DesktopItem(
      kind: kind,
      target: target,
      label: label,
      column: rawColumn is num && rawColumn >= 0 ? rawColumn.toInt() : 0,
      row: rawRow is num && rawRow >= 0 ? rawRow.toInt() : 0,
    );
  }

  /// The TOML table for this item. `label` is omitted when the user has not
  /// renamed it, so a config that was never edited stays minimal.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'kind': kind.name,
        'target': target,
        if (label != null) 'label': label,
        'column': column,
        'row': row,
      };
}

/// Geometry and behaviour of the desktop icon grid.
///
/// Column and row counts are *derived* from each monitor's usable area rather
/// than configured, so one item list renders sanely on monitors of different
/// sizes. See `computeGridGeometry` in `lib/desktop/desktop_layout.dart`.
class DesktopConfig {
  /// Whether the grid is drawn at all. Restart-only: it decides whether the
  /// native background surface is created (see `ConfigStore._restartSignature`).
  final bool enabled;

  final double cellWidth;
  final double cellHeight;
  final double spacing;

  /// Inset from the usable area's edges, on top of the panel exclusive zones.
  final double padding;

  final double iconSize;
  final bool showLabels;

  final List<DesktopItem> items;

  const DesktopConfig({
    this.enabled = false,
    this.cellWidth = 96,
    this.cellHeight = 96,
    this.spacing = 12,
    this.padding = 24,
    this.iconSize = 48,
    this.showLabels = true,
    this.items = const [],
  });

  factory DesktopConfig.fromMap(Map<String, dynamic> map) {
    double dimension(String key, double fallback, double floor) {
      final raw = map[key];
      if (raw is! num) return fallback;
      final value = raw.toDouble();
      return value < floor ? floor : value;
    }

    final rawItems = map['items'];
    // Document order is preserved; cells, not list position, decide layout.
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(DesktopItem.fromMap)
            .whereType<DesktopItem>()
            .toList()
        : <DesktopItem>[];

    return DesktopConfig(
      enabled: map['enabled'] is bool ? map['enabled'] as bool : false,
      // A cell smaller than its icon would clip; floors keep a hand-edited
      // config from producing an unusable grid rather than rejecting it.
      cellWidth: dimension('cell_width', 96, 32),
      cellHeight: dimension('cell_height', 96, 32),
      spacing: dimension('spacing', 12, 0),
      padding: dimension('padding', 24, 0),
      iconSize: dimension('icon_size', 48, 8),
      showLabels: map['show_labels'] is bool ? map['show_labels'] as bool : true,
      items: items,
    );
  }
}

class LayoutConfig {
  final List<String> left;
  final List<String> center;
  final List<String> right;

  const LayoutConfig({
    this.left = const ["workspaces"],
    this.center = const ["media_player"],
    this.right = const [
      "sound_control",
      "battery",
      "weather",
      "clock",
      "system",
    ],
  });

  factory LayoutConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const LayoutConfig();
    return LayoutConfig(
      left: _parseModuleList(map['left']),
      center: _parseModuleList(map['center']),
      right: _parseModuleList(map['right']),
    );
  }

  static List<String> _parseModuleList(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value.whereType<String>().toList();
  }

  Set<String> get enabledModules => {...left, ...center, ...right};
}

class PanelConfig {
  final String name;
  final int height;
  final int paddingHorizontal;
  final String anchor;
  final String layer;
  final LayoutConfig layout;

  const PanelConfig({
    this.name = 'default',
    this.height = 32,
    this.paddingHorizontal = 8,
    this.anchor = 'top',
    this.layer = 'top',
    this.layout = const LayoutConfig(),
  });

  factory PanelConfig.fromMap(String name, Map<String, dynamic> map) {
    final layoutMap = map['layout'] as Map<String, dynamic>?;
    return PanelConfig(
      name: name,
      height: map['height'] as int? ?? 32,
      paddingHorizontal: map['padding_horizontal'] as int? ?? 8,
      anchor: map['anchor'] as String? ?? 'top',
      layer: map['layer'] as String? ?? 'top',
      layout: LayoutConfig.fromMap(layoutMap),
    );
  }
}

/// The `[calendar]` section. The calendar is a local month grid with no account
/// integration, so this is only the grid's own presentation.
class CalendarConfig {
  /// A [DateTime] weekday constant: [DateTime.sunday] or [DateTime.monday].
  final int weekStart;

  const CalendarConfig({this.weekStart = DateTime.sunday});

  factory CalendarConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CalendarConfig();

    final weekStart = (map['week_start'] as String? ?? 'sunday').toLowerCase();

    return CalendarConfig(
      weekStart: weekStart == 'monday' ? DateTime.monday : DateTime.sunday,
    );
  }
}

/// The on-screen indicator shown when volume, microphone volume, or screen
/// brightness changes.
class OsdConfig {
  final bool enabled;

  /// Inactivity before the indicator fades out.
  final int hideDelayMs;

  /// Distance from the bottom edge of the screen, in logical pixels.
  final int margin;

  const OsdConfig({
    this.enabled = true,
    this.hideDelayMs = 1500,
    this.margin = 96,
  });

  factory OsdConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const OsdConfig();
    final hideDelay = (map['hide_delay_ms'] as num?)?.toInt() ?? 1500;
    return OsdConfig(
      enabled: map['enabled'] as bool? ?? true,
      // A zero delay would hide the indicator before it finished fading in.
      hideDelayMs: hideDelay < 100 ? 100 : hideDelay,
      margin: (map['margin'] as num?)?.toInt() ?? 96,
    );
  }
}

/// Screen sharing — the shell's xdg-desktop-portal ScreenCast backend.
class ScreenshareConfig {
  /// Whether to claim the ScreenCast backend bus name at all. Turning this
  /// off lets another backend (xdg-desktop-portal-wlr) take over without
  /// uninstalling anything.
  final bool enabled;

  /// Frame rate for the picker's live previews. Deliberately low: the picker
  /// runs one capture session per monitor *and* per window simultaneously.
  final int previewFps;

  /// Cap on the shared stream's frame rate. 0 follows the output's refresh
  /// rate; windows fall back to 60.
  final int maxFps;

  const ScreenshareConfig({
    this.enabled = true,
    this.previewFps = 10,
    this.maxFps = 0,
  });

  factory ScreenshareConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ScreenshareConfig();
    // Type-test, never cast: a wrongly-typed value must not throw out of
    // AppConfig.fromMap, whose caller answers by discarding the *entire*
    // config.
    final rawEnabled = map['enabled'];
    final rawPreviewFps = map['preview_fps'];
    final rawMaxFps = map['max_fps'];
    final previewFps = rawPreviewFps is num ? rawPreviewFps.toInt() : 10;
    final maxFps = rawMaxFps is num ? rawMaxFps.toInt() : 0;
    return ScreenshareConfig(
      enabled: rawEnabled is bool ? rawEnabled : true,
      previewFps: previewFps.clamp(1, 60),
      maxFps: maxFps < 0 ? 0 : maxFps,
    );
  }
}

/// The lock screen: its wallpaper and the chrome drawn over it.
///
/// Unlike [BackgroundConfig] this holds a single wallpaper rather than a
/// rotating list — a lock screen has no reason to cycle — but it accepts the
/// same image *and* video paths, rendered by the shared `MediaBackground`.
class LockConfig {
  /// Wallpaper path (image or video). Null falls back to the shipped default.
  final String? background;

  final BackgroundFit fit;

  /// Whether to show the account's name above the unlock control.
  final bool showUsername;

  /// Gaussian blur applied to the wallpaper once the password field is shown.
  final double blurSigma;

  const LockConfig({
    this.background,
    this.fit = BackgroundFit.fill,
    this.showUsername = true,
    this.blurSigma = 18.0,
  });

  factory LockConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const LockConfig();
    // Every read is type-tested rather than cast: a wrongly-typed value here
    // would otherwise throw out of AppConfig.fromMap, and the caller responds
    // to that by discarding the *whole* config, not just this table.
    final rawBackground = map['background'];
    final background = rawBackground is String ? rawBackground.trim() : null;
    final rawSigma = map['blur_sigma'];
    final sigma = rawSigma is num ? rawSigma.toDouble() : 18.0;
    final rawFit = map['fit'];
    final rawShowUsername = map['show_username'];
    return LockConfig(
      background: (background == null || background.isEmpty) ? null : background,
      fit: BackgroundFit.fromString(rawFit is String ? rawFit : 'fill'),
      showUsername: rawShowUsername is bool ? rawShowUsername : true,
      // A negative sigma throws inside ImageFilter.blur; clamp rather than
      // let a hand-edited config crash the lock screen.
      blurSigma: sigma.isNaN ? 18.0 : sigma.clamp(0.0, 100.0),
    );
  }
}

/// Ctrl+Shift+S. The shifted keysym (`S`, not `s`) is what Mir matches on —
/// see [parseShortcut]. Spelled numerically because a const field cannot call a
/// function; `test/shortcut_parse_test.dart` asserts the two agree.
const ShortcutSpec kDefaultOpenSettings =
    ShortcutSpec(modifiers: 0x108, keysym: 0x53);

/// Ctrl+Space.
const ShortcutSpec kDefaultOpenLauncher =
    ShortcutSpec(modifiers: 0x100, keysym: 0x20);

/// The compositor-level shortcuts the shell registers at start-up.
///
/// A null field means the shortcut is *disabled* (the user wrote `""`), which
/// is distinct from the key being absent — absent falls back to the default.
///
/// Registration latches on the first successful handshake
/// (`InputTriggerManager._registered`), so these are read once from the startup
/// snapshot and editing them needs a restart. If the settings UI ever grows a
/// shortcut editor, add `shortcuts` to `ConfigStore._restartSignature()` so the
/// "restart to apply" banner tells the truth.
class ShortcutsConfig {
  final ShortcutSpec? openSettings;
  final ShortcutSpec? openLauncher;

  const ShortcutsConfig({
    this.openSettings = kDefaultOpenSettings,
    this.openLauncher = kDefaultOpenLauncher,
  });

  factory ShortcutsConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ShortcutsConfig();
    return ShortcutsConfig(
      openSettings: _read(map, 'open_settings', kDefaultOpenSettings),
      openLauncher: _read(map, 'open_launcher', kDefaultOpenLauncher),
    );
  }

  /// Reads one shortcut, falling back to [fallback] on anything unusable. Each
  /// key is read independently so a typo in one does not disable the other —
  /// and, like every other config class here, a wrongly-typed value is tested
  /// for rather than cast, because a throw would discard the whole config.
  static ShortcutSpec? _read(
      Map<String, dynamic> map, String key, ShortcutSpec fallback) {
    if (!map.containsKey(key)) return fallback;
    final raw = map[key];
    if (raw is! String) {
      debugPrint('config: [shortcuts].$key is not a string; using the default');
      return fallback;
    }
    final trimmed = raw.trim().toLowerCase();
    // An explicit empty string (or "none") disables the shortcut entirely.
    if (trimmed.isEmpty || trimmed == 'none') return null;
    final spec = parseShortcut(raw);
    if (spec == null) {
      debugPrint('config: [shortcuts].$key ("$raw") is not a shortcut the '
          'shell understands; using the default');
      return fallback;
    }
    return spec;
  }
}

class AppConfig {
  final Map<String, PanelConfig> panels;
  final BackgroundConfig? background;

  /// The name of the active theme — the basename of a file under
  /// `~/.config/graceful-shell/themes/`. Resolving it to a [ThemeConfig] is
  /// `ThemeStore`'s job, not this one's; nothing here touches the disk.
  final String themeName;

  /// The desktop icon grid. Never null — an absent `[desktop]` section is a
  /// disabled grid, not "no grid config", so callers never null-check it.
  final DesktopConfig desktop;

  final CalendarConfig calendar;
  final OsdConfig osd;
  final LockConfig lock;
  final ShortcutsConfig shortcuts;
  final ScreenshareConfig screenshare;

  const AppConfig({
    this.panels = const {'default': PanelConfig()},
    this.background,
    this.desktop = const DesktopConfig(),
    this.themeName = kDefaultThemeName,
    this.calendar = const CalendarConfig(),
    this.osd = const OsdConfig(),
    this.lock = const LockConfig(),
    this.shortcuts = const ShortcutsConfig(),
    this.screenshare = const ScreenshareConfig(),
  });

  // Baked as absolute paths because config.toml is written once and then owned
  // by the user: resolving at every read would silently move their wallpaper if
  // the shell were later reinstalled somewhere else. Falls back to the XDG data
  // dir when nothing is installed yet, which is where `make install` will put
  // it.
  static String _buildDefaultConfig(String homeDir) {
    final wallpaper = shippedDataFile('wallpaper.jpg') ??
        '$homeDir/.local/share/graceful-shell/wallpaper.jpg';
    final lockWallpaper = shippedDataFile('lock-wallpaper.jpg') ??
        '$homeDir/.local/share/graceful-shell/lock-wallpaper.jpg';
    return '''
theme = "$kDefaultThemeName"

[panels.top]
height = 32
padding_horizontal = 8
anchor = "top"
layer = "top"

[panels.top.layout]
left = ["workspaces"]
center = ["clock"]
right = ["sound_control", "system_tray", "battery", "weather", "system"]

[panels.bottom]
height = 32
padding_horizontal = 0
anchor = "bottom"
layer = "top"

[panels.bottom.layout]
center = ["dock"]
right = ["media_player", "launcher"]

[modules.dock]
apps = ["firefox_firefox", "org.gnome.Ptyxis", "org.gnome.Nautilus"]

[modules.weather]
unit = "fahrenheit"
refresh_minutes = 10

[modules.battery]
poll_seconds = 30

[modules.clock]
show_date = true

[modules.media_player]
max_text_width = 200.0

[modules.system_tray]
icon_size = 16
collapsed_overlap = 10
expanded_spacing = 6

[modules.system_monitor]
poll_seconds = 2
temp_unit = "celsius"

[background]
fit = "fill"
interval_minutes = 5

[[background.entries]]
path = "$wallpaper"
shown = true

# Icons pinned to the desktop. Off by default; turn it on here or in
# Settings > Shell > Desktop. Items are appended as [[desktop.items]] tables.
[desktop]
enabled = false
cell_width = 96
cell_height = 96
spacing = 12
padding = 24
icon_size = 48
show_labels = true

[lock]
background = "$lockWallpaper"
fit = "fill"
show_username = true
blur_sigma = 18.0

[shortcuts]
open_settings = "ctrl+shift+s"
open_launcher = "ctrl+space"

[screenshare]
enabled = true
preview_fps = 10
max_fps = 0
''';
  }

  /// Resolves the absolute path to `config.toml`, honouring
  /// `XDG_CONFIG_HOME`. Shared by the loader and the settings writer so the
  /// two never diverge.
  static String resolveConfigPath() {
    final homeDir = Platform.environment['HOME'] ?? '';
    final configHome =
        Platform.environment['XDG_CONFIG_HOME'] ?? '$homeDir/.config';
    return '$configHome/graceful-shell/config.toml';
  }

  static Future<AppConfig> load() async {
    final homeDir = Platform.environment['HOME'] ?? '';
    final configPath = resolveConfigPath();
    final file = File(configPath);

    if (!await file.exists()) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(_buildDefaultConfig(homeDir));
      } catch (_) {
        // Could not write default config; proceed with defaults
      }
      try {
        final doc = TomlDocument.parse(_buildDefaultConfig(homeDir));
        return AppConfig.fromMap(doc.toMap());
      } catch (_) {
        return const AppConfig();
      }
    }

    try {
      final document = await TomlDocument.load(configPath);
      final map = document.toMap();
      return AppConfig.fromMap(map);
    } catch (_) {
      return const AppConfig();
    }
  }

  /// Builds a typed config from an already-parsed TOML map. Also applies the
  /// module subtable to every registered module via [Module.loadAll], so
  /// rebuilding an [AppConfig] from a live config map re-applies per-module
  /// options as a side effect.
  factory AppConfig.fromMap(Map<String, dynamic> map) {
    final modulesMap = map['modules'] as Map<String, dynamic>?;
    Module.loadAll(modulesMap);

    final panels = <String, PanelConfig>{};

    if (map.containsKey('panels')) {
      final panelsMap = map['panels'] as Map<String, dynamic>;
      for (final entry in panelsMap.entries) {
        panels[entry.key] = PanelConfig.fromMap(
          entry.key,
          entry.value as Map<String, dynamic>,
        );
      }
    }

    final backgroundMap = map['background'] as Map<String, dynamic>?;
    final background =
        backgroundMap != null ? BackgroundConfig.fromMap(backgroundMap) : null;

    final desktopMap = map['desktop'];
    final desktop = desktopMap is Map<String, dynamic>
        ? DesktopConfig.fromMap(desktopMap)
        : const DesktopConfig();

    // Type-tested, not cast: `theme` used to be a table and is now a name, so
    // an un-migrated config still has a map here. Casting would throw out of
    // this factory, and the caller answers that by discarding the *whole*
    // config — a stale [theme] table must cost the theme, nothing else.
    final rawTheme = map['theme'];
    final themeName = rawTheme is String && rawTheme.trim().isNotEmpty
        ? rawTheme.trim()
        : kDefaultThemeName;
    final calendarMap = map['calendar'] as Map<String, dynamic>?;
    final osdMap = map['osd'] as Map<String, dynamic>?;
    final lockMap = map['lock'] as Map<String, dynamic>?;
    final shortcutsMap = map['shortcuts'] as Map<String, dynamic>?;
    final screenshareMap = map['screenshare'] as Map<String, dynamic>?;

    return AppConfig(
      panels: panels.isEmpty ? const {'default': PanelConfig()} : panels,
      background: background,
      desktop: desktop,
      themeName: themeName,
      calendar: CalendarConfig.fromMap(calendarMap),
      osd: OsdConfig.fromMap(osdMap),
      lock: LockConfig.fromMap(lockMap),
      shortcuts: ShortcutsConfig.fromMap(shortcutsMap),
      screenshare: ScreenshareConfig.fromMap(screenshareMap),
    );
  }
}
