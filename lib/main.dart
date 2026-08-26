import 'dart:async';
import 'dart:ffi' as ffi;
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: implementation_imports
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/desktop/desktop_surface.dart';
import 'package:graceful_shell/display_provider.dart';
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
import 'package:graceful_shell/launcher/app_search.dart';
import 'package:graceful_shell/launcher/launcher_controller.dart';
import 'package:graceful_shell/launcher/launcher_overlay.dart';
import 'package:graceful_shell/lock/lock_controller.dart';
import 'package:graceful_shell/lock/lock_screen.dart';
import 'package:graceful_shell/live_config_provider.dart';
import 'package:graceful_shell/lock/session_lock_host.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/osd/osd.dart';
import 'package:graceful_shell/osd/osd_service.dart';
import 'package:graceful_shell/osd/osd_store.dart';
import 'package:graceful_shell/panel_background.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/screencast/picker_controller.dart';
import 'package:graceful_shell/screencast/picker_overlay.dart';
import 'package:graceful_shell/screencast/picker_sources.dart';
import 'package:graceful_shell/screencast/screencast_log.dart';
import 'package:graceful_shell/screencast/screencast_service.dart';
import 'package:graceful_shell/shell_services.dart';
import 'package:graceful_shell/shell_text_root.dart';
import 'package:graceful_shell/status_notifier_service.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/desktop/app_chooser.dart';
import 'package:graceful_shell/desktop/desktop_actions.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';
import 'package:graceful_shell/desktop/desktop_store.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/desktop/widgets/media_player_widget.dart';
import 'package:graceful_shell/desktop/widgets/fortune_widget.dart';
import 'package:graceful_shell/desktop/widgets/moon_widget.dart';
import 'package:graceful_shell/desktop/widgets/tux_widget.dart';
import 'package:graceful_shell/desktop/widgets/weather_widget.dart';
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

  Module.register(workspacesModule);
  Module.register(mediaPlayerModule);
  Module.register(soundControlModule);
  Module.register(batteryModule);
  Module.register(weatherModule);
  Module.register(clockModule);
  Module.register(dockModule);
  Module.register(systemMonitorModule);
  Module.register(notificationsModule);
  Module.register(networkModule);
  Module.register(systemModule);
  Module.register(systemTrayModule);
  Module.register(launcherModule);

  // The desktop grid's own registry, populated the same way and for the same
  // reason: `[[desktop.widgets]]` names a type, and lookup happens at render
  // time. See `lib/desktop/widgets/desktop_widget.dart`.
  DesktopWidgetRegistry.register(mediaPlayerDesktopWidget);
  DesktopWidgetRegistry.register(weatherDesktopWidget);
  DesktopWidgetRegistry.register(moonDesktopWidget);
  DesktopWidgetRegistry.register(fortuneDesktopWidget);
  DesktopWidgetRegistry.register(tuxDesktopWidget);

  // AppConfig.load() writes the default config on first run and applies the
  // module subtables; the shared ConfigStore then reads that same file and
  // becomes the single live source of truth the shell watches.
  //
  // These two are the only awaits left before the first frame, and they have to
  // be: every native window's geometry is read out of them, so there is
  // genuinely nothing to render until they land. Everything else the shell used
  // to wait on now starts in [_startShellServices], after it has painted.
  final appConfig = await AppConfig.load();
  final store = await ConfigStore.initShared();

  // Seeds the shipped themes into ~/.config/graceful-shell/themes on first run
  // and resolves the one config.toml names, before anything paints.
  startThemeService(store);

  // Reads the pinned desktop icons, so the grid paints with the first frame of
  // the background surface rather than popping in a moment later. Like the
  // theme store it watches ConfigStore for its own subtree only.
  startDesktopService(store);

  // Configures the system stats store, but does not start it polling — the
  // first lease (the bar module, or the monitor tab being opened) does that.
  startSystemStatsService();

  screencastLog = (message) => debugPrint('screencast: $message');

  // Miracle may not be running yet (or at all). The manager keeps the shell
  // usable either way — the workspaces module offers a retry when it is absent.
  final miracle = MiracleManager();

  // Live registry of outputs, kept current as monitors are plugged in and out.
  // Empty until [_connectDisplays] has enumerated them, which is why panels
  // render before they know which display they are on.
  final outputs = OutputTracker();

  final waylandClient = WaylandClient();
  final services = ShellServices();

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
    services: services,
  ));

  // Start-up I/O runs after the shell is on screen, never before it. The
  // post-frame callback is what makes that ordering real: the application index
  // in particular is a synchronous walk of every installed `.desktop` file, and
  // starting it any earlier would hold the isolate through the frame it is
  // supposed to come after.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _startShellServices(
      services: services,
      appConfig: appConfig,
      miracle: miracle,
      outputs: outputs,
      waylandClient: waylandClient,
    );
  });
}

/// Hands every global start-up task to [services], which runs them off the
/// first frame and publishes how far along each one is.
///
/// Order matters only in that it is the order the tasks get their first
/// event-loop turn in: the ones that block on I/O go first so their round-trips
/// are already in flight, and the application index — the one task that does
/// its work synchronously — goes last.
void _startShellServices({
  required ShellServices services,
  required AppConfig appConfig,
  required MiracleManager miracle,
  required OutputTracker outputs,
  required WaylandClient waylandClient,
}) {
  services.run(
    ShellService.displays,
    () => _connectDisplays(waylandClient, outputs, appConfig),
  );

  // `connect()` never throws: a failure leaves the manager disconnected with a
  // reason the workspaces module renders a retry button from.
  services.run(ShellService.miracle, miracle.connect);

  services.run(ShellService.notifications, startNotificationService);
  services.run(ShellService.tray, startStatusNotifierService);

  // Watches the default sink/source and the backlight so the on-screen
  // indicator can react to volume, mic, and brightness changes made anywhere.
  services.run(ShellService.audio, () => startOsdService(appConfig.osd));

  // Claims the xdg-desktop-portal ScreenCast backend name, so apps asking to
  // share their screen get the shell's own picker. A compositor without
  // ext-image-copy-capture or a machine with no PipeWire throws, which `run`
  // records as `failed` — the shell keeps going, but the status is truthful.
  if (appConfig.screenshare.enabled) {
    services.run(
      ShellService.screencast,
      () => startScreencastService(
        picker: ScreencastPickerController.instance,
        maxFrameRate: appConfig.screenshare.maxFps,
      ),
    );
  } else {
    services.skip(ShellService.screencast);
  }

  // Enumerates installed applications while the shell is already on screen, so
  // the launcher can paint the instant its shortcut fires. Until it lands the
  // launcher and the app choosers show a loader instead of "No applications".
  services.run(ShellService.applications, () async {
    startAppIndexService();
  });
}

/// Opens the Wayland connection, registers the shell's global shortcuts, and
/// enumerates the compositor's outputs into [outputs].
///
/// Completes once every output present at start-up has reported its properties.
/// The registry callbacks stay connected for the lifetime of the client, so
/// `wl_output` globals advertised afterwards are tracked too.
Future<void> _connectDisplays(
  WaylandClient waylandClient,
  OutputTracker outputs,
  AppConfig appConfig,
) async {
  await waylandClient.connect();

  // Registers the shell's global shortcuts (Ctrl+Shift+S to open settings by
  // default, configurable under `[shortcuts]`) with the compositor via the
  // ext-input-trigger protocols. It binds its globals from the same registry
  // callback below; on a compositor that lacks them nothing is bound and the
  // shell is unaffected.
  final inputTriggers =
      startInputTriggerService(waylandClient, shortcuts: appConfig.shortcuts);

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
    required this.services,
  });

  /// The config captured at startup. Native layer-shell windows (panels /
  /// background) are created from this snapshot and cannot change without a
  /// restart; live values come from [store] instead.
  final AppConfig appConfig;
  final ConfigStore store;
  final MiracleManager miracle;
  final OutputTracker outputs;

  /// How far along the global start-up tasks are. Provided to every window's
  /// subtree so the widgets that need one can show a loader until it lands.
  final ShellServices services;

  @override
  State<GracefulShellRoot> createState() => _GracefulShellRootState();
}

/// The layer-shell surfaces (optional background window plus the configured
/// panels) that belong to a single monitor.
class _MonitorSurfaces {
  _MonitorSurfaces(this.monitor, this.background, this.panels);

  /// The GDK description of this monitor, as of the last enumeration.
  ///
  /// Mutable, and refreshed by [_GracefulShellRootState._syncMonitors] when the
  /// monitor is reconfigured in place: [MonitorInfo] is a snapshot, and a panel
  /// carrying a stale position could no longer be matched to its `wl_output`.
  MonitorInfo monitor;
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

  /// The five root-owned full-screen overlays. Each [_OverlayWindow] carries
  /// the window controller, its [PopupCoordinator] registration, and the
  /// closing notifier — the bookkeeping every overlay used to hand-roll
  /// separately, which is how `dispose` once missed two of them.
  ///
  /// The settings overlay is opened by the global shortcut (Ctrl+Shift+S);
  /// the launcher by its shortcut or the magnifier module; the app chooser by
  /// the desktop's "Add application…"; the two pickers exist only while a
  /// request is outstanding. The pickers are modal: a consent prompt must
  /// displace whatever is up and be displaced by nothing — dismissing one is
  /// a denial, and only its controller may resolve it.
  final _OverlayWindow _settings = _OverlayWindow();
  final _OverlayWindow _launcher = _OverlayWindow(acquiresAppIndex: true);
  final _OverlayWindow _appChooser = _OverlayWindow(acquiresAppIndex: true);
  final _OverlayWindow _screencastPicker =
      _OverlayWindow(policy: TransientPolicy.modal);
  final _OverlayWindow _filePicker =
      _OverlayWindow(policy: TransientPolicy.modal);

  /// The page the open (or about-to-open) settings overlay was asked for. Null
  /// is the default landing page.
  SettingsRoute? _settingsRoute;

  /// A route that arrived while an overlay was already up. The overlay seeds
  /// its tab in `initState`, so retargeting means closing and reopening; this
  /// holds the destination across those two frames.
  SettingsRoute? _pendingSettingsRoute;

  /// Monitor keys whose background surface currently takes keyboard focus for
  /// an in-place desktop rename. Empty is the normal state.
  final Set<String> _desktopKeyboard = {};

  /// The cell the app chooser's pick should land in; non-null exactly while
  /// the chooser is on screen.
  GridCell? _appChooserCell;

  /// The request the open screencast picker is answering, captured when the
  /// window was created — the controller clears its own `pending` the moment
  /// the user answers, but the overlay stays mounted through its fade-out.
  PickRequest? _screencastRequest;

  /// The `ext-session-lock-v1` lifecycle. Owned by the root rather than by
  /// the module that offers the Lock button because the lock spans every
  /// monitor and outlives any one panel; everything else about it lives in
  /// [SessionLockHost].
  late final SessionLockHost _lockHost;

  late final MonitorWatcher _monitorWatcher;
  bool _syncScheduled = false;

  /// Every external listenable the root watches, with its handler. Wired in
  /// [initState] and drained in [dispose] from this one list, so the add and
  /// remove sides can never drift apart.
  late final List<(Listenable, VoidCallback)> _subscriptions;

  /// The current config the widget tree renders from. Kept in sync with
  /// [GracefulShellRoot.store] by [_onConfigChanged] so theme, panel layout,
  /// per-module options, and the background image update live. Window geometry
  /// still comes from [widget.appConfig] (the startup snapshot).
  ///
  /// A notifier rather than a plain field, published through
  /// [LiveConfigProvider], because `ConfigStore` notifies on every keystroke
  /// anywhere in the settings UI: answering each one with `setState` here
  /// rebuilt every view the root owns — every panel on every monitor, the
  /// backgrounds, the OSD, all five overlays — to deliver a value that at most
  /// five widgets read.
  late final ValueNotifier<AppConfig> _liveConfig;

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
    _liveConfig = ValueNotifier(appConfig);
    _lockHost = SessionLockHost(onChanged: () {
      if (mounted) setState(() {});
    });
    _hasBackgroundSurface =
        (appConfig.background?.entries.isNotEmpty ?? false) ||
            appConfig.desktop.enabled;
    _subscriptions = [
      (widget.store, _onConfigChanged),
      (OsdStore.instance, _onOsdChanged),
      (InputTriggerStore.instance, _onSettingsTriggered),
      (LauncherController.instance, _onLauncherTriggered),
      (ScreencastPickerController.instance, _onScreencastPickChanged),
      (LockController.instance, _onLockRequested),
      (SettingsController.instance, _onSettingsRouteRequested),
      (FilePickerController.instance, _onFilePickRequested),
      (ThemeStore.instance, _onThemeChanged),
      // The only signal a *reconfigured* (rather than plugged or unplugged)
      // monitor produces: GDK emits neither `monitor-added` nor
      // `monitor-removed` for a reposition, but every output reports its new
      // geometry over `wl_output`, which the tracker answers with a notify.
      (widget.outputs, _scheduleMonitorSync),
    ];
    for (final (listenable, handler) in _subscriptions) {
      listenable.addListener(handler);
    }
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
    // The surface is the card plus the theme's shadow: the card's Row has an
    // Expanded, so it fills the window edge to edge and a shadow would be
    // clipped on both sides. These windows are created fresh per request, so
    // reading the store here is enough to follow a theme change with no
    // listener of its own.
    //
    // Deliberately the no-`attachEdge` call, and it is half of a pair: the OSD
    // is not a bar popup — it is bottom-centred on its own overlay surface with
    // nothing to be flush against — and `osd.dart` hands this exact margin back
    // to the shadow with the same call. Nothing links the two at compile time,
    // so they move together or the card is drawn off-centre in its window.
    final shadow = popupShadowInsets(ThemeStore.instance.theme);
    final controller = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [LayerShellEdge.bottom],
      keyboardMode: LayerShellKeyboardMode.none,
      width: (kOsdWindowSize.width + shadow.horizontal).round(),
      height: (kOsdWindowSize.height + shadow.vertical).round(),
      monitor: monitor.gdkMonitor,
    );
    // A direct read, deliberately: this has no BuildContext and commits to a
    // native layer surface rather than rendering anything, so it cannot go
    // through [LiveConfigScope].
    //
    // The bottom margin gives back what the surface grew by on that edge, or a
    // shadow would lift the card off the gap the user configured. Floored at 0:
    // a shadow deeper than the margin cannot push the card off-screen.
    final margin =
        (_liveConfig.value.osd.margin - shadow.bottom).round();
    controller.setMargin(
        LayerShellEdge.bottom, margin < 0 ? 0 : margin);
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
    if (_settings.isOpen) {
      // SettingsOverlay plays its fade-out then calls _onSettingsClosed.
      _settings.closing.value = true;
    } else {
      // Whatever is up steps aside — two stacked focus-taking overlay surfaces
      // have no defined focus order. Registering with the coordinator in
      // [_openSettings] is what does it now.
      _openSettings();
    }
  }

  /// The launcher was asked for, by its shortcut or by the bar module. Toggles
  /// the same way the settings overlay does.
  void _onLauncherTriggered() {
    if (!mounted) return;
    if (_launcher.isOpen) {
      _launcher.closing.value = true;
    } else {
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
    _launcher.open();
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
      if (_screencastPicker.isOpen) return;
      // Like the launcher (and unlike settings) no monitor is passed, so the
      // compositor puts the picker on the focused output — where the user is.
      _screencastRequest = request;
      _screencastPicker.open();
      setState(() {});
    } else if (_screencastPicker.isOpen) {
      _screencastPicker.closing.value = true;
    }
  }

  /// Called by [ScreencastPickerOverlay] once its fade-out has finished.
  void _onScreencastPickerClosed() {
    if (!mounted) return;
    final removed = _screencastPicker.take();
    if (removed == null) return;
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
    final removed = _launcher.take();
    if (removed == null) return;
    setState(() {});
    _destroyAfterFrame([removed]);
  }

  /// Opens the settings overlay as a single full-monitor layer-shell window on
  /// the first connected monitor. It sits on the overlay layer and takes
  /// keyboard focus (onDemand) so its text fields and Escape-to-close work —
  /// the same recipe the clock uses to open this overlay from a panel.
  void _openSettings([SettingsRoute? route]) {
    if (_surfaces.isEmpty) return;
    _settingsRoute = route;
    _settings.open(monitor: _surfaces.values.first.monitor.gdkMonitor);
    setState(() {});
  }

  /// Called by [SettingsOverlay] once its fade-out has finished (from the toggle
  /// shortcut or its own Escape handler), so the native window can be torn down.
  void _onSettingsClosed() {
    if (!mounted) return;
    final removed = _settings.take();
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

    if (!_settings.isOpen) {
      _openSettings(route);
      return;
    }
    if (_settingsRoute == route) return;
    _pendingSettingsRoute = route;
    _settings.closing.value = true;
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
    // Applications get a searchable list of what is installed, with icons —
    // nobody should have to know that their launcher lives in
    // /usr/share/applications/firefox.desktop.
    if (applications) {
      _openAppChooser(cell);
      return;
    }

    final paths = await FilePickerController.instance.pick(
      const FilePickerRequest(
        filters: [FilePickerFilter.all],
        allowDirectories: true,
      ),
    );
    if (paths == null || paths.isEmpty || !mounted) return;
    for (final path in paths) {
      _pinToDesktop(desktopItemForPath(path), cell);
    }
  }

  /// Pins [item] at [cell], or as near to it as the grid allows.
  void _pinToDesktop(DesktopItem item, GridCell cell) {
    final store = DesktopStore.instance;
    // Nominal geometry: the surface that raised the menu knows the real one,
    // but placement only needs a free cell and the desktop reflows anything
    // out of range at render time anyway.
    final geometry = computeGridGeometry(const Size(1920, 1080), store.config);
    store.addItem(item.copyWith(column: cell.column, row: cell.row), geometry);
  }

  /// Opens the application chooser as a full-screen overlay-layer window.
  ///
  /// Like the launcher, no monitor: the compositor puts it on the focused
  /// output, which is where the user just right-clicked. The rows hold
  /// `GAppInfo` pointers from the index, so the index is pinned for the
  /// window's lifetime exactly as `_openLauncher` does.
  void _openAppChooser(GridCell cell) {
    if (_appChooser.isOpen) return;
    _appChooserCell = cell;
    // A direct close on dismiss: the chooser has no exit animation to play.
    _appChooser.open(onDismiss: _closeAppChooser);
    setState(() {});
  }

  void _closeAppChooser() {
    final removed = _appChooser.take();
    if (removed == null) return;
    _appChooserCell = null;
    setState(() {});
    _destroyAfterFrame([removed]);
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
      if (_filePicker.isOpen) _closeFilePicker();
      return;
    }
    if (_filePicker.isOpen) return;

    // Like the launcher, no monitor: the compositor puts it on the focused
    // output, which is where the user just right-clicked. A dismissal closes
    // directly — cancelling a modal picker has no exit animation — and only
    // [FilePickerController] may resolve the awaited pick.
    _filePicker.open(onDismiss: _closeFilePicker);
    setState(() {});
  }

  void _closeFilePicker() {
    final removed = _filePicker.take();
    if (removed == null) return;
    setState(() {});
    _destroyAfterFrame([removed]);
  }

  /// Destroys native windows only once Flutter has actually let go of their
  /// views — destroying while it still renders into one aborts the process
  /// inside the embedder's dispose (see [WindowTeardown]).
  ///
  /// The overlays have all played their fade-out through
  /// [FadeOverlayScaffold]'s closing handshake before this runs, so the unmap
  /// [destroyWindowWhenDetached] does up front costs nothing visually.
  void _destroyAfterFrame(List<LayershellWindowController> controllers) {
    for (final controller in controllers) {
      destroyWindowWhenDetached(controller);
    }
  }

  /// The Lock button (or anything else calling [LockController.lock]) asked for
  /// the session to be locked.
  void _onLockRequested() {
    if (!mounted) return;
    if (LockController.instance.isRequested && !_lockHost.isLocked) {
      // The compositor hides every other surface behind the lock, so anything
      // still registered would be a popup the user cannot see or reach — and
      // would still be there on unlock.
      PopupCoordinator.instance.dismissAll();
      _lockHost.lock({
        for (final entry in _surfaces.entries)
          entry.key: entry.value.monitor.gdkMonitor,
      });
    }
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
        final lock = _lockHost.removeMonitor(key);
        if (lock != null) removedLocks.add(lock);
        changed = true;
      }
    }

    for (final entry in incoming.entries) {
      final existing = _surfaces[entry.key];
      if (existing != null) {
        // The same monitor, described differently — a reposition, a mode or
        // scale change. Nothing native is recreated; the snapshot is simply
        // replaced, so `DisplayProvider` stops matching its `wl_output` against
        // a position the monitor left behind.
        if (!_sameMonitor(existing.monitor, entry.value)) {
          existing.monitor = entry.value;
          changed = true;
        }
        continue;
      }

      _surfaces[entry.key] = _createSurfaces(entry.value);
      // A monitor plugged in mid-indicator gets one too, so the card is not
      // missing from the display the user may well be looking at.
      if (_osd.isNotEmpty) _osd[entry.key] = _createOsd(entry.value);
      // Likewise a monitor plugged in while locked: without a lock surface
      // the compositor would just blank it.
      _lockHost.addMonitor(entry.key, entry.value.gdkMonitor);
      changed = true;
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

  /// Whether two enumerations describe the same monitor the same way.
  ///
  /// [MonitorInfo] carries no `==`, and the fields that matter here are the ones
  /// [resolveOutput] and the lock host read: the identity strings, the position
  /// it is matched on, and the `GdkMonitor` the native windows were given.
  bool _sameMonitor(MonitorInfo a, MonitorInfo b) =>
      a.connector == b.connector &&
      a.manufacturer == b.manufacturer &&
      a.model == b.model &&
      a.position == b.position &&
      a.gdkMonitor.address == b.gdkMonitor.address;

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
    // No [setState]: the value is published through [LiveConfigProvider], so
    // only the widgets that actually read it rebuild. The root's own build
    // reads nothing from it.
    _liveConfig.value = next;
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
    for (final (listenable, handler) in _subscriptions) {
      listenable.removeListener(handler);
    }
    _monitorWatcher.dispose();
    // Answer the pending picks before tearing their windows down: the UI that
    // would answer them is going away, and an unanswered pick strands its
    // caller — for the screencast picker, a D-Bus `Start` call — forever.
    // Our listeners are already removed, so neither notify reaches this
    // dying State.
    FilePickerController.instance.complete(null);
    ScreencastPickerController.instance.cancel();
    // Abandons rather than unlocks: a shell dying while the session is locked
    // must leave it locked. See [SessionLockHost.dispose].
    _lockHost.dispose();
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
    // All five root-owned overlays, symmetrically: each dispose covers the
    // window, the coordinator registration, the AppIndex bracket, and the
    // closing notifier.
    for (final overlay in [
      _settings,
      _launcher,
      _appChooser,
      _screencastPicker,
      _filePicker,
    ]) {
      overlay.dispose();
    }
    _liveConfig.dispose();
    super.dispose();
  }

  /// The ambient providers every window in the shell gets.
  ///
  /// An `InheritedWidget` cannot span FlutterViews and the shell renders into
  /// one view per panel per monitor plus a window for every popup, overlay, OSD
  /// card and lock surface — so the palette and the start-up service state are
  /// installed once per window rather than once for the tree. [ThemeProvider]
  /// stays the only thing that constructs a [ThemeScope].
  Widget _windowChrome(Widget child) => ShellServicesScope(
        services: widget.services,
        child: LiveConfigProvider(
          config: _liveConfig,
          // ShellTextRoot inside ThemeProvider: it reads ThemeScope for the
          // font family every window's text should inherit.
          child: ThemeProvider(child: ShellTextRoot(child: child)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Iterate the *startup* panels — those own the layer-shell controllers —
    // but render each with the live config merged onto its fixed geometry.
    final startupPanels = widget.appConfig.panels;

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
              // PanelWindowManager and the window chrome are what let the
              // desktop grid open popups: LayerShellWindow already supplies the
              // View and the WindowScope, but PopupHost also needs a
              // WindowRegistry, and popup content is built outside the parent's
              // ThemeScope.
              //
              // Deliberately no DisplayScope: the grid takes its geometry from
              // a LayoutBuilder and never needs the output at all.
              child: PanelWindowManager(
                child: _windowChrome(
                  // A click on the desktop dismisses whatever a *panel* has
                  // open: the two surfaces have separate registries and no
                  // shared widget tree, so the coordinator is the only thing
                  // that can carry the signal across.
                  PopupDismissArea(
                    child: Builder(builder: (context) {
                      final live = LiveConfigScope.of(context);
                      // Background surface existence is startup-only; while it
                      // exists, follow live edits (fit / entry paths) but keep
                      // the startup wallpaper if the user clears every entry
                      // (a full removal needs a restart).
                      //
                      // Null here means "surface, but nothing to paint" — the
                      // grid-only case. That must render as *nothing*, not as
                      // BackgroundWindow's opaque empty fill, or a user with
                      // icons and no wallpaper gets a black desktop instead of
                      // whatever their compositor draws.
                      final liveBg = live.background;
                      final startupBg = widget.appConfig.background;
                      final BackgroundConfig? bgConfig = !_hasBackgroundSurface
                          ? null
                          : (liveBg != null && liveBg.entries.isNotEmpty
                              ? liveBg
                              : startupBg);
                      return DesktopSurface(
                        background: bgConfig,
                        desktop: live.desktop,
                        store: DesktopStore.instance,
                        // Startup panel geometry, like _createSurfaces: the
                        // anchor a surface was built with cannot change
                        // without a restart.
                        panels: widget.appConfig.panels,
                        onChangeBackground: () => SettingsController.instance
                            .open(SettingsRoute.background),
                        onAddRequested: _onDesktopAddRequested,
                        onKeyboardRequested: (wanted) => _setDesktopKeyboard(
                            _monitorKey(surfaces.monitor), wanted),
                      );
                    }),
                  ),
                ),
              ),
            ),
          // Not gated on the output being known. Output enumeration is no
          // longer awaited before the first frame, so a bar that waited for it
          // would be a bar the user watches appear a beat after login; it
          // paints now and [DisplayScope] fills in a moment later.
          for (final entry in startupPanels.entries)
            if (surfaces.panels[entry.key] case final controller?)
              LayerShellWindow(
                key: ObjectKey(controller),
                controller: controller,
                child: PanelWindowManager(
                  child: _windowChrome(
                    MiracleScope(
                      manager: widget.miracle,
                      child: DisplayProvider(
                        monitor: surfaces.monitor,
                        outputs: widget.outputs,
                        child: Builder(builder: (context) {
                          final panel = effectivePanel(
                            entry.value,
                            LiveConfigScope.of(context).panels[entry.key],
                          );
                          // A click anywhere on the bar — an icon whose
                          // popup is not open, or bare padding — dismisses
                          // whatever else the shell has up.
                          return PopupDismissArea(
                            child: PanelMain(
                              panelConfig: panel,
                              anchor: panel.anchor,
                            ),
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
              child: _windowChrome(OsdWindow(store: OsdStore.instance)),
            ),
        ],
        // The settings overlay opened by the global shortcut. A single window
        // (not per-monitor), so it lives outside the per-monitor loop above.
        if (_settings.controller case final settings?)
          LayerShellWindow(
            key: ObjectKey(settings),
            controller: settings,
            child: _windowChrome(
              SettingsOverlay(
                closingNotifier: _settings.closing,
                onClosed: _onSettingsClosed,
                route: _settingsRoute,
              ),
            ),
          ),
        // The application chooser opened by the desktop's "Add application…".
        // A single window, like the launcher, so it lives outside the loop.
        if (_appChooser.controller case final chooser?)
          LayerShellWindow(
            key: ObjectKey(chooser),
            controller: chooser,
            child: _windowChrome(
              // The index is built after the first frame now, so a chooser
              // opened during start-up gets an empty list and a loader.
              _AppIndexBuilder(
                builder: (context, apps, loading) => AppChooserOverlay(
                  apps: apps,
                  loading: loading,
                  onSelected: (app) {
                    final cell = _appChooserCell;
                    _closeAppChooser();
                    if (cell != null && app.filename.isNotEmpty) {
                      _pinToDesktop(
                        DesktopItem(
                          kind: DesktopItemKind.app,
                          target: app.filename,
                        ),
                        cell,
                      );
                    }
                  },
                  onCancel: _closeAppChooser,
                ),
              ),
            ),
          ),
        // The file picker asked for by a surface that cannot host a modal —
        // today the desktop grid, which is on the background layer.
        if ((_filePicker.controller, FilePickerController.instance.pending)
            case (final picker?, final request?))
          LayerShellWindow(
            key: ObjectKey(picker),
            controller: picker,
            child: _windowChrome(
              FilePickerWindow(
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
        if (_launcher.controller case final launcher?)
          LayerShellWindow(
            key: ObjectKey(launcher),
            controller: launcher,
            child: _windowChrome(
              // Ctrl+Space can beat the index to the finish line. A loader
              // says so; "No applications" would be a lie the user acts on.
              _AppIndexBuilder(
                builder: (context, apps, loading) => LauncherOverlay(
                  closingNotifier: _launcher.closing,
                  onClosed: _onLauncherClosed,
                  apps: apps,
                  loading: loading,
                  onLaunch: (app) => launchApp(app.appInfo),
                  onLaunchAction: (app, action) =>
                      launchAppAction(app.appInfo, action.id),
                ),
              ),
            ),
          ),
        // The screen-share consent picker, open only while an application's
        // portal request is waiting on an answer. Single window, like the
        // launcher, so it lives outside the per-monitor loop.
        if ((_screencastPicker.controller, _screencastRequest)
            case (final picker?, final request?))
          LayerShellWindow(
            key: ObjectKey(picker),
            controller: picker,
            child: _windowChrome(
              Builder(builder: (context) {
                final connection = screencastService?.connection;
                final sources = connection == null
                    ? (monitors: <PickerSource>[], windows: <PickerSource>[])
                    : buildPickerSources(connection, request,
                        previewFps: LiveConfigScope.of(context)
                            .screenshare
                            .previewFps);
                return ScreencastPickerOverlay(
                  request: request,
                  monitors: sources.monitors,
                  windows: sources.windows,
                  closingNotifier: _screencastPicker.closing,
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
        for (final controller in _lockHost.windows)
          SessionLockWindow(
            key: ObjectKey(controller),
            controller: controller,
            child: _windowChrome(
              Builder(builder: (context) {
                return LockScreen(
                  config: LiveConfigScope.of(context).lock,
                  onUnlocked: _lockHost.unlock,
                );
              }),
            ),
          ),
      ],
    );
  }
}

/// Merges live-updatable panel fields (module layout, horizontal padding)
/// onto the startup window geometry (anchor/height/layer), which cannot change
/// without recreating the native window. Falls back to [startup] for a panel
/// removed after launch.
PanelConfig effectivePanel(PanelConfig startup, PanelConfig? live) {
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
    // Module options are pushed into the module imperatively and read out of
    // `builder` at build time, so nothing about this widget's inputs says they
    // moved — [Module.configChanges] is what does. Listening per module rather
    // than per panel keeps a `[modules.clock]` edit off every other module in
    // the bar.
    return ListenableBuilder(
      listenable: Module.configChanges,
      builder: (context, _) => module.builder(context),
    );
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

/// One root-owned full-screen overlay window.
///
/// Owns the four things every such overlay needs and that each of the five
/// used to carry as loose fields: the [LayershellWindowController], the
/// [PopupCoordinator] registration (keyed by a sentinel [owner], because one
/// State owns all five and the coordinator identifies a surface by owner),
/// the [closing] notifier that drives a graceful fade-out, and the AppIndex
/// bracket for windows whose rows hold `GAppInfo` pointers.
///
/// The deltas between the five are constructor arguments, not subclasses:
/// [policy] (modal for the consent pickers), [acquiresAppIndex] (launcher and
/// app chooser), and [open]'s `monitor` (the settings overlay pins to the
/// first monitor; the rest pass none, so the compositor places them on its
/// focused output — where the user is).
class _OverlayWindow {
  _OverlayWindow({
    this.policy = TransientPolicy.menu,
    this.acquiresAppIndex = false,
  });

  final TransientPolicy policy;

  /// Whether the window's content holds `GAppInfo` pointers from [AppIndex] —
  /// the index defers refreshes while it is open (`_openLauncher`'s rule).
  final bool acquiresAppIndex;

  final Object owner = Object();

  /// Drives the content's fade-out. The coordinator's dismiss flips it; the
  /// content plays its exit animation and calls back into the root, which
  /// calls [take].
  final ValueNotifier<bool> closing = ValueNotifier(false);

  LayershellWindowController? controller;
  TransientHandle? _handle;

  bool get isOpen => controller != null;

  /// Creates the native window and registers with the coordinator.
  ///
  /// The window is always overlay-layer, all-edges, keyboard `onDemand` —
  /// full-screen means the whole output, panels included, or the backdrop
  /// stops short of the bars and dismiss-on-backdrop has dead strips (hence
  /// [spanFullOutput]). [onDismiss] is what the coordinator calls to ask for
  /// a *graceful* close; the default flips [closing] and lets the content
  /// animate out. Pass a direct close for content with no exit animation.
  void open({ffi.Pointer<ffi.NativeType>? monitor, VoidCallback? onDismiss}) {
    if (isOpen) return;
    closing.value = false;
    if (acquiresAppIndex) AppIndex.instance.acquire();
    final created = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [
        LayerShellEdge.top,
        LayerShellEdge.bottom,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      keyboardMode: LayerShellKeyboardMode.onDemand,
      monitor: monitor,
    );
    spanFullOutput(created);
    controller = created;
    // The coordinator asks for the fade-out, never the teardown: the content
    // destroys the window once its animation is done.
    _handle = PopupCoordinator.instance.open(
      owner: owner,
      policy: policy,
      onDismiss: onDismiss ?? () => closing.value = true,
    );
  }

  /// Unregisters and hands back the controller for `_destroyAfterFrame`, or
  /// null when already closed. The caller detaches the view (setState) before
  /// the native window dies.
  LayershellWindowController? take() {
    final removed = controller;
    if (removed == null) return null;
    controller = null;
    PopupCoordinator.instance.close(_handle);
    _handle = null;
    if (acquiresAppIndex) AppIndex.instance.release();
    return removed;
  }

  /// Root teardown: window, registration, index bracket, notifier — all of
  /// it, so `dispose` cannot be asymmetric with what an open overlay holds.
  void dispose() {
    take()?.destroy();
    closing.dispose();
  }
}

/// Feeds a root-owned overlay the application index, live, so the root does not
/// have to rebuild every view when the index lands.
///
/// Two sources, because they answer different halves of the question. The list
/// comes from [AppIndex], which notifies when applications are installed or
/// removed. "Is it built yet" comes from the [ShellServicesScope] that
/// [_GracefulShellRootState._windowChrome] already installs — and that
/// dependency is *also* what delivers the very first list, because
/// [AppIndex.start] fills `searchable` without notifying anybody. A builder
/// that only listened to the index would sit on its loader forever, which is
/// why both reads have to happen on this one element rather than in nested
/// builders where only the inner one sees the list.
class _AppIndexBuilder extends StatelessWidget {
  const _AppIndexBuilder({required this.builder});

  final Widget Function(BuildContext context, List<SearchableApp> apps,
      bool loading) builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppIndex.instance,
        builder: (context, _) => builder(
          context,
          AppIndex.instance.searchable,
          ShellServicesScope.isLoading(context, ShellService.applications),
        ),
      );
}
