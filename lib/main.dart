import 'package:flutter/widgets.dart';
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
import 'layer_shell.dart';
import 'gtk.dart';
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

  MiracleConnection connection = MiracleConnection();
  await connection.connect();
  await connection.subscribe([SubscriptionType.workspace]);

  final monitors = listMonitors();

  final WaylandClient waylandClient = WaylandClient();
  await waylandClient.connect();

  final windowingOwner = ExtendedWindowingOwnerLinux();
  WidgetsBinding.instance.windowingOwner = windowingOwner;

  final backgroundControllers = <LayershellWindowController>[];
  if (appConfig.background != null &&
      appConfig.background!.entries.isNotEmpty) {
    for (final monitor in monitors) {
      backgroundControllers.add(LayershellWindowController(
        owner: windowingOwner,
        delegate: LayershellWindowControllerDelegate(),
        layer: GtkLayerShellLayer.background,
        anchorEdges: [
          GtkLayerShellEdge.top,
          GtkLayerShellEdge.bottom,
          GtkLayerShellEdge.left,
          GtkLayerShellEdge.right,
        ],
        keyboardMode: GtkLayerShellKeyboardMode.none,
        monitor: monitor.gdkMonitor,
      ));
    }
  }

  final monitorControllers = <Map<String, LayershellWindowController>>[];
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
        owner: windowingOwner,
        delegate: LayershellWindowControllerDelegate(),
        width: width,
        height: height,
        layer: layer,
        anchorEdges: anchorEdges,
        exclusiveZone: panelConfig.height,
        monitor: monitor.gdkMonitor,
      );
    }
    monitorControllers.add(controllers);
  }

  runWidget(ListenableBuilder(
    listenable: PopupManager.instance,
    builder: (context, _) => ViewCollection(
      views: [
        for (final ctrl in backgroundControllers)
          LayerShellWindow(
            controller: ctrl,
            child: BackgroundWindow(config: appConfig.background!),
          ),
        for (final controllers in monitorControllers)
          for (final entry in appConfig.panels.entries)
            LayerShellWindow(
              controller: controllers[entry.key]!,
              child: ThemeScope(
                theme: appConfig.theme,
                child: MiracleScope(
                  connection: connection,
                  child: PanelMain(
                    panelConfig: entry.value,
                    anchor: entry.value.anchor,
                  ),
                ),
              ),
            ),
        ...PopupManager.instance.popupViews,
      ],
    ),
  ));
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

    final sections = <Widget>[];

    if (layout.left.isNotEmpty) {
      sections.add(_buildSection(layout.left));
    }

    final bool vertical = widget.panelConfig.anchor == 'left' ||
        widget.panelConfig.anchor == 'right';

    if (layout.center.isNotEmpty) {
      if (sections.isNotEmpty) sections.add(_PanelDivider(vertical: vertical));
      sections
          .add(Expanded(child: Center(child: _buildSection(layout.center))));
    } else {
      sections.add(const Expanded(child: SizedBox.shrink()));
    }

    if (layout.right.isNotEmpty) {
      if (layout.center.isNotEmpty || layout.left.isNotEmpty) {
        sections.add(_PanelDivider(vertical: vertical));
      }
      sections.add(_buildSection(layout.right));
    }
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
                  ),
                  child: child,
                );
              },
              child: Padding(
                padding: vertical
                    ? EdgeInsets.fromLTRB(0, pad, 0, pad)
                    : EdgeInsets.fromLTRB(pad, 0, pad, 0),
                child: vertical
                    ? Column(children: sections)
                    : Row(children: sections),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider({this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Container(
        width: vertical ? null : 1,
        height: vertical ? 1 : null,
        color: ThemeScope.of(context).divider,
      ),
    );
  }
}
