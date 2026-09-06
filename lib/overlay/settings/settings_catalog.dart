// Every field the settings search can find, in one table.
//
// Deliberately not a *description* of the settings UI written beside it — this is
// where the labels live. Each row here is built with `SettingsRow.field`, which
// reads its label from the entry, and each module row derives its config path
// from the entry's id, so a rename is one edit and the index cannot fall behind
// the pane. The catalogue is what the pages import; nothing here imports a page,
// which keeps the file widget-free and its invariants a plain unit test.
//
// What belongs here: a control the user can be *sent to*. What does not: a device
// in a list, a wallpaper tile, a theme swatch — those come and go with the
// machine, and the entry that finds them is the page-level one.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'package:graceful_shell/overlay/settings/settings_search.dart';
import 'package:graceful_shell/overlay/settings_route.dart';

/// One themeable colour: the key it is written under, and its catalogue entry.
///
/// The Appearance pane renders its colour rows from this list, so the palette is
/// spelled once — it replaced a `Map<String, String>` of key to label that the
/// search index would otherwise have had to copy.
@immutable
class ThemeColorSetting {
  const ThemeColorSetting(this.key, this.field);

  /// The `ThemeConfig` key, e.g. `surface_hover`.
  final String key;

  final SettingsField field;
}

SettingsField _color(String key, String label, String description) =>
    shellField(
      'theme.$key',
      label,
      section: 'Appearance',
      description: description,
      tags: const ['colour', 'color', 'palette', 'theme'],
    );

/// A hardware pane — one of the first five sidebar entries. These are lists of
/// whatever the machine happens to have rather than tables of named fields, so
/// the entry carries no id and the result jumps to the pane itself.
SettingsField _pane(
  String category,
  String paneLabel,
  String label, {
  required String description,
  List<String> tags = const <String>[],
}) => SettingsField(
  id: '',
  label: label,
  section: paneLabel,
  route: SettingsRoute(category: category),
  description: description,
  tags: tags,
);

/// A Shell category with no single row to land on — the collections.
SettingsField _shellPane(
  String section,
  String label, {
  required String description,
  List<String> tags = const <String>[],
}) => shellField(
  '',
  label,
  section: section,
  description: description,
  tags: tags,
);

/// The index.
abstract final class SettingsCatalog {
  // -------------------------------------------------------------------------
  // Shell › Appearance
  // -------------------------------------------------------------------------

  static final themePicker = _shellPane(
    'Appearance',
    'Theme',
    description:
        'Pick one of the shipped palettes or one of your own, and duplicate a '
        'shipped one to edit it.',
    tags: const [
      'colour',
      'color',
      'palette',
      'dark',
      'light',
      'dracula',
      'glassy',
      'midnight',
      'carbon',
      'forest',
      'skin',
      'style',
    ],
  );

  static final font = shellField(
    'theme.font',
    'Font',
    section: 'Appearance',
    description: 'The font family every panel, popup and overlay is set in.',
    tags: const ['typeface', 'typography', 'family', 'text'],
  );

  static final fontSize = shellField(
    'theme.font_size',
    'Font size',
    section: 'Appearance',
    description:
        "The size of the shell's body text; every other size keeps its "
        'proportion either side of it.',
    tags: const ['type', 'text', 'scale', 'bigger', 'smaller', 'zoom'],
  );

  static final panelGradient = shellField(
    'theme.panel_gradient',
    'Panel gradient',
    section: 'Appearance',
    description:
        'Fades the bar from the accent across to the panel background instead '
        'of painting it flat.',
    tags: const ['bar', 'taskbar', 'fade', 'flat'],
  );

  static final panelMargin = shellField(
    'theme.panel_margin',
    'Panel margin',
    section: 'Appearance',
    description:
        'Floats the bar off the screen edges. The gap is real — windows will '
        'not tile into it.',
    tags: const ['bar', 'taskbar', 'float', 'gap', 'inset', 'spacing'],
  );

  static final panelRadius = shellField(
    'theme.panel_radius',
    'Panel corner radius',
    section: 'Appearance',
    description: 'How far the bar’s corners are rounded.',
    tags: const ['bar', 'taskbar', 'rounded', 'corners'],
  );

  static final panelBorderWidth = shellField(
    'theme.panel_border_width',
    'Panel border width',
    section: 'Appearance',
    description: 'The rim drawn around the bar. Zero draws none.',
    tags: const ['bar', 'taskbar', 'outline', 'rim', 'stroke'],
  );

  static final popupRadius = shellField(
    'theme.popup_radius',
    'Popup corner radius',
    section: 'Appearance',
    description: 'How far a menu, flyout or on-screen indicator is rounded.',
    tags: const ['menu', 'card', 'rounded', 'corners'],
  );

  static final popupGap = shellField(
    'theme.popup_gap',
    'Popup gap from bar',
    section: 'Appearance',
    description:
        'How far a menu sits off the bar it opens from. Zero attaches it flush.',
    tags: const ['menu', 'card', 'attach', 'spacing', 'offset'],
  );

  static final popupAttachRadius = shellField(
    'theme.popup_attach_radius',
    'Popup join flare',
    section: 'Appearance',
    description:
        'Sweeps an attached menu’s two joining corners outward into the '
        'bar. Unread at any gap above zero.',
    tags: const ['menu', 'card', 'attach', 'fillet', 'curve'],
  );

  static final popupBorderWidth = shellField(
    'theme.popup_border_width',
    'Popup border width',
    section: 'Appearance',
    description: 'The rim around a menu card. Zero draws none.',
    tags: const ['menu', 'card', 'outline', 'rim', 'stroke'],
  );

  static final popupShadowBlur = shellField(
    'theme.popup_shadow_blur',
    'Popup shadow blur',
    section: 'Appearance',
    description: 'How soft the shadow under a menu card is.',
    tags: const ['menu', 'card', 'drop shadow', 'elevation', 'depth'],
  );

  static final popupShadowSpread = shellField(
    'theme.popup_shadow_spread',
    'Popup shadow spread',
    section: 'Appearance',
    description:
        'How far the shadow under a menu card reaches before blurring.',
    tags: const ['menu', 'card', 'drop shadow', 'elevation', 'depth'],
  );

  static final popupShadowOffsetX = shellField(
    'theme.popup_shadow_offset_x',
    'Popup shadow offset X',
    section: 'Appearance',
    description: 'How far sideways a menu card’s shadow is cast.',
    tags: const ['menu', 'card', 'drop shadow', 'horizontal'],
  );

  static final popupShadowOffsetY = shellField(
    'theme.popup_shadow_offset_y',
    'Popup shadow offset Y',
    section: 'Appearance',
    description: 'How far down a menu card’s shadow is cast.',
    tags: const ['menu', 'card', 'drop shadow', 'vertical'],
  );

  static final popupAnimation = shellField(
    'theme.popup_animation',
    'Popup animation',
    section: 'Appearance',
    description:
        'How a menu card arrives — and, played backwards, how it leaves.',
    tags: const ['menu', 'motion', 'transition', 'slide', 'fade', 'grow'],
  );

  /// The palette, in the order the Appearance pane draws it.
  static final List<ThemeColorSetting> themeColors = [
    ThemeColorSetting(
      'accent',
      _color('accent', 'Accent', 'The highlight colour used throughout.'),
    ),
    ThemeColorSetting(
      'foreground',
      _color('foreground', 'Foreground', 'Text and icons on the bar.'),
    ),
    ThemeColorSetting(
      'surface_hover',
      _color(
        'surface_hover',
        'Surface (hover)',
        'The wash behind a control the pointer is over.',
      ),
    ),
    ThemeColorSetting(
      'surface_pressed',
      _color(
        'surface_pressed',
        'Surface (pressed)',
        'The wash behind a control being pressed.',
      ),
    ),
    ThemeColorSetting(
      'workspace_background',
      _color(
        'workspace_background',
        'Workspace background',
        'The fill behind a workspace button.',
      ),
    ),
    ThemeColorSetting(
      'popup_background',
      _color(
        'popup_background',
        'Popup background',
        'The fill of a menu, flyout or overlay panel.',
      ),
    ),
    ThemeColorSetting(
      'popup_foreground',
      _color(
        'popup_foreground',
        'Popup foreground',
        'Text and icons inside a menu or overlay.',
      ),
    ),
    ThemeColorSetting(
      'control_surface',
      _color(
        'control_surface',
        'Control surface',
        'The fill of a field, button or dropdown.',
      ),
    ),
    ThemeColorSetting(
      'slider_track',
      _color(
        'slider_track',
        'Slider track',
        'The unfilled part of a volume or brightness slider.',
      ),
    ),
    ThemeColorSetting(
      'muted',
      _color(
        'muted',
        'Muted text',
        'Hints, placeholders and secondary labels.',
      ),
    ),
    ThemeColorSetting(
      'divider',
      _color('divider', 'Divider', 'Hairlines between sections and rows.'),
    ),
    ThemeColorSetting(
      'panel_background',
      _color(
        'panel_background',
        'Panel background',
        'The bar’s own fill. Its alpha is what makes the bar see-through.',
      ),
    ),
    ThemeColorSetting(
      'panel_border',
      _color('panel_border', 'Panel border', 'The rim drawn around the bar.'),
    ),
    ThemeColorSetting(
      'popup_border',
      _color(
        'popup_border',
        'Popup border',
        'The rim drawn around a menu card.',
      ),
    ),
    ThemeColorSetting(
      'popup_shadow_color',
      _color(
        'popup_shadow_color',
        'Popup shadow',
        'The shadow under a menu card. Fully transparent turns it off.',
      ),
    ),
    ThemeColorSetting(
      'scrim',
      _color(
        'scrim',
        'Overlay scrim',
        'The wash over the desktop behind a full-screen overlay.',
      ),
    ),
  ];

  // -------------------------------------------------------------------------
  // Shell › Module Settings
  //
  // The id *is* the config path — `modules.dart` splits it rather than being
  // handed one, so a key and the row that edits it cannot disagree.
  // -------------------------------------------------------------------------

  static final workspacesShowAppIcons = _module(
    'modules.workspaces.show_app_icons',
    'Show app icons',
    'Draws the icons of what is open on each workspace button.',
    const ['workspace', 'icons', 'taskbar'],
  );
  static final workspacesIconSize = _module(
    'modules.workspaces.icon_size',
    'Icon size',
    'How large the per-workspace app icons are drawn.',
    const ['workspace', 'icons'],
  );
  static final workspacesMaxIcons = _module(
    'modules.workspaces.max_icons',
    'Max icons per workspace',
    'How many app icons one workspace button will show before it stops.',
    const ['workspace', 'icons', 'limit'],
  );
  static final workspacesFlashUrgent = _module(
    'modules.workspaces.flash_urgent',
    'Flash urgent workspaces',
    'Breathes the accent colour in a workspace button while something on it '
        'is demanding attention.',
    const ['workspace', 'urgent', 'attention', 'alert', 'blink', 'pulse'],
  );
  static final workspacesUrgentFlashSeconds = _module(
    'modules.workspaces.urgent_flash_seconds',
    'Urgent flash period (seconds)',
    'How long one breath of the urgency flash takes.',
    const ['workspace', 'urgent', 'speed', 'blink'],
  );

  static final weatherLocation = _module(
    'modules.weather.location',
    'Location',
    'Which place the weather is reported for. Left automatic, it is looked up '
        'from your IP address.',
    const ['weather', 'city', 'place', 'latitude', 'longitude', 'where'],
  );
  static final weatherUnit = _module(
    'modules.weather.unit',
    'Unit',
    'Whether temperatures are reported in Fahrenheit or Celsius.',
    const ['weather', 'temperature', 'celsius', 'fahrenheit', 'metric'],
  );
  static final weatherRefreshMinutes = _module(
    'modules.weather.refresh_minutes',
    'Refresh (minutes)',
    'How often a new forecast is fetched.',
    const ['weather', 'interval', 'update', 'poll'],
  );

  static final batteryPollSeconds = _module(
    'modules.battery.poll_seconds',
    'Poll (seconds)',
    'How often the battery level is re-read.',
    const ['battery', 'power', 'interval', 'charge'],
  );

  static final clockShowDate = _module(
    'modules.clock.show_date',
    'Show date',
    'Puts the date beside the time in the bar.',
    const ['clock', 'time', 'date', 'calendar'],
  );

  static final mediaPlayerMaxTextWidth = _module(
    'modules.media_player.max_text_width',
    'Max text width',
    'How wide the track title may get in the bar before it scrolls.',
    const ['media', 'music', 'mpris', 'marquee', 'title'],
  );

  static final systemTrayIconSize = _module(
    'modules.system_tray.icon_size',
    'Icon size',
    'How large each tray icon is drawn.',
    const ['tray', 'systray', 'notification area', 'icons'],
  );
  static final systemTrayCollapsedOverlap = _module(
    'modules.system_tray.collapsed_overlap',
    'Collapsed overlap',
    'How far tray icons overlap each other at rest.',
    const ['tray', 'systray', 'spacing', 'condensed'],
  );
  static final systemTrayExpandedSpacing = _module(
    'modules.system_tray.expanded_spacing',
    'Expanded spacing',
    'The gap between tray icons once the strip is hovered.',
    const ['tray', 'systray', 'spacing'],
  );
  static final systemTrayHiddenItems = _module(
    'modules.system_tray.hidden_items',
    'Hidden items',
    'Tray applications to keep out of the strip, by id or title.',
    const ['tray', 'systray', 'hide', 'ignore', 'blocklist'],
  );

  static final dockIconSize = _module(
    'modules.dock.icon_size',
    'Icon size',
    'How large each dock icon is drawn.',
    const ['dock', 'launcher', 'icons', 'taskbar'],
  );
  static final dockShowAppDirectory = _module(
    'modules.dock.show_app_directory',
    'Show app directory',
    'Puts the all-applications button on the dock.',
    const ['dock', 'launcher', 'apps', 'menu'],
  );
  static final dockApps = _module(
    'modules.dock.apps',
    'Apps',
    'Which applications are pinned to the dock, in order.',
    const ['dock', 'pinned', 'favourites', 'favorites', 'launcher'],
  );

  static final systemMonitorPollSeconds = _module(
    'modules.system_monitor.poll_seconds',
    'Poll (seconds)',
    'How often CPU, memory, temperature and network are sampled.',
    const ['monitor', 'cpu', 'memory', 'interval', 'stats'],
  );
  static final systemMonitorTempUnit = _module(
    'modules.system_monitor.temp_unit',
    'Temperature unit',
    'Whether temperatures are reported in Celsius or Fahrenheit.',
    const ['monitor', 'temperature', 'celsius', 'fahrenheit', 'thermal'],
  );
  static final systemMonitorHistorySamples = _module(
    'modules.system_monitor.history_samples',
    'Graph history (samples)',
    'How many samples the monitor graphs keep.',
    const ['monitor', 'graph', 'chart', 'history'],
  );
  static final systemMonitorCpuPercentMode = _module(
    'modules.system_monitor.cpu_percent_mode',
    'CPU percentages',
    'Whether a process’s CPU figure is a share of the whole machine or of '
        'one core, as top reports it.',
    const ['monitor', 'cpu', 'processes', 'top', 'percent'],
  );
  static final systemMonitorShowKernelThreads = _module(
    'modules.system_monitor.show_kernel_threads',
    'Show kernel threads',
    'Lists kernel threads alongside ordinary processes.',
    const ['monitor', 'processes', 'kernel', 'threads'],
  );
  static final systemMonitorConfirmKill = _module(
    'modules.system_monitor.confirm_kill',
    'Confirm before quitting a process',
    'Asks first when you end a process from the monitor.',
    const ['monitor', 'processes', 'kill', 'quit', 'confirm'],
  );

  static final networkPollSeconds = _module(
    'modules.network.poll_seconds',
    'Poll (seconds)',
    'How often the network module re-reads the connection.',
    // Deliberately not tagged "wifi": this is the bar module's poll interval,
    // and a search for wifi wants the Network pane. A tag is what a user would
    // type *looking for this row*, not every word the row is adjacent to —
    // over-tagging is how a search stops ranking.
    const ['network', 'connection', 'interval', 'status'],
  );

  static final screenshotDirectory = _module(
    'modules.screenshot.directory',
    'Save to',
    'The folder screenshots are written to.',
    const ['screenshot', 'capture', 'folder', 'directory', 'pictures'],
  );
  static final screenshotCopyToClipboard = _module(
    'modules.screenshot.copy_to_clipboard',
    'Copy to clipboard',
    'Also puts each screenshot on the clipboard, ready to paste.',
    const ['screenshot', 'clipboard', 'copy', 'paste'],
  );
  static final screenshotDelaySeconds = _module(
    'modules.screenshot.delay_seconds',
    'Delay (seconds)',
    'How long the shutter waits after you choose what to capture.',
    const ['screenshot', 'timer', 'countdown', 'delay'],
  );
  static final screenshotShowCursor = _module(
    'modules.screenshot.show_cursor',
    'Include the pointer',
    'Draws the mouse pointer into the screenshot.',
    const ['screenshot', 'cursor', 'mouse', 'pointer'],
  );

  static final recorderDirectory = _module(
    'modules.screen_recorder.directory',
    'Save to',
    'The folder screen recordings are written to.',
    const ['recording', 'screencast', 'video', 'folder', 'directory'],
  );
  static final recorderContainer = _module(
    'modules.screen_recorder.container',
    'Format',
    'The container a screen recording is written in.',
    const ['recording', 'screencast', 'video', 'mp4', 'webm', 'codec'],
  );
  static final recorderFps = _module(
    'modules.screen_recorder.fps',
    'Frames per second',
    'How many frames a second a screen recording is written at.',
    const ['recording', 'screencast', 'video', 'fps', 'framerate'],
  );
  static final recorderQuality = _module(
    'modules.screen_recorder.quality',
    'Quality (CRF, lower is better)',
    'The encoder’s constant rate factor: lower is better looking and '
        'larger.',
    const ['recording', 'screencast', 'video', 'bitrate', 'crf', 'size'],
  );
  static final recorderShowCursor = _module(
    'modules.screen_recorder.show_cursor',
    'Include the pointer',
    'Draws the mouse pointer into the recording.',
    const ['recording', 'screencast', 'cursor', 'mouse', 'pointer'],
  );

  // -------------------------------------------------------------------------
  // Shell › Panels & Layout
  // -------------------------------------------------------------------------

  static final panelHeight = shellField(
    'panels.height',
    'Height',
    section: 'Panels & Layout',
    description:
        'How thick the bar is. A larger font wants a taller bar to sit in.',
    tags: const ['bar', 'taskbar', 'panel', 'thickness', 'size'],
  );
  static final panelPaddingHorizontal = shellField(
    'panels.padding_horizontal',
    'Horizontal padding',
    section: 'Panels & Layout',
    description: 'The inset between the bar’s ends and its first module.',
    tags: const ['bar', 'taskbar', 'panel', 'spacing', 'margin'],
  );
  static final panelAnchor = shellField(
    'panels.anchor',
    'Anchor',
    section: 'Panels & Layout',
    description: 'Which screen edge the bar is pinned to.',
    tags: const [
      'bar',
      'taskbar',
      'panel',
      'top',
      'bottom',
      'left',
      'right',
      'edge',
      'position',
    ],
  );
  static final panelLayer = shellField(
    'panels.layer',
    'Layer',
    section: 'Panels & Layout',
    description:
        'How the bar stacks against application windows — background, bottom, '
        'top or overlay.',
    tags: const [
      'bar',
      'taskbar',
      'panel',
      'stacking',
      'above',
      'below',
      'z order',
    ],
  );
  static final panelModules = _shellPane(
    'Panels & Layout',
    'Panel modules',
    description:
        'Which modules each bar carries, and in which of its three slots — '
        'left, centre and right.',
    tags: const [
      'bar',
      'taskbar',
      'panel',
      'clock',
      'tray',
      'dock',
      'workspaces',
      'launcher',
      'slots',
      'layout',
      'add panel',
    ],
  );

  // -------------------------------------------------------------------------
  // Shell › Background
  // -------------------------------------------------------------------------

  static final backgroundWallpapers = _shellPane(
    'Background',
    'Wallpapers',
    description:
        'Which pictures or videos the desktop shows, including the ones this '
        'machine already ships.',
    tags: const [
      'wallpaper',
      'background',
      'desktop',
      'picture',
      'photo',
      'slideshow',
    ],
  );
  static final backgroundFit = shellField(
    'background.fit',
    'Fit',
    section: 'Background',
    description:
        'Whether the wallpaper fills the screen, fits inside it, or is drawn at '
        'its own size.',
    tags: const ['wallpaper', 'background', 'scale', 'stretch', 'crop', 'zoom'],
  );
  static final backgroundIntervalMinutes = shellField(
    'background.interval_minutes',
    'Rotation interval (minutes)',
    section: 'Background',
    description: 'How long each selected wallpaper is shown before the next.',
    tags: const [
      'wallpaper',
      'background',
      'slideshow',
      'rotate',
      'change',
      'timer',
    ],
  );

  // -------------------------------------------------------------------------
  // Shell › Desktop
  // -------------------------------------------------------------------------

  static final desktopEnabled = shellField(
    'desktop.enabled',
    'Show desktop icons',
    section: 'Desktop',
    description: 'Draws the grid of pinned applications, files and widgets.',
    tags: const ['desktop', 'icons', 'grid', 'widgets'],
  );
  static final desktopCellWidth = shellField(
    'desktop.cell_width',
    'Cell width',
    section: 'Desktop',
    description: 'How wide one cell of the desktop grid is.',
    tags: const ['desktop', 'grid', 'size', 'spacing'],
  );
  static final desktopCellHeight = shellField(
    'desktop.cell_height',
    'Cell height',
    section: 'Desktop',
    description: 'How tall one cell of the desktop grid is.',
    tags: const ['desktop', 'grid', 'size', 'spacing'],
  );
  static final desktopSpacing = shellField(
    'desktop.spacing',
    'Spacing',
    section: 'Desktop',
    description: 'The gap between one desktop cell and the next.',
    tags: const ['desktop', 'grid', 'gap', 'padding'],
  );
  static final desktopPadding = shellField(
    'desktop.padding',
    'Edge padding',
    section: 'Desktop',
    description: 'How far the grid keeps clear of the screen edges.',
    tags: const ['desktop', 'grid', 'margin', 'inset'],
  );
  static final desktopIconSize = shellField(
    'desktop.icon_size',
    'Icon size',
    section: 'Desktop',
    description: 'How large a pinned item’s icon is drawn.',
    tags: const ['desktop', 'icons', 'size'],
  );
  static final desktopShowLabels = shellField(
    'desktop.show_labels',
    'Show labels',
    section: 'Desktop',
    description: 'Writes each pinned item’s name under its icon.',
    tags: const ['desktop', 'icons', 'names', 'text', 'captions'],
  );
  static final desktopItems = _shellPane(
    'Desktop',
    'Pinned items',
    description:
        'The applications, files and folders on the desktop, and what to add.',
    tags: const ['desktop', 'icons', 'shortcuts', 'pin', 'add', 'files'],
  );

  // -------------------------------------------------------------------------
  // Shell › Lock Screen
  // -------------------------------------------------------------------------

  static final lockBackground = shellField(
    'lock.background',
    'Wallpaper',
    section: 'Lock Screen',
    description: 'The picture or video shown behind the password field.',
    tags: const ['lock', 'screensaver', 'wallpaper', 'background', 'picture'],
  );
  static final lockFit = shellField(
    'lock.fit',
    'Fit',
    section: 'Lock Screen',
    description:
        'Whether the lock wallpaper fills the screen, fits inside it, or is '
        'drawn at its own size.',
    tags: const ['lock', 'wallpaper', 'scale', 'stretch', 'crop'],
  );
  static final lockShowUsername = shellField(
    'lock.show_username',
    'Show name',
    section: 'Lock Screen',
    description: 'Puts the account’s name above the password field.',
    tags: const ['lock', 'username', 'account', 'user', 'privacy'],
  );
  static final lockBlurSigma = shellField(
    'lock.blur_sigma',
    'Blur when unlocking',
    section: 'Lock Screen',
    description:
        'How strongly the lock wallpaper blurs once the password field appears. '
        'Zero leaves it sharp.',
    tags: const ['lock', 'blur', 'wallpaper', 'password'],
  );

  // -------------------------------------------------------------------------
  // Shell › Power Button
  // -------------------------------------------------------------------------

  static final powerKeyAction = shellField(
    'power.key_action',
    'When pressed',
    section: 'Power Button',
    description:
        'What the machine’s power key does — open the power menu, or run '
        'one of its five actions directly.',
    tags: const [
      'power',
      'shutdown',
      'restart',
      'reboot',
      'sleep',
      'suspend',
      'log out',
      'lock',
      'button',
      'key',
    ],
  );
  static final powerInhibitLogind = shellField(
    'power.inhibit_logind',
    'Hold the system lock',
    section: 'Power Button',
    description:
        'Stops systemd-logind powering the machine off behind the power menu.',
    tags: const ['power', 'logind', 'systemd', 'inhibit', 'shutdown'],
  );

  // -------------------------------------------------------------------------
  // Shell › Calendar
  // -------------------------------------------------------------------------

  static final calendarWeekStart = shellField(
    'calendar.week_start',
    'Week starts on',
    section: 'Calendar',
    description: 'Whether the month grid begins each week on Sunday or Monday.',
    tags: const ['calendar', 'week', 'sunday', 'monday', 'month', 'date'],
  );

  // -------------------------------------------------------------------------
  // The hardware panes
  //
  // Lists of what the machine has rather than tables of named fields, so these
  // land on the pane and highlight nothing.
  // -------------------------------------------------------------------------

  static final List<SettingsField> _hardware = [
    _pane(
      'network',
      'Network',
      'Wi-Fi and wired networks',
      description:
          'Join a wireless network, see what this machine is connected to, and '
          'forget a saved one.',
      tags: const [
        'wifi',
        'wi-fi',
        'wireless',
        'ethernet',
        'internet',
        'connection',
        'password',
        'hotspot',
        'vpn',
      ],
    ),
    _pane(
      'bluetooth',
      'Bluetooth',
      'Bluetooth devices',
      description: 'Scan for, pair with and connect Bluetooth devices.',
      tags: const [
        'bluetooth',
        'pair',
        'headphones',
        'earbuds',
        'keyboard',
        'mouse',
        'speaker',
        'device',
      ],
    ),
    _pane(
      'display',
      'Display',
      'Displays and resolution',
      description:
          'Resolution, refresh rate, scale, rotation and how the monitors are '
          'arranged.',
      tags: const [
        'monitor',
        'screen',
        'resolution',
        'refresh rate',
        'hz',
        'scale',
        'hidpi',
        'rotate',
        'arrangement',
        'mirror',
        'brightness',
      ],
    ),
    _pane(
      'audio',
      'Audio',
      'Sound output and input',
      description:
          'Output and input devices, per-application volumes, and card '
          'profiles.',
      tags: const [
        'sound',
        'volume',
        'speaker',
        'headphones',
        'microphone',
        'mic',
        'mute',
        'pulseaudio',
        'balance',
        'profile',
      ],
    ),
    _pane(
      'keyboard',
      'Keyboard',
      'Keyboard layout',
      description:
          'The input sources this machine can switch between, and the layout '
          'in use.',
      tags: const [
        'keyboard',
        'layout',
        'input source',
        'language',
        'xkb',
        'variant',
        'qwerty',
        'dvorak',
      ],
    ),
  ];

  static SettingsField _module(
    String id,
    String label,
    String description,
    List<String> tags,
  ) => shellField(
    id,
    label,
    section: 'Module Settings',
    description: description,
    // The module's own name is always among the tags, because the group
    // heading is what a user reads the row under and it is nowhere in the
    // label: "Show date" says nothing about a clock, and "Icon size" is four
    // different rows.
    tags: tags,
  );

  /// Every entry, in the order the panes present them.
  ///
  /// Assembled here rather than concatenated from the pages, so nothing in this
  /// file imports a widget and the whole index stays testable without one.
  static final List<SettingsField> all = [
    themePicker,
    font,
    fontSize,
    panelGradient,
    panelMargin,
    panelRadius,
    panelBorderWidth,
    popupRadius,
    popupGap,
    popupAttachRadius,
    popupBorderWidth,
    popupShadowBlur,
    popupShadowSpread,
    popupShadowOffsetX,
    popupShadowOffsetY,
    popupAnimation,
    for (final colour in themeColors) colour.field,
    ...moduleFields,
    panelHeight,
    panelPaddingHorizontal,
    panelAnchor,
    panelLayer,
    panelModules,
    backgroundWallpapers,
    backgroundFit,
    backgroundIntervalMinutes,
    desktopEnabled,
    desktopCellWidth,
    desktopCellHeight,
    desktopSpacing,
    desktopPadding,
    desktopIconSize,
    desktopShowLabels,
    desktopItems,
    lockBackground,
    lockFit,
    lockShowUsername,
    lockBlurSigma,
    powerKeyAction,
    powerInhibitLogind,
    calendarWeekStart,
    ..._hardware,
  ];

  /// Every `[modules.*]` row, in the order `modules.dart` renders them.
  ///
  /// Split out because that file builds its table *from* this one — the
  /// setting's config path is its id, split on the dots.
  static final List<SettingsField> moduleFields = [
    workspacesShowAppIcons,
    workspacesIconSize,
    workspacesMaxIcons,
    workspacesFlashUrgent,
    workspacesUrgentFlashSeconds,
    weatherLocation,
    weatherUnit,
    weatherRefreshMinutes,
    batteryPollSeconds,
    clockShowDate,
    mediaPlayerMaxTextWidth,
    systemTrayIconSize,
    systemTrayCollapsedOverlap,
    systemTrayExpandedSpacing,
    systemTrayHiddenItems,
    dockIconSize,
    dockShowAppDirectory,
    dockApps,
    systemMonitorPollSeconds,
    systemMonitorTempUnit,
    systemMonitorHistorySamples,
    systemMonitorCpuPercentMode,
    systemMonitorShowKernelThreads,
    systemMonitorConfirmKill,
    networkPollSeconds,
    screenshotDirectory,
    screenshotCopyToClipboard,
    screenshotDelaySeconds,
    screenshotShowCursor,
    recorderDirectory,
    recorderContainer,
    recorderFps,
    recorderQuality,
    recorderShowCursor,
  ];

  /// [all], folded to lower case once.
  ///
  /// Lazy, so a shell whose user never opens the settings overlay builds none
  /// of it — `world_cities.dart`'s trick, which is `SearchableApp`'s.
  static final List<SearchableSetting> searchable = [
    for (final field in all) SearchableSetting(field),
  ];
}
