import 'dart:async';
// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:graceful_shell/background.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/modules/battery.dart';
import 'package:graceful_shell/modules/dock.dart';
import 'package:graceful_shell/modules/sound_control.dart';
import 'package:graceful_shell/modules/clock.dart';
import 'package:graceful_shell/modules/media_player.dart';
import 'package:graceful_shell/modules/network.dart';
import 'package:graceful_shell/modules/notifications.dart';
import 'package:graceful_shell/modules/system.dart';
import 'package:graceful_shell/modules/system_monitor.dart';
import 'package:graceful_shell/modules/weather.dart';
import 'package:graceful_shell/modules/workspaces.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/panel_background.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miracle/miracle.dart';
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

  final appConfig = await AppConfig.load();

  await startNotificationService();

  MiracleConnection? connection;
  try {
    connection = MiracleConnection();
    await connection.connect();
    await connection.subscribe([SubscriptionType.workspace]);
  } catch (e) {
    connection = null;
  }

  final WaylandClient waylandClient = WaylandClient();
  await waylandClient.connect();

  final waylandOutputs = <WaylandOutput>[];
  final outputCompleters = <Completer<void>>[];
  WaylandRegistry? waylandRegistry;
  waylandRegistry = waylandClient.getRegistry(
    onGlobal: (globalName, interface, version) {
      if (interface == 'wl_output') {
        final completer = Completer<void>();
        outputCompleters.add(completer);
        waylandOutputs.add(WaylandOutput(
          waylandClient,
          waylandRegistry!.bind(globalName, interface, version),
          onDone: completer.complete,
        ));
      }
    },
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
    connection: connection,
    waylandOutputs: waylandOutputs,
  ));
}

/// Root of the widget tree. Owns the lifecycle of every startup layer-shell
/// window (backgrounds + panels), creating them in [initState] and destroying
/// them in [dispose].
class GracefulShellRoot extends StatefulWidget {
  const GracefulShellRoot({
    super.key,
    required this.appConfig,
    required this.connection,
    required this.waylandOutputs,
  });

  final AppConfig appConfig;
  final MiracleConnection? connection;
  final List<WaylandOutput> waylandOutputs;

  @override
  State<GracefulShellRoot> createState() => _GracefulShellRootState();
}

class _GracefulShellRootState extends State<GracefulShellRoot> {
  final List<LayershellWindowController> _backgroundControllers = [];
  final List<Map<String, LayershellWindowController>> _monitorControllers = [];
  late final List<
      (
        MonitorInfo,
        Map<String, LayershellWindowController>,
        WaylandOutput
      )> _monitoredControllers;

  @override
  void initState() {
    super.initState();
    final appConfig = widget.appConfig;
    final monitors = listMonitors();

    if (appConfig.background != null &&
        appConfig.background!.entries.isNotEmpty) {
      for (final monitor in monitors) {
        _backgroundControllers.add(LayershellWindowController(
          layer: LayerShellLayer.background,
          anchorEdges: [
            LayerShellEdge.top,
            LayerShellEdge.bottom,
            LayerShellEdge.left,
            LayerShellEdge.right,
          ],
          keyboardMode: LayerShellKeyboardMode.none,
          monitor: monitor.gdkMonitor,
        ));
      }
    }

    for (final monitor in monitors) {
      final controllers = <String, LayershellWindowController>{};
      for (final entry in appConfig.panels.entries) {
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

        controllers[entry.key] = LayershellWindowController(
          width: width,
          height: height,
          layer: layer,
          anchorEdges: anchorEdges,
          exclusiveZone: panelConfig.height,
          monitor: monitor.gdkMonitor,
        );
      }
      _monitorControllers.add(controllers);
    }

    WaylandOutput matchOutput(MonitorInfo monitor) =>
        widget.waylandOutputs.firstWhere(
          (o) =>
              o.make == monitor.manufacturer &&
              o.model == monitor.model &&
              o.x == monitor.position.dx.toInt() &&
              o.y == monitor.position.dy.toInt(),
          orElse: () => widget.waylandOutputs.first,
        );

    _monitoredControllers = List.generate(
      monitors.length,
      (i) => (monitors[i], _monitorControllers[i], matchOutput(monitors[i])),
    );
  }

  @override
  void dispose() {
    for (final ctrl in _backgroundControllers) {
      ctrl.destroy();
    }
    for (final controllers in _monitorControllers) {
      for (final ctrl in controllers.values) {
        ctrl.destroy();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = widget.appConfig;
    return ViewCollection(
      views: [
        for (final ctrl in _backgroundControllers)
          LayerShellWindow(
            controller: ctrl,
            child: BackgroundWindow(config: appConfig.background!),
          ),
        for (final (_, controllers, waylandOutput) in _monitoredControllers)
          for (final entry in appConfig.panels.entries)
            LayerShellWindow(
              controller: controllers[entry.key]!,
              child: WindowManager(
                child: ThemeScope(
                  theme: appConfig.theme,
                  child: MiracleScope(
                    connection: widget.connection,
                    child: DisplayScope(
                      output: waylandOutput,
                      child: PanelMain(
                        panelConfig: entry.value,
                        anchor: entry.value.anchor,
                      ),
                    ),
                  ),
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
