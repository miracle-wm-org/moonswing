import 'dart:async';
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: implementation_imports
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/desktop/desktop_surface.dart';
import 'package:graceful_shell/overlay/file_picker.dart';
import 'package:graceful_shell/overlay/file_picker_controller.dart';
import 'package:graceful_shell/overlay/settings_route.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/miracle_manager.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/monitor_watcher.dart';
import 'package:graceful_shell/modules/battery.dart';
import 'package:graceful_shell/modules/dock.dart';
import 'package:graceful_shell/modules/launcher.dart';
import 'package:graceful_shell/modules/sound_control.dart';
import 'package:graceful_shell/modules/clock.dart';
import 'package:graceful_shell/modules/media_player.dart';
import 'package:graceful_shell/modules/network.dart';
import 'package:graceful_shell/modules/notifications.dart';
import 'package:graceful_shell/modules/system.dart';
import 'package:graceful_shell/modules/system_monitor.dart';
import 'package:graceful_shell/modules/system_tray.dart';
import 'package:graceful_shell/modules/weather.dart';
import 'package:graceful_shell/modules/workspaces.dart';
import 'package:graceful_shell/input_trigger/input_trigger_service.dart';
import 'package:graceful_shell/input_trigger/input_trigger_store.dart';
import 'package:graceful_shell/launcher/app_index.dart';
import 'package:graceful_shell/launcher/launcher_controller.dart';
import 'package:graceful_shell/launcher/launcher_overlay.dart';
import 'package:graceful_shell/lock/lock_controller.dart';
import 'package:graceful_shell/lock/lock_screen.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/osd/osd.dart';
import 'package:graceful_shell/osd/osd_service.dart';
import 'package:graceful_shell/osd/osd_store.dart';
import 'package:graceful_shell/panel_background.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/screencast/picker_controller.dart';
import 'package:graceful_shell/screencast/picker_overlay.dart';
import 'package:graceful_shell/screencast/picker_sources.dart';
import 'package:graceful_shell/screencast/screencast_log.dart';
import 'package:graceful_shell/screencast/screencast_service.dart';
import 'package:graceful_shell/status_notifier_service.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/desktop/desktop_actions.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';
import 'package:graceful_shell/desktop/desktop_store.dart';
import 'package:graceful_shell/overlay/calendar/calendar_store.dart';
import 'package:graceful_shell/overlay/overlay.dart';
import 'package:graceful_shell/system/system_stats_store.dart';
import 'package:graceful_shell/theme/theme_provider.dart';
import 'package:graceful_shell/theme/theme_store.dart';
import 'package:graceful_shell/window_manager.dart';
import 'package:ext_session_lock/ext_session_lock.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:media_kit/media_kit.dart';
import 'package:wayland/wayland.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  Module.register(WorkspacesModule());
  Module.register(MediaPlayerModule());
  Module.register(SoundControlModule());
  Module.register(BatteryModule());
  Module.register(WeatherModule());
  Module.register(ClockModule());
  Module.register(DockModule());
  Module.register(SystemMonitorModule());
  Module.register(NotificationsModule());
  Module.register(NetworkModule());
  Module.register(SystemModule());
  Module.register(SystemTrayModule());
  Module.register(LauncherModule());

  // AppConfig.load() writes the default config on first run and applies the
  // module subtables; the shared ConfigStore then reads that same file and
  // becomes the single live source of truth the shell watches.
  final appConfig = await AppConfig.load();
  final store = await ConfigStore.initShared();

  // Seeds the shipped themes into ~/.config/graceful-shell/themes on first run
  // and resolves the one config.toml names, before anything paints.
  startThemeService(store);

  // Reads the pinned desktop icons, so the grid paints with the first frame of
  // the background surface rather than popping in a moment later. Like the
  // theme store it watches ConfigStore for its own subtree only.
  startDesktopService(store);

  await startNotificationService();
  await startStatusNotifierService();
  // Restores saved calendar tokens from disk only — no network I/O, so an
  // offline machine or an expired account cannot delay the shell coming up.
  // The first fetch happens when the user opens the calendar tab.
  await startCalendarService(appConfig.calendar);
  // Watches the default sink/source and the backlight so the on-screen
  // indicator can react to volume, mic, and brightness changes made anywhere.
  await startOsdService(appConfig.osd);
  // Configures the system stats store, but does not start it polling — the
  // first lease (the bar module, or the monitor tab being opened) does that.
  startSystemStatsService();
  // Enumerates installed applications now, while nothing is on screen, so the
  // launcher can paint the instant its shortcut fires.
  startAppIndexService();
  // Claims the xdg-desktop-portal ScreenCast backend name, so apps asking to
  // share their screen get the shell's own picker. Fails soft on a compositor
  // without ext-image-copy-capture, or with no PipeWire.
  screencastLog = (message) => debugPrint('screencast: $message');
  if (appConfig.screenshare.enabled) {
    await startScreencastService(
      picker: ScreencastPickerController.instance,
      maxFrameRate: appConfig.screenshare.maxFps,
    );
  }

  // Miracle may not be running yet (or at all). The manager keeps the shell
  // usable either way — the workspaces module offers a retry when it is absent.
  final miracle = MiracleManager();
  await miracle.connect();

  final WaylandClient waylandClient = WaylandClient();
  await waylandClient.connect();

  // Registers the shell's global shortcuts (Ctrl+Shift+S to open settings by
  // default, configurable under `[shortcuts]`) with the compositor via the
  // ext-input-trigger protocols. It binds its globals from the same registry
  // callback below; on a compositor that lacks them nothing is bound and the
  // shell is unaffected.
  final inputTriggers =
      startInputTriggerService(waylandClient, shortcuts: appConfig.shortcuts);

  // Live registry of outputs, kept current as monitors are plugged in and out.
  // The registry callbacks below stay connected for the lifetime of the client,
  // so `wl_output` globals advertised after startup are tracked too.
  final outputs = OutputTracker();
  final outputCompleters = <Completer<void>>[];
  WaylandRegistry? waylandRegistry;
  waylandRegistry = waylandClient.getRegistry(
    onGlobal: (globalName, interface, version) {
      if (interface == 'wl_output') {
        final completer = Completer<void>();
        outputCompleters.add(completer);
        outputs.add(
          globalName,
          WaylandOutput(
            waylandClient,
            waylandRegistry!.bind(globalName, interface, version),
            onDone: () {
              // `done` fires once after the initial property burst and again
              // whenever the output changes; only the first completes startup.
              if (!completer.isCompleted) completer.complete();
              outputs.markChanged();
            },
          ),
        );
      }
      // Also offer every global to the input-trigger manager, which binds the
      // registration/action managers it needs and ignores the rest.
      inputTriggers.handleGlobal(
          waylandRegistry!, globalName, interface, version);
    },
    onGlobalRemove: (globalName) => outputs.remove(globalName),
  );
  final syncCompleter = Completer<void>();
  waylandClient.sync((_) => syncCompleter.complete());
  await syncCompleter.future;
  await Future.wait(outputCompleters.map((c) => c.future));

  // The initial global burst is done. If the input-trigger managers weren't
  // among them, the compositor doesn't implement these protocols (an older Mir,
  // or not Mir) — the shortcuts silently won't work, so say so once.
  if (!inputTriggers.isRegistered) {
    debugPrint('input-trigger: compositor did not advertise the '
        'ext-input-trigger globals; global shortcuts are unavailable');
  }

  // Installs a windowing owner that handles layer-shell *and* session-lock
  // windows; it subclasses the layer-shell one, so panels/popups are unaffected.
  initSessionLock();

  // Layer-shell controllers are created from within the widget tree (see
  // [_GracefulShellRootState.initState]), not here in main(), so that the GTK
  // windowing system is fully initialized before the first surface is created.
  runWidget(GracefulShellRoot(
    appConfig: appConfig,
    store: store,
    miracle: miracle,
    outputs: outputs,
  ));
}

/// Live set of Wayland outputs, kept in sync with the compositor's `wl_output`
/// globals. Panels match against this to resolve which physical display they
/// render on. Notifies listeners when outputs are added, removed, or their
/// details (name / geometry) change, so the shell can re-match after a hotplug.
class OutputTracker extends ChangeNotifier {
  final List<WaylandOutput> outputs = [];
  final Map<int, WaylandOutput> _byGlobal = {};

  void add(int global, WaylandOutput output) {
    _byGlobal[global] = output;
    outputs.add(output);
    notifyListeners();
  }

  void remove(int global) {
    final output = _byGlobal.remove(global);
    if (output == null) return;
    outputs.remove(output);
    notifyListeners();
  }

  /// Signals that an existing output's properties changed (e.g. its `done`
  /// event delivered a new name or geometry) without the set itself changing.
  void markChanged() => notifyListeners();
}

/// Root of the widget tree. Owns the lifecycle of every layer-shell window
/// (backgrounds + panels) on every monitor: it creates them for the monitors
/// present at startup, then adds and destroys them as monitors are plugged in
/// and unplugged, and tears them all down in [dispose].
class GracefulShellRoot extends StatefulWidget {
  const GracefulShellRoot({
    super.key,
    required this.appConfig,
    required this.store,
    required this.miracle,
    required this.outputs,
  });

  /// The config captured at startup. Native layer-shell windows (panels /
  /// background) are created from this snapshot and cannot change without a
  /// restart; live values come from [store] instead.
  final AppConfig appConfig;
  final ConfigStore store;
  final MiracleManager miracle;
  final OutputTracker outputs;

  @override
  State<GracefulShellRoot> createState() => _GracefulShellRootState();
}

/// The layer-shell surfaces (optional background window plus the configured
/// panels) that belong to a single monitor.
class _MonitorSurfaces {
  _MonitorSurfaces(this.monitor, this.background, this.panels);

  final MonitorInfo monitor;
  final LayershellWindowController? background;
  final Map<String, LayershellWindowController> panels;

  /// Every native controller owned by this monitor, for teardown.
  Iterable<LayershellWindowController> get controllers => [
        if (background != null) background!,
        ...panels.values,
      ];
}

class _GracefulShellRootState extends State<GracefulShellRoot> {
  /// Surfaces keyed by a stable monitor identity ([_monitorKey]). Entries are
  /// added when a monitor is plugged in and removed when it is unplugged, so
  /// this map is the live source of truth for what the shell renders.
  final Map<String, _MonitorSurfaces> _surfaces = {};

  /// Whether a background surface should exist on each monitor. Fixed at startup
  /// (like the native window geometry) so newly-plugged monitors get a matching
  /// background.
  ///
  /// Two things want it: a wallpaper to paint, and the desktop icon grid to
  /// host. Either alone is enough — with the grid on and no wallpaper the
  /// surface is transparent and the compositor's own background shows through.
  /// [ConfigStore.needsRestart] signs this same decision.
  late final bool _hasBackgroundSurface;

  /// The on-screen indicator's windows, keyed like [_surfaces]. Unlike panels
  /// these exist only while [OsdStore] holds a request: the shell has no
  /// input-region support, so a permanently-mapped surface — however small —
  /// would sit on the overlay layer eating clicks.
  final Map<String, LayershellWindowController> _osd = {};

  /// The settings overlay window, opened by the global shortcut (Ctrl+Shift+S).
  /// Unlike the OSD there is a single instance, not one per monitor, and it
  /// takes keyboard focus. Non-null exactly while the overlay is on screen.
  LayershellWindowController? _settings;

  /// Drives the settings overlay's fade-out. Flipping true asks [SettingsOverlay]
  /// to play its exit animation and then call back into [_onSettingsClosed].
  final ValueNotifier<bool> _settingsClosing = ValueNotifier(false);

  /// The page the open (or about-to-open) settings overlay was asked for. Null
  /// is the default landing page.
  SettingsRoute? _settingsRoute;

  /// A route that arrived while an overlay was already up. The overlay seeds
  /// its tab in `initState`, so retargeting means closing and reopening; this
  /// holds the destination across those two frames.
  SettingsRoute? _pendingSettingsRoute;

  /// The file picker's window, open only while a request is outstanding — like
  /// the OSD and the screencast picker, and unlike the panels.
  LayershellWindowController? _filePicker;

  /// Monitor keys whose background surface currently takes keyboard focus for
  /// an in-place desktop rename. Empty is the normal state.
  final Set<String> _desktopKeyboard = {};

  /// The application launcher's window, shaped exactly like [_settings]: one
  /// instance, keyboard-focusing, non-null exactly while it is on screen.
  LayershellWindowController? _launcher;

  /// Drives [LauncherOverlay]'s fade-out, as [_settingsClosing] does for the
  /// settings overlay.
  final ValueNotifier<bool> _launcherClosing = ValueNotifier(false);

  /// The screen-share consent picker's window, shaped like [_launcher]. Exists
  /// only while an app's portal `Start` call is blocked awaiting a choice.
  LayershellWindowController? _screencastPicker;

  /// The request the open picker is answering, captured when the window was
  /// created — the controller clears its own `pending` the moment the user
  /// answers, but the overlay stays mounted through its fade-out.
  PickRequest? _screencastRequest;

  /// Drives [ScreencastPickerOverlay]'s fade-out.
  final ValueNotifier<bool> _screencastClosing = ValueNotifier(false);

  /// The `ext-session-lock-v1` lock, non-null exactly while the session is
  /// locked. Owned here rather than by the module that offers the Lock button
  /// because the lock spans every monitor and outlives any one panel.
  SessionLock? _sessionLock;

  /// One lock surface per monitor, keyed like [_surfaces]. Outputs without one
  /// are blanked by the compositor, so a missing entry is safe, never a leak.
  final Map<String, SessionLockWindowController> _lockWindows = {};

  late final MonitorWatcher _monitorWatcher;
  bool _syncScheduled = false;

  /// The current config the widget tree renders from. Kept in sync with
  /// [GracefulShellRoot.store] by [_onConfigChanged] so theme, panel layout,
  /// per-module options, and the background image update live. Window geometry
  /// still comes from [widget.appConfig] (the startup snapshot).
  late AppConfig _liveConfig;

  /// The panel margin currently committed to the native surfaces.
  ///
  /// Cached rather than read from [ThemeStore] at use time so [_onThemeChanged]
  /// can tell whether the value actually moved: the store notifies on every
  /// frame of a colour-picker drag, and re-committing every layer surface that
  /// often would make the bars flicker.
  int _panelMargin = 0;

  @override
  void initState() {
    super.initState();
    final appConfig = widget.appConfig;
    _liveConfig = appConfig;
    _hasBackgroundSurface =
        (appConfig.background?.entries.isNotEmpty ?? false) ||
            appConfig.desktop.enabled;
    widget.store.addListener(_onConfigChanged);
    widget.outputs.addListener(_onOutputsChanged);
    OsdStore.instance.addListener(_onOsdChanged);
    InputTriggerStore.instance.addListener(_onSettingsTriggered);
    LauncherController.instance.addListener(_onLauncherTriggered);
    ScreencastPickerController.instance.addListener(_onScreencastPickChanged);
    LockController.instance.addListener(_onLockRequested);
    SettingsController.instance.addListener(_onSettingsRouteRequested);
    FilePickerController.instance.addListener(_onFilePickRequested);
    ThemeStore.instance.addListener(_onThemeChanged);
    // startThemeService() resolved the palette back in main(), so the margin is
    // known before the first surface is built and no bar is created flush and
    // then nudged.
    _panelMargin = ThemeStore.instance.theme.panelMargin;

    for (final monitor in listMonitors()) {
      _surfaces[_monitorKey(monitor)] = _createSurfaces(monitor);
    }

    // React to monitors being plugged in / unplugged at runtime.
    _monitorWatcher = MonitorWatcher(_scheduleMonitorSync);
  }

  /// A stable key identifying a monitor across enumerations. The connector name
  /// (e.g. `DP-1`) survives other monitors coming and going; only if the GDK
  /// build cannot report it do we fall back to make/model/position.
  String _monitorKey(MonitorInfo monitor) => monitor.connector.isNotEmpty
      ? monitor.connector
      : '${monitor.manufacturer}|${monitor.model}|'
          '${monitor.position.dx},${monitor.position.dy}';

  /// Builds the layer-shell controllers (background + panels) for [monitor].
  /// This realizes the native GTK windows immediately; the widgets that render
  /// into them are attached on the next [build].
  _MonitorSurfaces _createSurfaces(MonitorInfo monitor) {
    LayershellWindowController? background;
    if (_hasBackgroundSurface) {
      background = LayershellWindowController(
        layer: LayerShellLayer.background,
        anchorEdges: const [
          LayerShellEdge.top,
          LayerShellEdge.bottom,
          LayerShellEdge.left,
          LayerShellEdge.right,
        ],
        keyboardMode: LayerShellKeyboardMode.none,
        monitor: monitor.gdkMonitor,
      );
      // The wallpaper has to reach under the panels, or a translucent panel
      // has nothing behind it to show.
      spanFullOutput(background);
    }

    final panels = <String, LayershellWindowController>{};
    for (final entry in widget.appConfig.panels.entries) {
      final panelConfig = entry.value;
      final anchorEdges = anchorEdgesForPosition(panelConfig.anchor);
      final layer = layerFromString(panelConfig.layer);

      int? width;
      int? height;
      if (panelConfig.anchor == 'left' || panelConfig.anchor == 'right') {
        width = panelConfig.height;
      } else {
        height = panelConfig.height;
      }

      final controller = LayershellWindowController(
        width: width,
        height: height,
        layer: layer,
        anchorEdges: anchorEdges,
        exclusiveZone: panelConfig.height,
        monitor: monitor.gdkMonitor,
      );
      // Reading the field rather than the store means a monitor hot-plugged
      // after a theme change gets the current margin with no second call site.
      setPanelMargin(controller,
          anchor: panelConfig.anchor, margin: _panelMargin);
      panels[entry.key] = controller;
    }

    return _MonitorSurfaces(monitor, background, panels);
  }

  /// Builds the indicator window for [monitor]: a small card floating above the
  /// bottom edge. Anchoring to the bottom edge alone (rather than to the two
  /// side edges too) lets layer-shell centre the window horizontally, and keeps
  /// the surface — and so the region that swallows clicks — no larger than the
  /// card itself.
  LayershellWindowController _createOsd(MonitorInfo monitor) {
    final controller = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [LayerShellEdge.bottom],
      keyboardMode: LayerShellKeyboardMode.none,
      width: kOsdWindowSize.width.round(),
      height: kOsdWindowSize.height.round(),
      monitor: monitor.gdkMonitor,
    );
    controller.setMargin(LayerShellEdge.bottom, _liveConfig.osd.margin);
    return controller;
  }

  /// Creates the indicator windows when [OsdStore] gets a request and destroys
  /// them once it clears (which the card does after its fade-out). While a
  /// request is live this does nothing — the card listens to the store itself,
  /// so a change of value or of kind never touches the native windows, and a
  /// burst of volume-key presses maps to one window, not one per press.
  void _onOsdChanged() {
    if (!mounted) return;
    final wanted = OsdStore.instance.current != null;
    if (wanted == _osd.isNotEmpty) return;

    if (wanted) {
      for (final entry in _surfaces.entries) {
        _osd[entry.key] = _createOsd(entry.value.monitor);
      }
      setState(() {});
      return;
    }

    final removed = _osd.values.toList();
    _osd.clear();
    setState(() {});
    _destroyAfterFrame(removed);
  }

  /// The global "open settings" shortcut fired. It toggles: close the overlay
  /// if it is up, open it otherwise.
  void _onSettingsTriggered() {
    if (!mounted) return;
    if (_settings != null) {
      // SettingsOverlay plays its fade-out then calls _onSettingsClosed.
      _settingsClosing.value = true;
    } else {
      // Two stacked focus-taking overlay surfaces have no defined focus order,
      // so the one already up steps aside.
      if (_launcher != null) _launcherClosing.value = true;
      _openSettings();
    }
  }

  /// The launcher was asked for, by its shortcut or by the bar module. Toggles
  /// the same way the settings overlay does.
  void _onLauncherTriggered() {
    if (!mounted) return;
    if (_launcher != null) {
      _launcherClosing.value = true;
    } else {
      if (_settings != null) _settingsClosing.value = true;
      _openLauncher();
    }
  }

  /// Opens the launcher as a full-screen overlay-layer window.
  ///
  /// Unlike [_openSettings] this passes no monitor: with no `wl_output` on the
  /// layer surface the compositor picks, and miracle places shell surfaces on
  /// its focused output — which it retargets whenever the pointer crosses a
  /// monitor boundary. So the launcher appears where the user is looking.
  ///
  /// `onDemand` keyboard mode is enough for the search field to be typeable
  /// immediately, because miracle focuses every layer-shell window it maps.
  void _openLauncher() {
    _launcherClosing.value = false;
    // The rows hold GAppInfo pointers, so hold off any index rebuild until the
    // launcher is gone.
    AppIndex.instance.acquire();
    _launcher = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [
        LayerShellEdge.top,
        LayerShellEdge.bottom,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      keyboardMode: LayerShellKeyboardMode.onDemand,
    );
    // Full-screen means the whole output, panels included — otherwise the
    // backdrop stops short of the bars and dismiss-on-backdrop has dead strips.
    spanFullOutput(_launcher!);
    setState(() {});
  }

  /// An application asked to share the screen (or the pick was answered).
  ///
  /// The portal backend is blocked inside its `Start` call awaiting
  /// [ScreencastPickerController]; this opens the consent surface when a
  /// request appears and tears it down once one has been answered — including
  /// when the *portal* cancelled (`Request.Close`) rather than the user.
  void _onScreencastPickChanged() {
    if (!mounted) return;
    final request = ScreencastPickerController.instance.pending;
    if (request != null) {
      if (_screencastPicker != null) return;
      // Two stacked focus-taking overlays have no defined focus order, and a
      // consent prompt must be the one on top.
      if (_settings != null) _settingsClosing.value = true;
      if (_launcher != null) _launcherClosing.value = true;
      _openScreencastPicker(request);
    } else if (_screencastPicker != null) {
      _screencastClosing.value = true;
    }
  }

  /// Opens the picker as a full-screen overlay-layer window. Like the launcher
  /// (and unlike settings) it passes no monitor, so the compositor puts it on
  /// the focused output — where the user is.
  void _openScreencastPicker(PickRequest request) {
    _screencastClosing.value = false;
    _screencastRequest = request;
    _screencastPicker = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [
        LayerShellEdge.top,
        LayerShellEdge.bottom,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      keyboardMode: LayerShellKeyboardMode.onDemand,
    );
    spanFullOutput(_screencastPicker!);
    setState(() {});
  }

  /// Called by [ScreencastPickerOverlay] once its fade-out has finished.
  void _onScreencastPickerClosed() {
    if (!mounted) return;
    final removed = _screencastPicker;
    if (removed == null) return;
    _screencastPicker = null;
    _screencastRequest = null;
    // A window torn down without the user answering (the shell is shutting
    // down, or the frontend withdrew) still owes the portal a reply.
    ScreencastPickerController.instance.cancel();
    setState(() {});
    _destroyAfterFrame([removed]);
  }

  /// Called by [LauncherOverlay] once it is finished with its window — after
  /// the fade-out, or immediately when an application was launched.
  void _onLauncherClosed() {
    if (!mounted) return;
    final removed = _launcher;
    if (removed == null) return;
    _launcher = null;
    AppIndex.instance.release();
    setState(() {});
    _destroyAfterFrame([removed]);
  }

  /// Opens the settings overlay as a single full-monitor layer-shell window on
  /// the first connected monitor. It sits on the overlay layer and takes
  /// keyboard focus (onDemand) so its text fields and Escape-to-close work —
  /// the same recipe the clock uses to open this overlay from a panel.
  void _openSettings([SettingsRoute? route]) {
    if (_surfaces.isEmpty) return;
    final monitor = _surfaces.values.first.monitor;
    _settingsRoute = route;
    _settingsClosing.value = false;
    _settings = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [
        LayerShellEdge.top,
        LayerShellEdge.bottom,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      keyboardMode: LayerShellKeyboardMode.onDemand,
      monitor: monitor.gdkMonitor,
    );
    spanFullOutput(_settings!);
    setState(() {});
  }

  /// Called by [SettingsOverlay] once its fade-out has finished (from the toggle
  /// shortcut or its own Escape handler), so the native window can be torn down.
  void _onSettingsClosed() {
    if (!mounted) return;
    final removed = _settings;
    _settings = null;
    _settingsRoute = null;
    setState(() {});
    if (removed != null) _destroyAfterFrame([removed]);

    // A route that arrived while the overlay was up: the old window has now
    // finished its fade-out, so reopen at the requested page.
    final pending = _pendingSettingsRoute;
    if (pending != null) {
      _pendingSettingsRoute = null;
      _openSettings(pending);
    }
  }

  /// Something asked for the settings overlay at a particular page — today the
  /// desktop's "Change background…".
  ///
  /// Unlike [_onSettingsTriggered] this never toggles: the request names a
  /// destination, and closing the settings in response to "show me the
  /// background settings" would be nonsense. An overlay already on screen is
  /// closed and reopened, because it seeds its tab in `initState`.
  void _onSettingsRouteRequested() {
    if (!mounted) return;
    final route = SettingsController.instance.pending;
    if (route == null) return;
    SettingsController.instance.consume();

    if (_settings == null) {
      _openSettings(route);
      return;
    }
    if (_settingsRoute == route) return;
    _pendingSettingsRoute = route;
    _settingsClosing.value = true;
  }

  /// "Add application…" / "Add file or folder…" from the desktop's empty-space
  /// menu.
  ///
  /// The picker is asked for through [FilePickerController] because the desktop
  /// cannot host one itself; the chosen paths are then pinned at [cell], or as
  /// near to it as the grid allows.
  Future<void> _onDesktopAddRequested({
    required bool applications,
    required GridCell cell,
  }) async {
    final paths = await FilePickerController.instance.pick(
      FilePickerRequest(
        filters: applications
            ? const [FilePickerFilter.desktopEntries, FilePickerFilter.all]
            : const [FilePickerFilter.all],
        allowDirectories: !applications,
        initialDirectory: applications ? '/usr/share/applications' : null,
      ),
    );
    if (paths == null || paths.isEmpty || !mounted) return;

    final store = DesktopStore.instance;
    // Nominal geometry: the surface that raised the menu knows the real one,
    // but placement only needs a free cell and the desktop reflows anything
    // out of range at render time anyway.
    final geometry = computeGridGeometry(const Size(1920, 1080), store.config);
    for (final path in paths) {
      final item = desktopItemForPath(path);
      store.addItem(
        item.copyWith(column: cell.column, row: cell.row),
        geometry,
      );
    }
  }

  /// Flips one background surface between `none` and `onDemand` keyboard
  /// interactivity, for the duration of an in-place rename.
  ///
  /// The surface is created `none` (main.dart's `_createSurfaces`), so a text
  /// field on it would never see a key event. It is not simply left `onDemand`:
  /// a full-output background surface that can take focus would let a stray
  /// click on the desktop steal it from the focused application.
  ///
  /// Cached in a set rather than read back from the controller, on the
  /// [_panelMargin] precedent — re-committing a layer surface more often than
  /// it actually changes makes it flicker. And force-committed for the same
  /// reason [setPanelMargin] is: a change made after the surface is mapped
  /// causes no repaint of its own, so it would otherwise sit queued.
  void _setDesktopKeyboard(String monitorKey, bool wanted) {
    if (_desktopKeyboard.contains(monitorKey) == wanted) return;
    final controller = _surfaces[monitorKey]?.background;
    if (controller == null) return;
    controller.setKeyboardMode(
      wanted ? LayerShellKeyboardMode.onDemand : LayerShellKeyboardMode.none,
    );
    controller.tryForceCommit();
    if (wanted) {
      _desktopKeyboard.add(monitorKey);
    } else {
      _desktopKeyboard.remove(monitorKey);
    }
  }

  /// A surface that cannot host a modal asked for a file picker.
  ///
  /// The desktop grid is the caller: it lives on the background layer, where a
  /// picker would be drawn under every application window. This puts one on the
  /// overlay layer instead, with keyboard focus so Escape works.
  void _onFilePickRequested() {
    if (!mounted) return;
    final request = FilePickerController.instance.pending;
    if (request == null) {
      if (_filePicker != null) _closeFilePicker();
      return;
    }
    if (_filePicker != null) return;

    // Like the launcher, no monitor: the compositor puts it on the focused
    // output, which is where the user just right-clicked.
    _filePicker = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [
        LayerShellEdge.top,
        LayerShellEdge.bottom,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      keyboardMode: LayerShellKeyboardMode.onDemand,
    );
    spanFullOutput(_filePicker!);
    setState(() {});
  }

  void _closeFilePicker() {
    final removed = _filePicker;
    if (removed == null) return;
    _filePicker = null;
    setState(() {});
    _destroyAfterFrame([removed]);
  }

  /// Destroys native windows only once the frame that detached their views has
  /// been rendered — destroying while Flutter still renders into the view would
  /// use a freed FlView.
  void _destroyAfterFrame(List<LayershellWindowController> controllers) {
    if (controllers.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in controllers) {
        controller.destroy();
      }
    });
  }

  /// The Lock button (or anything else calling [LockController.lock]) asked for
  /// the session to be locked.
  void _onLockRequested() {
    if (!mounted) return;
    if (LockController.instance.isRequested && _sessionLock == null) {
      _startLock();
    }
  }

  /// Locks the session and puts a lock surface on every monitor.
  ///
  /// Ordering matters and mirrors gtk-session-lock's own example: prepare the
  /// lock, ask the compositor to lock, *then* create the surfaces. Each
  /// [SessionLockWindowController] claims its GTK window's surface before the
  /// window is realized.
  void _startLock() {
    if (_sessionLock != null) return;

    if (!SessionLock.isSupported) {
      final reason = SessionLock.isAvailable
          ? 'the compositor does not implement ext-session-lock-v1'
          : 'libgtk-session-lock is not installed';
      debugPrint('lock: cannot lock the session — $reason');
      LockController.instance.markFailed(reason);
      return;
    }

    debugPrint('lock: available=${SessionLock.isAvailable} '
        'supported=${SessionLock.isSupported} '
        'protocol=${SessionLock.protocolVersion}');

    final lock = SessionLock(
      onLocked: () =>
          debugPrint('lock: compositor confirmed the session is locked'),
      onFinished: _onLockFinished,
    );
    try {
      lock.prepare();
      debugPrint('lock: prepared, handle=0x${lock.handle.address.toRadixString(16)}');
      lock.lock();
      debugPrint('lock: lock request sent');
    } catch (error) {
      debugPrint('lock: failed to lock the session: $error');
      lock.release();
      LockController.instance.markFailed('$error');
      return;
    }

    _sessionLock = lock;
    for (final entry in _surfaces.entries) {
      try {
        final controller = SessionLockWindowController(
          sessionLock: lock,
          monitor: entry.value.monitor.gdkMonitor,
        );
        _lockWindows[entry.key] = controller;
        // Sampled before the window is realized: false means the lock surface
        // was never registered, so GDK will map an ordinary toplevel — a
        // floating window instead of a lock surface. Otherwise silent apart
        // from a g_critical on stderr.
        debugPrint('lock: ${entry.key} attached=${controller.attachedAsLockSurface}');
      } catch (error) {
        // A monitor we could not build a surface for is blanked by the
        // compositor, so the session stays covered either way.
        debugPrint('lock: no lock surface for ${entry.key}: $error');
      }
    }

    LockController.instance.markActive();
    setState(() {});

    // Re-check once the windows have been presented: `attached` above only
    // proves the handlers were connected, this proves the role survived
    // realize + map.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final entry in _lockWindows.entries) {
        debugPrint('lock: ${entry.key} isLockWindow after map='
            '${entry.value.isLockWindow}');
      }
    });
  }

  /// The compositor ended the lock without us asking (it refused the lock, or
  /// took it away). The session may well still be locked, so drop our lock
  /// object without sending an unlock.
  void _onLockFinished() {
    if (!mounted) return;
    _teardownLock(unlock: false);
  }

  /// PAM accepted the password: release the lock and restore the session.
  void _unlockSession() {
    if (!mounted) return;
    _teardownLock(unlock: true);
  }

  void _teardownLock({required bool unlock}) {
    final lock = _sessionLock;
    if (lock == null) return;
    _sessionLock = null;

    final removed = _lockWindows.values.toList();
    _lockWindows.clear();
    LockController.instance.clear();

    // Detach the views this frame, then tear down the native side once that
    // frame has rendered — destroying a window Flutter is still rendering into
    // would use a freed FlView.
    //
    // The lock is released *before* the windows are destroyed: the protocol
    // says lock surfaces should be destroyed after the unlock request, and
    // unlockAndDestroy() syncs with the compositor, without which the server
    // may kill the connection with a protocol error mid-teardown.
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (unlock) {
        lock.unlockAndDestroy();
      } else {
        lock.release();
      }
      for (final controller in removed) {
        controller.destroy();
      }
    });
  }

  /// Coalesces bursts of `monitor-added` / `monitor-removed` signals (a single
  /// reconfigure can emit several) into one reconciliation, and hops off the
  /// GTK signal-emission stack before creating or destroying windows.
  void _scheduleMonitorSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    scheduleMicrotask(() {
      _syncScheduled = false;
      if (mounted) _syncMonitors();
    });
  }

  /// Reconciles [_surfaces] with the current monitor list: destroys surfaces
  /// for monitors that were unplugged and creates them for monitors that were
  /// plugged in.
  void _syncMonitors() {
    final incoming = <String, MonitorInfo>{
      for (final monitor in listMonitors()) _monitorKey(monitor): monitor,
    };

    final removed = <LayershellWindowController>[];
    final removedLocks = <SessionLockWindowController>[];
    var changed = false;

    for (final key in _surfaces.keys.toList()) {
      if (!incoming.containsKey(key)) {
        removed.addAll(_surfaces.remove(key)!.controllers);
        final osd = _osd.remove(key);
        if (osd != null) removed.add(osd);
        final lock = _lockWindows.remove(key);
        if (lock != null) removedLocks.add(lock);
        changed = true;
      }
    }

    for (final entry in incoming.entries) {
      if (!_surfaces.containsKey(entry.key)) {
        _surfaces[entry.key] = _createSurfaces(entry.value);
        // A monitor plugged in mid-indicator gets one too, so the card is not
        // missing from the display the user may well be looking at.
        if (_osd.isNotEmpty) _osd[entry.key] = _createOsd(entry.value);
        // Likewise a monitor plugged in while locked: without a lock surface
        // the compositor would just blank it.
        if (_sessionLock case final lock?) {
          try {
            _lockWindows[entry.key] = SessionLockWindowController(
              sessionLock: lock,
              monitor: entry.value.gdkMonitor,
            );
          } catch (error) {
            debugPrint('lock: no lock surface for ${entry.key}: $error');
          }
        }
        changed = true;
      }
    }

    if (!changed) return;

    // Detach the removed views from the tree first, then destroy their native
    // windows after that frame has been rendered.
    setState(() {});
    _destroyAfterFrame(removed);
    if (removedLocks.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final controller in removedLocks) {
          controller.destroy();
        }
      });
    }
  }

  void _onOutputsChanged() {
    // Outputs were added/removed or finished reporting their properties;
    // rebuild so each panel re-resolves the display it renders on.
    if (mounted) setState(() {});
  }

  /// Resolves the Wayland output backing [monitor] for [DisplayScope]. Falls
  /// back to the first known output if an exact match is not (yet) available,
  /// or null only when no outputs are known at all.
  WaylandOutput? _outputFor(MonitorInfo monitor) {
    final outputs = widget.outputs.outputs;
    if (outputs.isEmpty) return null;
    for (final output in outputs) {
      if (output.make == monitor.manufacturer &&
          output.model == monitor.model &&
          output.x == monitor.position.dx.toInt() &&
          output.y == monitor.position.dy.toInt()) {
        return output;
      }
    }
    return outputs.first;
  }

  /// Rebuilds a fresh typed config from the store (which also re-applies
  /// per-module options via [Module.loadAll]) and rebuilds the tree. Runs in a
  /// listener, never during build, because deriving the config has side effects.
  void _onConfigChanged() {
    if (!mounted) return;
    final AppConfig next;
    try {
      next = widget.store.appConfig;
    } catch (_) {
      // A mid-edit or malformed map failed to parse — keep the last good
      // config rather than tearing down the running shell.
      return;
    }
    setState(() => _liveConfig = next);
  }

  /// Re-floats the bars when the active theme's margin changes.
  ///
  /// Panel geometry is otherwise frozen at startup, but this one has to follow
  /// the theme live: everything else about a theme switch applies immediately,
  /// and a bar that rounded its corners without also lifting off the screen
  /// edge until the next restart would just look broken.
  ///
  /// No [setState] — nothing in the tree reads [_panelMargin]. The radius and
  /// rim reach the panels through [ThemeProvider], which listens to this same
  /// store, so rebuilding here would only duplicate that work on every frame of
  /// a colour drag.
  void _onThemeChanged() {
    if (!mounted) return;
    final next = ThemeStore.instance.theme.panelMargin;
    if (next == _panelMargin) return;
    _panelMargin = next;
    for (final surfaces in _surfaces.values) {
      surfaces.panels.forEach((key, controller) {
        // Startup geometry, like _createSurfaces and _effectivePanel: the
        // anchor a surface was built with cannot change without recreating it.
        final panelConfig = widget.appConfig.panels[key];
        if (panelConfig == null) return;
        setPanelMargin(controller,
            anchor: panelConfig.anchor, margin: next);
      });
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onConfigChanged);
    widget.outputs.removeListener(_onOutputsChanged);
    OsdStore.instance.removeListener(_onOsdChanged);
    InputTriggerStore.instance.removeListener(_onSettingsTriggered);
    LauncherController.instance.removeListener(_onLauncherTriggered);
    ScreencastPickerController.instance
        .removeListener(_onScreencastPickChanged);
    LockController.instance.removeListener(_onLockRequested);
    SettingsController.instance.removeListener(_onSettingsRouteRequested);
    FilePickerController.instance.removeListener(_onFilePickRequested);
    ThemeStore.instance.removeListener(_onThemeChanged);
    _monitorWatcher.dispose();
    // Drop the lock windows, but never send an unlock on the way out: if the
    // shell is going away while the session is locked, the session must stay
    // locked. abandon() sends no Wayland request at all — after `locked` the
    // only legal destructor is unlock_and_destroy, which would do the opposite
    // of what we want; disconnecting instead leaves the session locked.
    for (final ctrl in _lockWindows.values) {
      ctrl.destroy();
    }
    _lockWindows.clear();
    _sessionLock?.abandon();
    _sessionLock = null;
    for (final surfaces in _surfaces.values) {
      for (final ctrl in surfaces.controllers) {
        ctrl.destroy();
      }
    }
    _surfaces.clear();
    for (final ctrl in _osd.values) {
      ctrl.destroy();
    }
    _osd.clear();
    _settings?.destroy();
    _settings = null;
    _settingsClosing.dispose();
    _launcher?.destroy();
    _launcher = null;
    _launcherClosing.dispose();
    _screencastPicker?.destroy();
    _screencastPicker = null;
    _screencastClosing.dispose();
    super.dispose();
  }

  /// Merges live-updatable panel fields (module layout, horizontal padding)
  /// onto the startup window geometry (anchor/height/layer), which cannot
  /// change without recreating the native window. Falls back to the startup
  /// config for panels removed after launch.
  PanelConfig _effectivePanel(String key, PanelConfig startup) {
    final live = _liveConfig.panels[key];
    if (live == null) return startup;
    return PanelConfig(
      name: startup.name,
      height: startup.height,
      anchor: startup.anchor,
      layer: startup.layer,
      paddingHorizontal: live.paddingHorizontal,
      layout: live.layout,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Iterate the *startup* panels — those own the layer-shell controllers —
    // but render each with the live config merged onto its fixed geometry.
    final startupPanels = widget.appConfig.panels;

    // Background surface existence is startup-only; while it exists, follow
    // live edits (fit / entry paths) but keep the startup wallpaper if the user
    // clears every entry (a full removal needs a restart).
    //
    // Null here means "surface, but nothing to paint" — the grid-only case.
    // That must render as *nothing*, not as BackgroundWindow's opaque empty
    // fill, or a user with icons and no wallpaper gets a black desktop instead
    // of whatever their compositor draws.
    final liveBg = _liveConfig.background;
    final startupBg = widget.appConfig.background;
    final BackgroundConfig? bgConfig = !_hasBackgroundSurface
        ? null
        : (liveBg != null && liveBg.entries.isNotEmpty ? liveBg : startupBg);

    return ViewCollection(
      views: [
        // One group of surfaces per currently-connected monitor. Monitors are
        // added to / removed from [_surfaces] as they are plugged and unplugged.
        for (final surfaces in _surfaces.values) ...[
          if (surfaces.background != null)
            LayerShellWindow(
              // Key by controller so add/remove of one monitor doesn't shift how
              // Flutter matches the remaining views onto their FlutterViews.
              key: ObjectKey(surfaces.background!),
              controller: surfaces.background!,
              // PanelWindowManager and ThemeProvider are what let the desktop
              // grid open popups: LayerShellWindow already supplies the View
              // and the WindowScope, but PopupHost also needs a WindowRegistry,
              // and popup content is built outside the parent's ThemeScope.
              //
              // Deliberately no DisplayScope: the grid takes its geometry from
              // a LayoutBuilder, and gating on `_outputFor` would mean no
              // wallpaper until Wayland output enumeration completed.
              child: PanelWindowManager(
                child: ThemeProvider(
                  child: DesktopSurface(
                    background: bgConfig,
                    desktop: _liveConfig.desktop,
                    store: DesktopStore.instance,
                    // Startup panel geometry, like _createSurfaces: the anchor
                    // a surface was built with cannot change without a restart.
                    panels: widget.appConfig.panels,
                    onChangeBackground: () => SettingsController.instance
                        .open(SettingsRoute.background),
                    onAddRequested: _onDesktopAddRequested,
                    onKeyboardRequested: (wanted) => _setDesktopKeyboard(
                        _monitorKey(surfaces.monitor), wanted),
                  ),
                ),
              ),
            ),
          if (_outputFor(surfaces.monitor) case final output?)
            for (final entry in startupPanels.entries)
              if (surfaces.panels[entry.key] case final controller?)
                LayerShellWindow(
                  key: ObjectKey(controller),
                  controller: controller,
                  child: PanelWindowManager(
                    child: ThemeProvider(
                      child: MiracleScope(
                        manager: widget.miracle,
                        child: DisplayScope(
                          output: output,
                          child: Builder(builder: (context) {
                            final panel =
                                _effectivePanel(entry.key, entry.value);
                            return PanelMain(
                              panelConfig: panel,
                              anchor: panel.anchor,
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
          // The indicator is not tied to any panel, so it lives here beside the
          // background rather than inside a module's window registry.
          if (_osd[_monitorKey(surfaces.monitor)] case final osd?)
            LayerShellWindow(
              key: ObjectKey(osd),
              controller: osd,
              child: ThemeProvider(
                child: OsdWindow(store: OsdStore.instance),
              ),
            ),
        ],
        // The settings overlay opened by the global shortcut. A single window
        // (not per-monitor), so it lives outside the per-monitor loop above.
        if (_settings case final settings?)
          LayerShellWindow(
            key: ObjectKey(settings),
            controller: settings,
            child: ThemeProvider(
              child: SettingsOverlay(
                closingNotifier: _settingsClosing,
                onClosed: _onSettingsClosed,
                route: _settingsRoute,
              ),
            ),
          ),
        // The file picker asked for by a surface that cannot host a modal —
        // today the desktop grid, which is on the background layer.
        if ((_filePicker, FilePickerController.instance.pending)
            case (final picker?, final request?))
          LayerShellWindow(
            key: ObjectKey(picker),
            controller: picker,
            child: ThemeProvider(
              child: FilePickerWindow(
                request: request,
                onResult: (paths) {
                  FilePickerController.instance.complete(paths);
                  _closeFilePicker();
                },
              ),
            ),
          ),
        // The application launcher. Like the settings overlay it is a single
        // window rather than one per monitor, so it lives outside the loop.
        if (_launcher case final launcher?)
          LayerShellWindow(
            key: ObjectKey(launcher),
            controller: launcher,
            child: ThemeProvider(
              child: LauncherOverlay(
                closingNotifier: _launcherClosing,
                onClosed: _onLauncherClosed,
                apps: AppIndex.instance.searchable,
                onLaunch: (app) => launchApp(app.appInfo),
                onLaunchAction: (app, action) =>
                    launchAppAction(app.appInfo, action.id),
              ),
            ),
          ),
        // The screen-share consent picker, open only while an application's
        // portal request is waiting on an answer. Single window, like the
        // launcher, so it lives outside the per-monitor loop.
        if ((_screencastPicker, _screencastRequest)
            case (final picker?, final request?))
          LayerShellWindow(
            key: ObjectKey(picker),
            controller: picker,
            child: ThemeProvider(
              child: Builder(builder: (context) {
                final connection = screencastService?.connection;
                final sources = connection == null
                    ? (monitors: <PickerSource>[], windows: <PickerSource>[])
                    : buildPickerSources(connection, request,
                        previewFps: _liveConfig.screenshare.previewFps);
                return ScreencastPickerOverlay(
                  request: request,
                  monitors: sources.monitors,
                  windows: sources.windows,
                  closingNotifier: _screencastClosing,
                  onClosed: _onScreencastPickerClosed,
                  onConfirm: (picked) => ScreencastPickerController.instance
                      .complete(PickResult(picked)),
                  onCancel: ScreencastPickerController.instance.cancel,
                );
              }),
            ),
          ),
        // The lock screen. These surfaces exist only while the session is
        // locked; the compositor hides every other surface — including the
        // panels above — for as long as they do.
        for (final controller in _lockWindows.values)
          SessionLockWindow(
            key: ObjectKey(controller),
            controller: controller,
            child: ThemeProvider(
              child: LockScreen(
                config: _liveConfig.lock,
                onUnlocked: _unlockSession,
              ),
            ),
          ),
      ],
    );
  }
}

class PanelMain extends StatefulWidget {
  const PanelMain({
    super.key,
    required this.panelConfig,
    required this.anchor,
  });

  final PanelConfig panelConfig;
  final String anchor;

  @override
  _PanelMainState createState() => _PanelMainState();
}

class _PanelMainState extends State<PanelMain> {
  Widget _buildModule(String name) {
    final module = Module.lookup(name);
    if (module == null) return const SizedBox.shrink();
    return Builder(builder: module.builder);
  }

  Widget _buildSection(List<String> modules) {
    if (modules.isEmpty) return const SizedBox.shrink();

    final bool vertical = widget.anchor == 'left' || widget.anchor == 'right';
    final children = <Widget>[];
    for (int i = 0; i < modules.length; i++) {
      if (i > 0) {
        children.add(
            vertical ? const SizedBox(height: 8) : const SizedBox(width: 8));
      }
      children.add(_buildModule(modules[i]));
    }
    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.panelConfig.layout;

    final bool vertical = widget.panelConfig.anchor == 'left' ||
        widget.panelConfig.anchor == 'right';

    final stackChildren = <Widget>[
      if (layout.left.isNotEmpty)
        Align(
          alignment: vertical ? Alignment.topCenter : Alignment.centerLeft,
          child: _buildSection(layout.left),
        ),
      if (layout.center.isNotEmpty)
        Align(
          alignment: Alignment.center,
          child: _buildSection(layout.center),
        ),
      if (layout.right.isNotEmpty)
        Align(
          alignment: vertical ? Alignment.bottomCenter : Alignment.centerRight,
          child: _buildSection(layout.right),
        ),
    ];
    final double pad = widget.panelConfig.paddingHorizontal.toDouble();

    final theme = ThemeScope.of(context);
    final radius = panelCornerRadius(
      anchor: widget.panelConfig.anchor,
      theme: theme,
    );
    final Widget content = Padding(
      padding: vertical
          ? EdgeInsets.fromLTRB(0, pad, 0, pad)
          : EdgeInsets.fromLTRB(pad, 0, pad, 0),
      child: Stack(children: stackChildren),
    );

    return BarScope(
      anchor: widget.panelConfig.anchor,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: theme.fontFamily,
          fontSize: 12,
          color: theme.foreground,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            // DecoratedBox, not Container: Container applies the decoration's
            // padding — which for a bordered box is the border's thickness — to
            // its child, silently insetting every module and changing what
            // padding_horizontal means. The clip is conditional so a square bar
            // (every install that has not opted in) adds no extra layer.
            child: DecoratedBox(
              decoration: panelBackgroundDecoration(
                anchor: widget.panelConfig.anchor,
                theme: theme,
              ),
              child: radius == BorderRadius.zero
                  ? content
                  : ClipRRect(borderRadius: radius, child: content),
            ),
          ),
        ),
      ),
    );
  }
}
