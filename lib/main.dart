import 'dart:async';
// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/background.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/miracle_manager.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/monitor_watcher.dart';
import 'package:graceful_shell/modules/battery.dart';
import 'package:graceful_shell/modules/dock.dart';
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
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/panel_background.dart';
import 'package:graceful_shell/status_notifier_service.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/settings/config_store.dart';
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

  // AppConfig.load() writes the default config on first run and applies the
  // module subtables; the shared ConfigStore then reads that same file and
  // becomes the single live source of truth the shell watches.
  final appConfig = await AppConfig.load();
  final store = await ConfigStore.initShared();

  await startNotificationService();
  await startStatusNotifierService();

  // Miracle may not be running yet (or at all). The manager keeps the shell
  // usable either way — the workspaces module offers a retry when it is absent.
  final miracle = MiracleManager();
  await miracle.connect();

  final WaylandClient waylandClient = WaylandClient();
  await waylandClient.connect();

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
    },
    onGlobalRemove: (globalName) => outputs.remove(globalName),
  );
  final syncCompleter = Completer<void>();
  waylandClient.sync((_) => syncCompleter.complete());
  await syncCompleter.future;
  await Future.wait(outputCompleters.map((c) => c.future));

  initLayerShell();

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

  /// Whether a background window should exist on each monitor. Fixed at startup
  /// (like the native window geometry) so newly-plugged monitors get a matching
  /// background.
  late final bool _hasBackground;

  late final MonitorWatcher _monitorWatcher;
  bool _syncScheduled = false;

  /// The current config the widget tree renders from. Kept in sync with
  /// [GracefulShellRoot.store] by [_onConfigChanged] so theme, panel layout,
  /// per-module options, and the background image update live. Window geometry
  /// still comes from [widget.appConfig] (the startup snapshot).
  late AppConfig _liveConfig;

  @override
  void initState() {
    super.initState();
    final appConfig = widget.appConfig;
    _liveConfig = appConfig;
    _hasBackground =
        appConfig.background != null && appConfig.background!.entries.isNotEmpty;
    widget.store.addListener(_onConfigChanged);
    widget.outputs.addListener(_onOutputsChanged);

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
    if (_hasBackground) {
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

      panels[entry.key] = LayershellWindowController(
        width: width,
        height: height,
        layer: layer,
        anchorEdges: anchorEdges,
        exclusiveZone: panelConfig.height,
        monitor: monitor.gdkMonitor,
      );
    }

    return _MonitorSurfaces(monitor, background, panels);
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
    var changed = false;

    for (final key in _surfaces.keys.toList()) {
      if (!incoming.containsKey(key)) {
        removed.addAll(_surfaces.remove(key)!.controllers);
        changed = true;
      }
    }

    for (final entry in incoming.entries) {
      if (!_surfaces.containsKey(entry.key)) {
        _surfaces[entry.key] = _createSurfaces(entry.value);
        changed = true;
      }
    }

    if (!changed) return;

    setState(() {});

    // Detach the removed views from the tree first (via the setState above),
    // then destroy their native windows once the frame that dropped them has
    // been rendered — destroying while Flutter still renders into the view
    // would use a freed FlView.
    if (removed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final controller in removed) {
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

  @override
  void dispose() {
    widget.store.removeListener(_onConfigChanged);
    widget.outputs.removeListener(_onOutputsChanged);
    _monitorWatcher.dispose();
    for (final surfaces in _surfaces.values) {
      for (final ctrl in surfaces.controllers) {
        ctrl.destroy();
      }
    }
    _surfaces.clear();
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

    // Background window existence is startup-only; while it exists, follow live
    // edits (fit / entry paths) but keep the startup wallpaper if the user
    // clears every entry (a full removal needs a restart).
    final liveBg = _liveConfig.background;
    final BackgroundConfig? bgConfig = !_hasBackground
        ? null
        : (liveBg != null && liveBg.entries.isNotEmpty
            ? liveBg
            : widget.appConfig.background!);

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
              child: BackgroundWindow(config: bgConfig!),
            ),
          if (_outputFor(surfaces.monitor) case final output?)
            for (final entry in startupPanels.entries)
              if (surfaces.panels[entry.key] case final controller?)
                LayerShellWindow(
                  key: ObjectKey(controller),
                  controller: controller,
                  child: WindowManager(
                    child: ThemeScope(
                      theme: _liveConfig.theme,
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
        ],
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

class _PanelMainState extends State<PanelMain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bgAnimation;

  @override
  void initState() {
    super.initState();
    _bgAnimation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _bgAnimation.dispose();
    super.dispose();
  }

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
            child: AnimatedBuilder(
              animation: _bgAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: PanelBackgroundPainter(
                    anchor: widget.panelConfig.anchor,
                    animationValue: _bgAnimation.value,
                    theme: theme,
                  ),
                  child: child,
                );
              },
              child: Padding(
                padding: vertical
                    ? EdgeInsets.fromLTRB(0, pad, 0, pad)
                    : EdgeInsets.fromLTRB(pad, 0, pad, 0),
                child: Stack(children: stackChildren),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
