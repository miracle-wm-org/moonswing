import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: implementation_imports
import 'package:flutter/widgets.dart';
// The controller supertype every window in the registry is keyed on.
// `layer_shell` re-exports WindowManager / WindowRegistry / WindowEntry but not
// this, and there is nowhere else to reach it from.
import 'package:flutter/src/widgets/_window.dart' show BaseWindowController;
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/app_scope.dart';
import 'package:graceful_shell/capture/selection_controller.dart';
import 'package:graceful_shell/capture/selector_overlay.dart';
import 'package:graceful_shell/capture/window_targets.dart';
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
import 'package:graceful_shell/modules/github.dart';
import 'package:graceful_shell/modules/keybinds.dart';
import 'package:graceful_shell/modules/keyboard_layout.dart';
import 'package:graceful_shell/modules/launcher.dart';
import 'package:graceful_shell/modules/sound_control.dart';
import 'package:graceful_shell/modules/clock.dart';
import 'package:graceful_shell/modules/media_player.dart';
import 'package:graceful_shell/modules/network.dart';
import 'package:graceful_shell/modules/notifications.dart';
import 'package:graceful_shell/modules/screen_recorder.dart';
import 'package:graceful_shell/modules/screenshot.dart';
import 'package:graceful_shell/modules/system.dart';
import 'package:graceful_shell/modules/system_monitor.dart';
import 'package:graceful_shell/modules/system_tray.dart';
import 'package:graceful_shell/modules/weather.dart';
import 'package:graceful_shell/modules/workspaces.dart';
import 'package:graceful_shell/emoji/emoji_clipboard.dart';
import 'package:graceful_shell/emoji/emoji_controller.dart';
import 'package:graceful_shell/emoji/emoji_picker_overlay.dart';
import 'package:graceful_shell/input_trigger/input_trigger_service.dart';
import 'package:graceful_shell/input_trigger/input_trigger_store.dart';
import 'package:graceful_shell/keybinds/keybind_cheatsheet_controller.dart';
import 'package:graceful_shell/keybinds/keybind_cheatsheet_overlay.dart';
import 'package:graceful_shell/keybinds/keybind_store.dart';
import 'package:graceful_shell/keybinds/shell_keybind_store.dart';
import 'package:graceful_shell/launcher/app_index.dart';
import 'package:graceful_shell/launcher/app_search.dart';
import 'package:graceful_shell/launcher/launcher_controller.dart';
import 'package:graceful_shell/launcher/launcher_overlay.dart';
import 'package:graceful_shell/lock/lock_controller.dart';
import 'package:graceful_shell/lock/lock_screen.dart';
import 'package:graceful_shell/live_config_provider.dart';
import 'package:graceful_shell/lock/session_lock_host.dart';
import 'package:graceful_shell/notification_badge.dart';
import 'package:graceful_shell/notification_panel_controller.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/osd/osd.dart';
import 'package:graceful_shell/osd/osd_service.dart';
import 'package:graceful_shell/osd/osd_store.dart';
import 'package:graceful_shell/panel_background.dart';
import 'package:graceful_shell/panel_rim.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/polkit/auth_controller.dart';
import 'package:graceful_shell/polkit/auth_dialog.dart';
import 'package:graceful_shell/polkit/auth_session.dart';
import 'package:graceful_shell/polkit/polkit_agent.dart';
import 'package:graceful_shell/polkit/polkit_types.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/power/power_actions.dart';
import 'package:graceful_shell/power/power_controller.dart';
import 'package:graceful_shell/power/power_menu_overlay.dart';
import 'package:graceful_shell/power/power_service.dart';
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
import 'package:graceful_shell/desktop/widgets/analog_clock_widget.dart';
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
import 'package:ext_session_lock/ext_session_lock.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:media_kit/media_kit.dart';
import 'package:wayland/wayland.dart';

/// Whether every root-owned window drops out of the semantics tree.
///
/// **This switches accessibility off, and it is a stopgap.** The semantics pass
/// measured as 37% of the shell's UI thread: it is charged per view per frame,
/// the shell has around seven views, and the Linux embedder offers no way to
/// refuse it — so the only lever is an empty tree. Set
/// `GRACEFUL_SHELL_SEMANTICS=1` to put it back; the real fix is a cheap tree.
final bool kExcludeSemantics = () {
  final on = Platform.environment['GRACEFUL_SHELL_SEMANTICS'];
  return on == null || on.isEmpty || on == '0';
}();

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
  Module.register(screenshotModule);
  Module.register(screenRecorderModule);
  Module.register(keyboardLayoutModule);
  Module.register(keybindsModule);
  Module.register(githubModule);

  // The desktop grid's own registry, populated the same way: `[[desktop.widgets]]`
  // names a type, and lookup happens at render time. See
  // `lib/desktop/widgets/desktop_widget.dart`.
  DesktopWidgetRegistry.register(mediaPlayerDesktopWidget);
  DesktopWidgetRegistry.register(weatherDesktopWidget);
  DesktopWidgetRegistry.register(moonDesktopWidget);
  DesktopWidgetRegistry.register(fortuneDesktopWidget);
  DesktopWidgetRegistry.register(tuxDesktopWidget);
  DesktopWidgetRegistry.register(analogClockDesktopWidget);

  // The only awaits before the first frame, and they have to be: every native
  // window's geometry comes out of them. Everything else starts in
  // [_startShellServices], after the shell has painted.
  final appConfig = await AppConfig.load();
  final store = await ConfigStore.initShared();

  // Seeds the shipped themes into ~/.config/graceful-shell/themes on first run
  // and resolves the one config.toml names, before anything paints.
  startThemeService(store);

  // Reads the pinned desktop icons, so the grid paints with the background
  // surface's first frame. Like the theme store it watches ConfigStore for its
  // own subtree only.
  startDesktopService(store);

  // Configures the system stats store, but does not start it polling — the
  // first lease (the bar module, or the monitor tab being opened) does that.
  startSystemStatsService();

  screencastLog = (message) => debugPrint('screencast: $message');
  polkitLog = (message) => debugPrint('polkit: $message');
  appScopeLog = (message) => debugPrint('app-scope: $message');

  // Miracle may not be running yet (or at all). The manager keeps the shell
  // usable either way — the workspaces module offers a retry when it is absent.
  final miracle = MiracleManager();

  // Points the keybind cheat sheet's store at that connection. Not a
  // `ShellService`: there is nothing to start — the sheet's first lease is what
  // reads — and a machine with no compositor must not settle a start-up task
  // `failed` over a cheat sheet nobody has opened.
  startKeybindService(miracle);

  // The sheet's other half: the shell's own `[shortcuts]`, which — unlike
  // miracle's bindings — it can also edit. Handed the snapshot the shortcuts
  // below are registered from, so an edit can be told apart from what the
  // keyboard actually does until the shell is restarted.
  startShellKeybindService(store, registered: appConfig.shortcuts);

  // Live registry of outputs, kept current as monitors come and go. Empty until
  // [_connectDisplays] has enumerated them, which is why panels render before
  // they know which display they are on.
  final outputs = OutputTracker();

  final waylandClient = WaylandClient();
  final services = ShellServices();

  // Installs a windowing owner that handles layer-shell *and* session-lock
  // windows; it subclasses the layer-shell one, so panels/popups are unaffected.
  initSessionLock();

  // Layer-shell controllers are created from within the widget tree (see
  // [_GracefulShellRootState.initState]), not here, so GTK's windowing system is
  // fully initialized before the first surface.
  runWidget(
    GracefulShellRoot(
      appConfig: appConfig,
      store: store,
      miracle: miracle,
      outputs: outputs,
      services: services,
    ),
  );

  // Start-up I/O runs after the shell is on screen. The application index in
  // particular is a synchronous walk of every installed `.desktop` file, and
  // starting it earlier would hold the isolate through the frame it follows.
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

/// Hands every global start-up task to [services], which runs them off the first
/// frame and publishes how far along each is.
///
/// Order is the order tasks get their first event-loop turn: I/O-bound ones
/// first so their round-trips are in flight, the application index last because
/// it works synchronously.
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
  // share get the shell's own picker. A compositor without ext-image-copy-capture
  // or a machine with no PipeWire throws, which `run` records as `failed`.
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

  // Registers the shell as this session's polkit authentication agent, so a
  // privileged operation gets a prompt instead of a flat `AccessDenied`. A
  // session that already has an agent is yielded to (recorded as ready);
  // anything else throws and is recorded as failed.
  if (appConfig.polkit.enabled) {
    services.run(
      ShellService.polkit,
      () => startPolkitAgentService(
        presenter: PolkitAuthController.instance.present,
        maxAttempts: appConfig.polkit.maxAttempts,
      ),
    );
  } else {
    services.skip(ShellService.polkit);
  }

  // Takes logind's `handle-power-key` inhibitor so the power button reaches the
  // shell rather than powering the machine off behind it. Nothing is claimed
  // until the compositor confirms the shell owns the key (see [PowerKeyService]),
  // and `key_action = "none"` claims nothing at all.
  services.run(ShellService.power, () => startPowerService(appConfig.power));

  // Enumerates installed applications while the shell is already on screen, so
  // the launcher can paint the instant its shortcut fires. Until it lands the
  // launcher and app choosers show a loader rather than "No applications".
  services.run(ShellService.applications, () async {
    startAppIndexService();
  });
}

/// Opens the Wayland connection, registers the shell's global shortcuts, and
/// enumerates the compositor's outputs into [outputs].
///
/// Completes once every start-up output has reported its properties. The
/// registry callbacks stay connected, so later `wl_output` globals are tracked.
Future<void> _connectDisplays(
  WaylandClient waylandClient,
  OutputTracker outputs,
  AppConfig appConfig,
) async {
  await waylandClient.connect();

  // Registers the shell's global shortcuts with the compositor via the
  // ext-input-trigger protocols. On a compositor lacking them nothing is bound
  // and the shell is unaffected.
  final inputTriggers = startInputTriggerService(
    waylandClient,
    shortcuts: appConfig.shortcuts,
  );

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
        waylandRegistry!,
        globalName,
        interface,
        version,
      );
    },
    onGlobalRemove: (globalName) => outputs.remove(globalName),
  );
  final syncCompleter = Completer<void>();
  waylandClient.sync((_) => syncCompleter.complete());
  await syncCompleter.future;
  await Future.wait(outputCompleters.map((c) => c.future));

  // The initial global burst is done. If the input-trigger managers weren't
  // among them the compositor doesn't implement these protocols — the shortcuts
  // silently won't work, so say so once.
  if (!inputTriggers.isRegistered) {
    debugPrint(
      'input-trigger: compositor did not advertise the '
      'ext-input-trigger globals; global shortcuts are unavailable',
    );
    // Including the power button, the one shortcut whose absence has a
    // consequence beyond itself: the shell must not go on holding logind's
    // inhibitor for a key that will never arrive.
    inputTriggers.reportUnregistered();
  }
}

/// Root of the widget tree. Owns the lifecycle of every layer-shell window
/// (backgrounds + panels) on every monitor: creating them for the monitors
/// present at startup, adding and destroying them on hotplug, and tearing them
/// all down in [dispose].
class GracefulShellRoot extends StatefulWidget {
  const GracefulShellRoot({
    super.key,
    required this.appConfig,
    required this.store,
    required this.miracle,
    required this.outputs,
    required this.services,
  });

  /// The config captured at startup. Native layer-shell windows are created from
  /// this snapshot and cannot change without a restart; live values come from
  /// [store].
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
  /// Mutable, and refreshed by [_GracefulShellRootState._syncMonitors] on a
  /// reconfigure: a panel carrying a stale position could no longer be matched
  /// to its `wl_output`.
  MonitorInfo monitor;
  final LayershellWindowController? background;
  final Map<String, LayershellWindowController> panels;

  /// Every native controller owned by this monitor, for teardown.
  Iterable<LayershellWindowController> get controllers => [
    ?background,
    ...panels.values,
  ];
}

/// One native window the root owns, and the content that goes in it.
///
/// A record rather than the [WindowEntry] itself: an entry lives as long as its
/// window, while this is recomputed on every reconciliation.
typedef _RootWindow = ({
  BaseWindowController controller,
  WidgetBuilder builder,
});

class _GracefulShellRootState extends State<GracefulShellRoot> {
  /// The [WindowRegistry] the root's [WindowManager] publishes, once a window
  /// below has handed it back (see [_RegistryBinder]).
  ///
  /// Null only while the registry is empty, so [_syncWindows] answers that by
  /// bumping [_managerGeneration] to remount the manager — losing nothing.
  WindowRegistry? _registry;

  /// Keys the root [WindowManager], so a bump gives it a fresh state that reads
  /// `initialWindows` again. Only [_syncWindows] bumps it, and only while
  /// [_registry] is still null.
  int _managerGeneration = 0;

  /// The root's own registry entries, keyed on the controller.
  ///
  /// Not the whole registry: modules register their popups into the same one.
  /// [_syncWindows] therefore diffs this map and registers/unregisters the
  /// difference alone.
  final Map<BaseWindowController, WindowEntry> _rootEntries = {};

  /// Surfaces keyed by a stable monitor identity ([_monitorKey]), added and
  /// removed on hotplug — the live source of truth for what the shell renders.
  final Map<String, _MonitorSurfaces> _surfaces = {};

  /// Whether a background surface should exist on each monitor. Fixed at startup
  /// (like the native window geometry) so newly-plugged monitors get one too.
  ///
  /// A wallpaper to paint or the desktop icon grid to host; either alone is
  /// enough. [ConfigStore.needsRestart] signs the same decision.
  late final bool _hasBackgroundSurface;

  /// The on-screen indicator's windows, keyed like [_surfaces]. Unlike panels
  /// these exist only while [OsdStore] holds a request: with no input-region
  /// support a permanently-mapped overlay surface would eat clicks.
  final Map<String, LayershellWindowController> _osd = {};

  /// The floating notification badges, keyed like [_osd] and living as long:
  /// only while there is something to report, or the surface would swallow
  /// clicks. One per monitor; tapping any opens the one panel, on that monitor.
  final Map<String, LayershellWindowController> _badges = {};

  /// Nine of the ten root-owned overlays — the full-screen ones; the
  /// notification panel is the exception. Each [_OverlayWindow] carries the
  /// controller, its [PopupCoordinator] registration and the closing notifier.
  ///
  /// The two pickers are modal: dismissing a consent prompt is a denial, and
  /// only its controller may resolve it.
  final _OverlayWindow _settings = _OverlayWindow();
  final _OverlayWindow _launcher = _OverlayWindow(acquiresAppIndex: true);
  final _OverlayWindow _appChooser = _OverlayWindow(acquiresAppIndex: true);

  /// The emoji picker (Ctrl+Shift+E). A menu policy rather than a modal one: it
  /// copies a character and nothing is owed an answer, so anything wanting the
  /// screen may displace it.
  final _OverlayWindow _emojiPicker = _OverlayWindow();

  /// The miracle keybind cheat sheet, opened by the bar's keyboard icon. A menu
  /// policy like the emoji picker: it is a thing to read, it owes nobody an
  /// answer, and anything wanting the screen may displace it.
  final _OverlayWindow _keybinds = _OverlayWindow();
  final _OverlayWindow _screencastPicker = _OverlayWindow(
    policy: TransientPolicy.modal,
  );
  final _OverlayWindow _filePicker = _OverlayWindow(
    policy: TransientPolicy.modal,
  );

  /// The power menu the physical power button opens (`[power] key_action =
  /// "menu"`, the default). Modal like the two pickers: it holds a shutdown, so
  /// the only ways out are its own Cancel path.
  final _OverlayWindow _powerMenu = _OverlayWindow(
    policy: TransientPolicy.modal,
  );

  /// The polkit prompt. Modal, for a stronger version of the consent pickers'
  /// reason: it grants administrator rights, so nothing else may dismiss it and
  /// dismissing it *is* the refusal.
  final _OverlayWindow _polkitPrompt = _OverlayWindow(
    policy: TransientPolicy.modal,
  );

  /// The authentication the open prompt is answering, captured at window
  /// creation: the controller's `pending` moves as soon as the user answers,
  /// while the dialog stays mounted through its fade-out, so a superseding
  /// request would otherwise render into the window the old one is leaving.
  PolkitAuthSession? _polkitSession;

  /// The notification panel — the tenth root-owned overlay, and the only one
  /// that is not full-screen. The bell and the badge share no widget ancestry,
  /// so both ask the root instead. `late final` because it brings its own
  /// window, a column down one output edge.
  late final _OverlayWindow _notifications = _OverlayWindow(
    create: _createNotificationWindow,
  );

  /// The page the open (or about-to-open) settings overlay was asked for. Null
  /// is the default landing page.
  SettingsRoute? _settingsRoute;

  /// A route that arrived while an overlay was already up. The overlay seeds its
  /// tab in `initState`, so retargeting means closing and reopening; this holds
  /// the destination across those two frames.
  SettingsRoute? _pendingSettingsRoute;

  /// Monitor keys whose background surface currently takes keyboard focus for
  /// an in-place desktop rename. Empty is the normal state.
  final Set<String> _desktopKeyboard = {};

  /// The cell the app chooser's pick should land in; non-null exactly while
  /// the chooser is on screen.
  GridCell? _appChooserCell;

  /// The request the open screencast picker is answering, captured at window
  /// creation: the controller clears `pending` as soon as the user answers, but
  /// the overlay stays mounted through its fade-out.
  PickRequest? _screencastRequest;

  /// The screenshot / recording selection surfaces, keyed like [_surfaces].
  ///
  /// One per monitor rather than one window: a layer-shell surface covers one
  /// output. Like the OSD's they exist only while something is being selected.
  final Map<String, LayershellWindowController> _selector = {};

  /// What the open selection surfaces are asking, the environment they are
  /// drawing, and what came back. All three are null/empty exactly when
  /// [_selector] is empty.
  SelectionRequest? _selectionRequest;
  CaptureScene _selectionScene = CaptureScene.empty;
  CaptureTarget? _selectionAnswer;

  /// Flips to start the surfaces coming down; every one of them answers with
  /// [_onSelectionClosed], which is idempotent.
  final ValueNotifier<bool> _selectionClosing = ValueNotifier(false);

  /// The coordinator registration all of the selection surfaces share — they
  /// are one modal, drawn once per output.
  final Object _selectionOwner = Object();
  TransientHandle? _selectionHandle;

  /// True between a selection being asked for and its surfaces existing: the
  /// environment is read over the IPC socket in between, and a second notify in
  /// that gap would open a second set.
  bool _selectionOpening = false;

  /// The `ext-session-lock-v1` lifecycle. The root's rather than the module
  /// offering the Lock button, because the lock spans every monitor and outlives
  /// any one panel; everything else lives in [SessionLockHost].
  late final SessionLockHost _lockHost;

  late final MonitorWatcher _monitorWatcher;
  bool _syncScheduled = false;

  /// Every external listenable the root watches, with its handler. Wired in
  /// [initState] and drained in [dispose] from this one list, so the add and
  /// remove sides cannot drift apart.
  late final List<(Listenable, VoidCallback)> _subscriptions;

  /// The config the widget tree renders from, kept in sync by [_onConfigChanged].
  /// Window geometry still comes from [widget.appConfig], the startup snapshot.
  ///
  /// A notifier published through [LiveConfigProvider] rather than a plain field:
  /// `ConfigStore` notifies on every keystroke in the settings UI, and answering
  /// each with `setState` rebuilt every view the root owns.
  late final ValueNotifier<AppConfig> _liveConfig;

  /// The panel margin currently committed to the native surfaces.
  ///
  /// Cached so [_onThemeChanged] can tell whether it actually moved: the store
  /// notifies on every frame of a colour-picker drag, and re-committing every
  /// layer surface that often makes the bars flicker.
  int _panelMargin = 0;

  @override
  void initState() {
    super.initState();
    final appConfig = widget.appConfig;
    _liveConfig = ValueNotifier(appConfig);
    _lockHost = SessionLockHost(onChanged: _refreshWindows);
    _hasBackgroundSurface =
        (appConfig.background?.entries.isNotEmpty ?? false) ||
        appConfig.desktop.enabled;
    _subscriptions = [
      (widget.store, _onConfigChanged),
      (OsdStore.instance, _onOsdChanged),
      (InputTriggerStore.instance, _onSettingsTriggered),
      (LauncherController.instance, _onLauncherTriggered),
      (EmojiPickerController.instance, _onEmojiPickerTriggered),
      (KeybindCheatsheetController.instance, _onKeybindsTriggered),
      (PowerController.instance, _onPowerKeyPressed),
      (ScreencastPickerController.instance, _onScreencastPickChanged),
      (PolkitAuthController.instance, _onPolkitAuthChanged),
      (CaptureSelectionController.instance, _onCaptureSelectionChanged),
      (LockController.instance, _onLockRequested),
      (NotificationPanelController.instance, _onNotificationPanelToggled),
      // The badges are created and destroyed off the store's own emptiness,
      // which makes them appear the moment something arrives without anything
      // having to notice that it did.
      (NotificationStore.instance, _syncNotificationBadges),
      (SettingsController.instance, _onSettingsRouteRequested),
      (FilePickerController.instance, _onFilePickRequested),
      (ThemeStore.instance, _onThemeChanged),
      // The only signal a *reconfigured* monitor produces: GDK emits neither
      // `monitor-added` nor `monitor-removed` for a reposition, but every output
      // reports its new geometry over `wl_output`.
      (widget.outputs, _scheduleMonitorSync),
    ];
    for (final (listenable, handler) in _subscriptions) {
      listenable.addListener(handler);
    }
    // startThemeService() resolved the palette in main(), so the margin is known
    // before the first surface is built and no bar is created flush and then
    // nudged.
    _panelMargin = ThemeStore.instance.theme.panelMargin;

    for (final monitor in listMonitors()) {
      _surfaces[_monitorKey(monitor)] = _createSurfaces(monitor);
    }

    // React to monitors being plugged in / unplugged at runtime.
    _monitorWatcher = MonitorWatcher(_scheduleMonitorSync);

    // Fills [_rootEntries] before the first build, so the surfaces just created
    // are what the root [WindowManager] gets as `initialWindows`. Not
    // [_refreshWindows]: nothing is built yet, and `setState` from `initState`
    // is an error.
    _syncWindows();
  }

  /// A stable key identifying a monitor across enumerations. The connector name
  /// (e.g. `DP-1`) survives other monitors coming and going; only a GDK build
  /// that cannot report it falls back to make/model/position.
  String _monitorKey(MonitorInfo monitor) => monitor.connector.isNotEmpty
      ? monitor.connector
      : '${monitor.manufacturer}|${monitor.model}|'
            '${monitor.position.dx},${monitor.position.dy}';

  /// Builds the layer-shell controllers (background + panels) for [monitor],
  /// realizing the native GTK windows immediately; the widgets rendering into
  /// them are attached on the next [build].
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

      // No `keyboardMode`, deliberately: layer_shell defaults it to
      // [LayerShellKeyboardMode.none], which is what a bar wants — a panel that
      // takes focus takes it on every click and pulls it off whatever the user
      // was typing in. The cost is that a popup inherits `none`; see
      // [_borrowPopupKeyboard].
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
      setPanelMargin(
        controller,
        anchor: panelConfig.anchor,
        margin: _panelMargin,
      );
      panels[entry.key] = controller;
    }

    return _MonitorSurfaces(monitor, background, panels);
  }

  /// Builds the indicator window for [monitor]: a small card above the bottom
  /// edge. Anchoring to that edge alone lets layer-shell centre the window, and
  /// keeps the surface — and the region that swallows clicks — card-sized.
  LayershellWindowController _createOsd(MonitorInfo monitor) {
    // The surface is the card plus the theme's shadow: the card's Row has an
    // Expanded, so a shadow would be clipped. Deliberately the no-`attachEdge`
    // call — the OSD is bottom-centred with nothing to be flush against — and
    // `osd.dart` hands the same margin back with the same call, with nothing
    // linking the two at compile time.
    final shadow = popupShadowInsets(ThemeStore.instance.theme);
    final controller = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [LayerShellEdge.bottom],
      keyboardMode: LayerShellKeyboardMode.none,
      width: (kOsdWindowSize.width + shadow.horizontal).round(),
      height: (kOsdWindowSize.height + shadow.vertical).round(),
      monitor: monitor.gdkMonitor,
    );
    // A direct read: this commits to a native layer surface rather than
    // rendering, so it cannot go through [LiveConfigScope]. The bottom margin
    // gives back what the surface grew by, floored at 0 so a deep shadow cannot
    // push the card off-screen.
    final margin = (_liveConfig.value.osd.margin - shadow.bottom).round();
    controller.setMargin(LayerShellEdge.bottom, margin < 0 ? 0 : margin);
    return controller;
  }

  /// Creates the indicator windows when [OsdStore] gets a request and destroys
  /// them once it clears. While a request is live this does nothing — the card
  /// listens to the store itself, so a burst of volume-key presses maps to one
  /// window rather than one per press.
  void _onOsdChanged() {
    if (!mounted) return;
    final wanted = OsdStore.instance.current != null;
    if (wanted == _osd.isNotEmpty) return;

    if (wanted) {
      for (final entry in _surfaces.entries) {
        _osd[entry.key] = _createOsd(entry.value.monitor);
      }
      _refreshWindows();
      return;
    }

    final removed = _osd.values.toList();
    _osd.clear();
    _refreshWindows();
    _destroyAfterFrame(removed);
  }

  /// Builds the floating badge's window for [monitor]: a card pinned to the
  /// output's top-right corner.
  ///
  /// Deliberately **no** [spanFullOutput]. At the default exclusive zone of 0 the
  /// compositor has already placed the surface clear of the bars, margins
  /// included; [panelInsetsFor] would count every bar twice.
  LayershellWindowController _createBadge(MonitorInfo monitor) {
    final controller = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [LayerShellEdge.top, LayerShellEdge.right],
      // Nothing on the badge is typed into, and taking the keyboard off whatever
      // the user is working in to show them a bell would be worse than the
      // notification.
      keyboardMode: LayerShellKeyboardMode.none,
      width: kNotificationBadgeWindowSize.width.round(),
      height: kNotificationBadgeWindowSize.height.round(),
      monitor: monitor.gdkMonitor,
    );
    controller.setMargin(LayerShellEdge.top, kNotificationBadgeGap.round());
    controller.setMargin(LayerShellEdge.right, kNotificationBadgeGap.round());
    return controller;
  }

  /// Creates the badge windows when there is something to report and destroys
  /// them when there is not — [_onOsdChanged]'s shape and early return. The panel
  /// counts as "reported": it is a column down the same edge, so leaving the
  /// badge up would put it under the thing it exists to open.
  ///
  /// Silencing takes the badge away entirely, and it is the loudest thing
  /// silencing has to take: a button that plants itself in the corner of every
  /// output is the shell's most insistent way of asking for attention, so a
  /// user who has said "not now" and still gets it has not silenced anything.
  /// The store notifies on the flag, so flipping it here is a window teardown
  /// on the same listener a notification arriving is.
  void _syncNotificationBadges() {
    if (!mounted) return;
    final store = NotificationStore.instance;
    final wanted =
        store.items.isNotEmpty && !store.silenced && !_notifications.isOpen;
    if (wanted == _badges.isNotEmpty) return;

    if (wanted) {
      for (final entry in _surfaces.entries) {
        _badges[entry.key] = _createBadge(entry.value.monitor);
      }
      _refreshWindows();
      return;
    }

    final removed = _badges.values.toList();
    _badges.clear();
    _refreshWindows();
    _destroyAfterFrame(removed);
  }

  /// The notification panel's own window: full-height against the output's right
  /// edge, a quarter of its width.
  ///
  /// [spanFullOutput] here and not on the badge, because this surface is meant to
  /// cover the bars. `onDemand` keyboard is what lets its Escape binding fire —
  /// not `exclusive`, which would hold the keyboard off the focused window.
  LayershellWindowController _createNotificationWindow(
    ffi.Pointer<ffi.NativeType>? monitor,
  ) {
    final controller = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [
        LayerShellEdge.right,
        LayerShellEdge.top,
        LayerShellEdge.bottom,
      ],
      width: notificationPanelWidth(getScreenSize().width),
      // height omitted: top+bottom anchoring makes this full-height.
      keyboardMode: LayerShellKeyboardMode.onDemand,
      monitor: monitor,
    );
    spanFullOutput(controller);
    return controller;
  }

  /// The bell module asked for the panel. No monitor, so the compositor puts it
  /// on the focused output — the right rule for a trigger that could be on any
  /// bar on any display.
  void _onNotificationPanelToggled() {
    if (!mounted) return;
    _toggleNotificationPanel();
  }

  /// Toggles the panel, opening it on [monitor] when one is named. The badge
  /// names its own, so the panel arrives on the display just clicked rather than
  /// wherever the pointer last crossed a boundary.
  void _toggleNotificationPanel({ffi.Pointer<ffi.NativeType>? monitor}) {
    if (_notifications.isOpen) {
      // NotificationPanel plays its exit animation, then calls back into
      // [_onNotificationPanelClosed].
      _notifications.closing.value = true;
      return;
    }
    _notifications.open(monitor: monitor);
    NotificationPanelController.instance.setOpen(true);
    // Takes the badges down: they sit under the panel's own edge.
    _syncNotificationBadges();
    _refreshWindows();
  }

  /// Called by [NotificationPanel] once its exit animation has finished — from
  /// the bell, its own close button, Escape, or the [PopupCoordinator].
  void _onNotificationPanelClosed() {
    if (!mounted) return;
    final removed = _notifications.take();
    if (removed == null) return;
    NotificationPanelController.instance.setOpen(false);
    _refreshWindows();
    _destroyAfterFrame([removed]);
    // Anything still on the list gets its badge back, so a panel closed on a
    // full list does not leave the shell silent about it.
    _syncNotificationBadges();
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
      // [_openSettings] is what does it.
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
  /// Unlike [_openSettings] this passes no monitor: miracle places shell surfaces
  /// on its focused output, so the launcher appears where the user is looking.
  /// `onDemand` keyboard makes the field typeable at once.
  void _openLauncher() {
    _launcher.open();
    _refreshWindows();
  }

  /// The machine's physical power button was pressed.
  ///
  /// What that means is `[power] key_action`, read from the *live* config: the
  /// binding latches at registration, but the action is a Settings dropdown and
  /// has to take effect on the next press. A configured verb runs unconfirmed,
  /// because choosing one *is* the confirmation; the default menu toggles.
  void _onPowerKeyPressed() {
    if (!mounted) return;
    final action = _liveConfig.value.power.keyAction;
    if (action == PowerKeyAction.none) return;
    if (action == PowerKeyAction.menu) {
      if (_powerMenu.isOpen) {
        _powerMenu.closing.value = true;
      } else {
        _openPowerMenu();
      }
      return;
    }
    final verb = powerActionFor(action);
    if (verb != null) unawaited(PowerActions.run(verb));
  }

  /// Opens the power menu as a full-screen overlay-layer window.
  ///
  /// Like the launcher and unlike the settings overlay, no monitor: the
  /// compositor puts it on its focused output, which is where the user is.
  void _openPowerMenu() {
    _powerMenu.open();
    _refreshWindows();
  }

  /// Called by [PowerMenuOverlay] once its fade-out has finished.
  void _onPowerMenuClosed() {
    if (!mounted) return;
    final removed = _powerMenu.take();
    if (removed == null) return;
    _refreshWindows();
    _destroyAfterFrame([removed]);
  }

  /// An application asked to share the screen (or the pick was answered).
  ///
  /// The portal backend is blocked inside `Start` awaiting
  /// [ScreencastPickerController]. Includes the case where the *portal*
  /// cancelled (`Request.Close`) rather than the user.
  void _onScreencastPickChanged() {
    if (!mounted) return;
    final request = ScreencastPickerController.instance.pending;
    if (request != null) {
      if (_screencastPicker.isOpen) return;
      // Like the launcher (and unlike settings) no monitor is passed, so the
      // compositor puts the picker on the focused output — where the user is.
      _screencastRequest = request;
      _screencastPicker.open();
      _refreshWindows();
    } else if (_screencastPicker.isOpen) {
      _screencastPicker.closing.value = true;
    }
  }

  /// A capture module asked the user to choose what to capture.
  ///
  /// Unlike every other root-owned surface this cannot be raised inside the
  /// notification that asked for it, because its rectangles come from a
  /// `GET_TREE` round trip. [_selectionOpening] covers that gap.
  void _onCaptureSelectionChanged() {
    if (!mounted) return;
    final request = CaptureSelectionController.instance.pending;
    if (request == null) {
      if (_selector.isNotEmpty) _selectionClosing.value = true;
      return;
    }
    if (_selector.isNotEmpty || _selectionOpening) return;
    unawaited(_openSelection(request));
  }

  Future<void> _openSelection(SelectionRequest request) async {
    _selectionOpening = true;
    try {
      final scene = await _readCaptureScene();
      if (!mounted) return;
      // Whatever is pending *now*, which need not be the request that got us
      // here: the controller supersedes, so a second click while the socket was
      // answering has already cancelled ours. The scene is equally the answer
      // for either, so the one thing that must not happen is bailing out — that
      // would strand the newer request with no surfaces.
      final pending = CaptureSelectionController.instance.pending;
      if (pending == null) return;

      _selectionRequest = pending;
      _selectionScene = scene;
      _selectionAnswer = null;
      _selectionClosing.value = false;
      for (final entry in _surfaces.entries) {
        _selector[entry.key] = _createSelector(entry.value.monitor);
      }
      // Modal, like the two consent pickers: a full-screen surface that has taken
      // the pointer must not be dismissed by something else wanting the screen,
      // and only the user's own Escape, right-click or pick may answer it.
      _selectionHandle = PopupCoordinator.instance.open(
        owner: _selectionOwner,
        policy: TransientPolicy.modal,
        onDismiss: () => _selectionClosing.value = true,
      );
      _refreshWindows();
    } finally {
      _selectionOpening = false;
    }
  }

  /// The windowing environment, or an empty one.
  ///
  /// One read for the machine — see [CaptureScene]. A tree that will not arrive
  /// or parse costs the *window* mode its rectangles and nothing else.
  Future<CaptureScene> _readCaptureScene() async {
    final connection = widget.miracle.connection;
    if (connection == null) return CaptureScene.empty;
    try {
      return CaptureScene.fromTree(await connection.getTree());
    } catch (error) {
      debugPrint('capture selection: could not read the window tree: $error');
      return CaptureScene.empty;
    }
  }

  /// Builds one selection surface: the whole of one output, on the overlay
  /// layer, taking the keyboard so Escape reaches it.
  LayershellWindowController _createSelector(MonitorInfo monitor) {
    final controller = LayershellWindowController(
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
    // Or the compositor shrinks it into the gap between the panels, and the
    // area under the bars could neither be selected nor dimmed.
    spanFullOutput(controller);
    return controller;
  }

  void _onSelectionPicked(CaptureTarget target) {
    if (!mounted) return;
    _selectionAnswer = target;
    _selectionClosing.value = true;
  }

  void _onSelectionCancelled() {
    if (!mounted) return;
    _selectionAnswer = null;
    _selectionClosing.value = true;
  }

  /// Called by every selection surface once it has stopped painting; the first
  /// takes them all down.
  ///
  /// The controller is answered here rather than at the click, so
  /// `runCaptureFlow` starts its settle from the teardown rather than the click.
  void _onSelectionClosed() {
    if (!mounted || _selector.isEmpty) return;
    final removed = _selector.values.toList();
    _selector.clear();
    _selectionRequest = null;
    _selectionScene = CaptureScene.empty;
    PopupCoordinator.instance.close(_selectionHandle);
    _selectionHandle = null;
    final answer = _selectionAnswer;
    _selectionAnswer = null;
    _refreshWindows();
    _destroyAfterFrame(removed);
    CaptureSelectionController.instance.complete(answer);
  }

  /// polkitd asked the user to prove who they are (or the prompt was answered).
  ///
  /// The agent is blocked inside `BeginAuthentication` awaiting
  /// [PolkitAuthController] — including when *polkitd* withdrew the request. A
  /// superseding request has already been declined by the controller, so all that
  /// is left here is bringing its window down.
  void _onPolkitAuthChanged() {
    if (!mounted) return;
    final session = PolkitAuthController.instance.pending;
    if (session == null) {
      if (_polkitPrompt.isOpen) _polkitPrompt.closing.value = true;
      return;
    }
    if (_polkitPrompt.isOpen) {
      if (identical(_polkitSession, session)) return;
      _polkitPrompt.closing.value = true;
      return;
    }
    _polkitSession = session;
    // No `monitor:`, like the launcher: the compositor puts the surface on its
    // focused output, which is the display the user was working on when whatever
    // asked for privileges asked for them.
    _polkitPrompt.open();
    _refreshWindows();
  }

  /// Called by [PolkitAuthDialog] once its fade-out has finished.
  void _onPolkitPromptClosed() {
    if (!mounted) return;
    final session = _polkitSession;
    final removed = _polkitPrompt.take();
    if (removed == null) return;
    _polkitSession = null;
    if (session != null) {
      // A window taken down without the user answering — the session lock, a
      // superseding request, the shell shutting down — is a refusal, and the
      // helper sitting on a PAM prompt has to be told rather than left running.
      if (!session.isFinished) session.cancel();
      // Guarded on identity rather than a bare `complete`: a superseding request
      // may be pending by now, and answering *that* with the outcome of the
      // dialog the user was looking at would resolve a prompt nobody has seen.
      PolkitAuthController.instance.finish(
        session,
        session.outcome ?? PolkitAuthOutcome.cancelled,
      );
    }
    _refreshWindows();
    _destroyAfterFrame([removed]);
    // A request that arrived while this one was animating out.
    _onPolkitAuthChanged();
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
    _refreshWindows();
    _destroyAfterFrame([removed]);
  }

  /// Called by [LauncherOverlay] once it is finished with its window — after
  /// the fade-out, or immediately when an application was launched.
  void _onLauncherClosed() {
    if (!mounted) return;
    final removed = _launcher.take();
    if (removed == null) return;
    _refreshWindows();
    _destroyAfterFrame([removed]);
  }

  /// The emoji picker's shortcut fired. Toggles the way the launcher's does.
  void _onEmojiPickerTriggered() {
    if (!mounted) return;
    if (_emojiPicker.isOpen) {
      _emojiPicker.closing.value = true;
    } else {
      _openEmojiPicker();
    }
  }

  /// Opens the emoji picker as a full-screen overlay-layer window.
  ///
  /// No monitor, for [_openLauncher]'s reason: miracle places it on the focused
  /// output, which is where the user is — and this window exists to hand a
  /// character back to whatever they were typing into.
  void _openEmojiPicker() {
    _emojiPicker.open();
    _refreshWindows();
  }

  /// Called by [EmojiPickerOverlay] once it is finished with its window —
  /// after the fade-out, or immediately when something was copied.
  void _onEmojiPickerClosed() {
    if (!mounted) return;
    final removed = _emojiPicker.take();
    if (removed == null) return;
    _refreshWindows();
    _destroyAfterFrame([removed]);
  }

  /// Puts a picked emoji on the clipboard, and says so when it could not.
  ///
  /// Fired and not awaited, because the picker closes on the same keystroke. Only
  /// a failure is reported, through the notification store rather than a card
  /// that is already gone.
  void _onEmojiCopied(String char) {
    unawaited(
      copyTextToClipboard(char).then((result) {
        if (result == ClipboardResult.copied) return;
        final store = NotificationStore.instance;
        store.addOrReplace(
          NotificationItem(
            id: store.allocateId(),
            appName: 'Graceful Shell',
            summary: 'Could not copy $char',
            body: result == ClipboardResult.unavailable
                ? 'The emoji picker copies through $kClipboardCommand, which '
                      'is not installed. Install $kClipboardPackage to use it.'
                : '$kClipboardCommand could not take the clipboard.',
            actions: const [],
            // Stays until dismissed: it is the only place the reason is written
            // down, and the user is by now looking at a field that did not
            // receive a paste.
            expireTimeout: 0,
            arrivedAt: DateTime.now(),
          ),
        );
      }),
    );
  }

  /// The bar's keyboard icon was pressed. Toggles the way the launcher's does.
  void _onKeybindsTriggered() {
    if (!mounted) return;
    if (_keybinds.isOpen) {
      _keybinds.closing.value = true;
    } else {
      _openKeybinds();
    }
  }

  /// Opens the keybind cheat sheet as a full-screen overlay-layer window.
  ///
  /// No monitor, for [_openLauncher]'s reason: miracle places the surface on the
  /// focused output, which is the one the user is looking at — and on a
  /// multi-head shell every bar carries the same icon, so a fixed monitor would
  /// answer half of them on the wrong screen.
  void _openKeybinds() {
    _keybinds.open();
    _refreshWindows();
  }

  /// Called by [KeybindCheatsheetOverlay] once its fade-out has finished.
  void _onKeybindsClosed() {
    if (!mounted) return;
    final removed = _keybinds.take();
    if (removed == null) return;
    _refreshWindows();
    _destroyAfterFrame([removed]);
  }

  /// Opens the settings overlay as a single full-monitor layer-shell window on
  /// the first connected monitor, on the overlay layer with `onDemand` keyboard
  /// focus so its text fields and Escape-to-close work.
  void _openSettings([SettingsRoute? route]) {
    if (_surfaces.isEmpty) return;
    _settingsRoute = route;
    _settings.open(monitor: _surfaces.values.first.monitor.gdkMonitor);
    _refreshWindows();
  }

  /// Called by [SettingsOverlay] once its fade-out has finished (from the toggle
  /// shortcut or its own Escape handler), so the native window can be torn down.
  void _onSettingsClosed() {
    if (!mounted) return;
    final removed = _settings.take();
    _settingsRoute = null;
    _refreshWindows();
    if (removed != null) _destroyAfterFrame([removed]);

    // A route that arrived while the overlay was up: the old window has now
    // finished its fade-out, so reopen at the requested page.
    final pending = _pendingSettingsRoute;
    if (pending != null) {
      _pendingSettingsRoute = null;
      _openSettings(pending);
    }
  }

  /// Something asked for the settings overlay at a particular page.
  ///
  /// Unlike [_onSettingsTriggered] this never toggles. An overlay already on
  /// screen is closed and reopened, because it seeds its tab in `initState`.
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
  /// menu. The picker is asked for through [FilePickerController] because the
  /// desktop cannot host one; the chosen paths are pinned at [cell].
  Future<void> _onDesktopAddRequested({
    required bool applications,
    required GridCell cell,
  }) async {
    // Applications get a searchable list of what is installed, with icons —
    // nobody should have to know their launcher lives in
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
    // Nominal geometry: the surface that raised the menu knows the real one, but
    // placement only needs a free cell and the desktop reflows anything out of
    // range at render time.
    final geometry = computeGridGeometry(const Size(1920, 1080), store.config);
    store.addItem(item.copyWith(column: cell.column, row: cell.row), geometry);
  }

  /// Opens the application chooser as a full-screen overlay-layer window.
  ///
  /// Like the launcher, no monitor: the compositor puts it on the focused
  /// output. The rows hold `GAppInfo` pointers from the index, so the index is
  /// pinned for the window's lifetime exactly as `_openLauncher` does.
  void _openAppChooser(GridCell cell) {
    if (_appChooser.isOpen) return;
    _appChooserCell = cell;
    // A direct close on dismiss: the chooser has no exit animation to play.
    _appChooser.open(onDismiss: _closeAppChooser);
    _refreshWindows();
  }

  void _closeAppChooser() {
    final removed = _appChooser.take();
    if (removed == null) return;
    _appChooserCell = null;
    _refreshWindows();
    _destroyAfterFrame([removed]);
  }

  /// Flips one background surface between `none` and `onDemand` keyboard
  /// interactivity, for the duration of an in-place rename.
  ///
  /// Not left `onDemand`: a full-output surface that can take focus would let a
  /// stray desktop click steal it from the focused application. Cached in a set
  /// on the [_panelMargin] precedent, and force-committed for [setPanelMargin]'s
  /// reason.
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
  /// The desktop grid is the caller: on the background layer a picker would be
  /// drawn under every application window. This puts one on the overlay layer
  /// instead, with keyboard focus so Escape works.
  void _onFilePickRequested() {
    if (!mounted) return;
    final request = FilePickerController.instance.pending;
    if (request == null) {
      if (_filePicker.isOpen) _closeFilePicker();
      return;
    }
    if (_filePicker.isOpen) return;

    // Like the launcher, no monitor: the compositor puts it on the focused
    // output, where the user just right-clicked. A dismissal closes directly —
    // cancelling a modal picker has no exit animation — and only
    // [FilePickerController] may resolve the awaited pick.
    _filePicker.open(onDismiss: _closeFilePicker);
    _refreshWindows();
  }

  void _closeFilePicker() {
    final removed = _filePicker.take();
    if (removed == null) return;
    _refreshWindows();
    _destroyAfterFrame([removed]);
  }

  /// Reconciles the registry with the windows the root wants open, and rebuilds
  /// so their content follows whatever state changed.
  ///
  /// The halves stay in this order and in one call: a caller following it with
  /// [_destroyAfterFrame] relies on the dropped view having been detached first,
  /// since destroying a window Flutter still renders into aborts the process.
  void _refreshWindows() {
    if (!mounted) return;
    _syncWindows();
    setState(() {});
  }

  /// Brings the root's own entries in the [WindowRegistry] in line with
  /// [_desiredWindows], touching nothing else in it.
  ///
  /// Windows are matched on their controller, so a surface still wanted keeps its
  /// entry and builder — which is why those builders read the root's fields
  /// rather than capturing them.
  void _syncWindows() {
    final desired = _desiredWindows();
    final wanted = <BaseWindowController>{
      for (final window in desired) window.controller,
    };
    for (final controller in _rootEntries.keys.toList(growable: false)) {
      if (wanted.contains(controller)) continue;
      final gone = _rootEntries.remove(controller)!;
      _registry?.unregister(gone);
    }
    for (final window in desired) {
      if (_rootEntries.containsKey(window.controller)) continue;
      final entry = WindowEntry(
        controller: window.controller,
        builder: window.builder,
      );
      _rootEntries[window.controller] = entry;
      if (_registry case final registry?) {
        registry.register(entry);
      } else {
        // Nothing below has built yet, so the manager holds nothing a fresh
        // state would lose — see [_registry]. `initialWindows` reads
        // [_rootEntries], which now carries this one too.
        _managerGeneration++;
      }
    }
  }

  /// Takes the registry the root's [WindowManager] published.
  ///
  /// Assigning a field is all this does: it is called from a descendant's
  /// `didChangeDependencies`, inside the build phase where marking anything dirty
  /// would be an error.
  void _bindRegistry(WindowRegistry registry) {
    if (identical(_registry, registry)) return;
    _registry = registry;
    // Everything the root already owns was handed to the manager as
    // `initialWindows`, so the registry is already holding it.
  }

  /// Destroys native windows only once Flutter has let go of their views —
  /// destroying while it still renders into one aborts the process (see
  /// [WindowTeardown]). The overlays have played their fade-out by now, so the
  /// up-front unmap costs nothing visually.
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

  /// Coalesces bursts of `monitor-added` / `monitor-removed` (one reconfigure
  /// can emit several) into a single reconciliation, and hops off the GTK
  /// signal-emission stack before creating or destroying windows.
  void _scheduleMonitorSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    scheduleMicrotask(() {
      _syncScheduled = false;
      if (mounted) _syncMonitors();
    });
  }

  /// Reconciles [_surfaces] with the current monitor list: destroying surfaces
  /// for unplugged monitors and creating them for plugged-in ones.
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
        final badge = _badges.remove(key);
        if (badge != null) removed.add(badge);
        final selector = _selector.remove(key);
        if (selector != null) removed.add(selector);
        final lock = _lockHost.removeMonitor(key);
        if (lock != null) removedLocks.add(lock);
        changed = true;
      }
    }

    for (final entry in incoming.entries) {
      final existing = _surfaces[entry.key];
      if (existing != null) {
        // The same monitor described differently — a reposition, mode or scale
        // change. Nothing native is recreated; the snapshot is replaced so
        // `DisplayProvider` stops matching its `wl_output` against a position the
        // monitor has left behind.
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
      // Same for a monitor plugged in while something is on the list: the
      // badge is per-output precisely so the user sees it wherever they are.
      if (_badges.isNotEmpty) _badges[entry.key] = _createBadge(entry.value);
      // Likewise a monitor plugged in while locked: without a lock surface
      // the compositor would just blank it.
      _lockHost.addMonitor(entry.key, entry.value.gdkMonitor);
      changed = true;
    }

    if (!changed) return;

    // Detach the removed views from the tree first, then destroy their native
    // windows after that frame has been rendered.
    _refreshWindows();
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
  /// [MonitorInfo] carries no `==`; the fields that matter are the ones
  /// [resolveOutput] and the lock host read.
  bool _sameMonitor(MonitorInfo a, MonitorInfo b) =>
      a.connector == b.connector &&
      a.manufacturer == b.manufacturer &&
      a.model == b.model &&
      a.position == b.position &&
      a.gdkMonitor.address == b.gdkMonitor.address;

  /// Rebuilds a fresh typed config from the store (which also re-applies module
  /// options via [Module.loadAll]) and rebuilds the tree. Runs in a listener,
  /// never during build, because deriving the config has side effects.
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
    // No [setState]: the value is published through [LiveConfigProvider], so only
    // the widgets that read it rebuild. The root's own build reads nothing.
    _liveConfig.value = next;
    // The power key is the one setting outside the widget tree that follows live
    // config: switching it off has to give logind's inhibitor back rather than
    // wait for a restart. The service compares before acting, so this costs
    // nothing on keystrokes that changed something else.
    PowerKeyService.instance.setConfig(next.power);
  }

  /// Re-floats the bars when the active theme's margin changes.
  ///
  /// Panel geometry is otherwise frozen at startup, but a bar that rounded its
  /// corners without lifting off the screen edge until the next restart would
  /// look broken. No [setState] — nothing in the tree reads [_panelMargin].
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
        setPanelMargin(controller, anchor: panelConfig.anchor, margin: next);
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
    // caller — for the screencast picker, a D-Bus `Start` call — forever. Our
    // listeners are already removed, so neither notify reaches this dying State.
    FilePickerController.instance.complete(null);
    ScreencastPickerController.instance.cancel();
    // The most expensive debt to default on: an unanswered `BeginAuthentication`
    // blocks whatever asked for privileges until its own timeout. Cancelled is
    // the answer, because a shell going away has not authenticated anybody.
    PolkitAuthController.instance.complete(PolkitAuthOutcome.cancelled);
    // Same debt, with `runCaptureFlow` as the caller rather than a D-Bus method
    // — but a future nobody will ever complete is a future nobody will ever
    // complete.
    CaptureSelectionController.instance.cancel();
    // Hands the power key back. The fd closing would do it anyway — logind drops
    // an inhibitor when the peer disconnects, which is what keeps a crashed
    // shell from leaving a machine that will not power off — but a shell going
    // away deliberately says so.
    unawaited(PowerKeyService.instance.shutdown());
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
    for (final ctrl in _badges.values) {
      ctrl.destroy();
    }
    _badges.clear();
    for (final ctrl in _selector.values) {
      ctrl.destroy();
    }
    _selector.clear();
    PopupCoordinator.instance.close(_selectionHandle);
    _selectionHandle = null;
    // Every root-owned overlay, symmetrically: each dispose covers the window,
    // the coordinator registration, the AppIndex bracket and the closing
    // notifier.
    for (final overlay in [
      _settings,
      _launcher,
      _appChooser,
      _emojiPicker,
      _keybinds,
      _screencastPicker,
      _filePicker,
      _powerMenu,
      _polkitPrompt,
      _notifications,
    ]) {
      overlay.dispose();
    }
    _liveConfig.dispose();
    _selectionClosing.dispose();
    super.dispose();
  }

  /// The ambient providers every window in the shell gets.
  ///
  /// An `InheritedWidget` cannot span FlutterViews and the shell renders into one
  /// per panel per monitor plus one per popup, overlay, OSD card and lock
  /// surface. [ThemeProvider] stays the only thing constructing a [ThemeScope].
  Widget _windowChrome(Widget child) => _RegistryBinder(
    // Every root-owned window's content goes through here, which makes this the
    // first place under the [WindowManager] that builds — and so the one place
    // the root can be handed the registry it registers the rest of its windows
    // into. See [_registry].
    onRegistry: _bindRegistry,
    child: ShellServicesScope(
      services: widget.services,
      child: LiveConfigProvider(
        config: _liveConfig,
        // ShellTextRoot inside ThemeProvider: it reads ThemeScope for the
        // font family every window's text should inherit.
        child: ThemeProvider(
          child: ShellTextRoot(child: _maybeExcludeSemantics(child)),
        ),
      ),
    ),
  );

  /// [child], with the semantics tree switched off — see [kExcludeSemantics].
  ///
  /// Here rather than at each call site because this is the one place every
  /// root-owned window's content goes through.
  Widget _maybeExcludeSemantics(Widget child) =>
      kExcludeSemantics ? ExcludeSemantics(child: child) : child;

  @override
  Widget build(BuildContext context) {
    // Flutter's own [WindowManager] renders the shell from the single
    // [WindowRegistry] it publishes.
    //
    // Two things put windows in that registry: the root, through [_syncWindows],
    // and every module that opens a popup from inside the tree. That is why the
    // root's set is *reconciled* rather than rebuilt — a declarative list of
    // views returned from `build` would take every module's window down with it.
    // [initialWindows] is what a remount re-registers; see [_registry].
    //
    // The manager renders its registry as *unkeyed* `Window`s, so dropping one
    // from the middle shifts every later one down a slot — reparenting rather
    // than rebuilding, since each `RawView` is globally keyed on its own
    // `FlutterView`, but still cascading. Hence the registration order below:
    // per-monitor surfaces first, the overlays that open and close all day after
    // them, and the modules' own popups last.
    return WindowManager(
      key: ValueKey(_managerGeneration),
      initialWindows: _rootEntries.values.toList(growable: false),
    );
  }

  /// Every native window the root itself owns, paired with its content.
  ///
  /// The controller is a window's identity, so a window that survives a
  /// reconciliation keeps the [WindowEntry] and builder it was created with.
  /// Capture only what is fixed for that window's life, and read anything that
  /// can still move out of the root's fields *inside* the builder.
  List<_RootWindow> _desiredWindows() {
    // Iterate the *startup* panels — those own the layer-shell controllers —
    // but render each with the live config merged onto its fixed geometry.
    final startupPanels = widget.appConfig.panels;

    return <_RootWindow>[
      // One group of surfaces per currently-connected monitor. Monitors are
      // added to / removed from [_surfaces] as they are plugged and unplugged.
      for (final surfaces in _surfaces.values) ...[
        if (surfaces.background case final background?)
          (
            controller: background,
            // The window chrome is what lets the desktop grid open popups: the
            // SDK's `Window` supplies the View and WindowScope, but popup content
            // is built outside the parent's ThemeScope. Deliberately no
            // DisplayScope: the grid takes its geometry from a LayoutBuilder.
            builder: (_) => _windowChrome(
              // A click on the desktop dismisses whatever a *panel* has open:
              // the two surfaces share a registry but still no widget tree, so
              // the coordinator remains the only thing that can carry the signal
              // across.
              PopupDismissArea(
                child: Builder(
                  builder: (context) {
                    final live = LiveConfigScope.of(context);
                    // Background surface existence is startup-only; while it
                    // exists, follow live edits but keep the startup wallpaper if
                    // the user clears every entry.
                    //
                    // Null means "surface, but nothing to paint" — the grid-only
                    // case, which must render as *nothing* rather than as
                    // BackgroundWindow's opaque empty fill.
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
                      // Startup panel geometry, like _createSurfaces: the anchor
                      // a surface was built with cannot change without a
                      // restart.
                      panels: widget.appConfig.panels,
                      onChangeBackground: () => SettingsController.instance
                          .open(SettingsRoute.background),
                      onAddRequested: _onDesktopAddRequested,
                      onKeyboardRequested: (wanted) => _setDesktopKeyboard(
                        _monitorKey(surfaces.monitor),
                        wanted,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        // Not gated on the output being known. Enumeration is no longer awaited
        // before the first frame, so a bar that waited would be one the user
        // watches appear a beat after login; it paints now and [DisplayScope]
        // fills in a moment later.
        for (final entry in startupPanels.entries)
          if (surfaces.panels[entry.key] case final controller?)
            (
              controller: controller,
              builder: (_) => _windowChrome(
                MiracleScope(
                  manager: widget.miracle,
                  child: DisplayProvider(
                    // Read here rather than captured: [_syncMonitors] replaces
                    // this snapshot in place on a reposition, and a panel matched
                    // against the position its display has left behind shows
                    // another one's workspaces.
                    monitor: surfaces.monitor,
                    outputs: widget.outputs,
                    child: Builder(
                      builder: (context) {
                        final panel = effectivePanel(
                          entry.value,
                          LiveConfigScope.of(context).panels[entry.key],
                        );
                        // A click anywhere on the bar — an icon whose popup is
                        // not open, or bare padding — dismisses whatever else the
                        // shell has up.
                        return PopupDismissArea(
                          child: PanelMain(
                            panelConfig: panel,
                            anchor: panel.anchor,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
        // The indicator is not tied to any panel, so it lives here beside the
        // background rather than being opened from inside a module.
        if (_osd[_monitorKey(surfaces.monitor)] case final osd?)
          (
            controller: osd,
            builder: (_) => _windowChrome(OsdWindow(store: OsdStore.instance)),
          ),
        // The floating notification badge, tied to the output rather than to any
        // panel — it is there whether or not this monitor's bars carry the bell
        // module.
        if (_badges[_monitorKey(surfaces.monitor)] case final badge?)
          (
            controller: badge,
            builder: (_) => _windowChrome(
              NotificationBadge(
                // This monitor, not the focused one: the user has just pointed
                // at this display.
                onTap: () => _toggleNotificationPanel(
                  monitor: surfaces.monitor.gdkMonitor,
                ),
              ),
            ),
          ),
        // The screenshot / recording selection surface, likewise not tied to
        // any panel — it covers the whole of this output, bars included.
        if (_selectionRequest != null)
          if (_selector[_monitorKey(surfaces.monitor)] case final selector?)
            (
              controller: selector,
              builder: (_) {
                // Re-read rather than captured, the rule this list states: one
                // pick answered and another asked for keeps these surfaces up.
                final selection = _selectionRequest;
                if (selection == null) return const SizedBox.shrink();
                return _windowChrome(
                  CaptureSelectorOverlay(
                    request: selection,
                    // The connector, not the wl_output: this is what the capture
                    // stack and miracle's tree key an output on, and
                    // `DisplayScope` would answer null for exactly the first
                    // frames a selection surface is drawn for. The corner goes
                    // with it, because GDK reports no connector at all without an
                    // `xdg-output` manager.
                    connector: surfaces.monitor.connector,
                    origin: CapturePoint(
                      surfaces.monitor.position.dx.round(),
                      surfaces.monitor.position.dy.round(),
                    ),
                    scene: _selectionScene,
                    closingNotifier: _selectionClosing,
                    onClosed: _onSelectionClosed,
                    onPicked: _onSelectionPicked,
                    onCancel: _onSelectionCancelled,
                  ),
                );
              },
            ),
      ],
      // The notification panel. A single window like the overlays below it — one
      // panel for the machine, however many bells and badges ask for it — so it
      // lives outside the per-monitor loop too.
      if (_notifications.controller case final notifications?)
        (
          controller: notifications,
          builder: (_) => _windowChrome(
            NotificationPanel(
              closingNotifier: _notifications.closing,
              onClosed: _onNotificationPanelClosed,
            ),
          ),
        ),
      // The settings overlay opened by the global shortcut. A single window
      // (not per-monitor), so it lives outside the per-monitor loop above.
      if (_settings.controller case final settings?)
        (
          controller: settings,
          builder: (_) => _windowChrome(
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
        (
          controller: chooser,
          builder: (_) => _windowChrome(
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
      if (_filePicker.controller case final picker?)
        if (FilePickerController.instance.pending != null)
          (
            controller: picker,
            builder: (_) {
              // Re-read for [_desiredWindows]'s reason: one request completed
              // and the next opened keeps this window and its entry.
              final request = FilePickerController.instance.pending;
              if (request == null) return const SizedBox.shrink();
              return _windowChrome(
                FilePickerWindow(
                  request: request,
                  onResult: (paths) {
                    FilePickerController.instance.complete(paths);
                    _closeFilePicker();
                  },
                ),
              );
            },
          ),
      // The application launcher. Like the settings overlay it is a single
      // window rather than one per monitor, so it lives outside the loop.
      if (_launcher.controller case final launcher?)
        (
          controller: launcher,
          builder: (_) => _windowChrome(
            // Ctrl+Space can beat the index to the finish line. A loader says
            // so; "No applications" would be a lie the user acts on.
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
      // The emoji picker. A single window like the launcher, and registered
      // after it: the overlays that open and close all day go late in this list,
      // because dropping an unkeyed Window from the middle reparents every later
      // one (see the reconciliation note on [WindowManager]).
      if (_emojiPicker.controller case final picker?)
        (
          controller: picker,
          builder: (_) => _windowChrome(
            EmojiPickerOverlay(
              closingNotifier: _emojiPicker.closing,
              onClosed: _onEmojiPickerClosed,
              onCopy: _onEmojiCopied,
            ),
          ),
        ),
      // The keybind cheat sheet, registered beside the emoji picker and for the
      // same reason: it opens and closes all day, so it goes late in this list.
      if (_keybinds.controller case final sheet?)
        (
          controller: sheet,
          builder: (_) => _windowChrome(
            KeybindCheatsheetOverlay(
              closingNotifier: _keybinds.closing,
              onClosed: _onKeybindsClosed,
            ),
          ),
        ),
      // The screen-share consent picker, open only while an application's portal
      // request is waiting on an answer. Single window like the launcher, so it
      // lives outside the per-monitor loop.
      if (_screencastPicker.controller case final picker?)
        if (_screencastRequest != null)
          (
            controller: picker,
            builder: (_) {
              // Re-read, as everything mutable in this list is.
              final request = _screencastRequest;
              if (request == null) return const SizedBox.shrink();
              return _windowChrome(
                Builder(
                  builder: (context) {
                    final connection = screencastService?.connection;
                    final sources = connection == null
                        ? (
                            monitors: <PickerSource>[],
                            windows: <PickerSource>[],
                          )
                        : buildPickerSources(
                            connection,
                            request,
                            previewFps: LiveConfigScope.of(
                              context,
                            ).screenshare.previewFps,
                          );
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
                  },
                ),
              );
            },
          ),
      // The polkit prompt, open only while a request for administrator rights is
      // waiting on the user. Single window like the launcher, so it lives outside
      // the per-monitor loop.
      if (_polkitPrompt.controller case final prompt?)
        if (_polkitSession != null)
          (
            controller: prompt,
            builder: (_) {
              // Re-read, as everything mutable in this list is: a surviving
              // window keeps the [WindowEntry], and so the builder, it was
              // created with.
              final session = _polkitSession;
              if (session == null) return const SizedBox.shrink();
              return _windowChrome(
                PolkitAuthDialog(
                  session: session,
                  closingNotifier: _polkitPrompt.closing,
                  onClosed: _onPolkitPromptClosed,
                ),
              );
            },
          ),
      // The power menu, open only while the power button's press is being
      // answered. Single window like the launcher, so it lives outside the
      // per-monitor loop.
      if (_powerMenu.controller case final menu?)
        (
          controller: menu,
          builder: (_) => _windowChrome(
            PowerMenuOverlay(
              closingNotifier: _powerMenu.closing,
              onClosed: _onPowerMenuClosed,
              // The overlay dismisses itself and then this tears the window
              // down, so the verb runs while its own surface is still fading —
              // which is what "Lock" needs, since the lock surface is mapped over
              // the top of it.
              onAction: (action) => unawaited(PowerActions.run(action)),
            ),
          ),
        ),
      // The lock screen. These surfaces exist only while the session is locked;
      // the compositor hides every other surface — the panels above included —
      // for as long as they do.
      for (final controller in _lockHost.windows)
        (
          controller: controller,
          builder: (_) => _windowChrome(
            Builder(
              builder: (context) {
                return LockScreen(
                  config: LiveConfigScope.of(context).lock,
                  onUnlocked: _lockHost.unlock,
                );
              },
            ),
          ),
        ),
    ];
  }
}

/// Merges live-updatable panel fields (module layout, horizontal padding) onto
/// the startup window geometry (anchor/height/layer), which cannot change
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
  const PanelMain({super.key, required this.panelConfig, required this.anchor});

  final PanelConfig panelConfig;
  final String anchor;

  @override
  State<PanelMain> createState() => _PanelMainState();
}

class _PanelMainState extends State<PanelMain> {
  Widget _buildModule(String name) {
    final module = Module.lookup(name);
    if (module == null) return const SizedBox.shrink();
    // Module options are pushed imperatively and read out of `builder` at build
    // time, so nothing about this widget's inputs says they moved —
    // [Module.configChanges] is what does. Listening per module keeps a
    // `[modules.clock]` edit off every other module in the bar.
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
          vertical ? const SizedBox(height: 8) : const SizedBox(width: 8),
        );
      }
      children.add(_buildModule(modules[i]));
    }
    if (vertical) {
      return Column(mainAxisSize: MainAxisSize.min, children: children);
    } else {
      return Row(mainAxisSize: MainAxisSize.min, children: children);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.panelConfig.layout;

    final bool vertical =
        widget.panelConfig.anchor == 'left' ||
        widget.panelConfig.anchor == 'right';

    final stackChildren = <Widget>[
      if (layout.left.isNotEmpty)
        Align(
          alignment: vertical ? Alignment.topCenter : Alignment.centerLeft,
          child: _buildSection(layout.left),
        ),
      if (layout.center.isNotEmpty)
        Align(alignment: Alignment.center, child: _buildSection(layout.center)),
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
    // A rimmed bar that attaches its popups paints its own rim, because that
    // rim has to be left out across the mouth of an open menu and a `Border`
    // cannot have a gap in it. The popup is placed *below* the panel and can
    // never cover the line itself; see `panel_rim.dart`. The panel is named by
    // its own FlutterView, which is what both ends resolve to the same object:
    // the panel's tree is in it, and `PopupHost.openPopup` runs from a module's
    // context inside that same tree. `panelWithRim` paints it as a *foreground*
    // painter over the bar's own content, which is what keeps the modules
    // clickable — a `CustomPaint` laid over them as a background painter is
    // opaque to hits.
    final paintsOwnRim = panelPaintsOwnRim(theme);

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
            // padding — the border's thickness — to its child, silently
            // insetting every module and changing what padding_horizontal means.
            // The clip is conditional so a square bar adds no extra layer.
            child: DecoratedBox(
              decoration: panelBackgroundDecoration(
                anchor: widget.panelConfig.anchor,
                theme: theme,
                includeRim: !paintsOwnRim,
              ),
              child: panelWithRim(
                theme: theme,
                anchor: widget.panelConfig.anchor,
                panel: View.maybeOf(context),
                content: radius == BorderRadius.zero
                    ? content
                    : ClipRRect(borderRadius: radius, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One root-owned full-screen overlay window.
///
/// Owns the four things every such overlay needs: the controller, the
/// [PopupCoordinator] registration (keyed by a sentinel [owner], since one State
/// owns them all), the [closing] notifier driving the fade-out, and the AppIndex
/// bracket. The deltas are constructor arguments rather than subclasses.
class _OverlayWindow {
  _OverlayWindow({
    this.policy = TransientPolicy.menu,
    this.acquiresAppIndex = false,
    this.create,
  });

  final TransientPolicy policy;

  /// Builds the native window for the monitor [open] was asked for.
  ///
  /// Null is the full-screen backdrop eight of these nine want; the notification
  /// panel supplies its own. What [_OverlayWindow] owns is the bookkeeping, which
  /// does not care what shape the surface is.
  final LayershellWindowController Function(
    ffi.Pointer<ffi.NativeType>? monitor,
  )?
  create;

  /// Whether the window's content holds `GAppInfo` pointers from [AppIndex] —
  /// the index defers refreshes while it is open (`_openLauncher`'s rule).
  final bool acquiresAppIndex;

  final Object owner = Object();

  /// Drives the content's fade-out. The coordinator's dismiss flips it; the
  /// content plays its exit animation and calls back into the root, which calls
  /// [take].
  final ValueNotifier<bool> closing = ValueNotifier(false);

  LayershellWindowController? controller;
  TransientHandle? _handle;

  bool get isOpen => controller != null;

  /// Creates the native window and registers with the coordinator.
  ///
  /// Without a [create] the window is overlay-layer, all-edges, keyboard
  /// `onDemand` and [spanFullOutput]ed, or the backdrop stops short of the bars.
  /// [onDismiss] asks for a graceful close; the default flips [closing] and lets
  /// the content animate out.
  void open({ffi.Pointer<ffi.NativeType>? monitor, VoidCallback? onDismiss}) {
    if (isOpen) return;
    closing.value = false;
    if (acquiresAppIndex) AppIndex.instance.acquire();
    final created = create?.call(monitor) ?? _fullScreenOverlay(monitor);
    controller = created;
    // The coordinator asks for the fade-out, never the teardown: the content
    // destroys the window once its animation is done.
    _handle = PopupCoordinator.instance.open(
      owner: owner,
      policy: policy,
      onDismiss: onDismiss ?? () => closing.value = true,
    );
  }

  /// Unregisters and hands back the controller for `_destroyAfterFrame`, or null
  /// when already closed. The caller detaches the view (setState) before the
  /// native window dies.
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

/// Hands [onRegistry] the [WindowRegistry] the root's [WindowManager] publishes.
///
/// The manager has no `child` slot, so the only context below it belongs to a
/// window's own content — this rides along on every one through `_windowChrome`.
/// Depending on the scope rather than reading it once is what makes a remounted
/// manager report its new registry.
class _RegistryBinder extends StatefulWidget {
  const _RegistryBinder({required this.onRegistry, required this.child});

  final ValueChanged<WindowRegistry> onRegistry;
  final Widget child;

  @override
  State<_RegistryBinder> createState() => _RegistryBinderState();
}

class _RegistryBinderState extends State<_RegistryBinder> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onRegistry(WindowRegistry.of(context));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The default shape: a backdrop over the whole of one output.
LayershellWindowController _fullScreenOverlay(
  ffi.Pointer<ffi.NativeType>? monitor,
) {
  final controller = LayershellWindowController(
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
  spanFullOutput(controller);
  return controller;
}

/// Feeds a root-owned overlay the application index live, so the root need not
/// rebuild every view when it lands.
///
/// Two sources: [AppIndex] notifies on install and removal, and the
/// [ShellServicesScope] answers "is it built yet" — and delivers the very first
/// list, because [AppIndex.start] fills `searchable` without notifying. Both
/// reads have to happen on this one element or the loader never comes down.
class _AppIndexBuilder extends StatelessWidget {
  const _AppIndexBuilder({required this.builder});

  final Widget Function(
    BuildContext context,
    List<SearchableApp> apps,
    bool loading,
  )
  builder;

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
