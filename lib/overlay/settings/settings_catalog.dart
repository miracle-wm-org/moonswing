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

import 'package:moonswing/overlay/settings/settings_search.dart';
import 'package:moonswing/overlay/settings_route.dart';

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

  static final themeName = shellField(
    'theme.name',
    'Name',
    section: 'Appearance',
    description:
        'What the active theme is called in the picker. Renaming a shipped '
        'theme saves a copy of it under the new name.',
    tags: const ['rename', 'title', 'label', 'theme'],
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

  static final popupAnimationDuration = shellField(
    'theme.popup_animation_duration',
    'Popup animation duration',
    section: 'Appearance',
    description:
        'How long that animation runs, in milliseconds. The exit is shorter.',
    tags: const ['menu', 'motion', 'transition', 'speed', 'timing', 'ms'],
  );

  static final overlayAnimation = shellField(
    'theme.overlay_animation',
    'Overlay animation',
    section: 'Appearance',
    description:
        'How a full-screen overlay arrives — and, played backwards, how it '
        'leaves.',
    tags: const [
      'settings', 'launcher', 'motion', 'transition', 'fade', 'scale', 'rise',
      'flip', 'zoom',
    ],
  );

  static final overlayAnimationCurve = shellField(
    'theme.overlay_animation_curve',
    'Overlay animation curve',
    section: 'Appearance',
    description:
        'The easing that animation is paced on, from linear to elastic.',
    tags: const [
      'settings', 'launcher', 'motion', 'easing', 'curve', 'bounce',
      'overshoot', 'elastic',
    ],
  );

  static final overlayAnimationDuration = shellField(
    'theme.overlay_animation_duration',
    'Overlay animation duration',
    section: 'Appearance',
    description: 'How long that animation runs, in milliseconds.',
    tags: const [
      'settings', 'launcher', 'motion', 'speed', 'timing', 'ms',
    ],
  );

  static final overlayAnimationExitRatio = shellField(
    'theme.overlay_animation_exit_ratio',
    'Overlay exit ratio',
    section: 'Appearance',
    description:
        'What fraction of the entrance the exit takes. Below 1 leaves faster '
        'than it arrived.',
    tags: const [
      'settings', 'launcher', 'motion', 'timing', 'exit', 'close', 'dismiss',
    ],
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
      'notification_badge',
      _color(
        'notification_badge',
        'Notification badge',
        'The colour an unread notification is announced in — the floating '
            'card, the bell’s count and the dot on an unread message.',
      ),
    ),
    ThemeColorSetting(
      'notification_badge_foreground',
      _color(
        'notification_badge_foreground',
        'Notification badge text',
        'Text and glyphs drawn on the notification badge colour.',
      ),
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
  static final workspacesShowPolicyToggle = _module(
    'modules.workspaces.show_policy_toggle',
    'Tiling/floating toggle',
    "Puts the rows that switch a workspace between tiling and floating the "
        "windows opened on it next in that workspace button's right-click "
        'menu.',
    const [
      'workspace',
      'tile',
      'tiling',
      'float',
      'floating',
      'policy',
      'placement',
      'layout',
      'menu',
      'right-click',
    ],
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
  static final clockTimerSound = _module(
    'modules.clock.timer_sound',
    'Timer sound',
    'What rings when a countdown reaches zero.',
    // Tagged for "timer" and "alarm" as well as "clock", because a user
    // looking for this types what ran out rather than what module owns it.
    const [
      'timer',
      'alarm',
      'countdown',
      'sound',
      'ding',
      'clock',
      'silent',
    ],
  );
  static final clockTimerVolume = _module(
    'modules.clock.timer_volume',
    'Timer volume',
    'How loud the timer alarm is, from 0 to 1.',
    const ['timer', 'alarm', 'volume', 'sound', 'loud', 'quiet'],
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

  static final notificationsSound = _module(
    'modules.notifications.sound',
    'Notification sound',
    'What plays when a notification arrives. One of the shipped sounds — '
        'chime, ping, glass, bell, knock — the name of a sound from the '
        'system’s sound theme, a path to a sound file, or none for silence.',
    const [
      'notifications',
      'sound',
      'chime',
      'audio',
      'alert',
      'bell',
      'ping',
      'noise',
      'silent',
    ],
  );
  static final notificationsSoundVolume = _module(
    'modules.notifications.sound_volume',
    'Notification sound volume',
    'How loud that sound plays, from 0 to 1. It does not touch the system '
        'volume.',
    const ['notifications', 'sound', 'volume', 'loud', 'quiet', 'chime'],
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
  static final screenshotShutterSound = _module(
    'modules.screenshot.shutter_sound',
    'Shutter sound',
    'What plays when a screenshot has been saved.',
    const [
      'screenshot',
      'shutter',
      'sound',
      'click',
      'camera',
      'audio',
      'silent',
    ],
  );
  static final screenshotShutterVolume = _module(
    'modules.screenshot.shutter_volume',
    'Shutter volume',
    'How loud the shutter is, from 0 to 1.',
    const ['screenshot', 'shutter', 'volume', 'sound', 'loud', 'quiet'],
  );
  static final screenshotShowCursor = _module(
    'modules.screenshot.show_cursor',
    'Include the pointer',
    'Draws the mouse pointer into the screenshot.',
    const ['screenshot', 'cursor', 'mouse', 'pointer'],
  );

  static final githubRefreshSeconds = _module(
    'modules.github.refresh_seconds',
    'Check every (seconds)',
    'How often the notification list is re-read. GitHub enforces a floor of a '
        'minute, and asks for longer when it is busy.',
    const ['github', 'notifications', 'refresh', 'poll', 'interval'],
  );
  static final githubShowCount = _module(
    'modules.github.show_count',
    'Show the unread count',
    'Puts the number of unread notifications beside the mark in the bar.',
    const ['github', 'notifications', 'count', 'badge'],
  );
  static final githubParticipatingOnly = _module(
    'modules.github.participating_only',
    'Only what involves you',
    'Lists threads you are mentioned in, assigned to or asked to review, '
        'rather than everything you watch.',
    const ['github', 'notifications', 'mention', 'review', 'participating'],
  );
  static final githubIncludeRead = _module(
    'modules.github.include_read',
    'Include read notifications',
    'Keeps threads in the list after they have been marked read.',
    const ['github', 'notifications', 'read', 'history'],
  );
  static final githubMarkReadOnOpen = _module(
    'modules.github.mark_read_on_open',
    'Mark read when opened',
    'Marks a notification read as it opens in the browser, the way clicking '
        'one on github.com does.',
    const ['github', 'notifications', 'read', 'open', 'browser'],
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

  // -------------------------------------------------------------------------
  // Window Manager (miracle-wm's own configuration)
  // -------------------------------------------------------------------------
  //
  // These name rows in a *different* file from every entry above: miracle's
  // configuration is the compositor's, read and written through
  // `libmiracle-wm-c` rather than through `ConfigStore`. They are catalogued
  // here all the same, because the index is the settings overlay's index and a
  // user searching for "gaps" or "action key" is not thinking about which
  // process owns the file.

  static final miracleTerminal = miracleField(
    'miracle.terminal',
    'Terminal',
    section: 'General',
    description:
        'The terminal emulator the compositor\'s own terminal binding '
        'launches. Left empty, miracle picks the first one it can find.',
    tags: const [
      'console', 'shell', 'kitty', 'alacritty', 'gnome-terminal',
      'command',
    ],
  );

  static final miracleActionKey = miracleField(
    'miracle.primary_modifier',
    'Action Key',
    section: 'General',
    description:
        'The modifier every one of miracle\'s built-in bindings is built '
        'on — the Super key unless you change it.',
    tags: const [
      'modifier', 'super', 'meta', 'windows', 'logo', 'alt', 'mod',
      'shortcut', 'keybind',
    ],
  );

  static final miracleMoveModifier = miracleField(
    'miracle.move_modifier',
    'Move modifier',
    section: 'General',
    description:
        'The modifier held down to move a window with the pointer.',
    tags: const ['modifier', 'drag', 'window', 'pointer', 'mouse'],
  );

  static final miraclePrimaryButton = miracleField(
    'miracle.primary_button',
    'Primary mouse button',
    section: 'General',
    description:
        'Which physical button miracle\'s pointer bindings count as the '
        'primary one. Set by plugins rather than by the configuration '
        'file, so it is not written when you save.',
    tags: const ['mouse', 'button', 'click', 'left', 'right', 'pointer'],
  );

  static final miracleBackAndForth = miracleField(
    'miracle.workspace_back_and_forth',
    'Switch back and forth',
    section: 'General',
    description:
        'Selecting the workspace you are already on returns you to the '
        'previous one.',
    tags: const ['workspace', 'toggle', 'previous', 'switch', 'desktop'],
  );

  static final miracleResizeJump = miracleField(
    'miracle.resize_jump',
    'Resize step',
    section: 'General',
    description:
        'How many pixels one press of a resize binding moves a window '
        'edge by.',
    tags: const ['resize', 'pixels', 'step', 'jump', 'keyboard', 'window'],
  );

  static final miracleBackgroundColor = miracleField(
    'miracle.background_color',
    'Background colour',
    section: 'General',
    description:
        'The colour the compositor clears the screen to, behind every '
        'window and behind the wallpaper. Always opaque.',
    tags: const [
      'colour', 'color', 'clear', 'desktop', 'wallpaper',
      'backdrop',
    ],
  );

  static final miracleInnerGapsX = miracleField(
    'miracle.inner_gaps_x',
    'Inner gap, horizontal',
    section: 'Gaps & Borders',
    description:
        'The horizontal space left between two windows sitting side by '
        'side.',
    tags: const ['gap', 'spacing', 'tiling', 'padding', 'window', 'margin'],
  );

  static final miracleInnerGapsY = miracleField(
    'miracle.inner_gaps_y',
    'Inner gap, vertical',
    section: 'Gaps & Borders',
    description:
        'The vertical space left between two windows stacked one above '
        'the other.',
    tags: const ['gap', 'spacing', 'tiling', 'padding', 'window', 'margin'],
  );

  static final miracleOuterGapsX = miracleField(
    'miracle.outer_gaps_x',
    'Outer gap, horizontal',
    section: 'Gaps & Borders',
    description:
        'The space left between the tiled windows and the left and '
        'right screen edges.',
    tags: const ['gap', 'spacing', 'tiling', 'edge', 'screen', 'margin'],
  );

  static final miracleOuterGapsY = miracleField(
    'miracle.outer_gaps_y',
    'Outer gap, vertical',
    section: 'Gaps & Borders',
    description:
        'The space left between the tiled windows and the top and '
        'bottom screen edges.',
    tags: const ['gap', 'spacing', 'tiling', 'edge', 'screen', 'margin'],
  );

  static final miracleBorderSize = miracleField(
    'miracle.border.size',
    'Border thickness',
    section: 'Gaps & Borders',
    description:
        'How thick a line miracle draws around each window. Zero draws '
        'none.',
    tags: const ['border', 'outline', 'width', 'frame', 'window'],
  );

  static final miracleBorderRadius = miracleField(
    'miracle.border.radius',
    'Border corner radius',
    section: 'Gaps & Borders',
    description:
        'How far the corners of a window\'s border are rounded.',
    tags: const ['border', 'rounded', 'corners', 'radius', 'window'],
  );

  static final miracleBorderFocusColor = miracleField(
    'miracle.border.focus_color',
    'Focused border colour',
    section: 'Gaps & Borders',
    description:
        'The colour of the border around the window that currently has '
        'focus.',
    tags: const ['border', 'colour', 'color', 'active', 'focus', 'highlight'],
  );

  static final miracleBorderColor = miracleField(
    'miracle.border.color',
    'Unfocused border colour',
    section: 'Gaps & Borders',
    description:
        'The colour of the border around every window that does not '
        'have focus.',
    tags: const ['border', 'colour', 'color', 'inactive', 'unfocused'],
  );

  static final miracleAnimationsEnabled = miracleField(
    'miracle.animations_enabled',
    'Animations',
    section: 'Animations',
    description:
        'Whether miracle animates anything at all. Off means every '
        'window appears, moves and disappears instantly.',
    tags: const [
      'animation', 'motion', 'effects', 'transition', 'reduce',
      'performance',
    ],
  );

  static final miracleAnimatedEvents = miracleField(
    '',
    'Animated events',
    section: 'Animations',
    description:
        'The animation each window and workspace event plays: how long '
        'it runs, and which movements and fades are combined into it.',
    tags: const [
      'animation', 'easing', 'curve', 'slide', 'fade', 'grow',
      'shrink', 'duration', 'event',
    ],
  );

  static final miracleMouseHandedness = miracleField(
    'miracle.mouse.handedness',
    'Handedness',
    section: 'Mouse',
    description:
        'Whether the mouse is set up for a right hand or a left one.',
    tags: const ['left', 'right', 'hand', 'buttons', 'swap', 'southpaw'],
  );

  static final miracleMouseAcceleration = miracleField(
    'miracle.mouse.acceleration',
    'Pointer acceleration',
    section: 'Mouse',
    description:
        'How pointer movement is filtered: flat, or adaptive to how '
        'fast you move.',
    tags: const [
      'acceleration', 'profile', 'pointer', 'speed', 'flat',
      'adaptive',
    ],
  );

  static final miracleMouseAccelerationBias = miracleField(
    'miracle.mouse.acceleration_bias',
    'Acceleration bias',
    section: 'Mouse',
    description:
        'How strongly pointer movement is accelerated, from -1 '
        '(slowest) through 0 to 1.',
    tags: const ['acceleration', 'sensitivity', 'speed', 'pointer', 'bias'],
  );

  static final miracleMouseVscroll = miracleField(
    'miracle.mouse.vscroll_speed',
    'Vertical scroll speed',
    section: 'Mouse',
    description:
        'A multiplier on how far one notch of the wheel scrolls up or '
        'down.',
    tags: const ['scroll', 'wheel', 'speed', 'vertical', 'multiplier'],
  );

  static final miracleMouseHscroll = miracleField(
    'miracle.mouse.hscroll_speed',
    'Horizontal scroll speed',
    section: 'Mouse',
    description:
        'A multiplier on how far one notch of horizontal scrolling '
        'moves.',
    tags: const ['scroll', 'wheel', 'speed', 'horizontal', 'multiplier'],
  );

  static final miracleCursorScale = miracleField(
    'miracle.cursor.scale',
    'Cursor size',
    section: 'Mouse',
    description:
        'How large the pointer is drawn, as a multiple of its natural '
        'size.',
    tags: const ['cursor', 'pointer', 'size', 'scale', 'bigger', 'larger'],
  );

  static final miracleCursorFocusMode = miracleField(
    'miracle.cursor.focus_mode',
    'Focus follows',
    section: 'Mouse',
    description:
        'Whether moving the pointer over a window focuses it, or '
        'whether you have to click.',
    tags: const ['focus', 'hover', 'click', 'sloppy', 'follows', 'mouse'],
  );

  static final miracleDragAndDrop = miracleField(
    'miracle.drag_and_drop.enabled',
    'Drag windows',
    section: 'Mouse',
    description:
        'Whether a window can be picked up and moved with the pointer '
        'at all.',
    tags: const ['drag', 'drop', 'move', 'window', 'pointer', 'mouse'],
  );

  static final miracleDragModifiers = miracleField(
    'miracle.drag_and_drop.modifiers',
    'Drag modifiers',
    section: 'Mouse',
    description:
        'The modifiers that must be held down before a drag starts.',
    tags: const ['drag', 'modifier', 'super', 'alt', 'ctrl', 'shift', 'move'],
  );

  static final miracleTouchpadDisableTyping = miracleField(
    'miracle.touchpad.disable_while_typing',
    'Disable while typing',
    section: 'Touchpad',
    description:
        'Ignores the touchpad for a moment after each keystroke, so a '
        'palm cannot move the pointer mid-sentence.',
    tags: const ['palm', 'rejection', 'typing', 'keyboard', 'accidental'],
  );

  static final miracleTouchpadDisableMouse = miracleField(
    'miracle.touchpad.disable_with_external_mouse',
    'Disable with a mouse plugged in',
    section: 'Touchpad',
    description:
        'Turns the touchpad off entirely whenever an external mouse is '
        'connected.',
    tags: const ['external', 'mouse', 'usb', 'disable', 'laptop'],
  );

  static final miracleTouchpadTapToClick = miracleField(
    'miracle.touchpad.tap_to_click',
    'Tap to click',
    section: 'Touchpad',
    description:
        'A tap on the touchpad counts as a click, without pressing it '
        'down.',
    tags: const ['tap', 'click', 'touch', 'gesture'],
  );

  static final miracleTouchpadMiddleEmulation = miracleField(
    'miracle.touchpad.middle_mouse_button_emulation',
    'Middle-click emulation',
    section: 'Touchpad',
    description:
        'Pressing the left and right buttons together counts as a '
        'middle click.',
    tags: const ['middle', 'button', 'emulation', 'paste', 'three'],
  );

  static final miracleTouchpadClickMode = miracleField(
    'miracle.touchpad.click_mode',
    'Click mode',
    section: 'Touchpad',
    description:
        'How the touchpad decides which button a press is: by which '
        'area you pressed, or by how many fingers were down.',
    tags: const ['click', 'button', 'area', 'finger', 'count', 'right click'],
  );

  static final miracleTouchpadScrollMode = miracleField(
    'miracle.touchpad.scroll_mode',
    'Scroll mode',
    section: 'Touchpad',
    description:
        'How the touchpad scrolls: two fingers, along an edge, or while '
        'a button is held.',
    tags: const ['scroll', 'two finger', 'edge', 'button', 'gesture'],
  );

  static final miracleTouchpadAccelerationBias = miracleField(
    'miracle.touchpad.acceleration_bias',
    'Acceleration bias',
    section: 'Touchpad',
    description:
        'How strongly touchpad movement is accelerated, from -1 '
        '(slowest) through 0 to 1.',
    tags: const ['acceleration', 'sensitivity', 'speed', 'pointer', 'bias'],
  );

  static final miracleTouchpadVscroll = miracleField(
    'miracle.touchpad.vscroll_speed',
    'Vertical scroll speed',
    section: 'Touchpad',
    description:
        'A multiplier on how far a vertical scroll gesture moves the '
        'page.',
    tags: const ['scroll', 'speed', 'vertical', 'multiplier', 'gesture'],
  );

  static final miracleTouchpadHscroll = miracleField(
    'miracle.touchpad.hscroll_speed',
    'Horizontal scroll speed',
    section: 'Touchpad',
    description:
        'A multiplier on how far a horizontal scroll gesture moves the '
        'page.',
    tags: const ['scroll', 'speed', 'horizontal', 'multiplier', 'gesture'],
  );

  static final miracleKeymapEnabled = miracleField(
    'miracle.keymap.enabled',
    'Set the keyboard layout',
    section: 'Keyboard',
    description:
        'Whether miracle applies a layout of its own. Off leaves the '
        'system default in place.',
    tags: const ['keymap', 'layout', 'xkb', 'language', 'default'],
  );

  static final miracleKeymapLanguage = miracleField(
    'miracle.keymap.language',
    'Layout',
    section: 'Keyboard',
    description:
        'The XKB layout code miracle applies, e.g. `us`, `de`, `fr`.',
    tags: const [
      'keymap', 'xkb', 'language', 'country', 'us', 'de', 'fr',
      'layout',
    ],
  );

  static final miracleKeymapVariant = miracleField(
    'miracle.keymap.variant',
    'Variant',
    section: 'Keyboard',
    description:
        'The XKB variant of the layout, e.g. `dvorak` or `colemak`. '
        'Empty for the layout\'s default.',
    tags: const ['keymap', 'xkb', 'variant', 'dvorak', 'colemak', 'intl'],
  );

  static final miracleKeymapOptions = miracleField(
    'miracle.keymap.options',
    'XKB options',
    section: 'Keyboard',
    description:
        'Extra XKB options applied on top of the layout, e.g. '
        '`caps:swapescape` or `compose:ralt`.',
    tags: const [
      'xkb', 'option', 'caps', 'escape', 'compose', 'terminate',
      'swap',
    ],
  );

  static final miracleKeyRepeatDelay = miracleField(
    'miracle.key_repeat_delay',
    'Repeat delay',
    section: 'Keyboard',
    description:
        'How long a key must be held before it starts repeating, in '
        'milliseconds.',
    tags: const ['repeat', 'delay', 'hold', 'keyboard', 'milliseconds'],
  );

  static final miracleKeyRepeatRate = miracleField(
    'miracle.key_repeat_rate',
    'Repeat rate',
    section: 'Keyboard',
    description:
        'How many times a second a held key repeats.',
    tags: const ['repeat', 'rate', 'speed', 'keyboard', 'characters'],
  );

  static final miracleMagnifierEnabled = miracleField(
    'miracle.magnifier.enabled',
    'Magnifier',
    section: 'Accessibility',
    description:
        'Whether the screen magnifier can be turned on.',
    tags: const [
      'zoom', 'magnify', 'accessibility', 'vision', 'low vision',
      'loupe',
    ],
  );

  static final miracleMagnifierScale = miracleField(
    'miracle.magnifier.scale',
    'Magnification',
    section: 'Accessibility',
    description:
        'How far the magnifier zooms in.',
    tags: const ['zoom', 'magnify', 'scale', 'accessibility'],
  );

  static final miracleMagnifierScaleIncrement = miracleField(
    'miracle.magnifier.scale_increment',
    'Magnification step',
    section: 'Accessibility',
    description:
        'How much one press of a zoom binding changes the magnification '
        'by.',
    tags: const ['zoom', 'magnify', 'step', 'increment', 'keybind'],
  );

  static final miracleMagnifierWidth = miracleField(
    'miracle.magnifier.width',
    'Magnifier width',
    section: 'Accessibility',
    description:
        'The magnifier window\'s width, in pixels.',
    tags: const ['zoom', 'magnify', 'size', 'width', 'pixels'],
  );

  static final miracleMagnifierHeight = miracleField(
    'miracle.magnifier.height',
    'Magnifier height',
    section: 'Accessibility',
    description:
        'The magnifier window\'s height, in pixels.',
    tags: const ['zoom', 'magnify', 'size', 'height', 'pixels'],
  );

  static final miracleMagnifierSizeIncrement = miracleField(
    'miracle.magnifier.size_increment',
    'Magnifier size step',
    section: 'Accessibility',
    description:
        'How many pixels one press of a resize binding changes the '
        'magnifier by.',
    tags: const ['zoom', 'magnify', 'size', 'step', 'increment'],
  );

  static final miracleHoverClickEnabled = miracleField(
    'miracle.hover_click.enabled',
    'Hover click',
    section: 'Accessibility',
    description:
        'Clicks by resting the pointer still, for anybody who cannot '
        'press a button.',
    tags: const ['dwell', 'hover', 'click', 'accessibility', 'rest', 'motor'],
  );

  static final miracleHoverClickDuration = miracleField(
    'miracle.hover_click.hover_duration',
    'Hover time',
    section: 'Accessibility',
    description:
        'How long the pointer must rest before the click is dispatched, '
        'in milliseconds.',
    tags: const ['dwell', 'hover', 'delay', 'duration', 'milliseconds'],
  );

  static final miracleHoverClickCancel = miracleField(
    'miracle.hover_click.cancel_displacement_threshold',
    'Cancel distance',
    section: 'Accessibility',
    description:
        'How far the pointer may drift, in pixels, before a pending '
        'hover click is cancelled.',
    tags: const ['dwell', 'hover', 'cancel', 'drift', 'pixels', 'threshold'],
  );

  static final miracleHoverClickReclick = miracleField(
    'miracle.hover_click.reclick_displacement_threshold',
    'Re-click distance',
    section: 'Accessibility',
    description:
        'How far the pointer must move, in pixels, before it will '
        'hover-click again.',
    tags: const [
      'dwell', 'hover', 'repeat', 'distance', 'pixels',
      'threshold',
    ],
  );

  static final miracleSecondaryClickEnabled = miracleField(
    'miracle.simulated_secondary_click.enabled',
    'Hold to right-click',
    section: 'Accessibility',
    description:
        'Holding the primary button down counts as a right click.',
    tags: const [
      'right click', 'secondary', 'hold', 'long press',
      'accessibility',
    ],
  );

  static final miracleSecondaryClickHold = miracleField(
    'miracle.simulated_secondary_click.hold_duration',
    'Hold time',
    section: 'Accessibility',
    description:
        'How long the button must be held before the right click fires, '
        'in milliseconds.',
    tags: const [
      'right click', 'secondary', 'hold', 'duration',
      'milliseconds',
    ],
  );

  static final miracleSecondaryClickThreshold = miracleField(
    'miracle.simulated_secondary_click.displacement_threshold',
    'Hold cancel distance',
    section: 'Accessibility',
    description:
        'How far the pointer may drift, in pixels, before the pending '
        'right click is cancelled.',
    tags: const [
      'right click', 'secondary', 'drift', 'cancel', 'pixels',
      'threshold',
    ],
  );

  static final miracleSlowKeysEnabled = miracleField(
    'miracle.slow_keys.enabled',
    'Slow keys',
    section: 'Accessibility',
    description:
        'Ignores a key unless it is held down long enough, so a brushed '
        'key does nothing.',
    tags: const [
      'slow', 'keys', 'accessibility', 'tremor', 'accidental',
      'hold',
    ],
  );

  static final miracleSlowKeysDuration = miracleField(
    'miracle.slow_keys.hold_duration',
    'Slow keys hold time',
    section: 'Accessibility',
    description:
        'How long a key must be held before it registers, in '
        'milliseconds.',
    tags: const ['slow', 'keys', 'hold', 'duration', 'milliseconds'],
  );

  static final miracleStickyKeysEnabled = miracleField(
    'miracle.sticky_keys.enabled',
    'Sticky keys',
    section: 'Accessibility',
    description:
        'Latches a modifier when it is pressed, so a shortcut can be '
        'typed one key at a time.',
    tags: const ['sticky', 'modifier', 'latch', 'accessibility', 'one handed'],
  );

  static final miracleStickyKeysDisable = miracleField(
    'miracle.sticky_keys.disable_on_two_keys',
    'Release on two keys',
    section: 'Accessibility',
    description:
        'Pressing two modifiers together turns sticky keys off until '
        'every key is released.',
    tags: const ['sticky', 'modifier', 'disable', 'two', 'together'],
  );

  static final miracleOutputFilterShader = miracleField(
    'miracle.output_filter.shader_path',
    'Output shader',
    section: 'Accessibility',
    description:
        'A shader run over the whole screen — a colour-blindness '
        'filter, a night tint. Empty for none.',
    tags: const [
      'shader', 'filter', 'colour', 'color', 'blind', 'invert',
      'grayscale', 'night',
    ],
  );

  static final miracleCustomBindings = miracleField(
    '',
    'Custom key bindings',
    section: 'Key Bindings',
    description:
        'Your own shortcuts: a key, the modifiers held with it, and the '
        'shell command it runs.',
    tags: const [
      'keybind', 'shortcut', 'hotkey', 'command', 'bind', 'exec',
      'launch',
    ],
  );

  static final miracleBuiltInOverrides = miracleField(
    '',
    'Built-in command overrides',
    section: 'Key Bindings',
    description:
        'Rebindings of miracle\'s own commands — closing a window, '
        'switching workspace, reloading the configuration.',
    tags: const [
      'keybind', 'shortcut', 'hotkey', 'override', 'rebind',
      'default', 'workspace',
    ],
  );

  static final miracleStartupApps = miracleField(
    '',
    'Startup applications',
    section: 'Startup',
    description:
        'The programs miracle launches once the compositor is ready, '
        'and what it does if one of them exits.',
    tags: const [
      'autostart', 'launch', 'startup', 'boot', 'login', 'restart',
      'systemd',
    ],
  );

  static final miracleEnvironmentVariables = miracleField(
    '',
    'Environment variables',
    section: 'Startup',
    description:
        'The variables miracle sets for every application it launches.',
    tags: const [
      'environment', 'variable', 'env', 'export', 'toolkit',
      'scale',
    ],
  );

  static final miracleWorkspaces = miracleField(
    '',
    'Workspaces',
    section: 'Workspaces',
    description:
        'Per-workspace settings, matched to a workspace by its number '
        'or by its name.',
    tags: const ['workspace', 'desktop', 'name', 'number', 'label'],
  );

  static final miracleIncludes = miracleField(
    '',
    'Included files',
    section: 'Includes & Plugins',
    description:
        'Other configuration files merged into this one, so a '
        'configuration can be split up.',
    tags: const ['include', 'import', 'merge', 'file', 'split', 'fragment'],
  );

  static final miraclePlugins = miracleField(
    '',
    'Plugins',
    section: 'Includes & Plugins',
    description:
        'The shared objects miracle loads at startup to extend the '
        'compositor.',
    tags: const [
      'plugin', 'extension', 'shared object', 'so', 'load',
      'addon',
    ],
  );

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
    themeName,
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
    popupAnimationDuration,
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
    ...miracleFields,
  ];

  /// Every Window Manager row, in the order the pane renders them.
  ///
  /// Split out for the same reason [moduleFields] is: it is the one block of
  /// the index that belongs to another program's configuration file, and
  /// `test/settings_search_test.dart` checks its ids and its categories against
  /// that pane rather than against the Shell one.
  static final List<SettingsField> miracleFields = [
    miracleTerminal,
    miracleActionKey,
    miracleMoveModifier,
    miraclePrimaryButton,
    miracleBackAndForth,
    miracleResizeJump,
    miracleBackgroundColor,
    miracleInnerGapsX,
    miracleInnerGapsY,
    miracleOuterGapsX,
    miracleOuterGapsY,
    miracleBorderSize,
    miracleBorderRadius,
    miracleBorderFocusColor,
    miracleBorderColor,
    miracleAnimationsEnabled,
    miracleAnimatedEvents,
    miracleMouseHandedness,
    miracleMouseAcceleration,
    miracleMouseAccelerationBias,
    miracleMouseVscroll,
    miracleMouseHscroll,
    miracleCursorScale,
    miracleCursorFocusMode,
    miracleDragAndDrop,
    miracleDragModifiers,
    miracleTouchpadDisableTyping,
    miracleTouchpadDisableMouse,
    miracleTouchpadTapToClick,
    miracleTouchpadMiddleEmulation,
    miracleTouchpadClickMode,
    miracleTouchpadScrollMode,
    miracleTouchpadAccelerationBias,
    miracleTouchpadVscroll,
    miracleTouchpadHscroll,
    miracleKeymapEnabled,
    miracleKeymapLanguage,
    miracleKeymapVariant,
    miracleKeymapOptions,
    miracleKeyRepeatDelay,
    miracleKeyRepeatRate,
    miracleMagnifierEnabled,
    miracleMagnifierScale,
    miracleMagnifierScaleIncrement,
    miracleMagnifierWidth,
    miracleMagnifierHeight,
    miracleMagnifierSizeIncrement,
    miracleHoverClickEnabled,
    miracleHoverClickDuration,
    miracleHoverClickCancel,
    miracleHoverClickReclick,
    miracleSecondaryClickEnabled,
    miracleSecondaryClickHold,
    miracleSecondaryClickThreshold,
    miracleSlowKeysEnabled,
    miracleSlowKeysDuration,
    miracleStickyKeysEnabled,
    miracleStickyKeysDisable,
    miracleOutputFilterShader,
    miracleCustomBindings,
    miracleBuiltInOverrides,
    miracleStartupApps,
    miracleEnvironmentVariables,
    miracleWorkspaces,
    miracleIncludes,
    miraclePlugins,
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
    workspacesShowPolicyToggle,
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
    notificationsSound,
    notificationsSoundVolume,
    screenshotDirectory,
    screenshotCopyToClipboard,
    screenshotDelaySeconds,
    screenshotShowCursor,
    screenshotShutterSound,
    screenshotShutterVolume,
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
