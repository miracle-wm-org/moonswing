import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: implementation_imports
import 'package:flutter/widgets.dart';
// The controller supertype every window in the registry is keyed on.
// `layer_shell` re-exports WindowManager / WindowRegistry / WindowEntry
// but not this, and there is nowhere else to reach it from.
import 'package:flutter/src/widgets/_window.dart' show BaseWindowController;
import 'package:graceful_shell/app_info.dart';
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
import 'package:graceful_shell/notification_badge.dart';
import 'package:graceful_shell/notification_panel_controller.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/osd/osd.dart';
import 'package:graceful_shell/osd/osd_service.dart';
import 'package:graceful_shell/osd/osd_store.dart';
import 'package:graceful_shell/panel_background.dart';
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
/// **This switches accessibility off, and it is a stopgap.** A screen reader
/// sees nothing of the bar, the desktop, the overlays or the lock screen while
/// this is true. It is here because the semantics pass was measured, on a live
/// miracle session, as the **single largest consumer of the shell's UI
/// thread** — 1090 ms of a 2935 ms total across a 40-second capture, 37.1%,
/// against `LAYOUT`'s 27.3% and `BUILD`'s 16.4%.
///
/// It costs that much because it is charged *per view per frame* and this
/// shell has around seven of them: one `SEMANTICS (root)` pass per rasterized
/// frame per window, 4510 semantics passes over 659 frames in the capture.
///
/// There is no supported way to refuse it. The Linux embedder turns semantics
/// on regardless of whether an assistive client is attached — verified: with
/// `GTK_A11Y=none`, `NO_AT_BRIDGE=1` and `toolkit-accessibility false`, a
/// 25-second idle run still produced 95 `SEMANTICS (root)` passes for its 95
/// frames. There is no `disable-semantics` engine switch, and the framework
/// creates the semantics owner from whatever the platform reports. So the only
/// lever left is to hand it an empty tree, which is what [ExcludeSemantics]
/// does.
///
/// Set `GRACEFUL_SHELL_SEMANTICS=1` to put it back — which is also how to
/// re-measure before removing this, and how somebody who needs a screen reader
/// gets a working shell today. Reinstating it properly means making the tree
/// cheap rather than empty; the per-view cost is the thing to attack.
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
  polkitLog = (message) => debugPrint('polkit: $message');

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
  runWidget(
    GracefulShellRoot(
      appConfig: appConfig,
      store: store,
      miracle: miracle,
      outputs: outputs,
      services: services,
    ),
  );

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

  // Registers the shell as this session's polkit authentication agent, so a
  // privileged operation anywhere on the desktop gets a prompt instead of a
  // flat `AccessDenied`. A session that already has an agent is yielded to,
  // which `run` records as ready; anything else — no system bus, no polkitd,
  // no logind session to register for — throws and is recorded as failed.
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

  // Takes logind's `handle-power-key` inhibitor so the machine's power button
  // reaches the shell rather than powering the machine off behind it. Nothing
  // is claimed until the compositor confirms the shell owns the key (see
  // [PowerKeyService]), and `key_action = "none"` claims nothing at all.
  services.run(ShellService.power, () => startPowerService(appConfig.power));

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
  // among them, the compositor doesn't implement these protocols (an older Mir,
  // or not Mir) — the shortcuts silently won't work, so say so once.
  if (!inputTriggers.isRegistered) {
    debugPrint(
      'input-trigger: compositor did not advertise the '
      'ext-input-trigger globals; global shortcuts are unavailable',
    );
    // Including the power button, which is the one shortcut whose absence has
    // a consequence beyond itself: the shell must not go on holding logind's
    // inhibitor for a key that will never arrive.
    inputTriggers.reportUnregistered();
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

/// One native window the root owns, and the content that goes in it.
///
/// The pair [_desiredWindows] answers in and [_syncWindows] turns into
/// [WindowEntry]s. Kept as a record rather than as the entries themselves
/// because an entry is created once per window and reused for as long as that
/// window lives, while this is recomputed on every reconciliation.
typedef _RootWindow = ({
  BaseWindowController controller,
  WidgetBuilder builder,
});

class _GracefulShellRootState extends State<GracefulShellRoot> {
  /// The [WindowRegistry] the root's [WindowManager] publishes, once something
  /// below it has handed it back (see [_RegistryBinder]).
  ///
  /// The manager creates the registry itself and takes no injected one, so the
  /// root — its *parent* — cannot hold it before a window has been built. That
  /// gap is only ever real while the registry is empty: nothing else can have
  /// registered a popup into a manager that has never rendered a window to open
  /// one from. So [_syncWindows] answers a null registry by bumping
  /// [_managerGeneration], which remounts the manager with the current set as
  /// its `initialWindows` — losing nothing, because there was nothing to lose —
  /// and after the first window has built it never has to again.
  WindowRegistry? _registry;

  /// Keys the root [WindowManager], so a bump gives it a fresh state that reads
  /// `initialWindows` again. Only [_syncWindows] bumps it, and only while
  /// [_registry] is still null.
  int _managerGeneration = 0;

  /// The root's own registry entries, keyed on the controller that identifies
  /// the window, in the order they were registered.
  ///
  /// This is not the whole registry: every popup and runtime layer-shell window
  /// a module opens registers itself into the same one from inside the tree.
  /// [_syncWindows] therefore diffs this map and calls `register` / `unregister`
  /// for the difference alone — it must never replace the registry's contents
  /// wholesale, which would take every module's window down with it.
  final Map<BaseWindowController, WindowEntry> _rootEntries = {};

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

  /// The floating notification badges, keyed like [_osd] and existing for the
  /// same span of time: only while there is something to report, because a
  /// permanently mapped corner surface would swallow every click that landed
  /// on it and the shell has no input-region support to let them through.
  ///
  /// One per monitor, the OSD's rule rather than the launcher's: the badge is
  /// the shell saying something arrived, and a user looking at the other
  /// display would never see it. Tapping any of them opens the one panel, on
  /// the monitor whose badge was tapped.
  final Map<String, LayershellWindowController> _badges = {};

  /// Seven of the eight root-owned overlays — the full-screen ones; the
  /// notification panel below is the exception. Each [_OverlayWindow] carries
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
  final _OverlayWindow _screencastPicker = _OverlayWindow(
    policy: TransientPolicy.modal,
  );
  final _OverlayWindow _filePicker = _OverlayWindow(
    policy: TransientPolicy.modal,
  );

  /// The power menu the physical power button opens (`[power] key_action =
  /// "menu"`, the default). Modal, like the two pickers and for the same
  /// reason: it holds a shutdown, and a click elsewhere must not answer it —
  /// the ways out are its own Cancel path (Escape, the backdrop) and nothing
  /// else. It is the sixth root-owned overlay.
  final _OverlayWindow _powerMenu = _OverlayWindow(
    policy: TransientPolicy.modal,
  );

  /// The polkit prompt — the eighth root-owned overlay. Modal, like the two
  /// consent pickers and for a stronger version of their reason: it is a
  /// grant of administrator rights, so nothing else on the desktop may
  /// dismiss it, and dismissing it *is* the refusal.
  final _OverlayWindow _polkitPrompt = _OverlayWindow(
    policy: TransientPolicy.modal,
  );

  /// The authentication the open prompt is answering, captured when the
  /// window was created — the controller's `pending` moves on the moment the
  /// user answers, while the dialog stays mounted through its fade-out, and a
  /// *superseding* request would otherwise be rendered into the window the
  /// old one is still animating out of.
  PolkitAuthSession? _polkitSession;

  /// The notification panel — the seventh root-owned overlay, and the first
  /// that is not full-screen. It used to be the bell module's own
  /// `LayerShellHost` window; the floating badge is a surface of its own with
  /// no widget ancestry in common with the bell, so neither could reach the
  /// other's window and both now ask the root. See
  /// [NotificationPanelController].
  ///
  /// `late final` rather than a plain initialiser because it brings its own
  /// window: a column down one output edge, not a backdrop over the whole of
  /// it, so [_createNotificationWindow] is `this`'s to supply.
  late final _OverlayWindow _notifications = _OverlayWindow(
    create: _createNotificationWindow,
  );

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

  /// The screenshot / recording selection surfaces, keyed like [_surfaces].
  ///
  /// One per monitor rather than one window, which is what separates this from
  /// the six [_OverlayWindow]s: the user has to be able to drag a rectangle or
  /// point at a window on *any* display, and a layer-shell surface covers one
  /// output. Like the OSD's and unlike a panel's these exist only while
  /// something is being selected — the shell has no input-region support, so a
  /// permanently mapped overlay surface would swallow every click on the
  /// machine.
  final Map<String, LayershellWindowController> _selector = {};

  /// What the open selection surfaces are asking, the windowing environment
  /// they are drawing, and what came back. All three are null/empty exactly
  /// when [_selector] is empty.
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
  /// windowing environment is read over the IPC socket in between, and a
  /// second notify arriving in that gap would open a second set.
  bool _selectionOpening = false;

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
  /// backgrounds, the OSD, every overlay — to deliver a value that at most
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
    _lockHost = SessionLockHost(onChanged: _refreshWindows);
    _hasBackgroundSurface =
        (appConfig.background?.entries.isNotEmpty ?? false) ||
        appConfig.desktop.enabled;
    _subscriptions = [
      (widget.store, _onConfigChanged),
      (OsdStore.instance, _onOsdChanged),
      (InputTriggerStore.instance, _onSettingsTriggered),
      (LauncherController.instance, _onLauncherTriggered),
      (PowerController.instance, _onPowerKeyPressed),
      (ScreencastPickerController.instance, _onScreencastPickChanged),
      (PolkitAuthController.instance, _onPolkitAuthChanged),
      (CaptureSelectionController.instance, _onCaptureSelectionChanged),
      (LockController.instance, _onLockRequested),
      (NotificationPanelController.instance, _onNotificationPanelToggled),
      // The badges are created and destroyed off the store's own emptiness,
      // which is what makes them appear the moment something arrives without
      // anything having to notice that it did.
      (NotificationStore.instance, _syncNotificationBadges),
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

    // Fills [_rootEntries] before the first build, so the surfaces created just
    // above are what the root [WindowManager] is handed as `initialWindows`.
    // Not [_refreshWindows]: there is nothing built yet to rebuild, and
    // `setState` from `initState` is an error.
    _syncWindows();
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
      setPanelMargin(
        controller,
        anchor: panelConfig.anchor,
        margin: _panelMargin,
      );
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
    final margin = (_liveConfig.value.osd.margin - shadow.bottom).round();
    controller.setMargin(LayerShellEdge.bottom, margin < 0 ? 0 : margin);
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
      _refreshWindows();
      return;
    }

    final removed = _osd.values.toList();
    _osd.clear();
    _refreshWindows();
    _destroyAfterFrame(removed);
  }

  /// Builds the floating badge's window for [monitor]: a small card pinned to
  /// the output's top-right corner.
  ///
  /// Deliberately **no** [spanFullOutput]. Left at gtk-layer-shell's default
  /// exclusive zone of 0, the surface means "move me so I don't occlude
  /// anything that reserved space", so the compositor has already placed it
  /// clear of a top bar and of a right-hand one — margins included, since the
  /// zone includes the margin. That is the whole of "does not overlap the
  /// bars", and it stays true for a panel layout this code never sees. Adding
  /// [panelInsetsFor] on top of it would count every bar twice; a zone of -1
  /// would switch the placement off altogether.
  LayershellWindowController _createBadge(MonitorInfo monitor) {
    final controller = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: const [LayerShellEdge.top, LayerShellEdge.right],
      // Nothing on the badge is typed into, and taking the keyboard off
      // whatever the user is working in to show them a bell would be worse
      // than the notification.
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
  /// them when there is not — [_onOsdChanged]'s shape, and its early return:
  /// this runs on every arrival, dismissal and expiry, and in the steady state
  /// none of those touches a native window. The badge listens to the store
  /// itself for the count, so a second notification arriving is a repaint of
  /// one surface rather than a new one.
  ///
  /// The panel counts as "reported": it is a full-height column down the same
  /// edge the badge sits in, so leaving the badge up would put it under the
  /// thing it exists to open.
  void _syncNotificationBadges() {
    if (!mounted) return;
    final wanted =
        NotificationStore.instance.items.isNotEmpty && !_notifications.isOpen;
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

  /// The notification panel's own window: full-height against the output's
  /// right edge, a quarter of its width.
  ///
  /// [spanFullOutput] here and not on the badge, and the difference is the
  /// point of both: this surface is meant to cover the bars, and a zone of 0
  /// would have the compositor shrink it into the gap *between* them, so the
  /// slide-in would start and end short of the screen edges. `onDemand`
  /// keyboard is what lets the panel's own Escape binding fire at all —
  /// deliberately not `exclusive`, which would hold the keyboard off whatever
  /// the user was typing in for as long as a panel they only glance at is up.
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

  /// The bell module asked for the panel. No monitor, so the compositor puts
  /// it on the focused output — the launcher's rule, and the right one for a
  /// trigger that could be on any bar on any display.
  void _onNotificationPanelToggled() {
    if (!mounted) return;
    _toggleNotificationPanel();
  }

  /// Toggles the panel, opening it on [monitor] when one is named. The badge
  /// names its own, so the panel arrives on the display the user just clicked
  /// on rather than wherever the pointer last crossed a boundary.
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
    _refreshWindows();
  }

  /// The machine's physical power button was pressed.
  ///
  /// What that means is `[power] key_action`, read from the *live* config
  /// rather than the start-up snapshot: the key binding latches when the
  /// compositor accepts the registration and cannot change without a restart,
  /// but the action is a dropdown in Settings and changing it there has to
  /// take effect on the next press. [PowerKeyAction.none] is therefore still
  /// checked here — the trigger was registered when the shell started, and
  /// the user has since said they want the key left alone.
  ///
  /// A configured verb runs with no confirmation, because choosing one *is*
  /// the confirmation: a user who set the button to "shutdown" asked for a
  /// power button that powers the machine off. The default is the menu, which
  /// toggles the way the settings and launcher shortcuts do — a second press
  /// on a menu already up is somebody changing their mind.
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
  /// Like the launcher and unlike the settings overlay, no monitor is passed:
  /// the compositor puts it on its focused output, which is the one the user
  /// is at. (A machine whose power button was pressed by somebody who is not
  /// looking at either monitor is not a case a choice of output improves.)
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
      _refreshWindows();
    } else if (_screencastPicker.isOpen) {
      _screencastPicker.closing.value = true;
    }
  }

  /// A capture module asked the user to choose what to capture.
  ///
  /// Every other root-owned surface can be raised inside the notification that
  /// asked for it; this one cannot, because the window rectangles it draws
  /// come from a `GET_TREE` round trip over the IPC socket. [_selectionOpening]
  /// is what covers that gap — without it a second notify (a module clicked
  /// twice, or the controller superseding one request with another) would put
  /// a second set of full-screen surfaces on top of the first.
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
      // here: the controller supersedes, so a second click while the socket
      // was answering has already cancelled ours and is itself waiting. The
      // scene is a moment old and is equally the answer for either, so the
      // one thing that must not happen is bailing out — that would strand the
      // newer request with no surfaces and no listener left to raise them.
      final pending = CaptureSelectionController.instance.pending;
      if (pending == null) return;

      _selectionRequest = pending;
      _selectionScene = scene;
      _selectionAnswer = null;
      _selectionClosing.value = false;
      for (final entry in _surfaces.entries) {
        _selector[entry.key] = _createSelector(entry.value.monitor);
      }
      // Modal, like the two consent pickers: a full-screen surface that has
      // taken the pointer must not be dismissed by something else deciding it
      // wants the screen, and only the user's own Escape, right-click or pick
      // may answer it.
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
  /// One read for the machine, handed to every surface — see [CaptureScene].
  /// A tree that will not arrive or will not parse costs the *window* mode its
  /// rectangles and nothing else: an area is measured in the surface's own
  /// space and a whole screen needs only the connector, so both still work
  /// with the IPC socket down.
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
  /// one takes them all down and the rest find nothing to do.
  ///
  /// The controller is answered *here* rather than at the click, which is the
  /// half that makes the picture right: `runCaptureFlow` starts its settle
  /// from this moment, so the wait it spends is the wait between the surfaces
  /// being torn down and the shutter — not between the click and the shutter,
  /// most of which the teardown would still be inside.
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

  /// polkitd asked the user to prove who they are (or the prompt was
  /// answered).
  ///
  /// The agent is blocked inside `BeginAuthentication` awaiting
  /// [PolkitAuthController]; this raises the dialog when a session appears and
  /// takes it down once one has been answered — including when *polkitd*
  /// withdrew the request (`CancelAuthentication`) rather than the user.
  ///
  /// A superseding request is the case worth reading twice: the controller has
  /// already resolved the first one as declined, so all that is left here is
  /// to bring the window carrying it down. [_onPolkitPromptClosed] re-checks
  /// `pending` and opens the next one, which is why nothing reopens here.
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
    // No `monitor:`, like the launcher: the compositor puts the surface on
    // its focused output, which is the display the user was working on when
    // whatever asked for privileges asked for them.
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
      // A window taken down without the user answering — the session lock
      // sweeping every transient off the screen, a superseding request, the
      // shell shutting down — is a refusal, and the helper sitting on a PAM
      // prompt has to be told so rather than left running.
      if (!session.isFinished) session.cancel();
      // Guarded on identity rather than a bare `complete`: by now a
      // superseding request may be the pending one, and answering *that* with
      // the outcome of the dialog the user was just looking at would resolve
      // a prompt nobody has seen.
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

  /// Opens the settings overlay as a single full-monitor layer-shell window on
  /// the first connected monitor. It sits on the overlay layer and takes
  /// keyboard focus (onDemand) so its text fields and Escape-to-close work —
  /// the same recipe the clock uses to open this overlay from a panel.
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
  /// This is what every `setState(() {})` in this class used to be. The two
  /// halves have to stay in this order and in one call: the reconciliation is
  /// what adds and drops the *views*, and a caller that follows it with
  /// [_destroyAfterFrame] is relying on the dropped view having been detached
  /// first — destroying a native window Flutter still renders into aborts the
  /// process (see `WindowTeardown`).
  void _refreshWindows() {
    if (!mounted) return;
    _syncWindows();
    setState(() {});
  }

  /// Brings the root's own entries in the [WindowRegistry] in line with
  /// [_desiredWindows], touching nothing else in it.
  ///
  /// Windows are matched on their controller, so a surface that is still wanted
  /// keeps the entry — and the builder — it already had, and the registry
  /// notifies only when one is actually created or destroyed. That is also why
  /// the builders in [_desiredWindows] read the root's fields rather than
  /// capturing them.
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
        // Nothing below has built yet, so the manager holds nothing that a
        // fresh state would lose — see [_registry]. `initialWindows` reads
        // [_rootEntries], which now carries this one too.
        _managerGeneration++;
      }
    }
  }

  /// Takes the registry the root's [WindowManager] published, from the first
  /// window of the shell to build.
  ///
  /// Assigning a field is all this does: no `setState`, because it is called
  /// from a descendant's `didChangeDependencies` — inside the build phase,
  /// where marking anything dirty would be an error — and because the root has
  /// nothing to redraw on account of learning where to register.
  void _bindRegistry(WindowRegistry registry) {
    if (identical(_registry, registry)) return;
    _registry = registry;
    // Everything the root already owns was handed to the manager as
    // `initialWindows`, so the registry is already holding it; nothing to
    // replay here.
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
    // The power key is the one setting outside the widget tree that follows
    // live config: switching it off in Settings has to give logind's inhibitor
    // back, not wait for a restart. The service compares before acting, so
    // this costs nothing on the keystrokes that changed something else.
    PowerKeyService.instance.setConfig(next.power);
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
    // caller — for the screencast picker, a D-Bus `Start` call — forever.
    // Our listeners are already removed, so neither notify reaches this
    // dying State.
    FilePickerController.instance.complete(null);
    ScreencastPickerController.instance.cancel();
    // Same debt again, and the most expensive one to default on: an
    // unanswered `BeginAuthentication` blocks whatever asked for privileges
    // for as long as its own timeout allows. Cancelled is the answer, because
    // a shell that is going away has not authenticated anybody.
    PolkitAuthController.instance.complete(PolkitAuthOutcome.cancelled);
    // Same debt, and the caller here is `runCaptureFlow` rather than a D-Bus
    // method — but a future nobody will ever complete is a future nobody will
    // ever complete.
    CaptureSelectionController.instance.cancel();
    // Hands the power key back. The fd closing would do it anyway — logind
    // drops an inhibitor when the peer holding it disconnects, which is what
    // keeps a crashed shell from leaving a machine that will not power off —
    // but a shell that is going away deliberately says so.
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
    // Every root-owned overlay, symmetrically: each dispose covers the
    // window, the coordinator registration, the AppIndex bracket, and the
    // closing notifier.
    for (final overlay in [
      _settings,
      _launcher,
      _appChooser,
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
  /// An `InheritedWidget` cannot span FlutterViews and the shell renders into
  /// one view per panel per monitor plus a window for every popup, overlay, OSD
  /// card and lock surface — so the palette and the start-up service state are
  /// installed once per window rather than once for the tree. [ThemeProvider]
  /// stays the only thing that constructs a [ThemeScope].
  Widget _windowChrome(Widget child) => _RegistryBinder(
    // Every root-owned window's content goes through here, which makes this
    // the first place under the [WindowManager] that builds — and so the
    // one place the root can be handed the registry it has to register the
    // *rest* of its windows into. See [_registry].
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
  /// root-owned window's content goes through, which is the same property the
  /// theme and text roots above rely on.
  Widget _maybeExcludeSemantics(Widget child) =>
      kExcludeSemantics ? ExcludeSemantics(child: child) : child;

  @override
  Widget build(BuildContext context) {
    // Flutter's own [WindowManager] renders the shell, from the single
    // [WindowRegistry] it publishes to everything below it.
    //
    // Two things put windows in that registry and neither may tread on the
    // other: the root, through [_syncWindows], which owns the panels,
    // backgrounds, indicators, badges, selection surfaces, overlays and lock
    // screens; and every module that opens a popup or a runtime layer-shell
    // window, which registers itself from inside the tree (see `PopupHost` and
    // `LayerShellHost`). That is why the root's set is *reconciled* rather than
    // rebuilt here: a declarative list of views returned from `build` would
    // take every module's window down with it on each rebuild.
    //
    // [initialWindows] carries what the root owns *now* rather than only what
    // it owned at start-up, because it is also what a remount re-registers —
    // see [_registry] for the one case that needs one.
    //
    // One property this gave up, knowingly: the manager renders its registry as
    // *unkeyed* `Window`s, where the hand-built view list keyed each on its
    // controller. Keyless widgets of one type all satisfy `Widget.canUpdate`,
    // so `updateChildren` matches them positionally and dropping a window from
    // the middle shifts every later one down a slot. That is not a bug — each
    // `RawView` is globally keyed on its own `FlutterView`, so the render tree
    // and every bit of state under it are reparented rather than rebuilt, which
    // is the path `_retakeInactiveElement` documents as forward-looking
    // inactivity — but it does mean a close cascades through the windows
    // *after* it. Hence the registration order below: the per-monitor surfaces,
    // which almost never move, first; the overlays that open and close all day
    // after them; and the modules' own popups, appended last by whoever opened
    // them, after everything.
    return WindowManager(
      key: ValueKey(_managerGeneration),
      initialWindows: _rootEntries.values.toList(growable: false),
    );
  }

  /// Every native window the root itself owns, paired with the content that
  /// goes in it.
  ///
  /// The controller is a window's identity — [_syncWindows] keys the registry
  /// entries on it — so a window that survives a reconciliation keeps the
  /// [WindowEntry], and with it the builder, it was created with. Two rules
  /// follow for everything below: capture only what is fixed for the life of
  /// that window (its controller, its monitor, its panel name), and read
  /// anything that can still move out of the root's own fields *inside* the
  /// builder, where it is re-read on every rebuild.
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
            // SDK's `Window` already supplies the View and the WindowScope and
            // the registry now comes from the root, but popup content is built
            // outside the parent's ThemeScope.
            //
            // Deliberately no DisplayScope: the grid takes its geometry from a
            // LayoutBuilder and never needs the output at all.
            builder: (_) => _windowChrome(
              // A click on the desktop dismisses whatever a *panel* has open:
              // the two surfaces share a registry now but still no widget
              // tree, so the coordinator remains the only thing that can carry
              // the signal across.
              PopupDismissArea(
                child: Builder(
                  builder: (context) {
                    final live = LiveConfigScope.of(context);
                    // Background surface existence is startup-only; while it
                    // exists, follow live edits (fit / entry paths) but keep the
                    // startup wallpaper if the user clears every entry (a full
                    // removal needs a restart).
                    //
                    // Null here means "surface, but nothing to paint" — the
                    // grid-only case. That must render as *nothing*, not as
                    // BackgroundWindow's opaque empty fill, or a user with icons
                    // and no wallpaper gets a black desktop instead of whatever
                    // their compositor draws.
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
        // Not gated on the output being known. Output enumeration is no longer
        // awaited before the first frame, so a bar that waited for it would be
        // a bar the user watches appear a beat after login; it paints now and
        // [DisplayScope] fills in a moment later.
        for (final entry in startupPanels.entries)
          if (surfaces.panels[entry.key] case final controller?)
            (
              controller: controller,
              builder: (_) => _windowChrome(
                MiracleScope(
                  manager: widget.miracle,
                  child: DisplayProvider(
                    // Read here rather than captured: [_syncMonitors] replaces
                    // this snapshot in place when a monitor is repositioned,
                    // and a panel matched against the position its display has
                    // left behind shows another one's workspaces.
                    monitor: surfaces.monitor,
                    outputs: widget.outputs,
                    child: Builder(
                      builder: (context) {
                        final panel = effectivePanel(
                          entry.value,
                          LiveConfigScope.of(context).panels[entry.key],
                        );
                        // A click anywhere on the bar — an icon whose popup is
                        // not open, or bare padding — dismisses whatever else
                        // the shell has up.
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
        // The floating notification badge, likewise tied to the output rather
        // than to any panel — it is there whether or not this monitor's bars
        // carry the bell module at all.
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
                    // The connector, not the wl_output: this is what both the
                    // capture stack and miracle's tree key an output on, and
                    // `DisplayScope` would answer null for the first frames
                    // anyway — which is exactly the frames a selection surface
                    // is drawn for.
                    //
                    // The corner goes with it, and is not decoration: GDK
                    // reports no connector at all on a compositor with no
                    // `xdg-output` manager, so on those machines the string
                    // above is empty and this is the only identity the pick
                    // carries back to a display.
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
      // The notification panel. A single window like the overlays below it —
      // one panel for the machine, however many bells and badges ask for it —
      // so it lives outside the per-monitor loop as well.
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
      // The screen-share consent picker, open only while an application's
      // portal request is waiting on an answer. Single window, like the
      // launcher, so it lives outside the per-monitor loop.
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
      // The polkit prompt, open only while an application's request for
      // administrator rights is waiting on the user. A single window like the
      // launcher, so it lives outside the per-monitor loop.
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
      // The power menu, open only while the physical power button's press is
      // being answered. A single window like the launcher, so it lives outside
      // the per-monitor loop.
      if (_powerMenu.controller case final menu?)
        (
          controller: menu,
          builder: (_) => _windowChrome(
            PowerMenuOverlay(
              closingNotifier: _powerMenu.closing,
              onClosed: _onPowerMenuClosed,
              // The overlay dismisses itself and then this tears the window
              // down, so the verb runs while its own surface is still fading —
              // which is what "Lock" needs, since the lock surface is mapped
              // over the top of it.
              onAction: (action) => unawaited(PowerActions.run(action)),
            ),
          ),
        ),
      // The lock screen. These surfaces exist only while the session is
      // locked; the compositor hides every other surface — including the
      // panels above — for as long as they do.
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
  const PanelMain({super.key, required this.panelConfig, required this.anchor});

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
/// The deltas between them are constructor arguments, not subclasses:
/// [policy] (modal for the consent pickers), [acquiresAppIndex] (launcher and
/// app chooser), and [open]'s `monitor` (the settings overlay pins to the
/// first monitor; the rest pass none, so the compositor places them on its
/// focused output — where the user is).
class _OverlayWindow {
  _OverlayWindow({
    this.policy = TransientPolicy.menu,
    this.acquiresAppIndex = false,
    this.create,
  });

  final TransientPolicy policy;

  /// Builds the native window for the monitor [open] was asked for.
  ///
  /// Null is the full-screen backdrop seven of these eight want, which is
  /// what the class was for the whole time there was only that one shape. The
  /// notification panel is the exception — a column down one output edge —
  /// and it supplies its own rather than growing this into a geometry
  /// builder: what [_OverlayWindow] actually owns is the *bookkeeping* (the
  /// coordinator handle, the closing notifier, the index bracket, and a
  /// `dispose` that cannot be asymmetric with them), none of which cares what
  /// shape the surface is.
  final LayershellWindowController Function(
    ffi.Pointer<ffi.NativeType>? monitor,
  )?
  create;

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
  /// Without a [create] the window is overlay-layer, all-edges, keyboard
  /// `onDemand` — full-screen means the whole output, panels included, or the
  /// backdrop stops short of the bars and dismiss-on-backdrop has dead strips
  /// (hence [spanFullOutput]). [onDismiss] is what the coordinator calls to
  /// ask for a *graceful* close; the default flips [closing] and lets the
  /// content animate out. Pass a direct close for content with no exit
  /// animation.
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

/// Hands [onRegistry] the [WindowRegistry] the root's [WindowManager]
/// publishes.
///
/// The manager renders nothing but the windows in its registry — it has no
/// `child` slot — so the only context below it belongs to a window's own
/// content, and this rides along on every one of them through
/// `_GracefulShellRootState._windowChrome`. Depending on the scope rather than
/// reading it once is what makes a remounted manager (see
/// `_GracefulShellRootState._registry`) report its new registry rather than
/// leaving the root writing into a dead one.
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
