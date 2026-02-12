import 'package:flutter/widgets.dart';
import 'package:graceful_panel/config.dart';
import 'package:graceful_panel/modules/battery.dart';
import 'package:graceful_panel/modules/sound_control.dart';
import 'package:graceful_panel/modules/clock.dart';
import 'package:graceful_panel/modules/media_player.dart';
import 'package:graceful_panel/modules/weather.dart';
import 'package:graceful_panel/modules/workspaces.dart';
import 'package:graceful_panel/panel_background.dart';
import 'layer_shell.dart';
import 'package:miracle/miracle.dart';
import 'package:wayland/wayland.dart';

void main() async {
  final appConfig = await AppConfig.load();

  MiracleConnection connection = MiracleConnection();
  await connection.connect();
  await connection.subscribe([SubscriptionType.workspace]);

  final monitors = listMonitors();

  final WaylandClient waylandClient = WaylandClient();
  await waylandClient.connect();

  WidgetsFlutterBinding.ensureInitialized();
  final windowingOwner = ExtendedWindowingOwnerLinux();
  WidgetsBinding.instance.windowingOwner = windowingOwner;

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

    controllers[entry.key] = windowingOwner.createLayerShellWindowController(
      delegate: LayershellWindowControllerDelegate(),
      width: width,
      height: height,
      layer: layer,
      anchorEdges: anchorEdges,
      exclusiveZone: panelConfig.height,
      monitor: monitors.first.gdkMonitor,
    );
  }

  runWidget(ViewCollection(
    views: [
      for (final entry in appConfig.panels.entries)
        LayerShellWindow(
          controller: controllers[entry.key]!,
          child: PanelMain(
            panelConfig: entry.value,
            modulesConfig: appConfig.modules,
            connection: connection,
          ),
        ),
    ],
  ));
}

class PanelMain extends StatefulWidget {
  const PanelMain({
    super.key,
    required this.panelConfig,
    required this.modulesConfig,
    required this.connection,
  });

  final PanelConfig panelConfig;
  final ModulesConfig modulesConfig;
  final MiracleConnection connection;

  @override
  _PanelMainState createState() => _PanelMainState();
}

class _PanelMainState extends State<PanelMain> {
  Widget _buildModule(ModuleName name) {
    switch (name) {
      case ModuleName.workspaces:
        return Workspaces(connection: widget.connection);
      case ModuleName.mediaPlayer:
        return MediaPlayer(config: widget.modulesConfig.mediaPlayer);
      case ModuleName.soundControl:
        return const SoundControl();
      case ModuleName.battery:
        return Battery(config: widget.modulesConfig.battery);
      case ModuleName.weather:
        return Weather(config: widget.modulesConfig.weather);
      case ModuleName.clock:
        return Clock(config: widget.modulesConfig.clock);
    }
  }

  Widget _buildSection(List<ModuleName> modules) {
    if (modules.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (int i = 0; i < modules.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 8));
      children.add(_buildModule(modules[i]));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.panelConfig.layout;

    final sections = <Widget>[];

    if (layout.left.isNotEmpty) {
      sections.add(_buildSection(layout.left));
    }

    if (layout.center.isNotEmpty) {
      if (sections.isNotEmpty) sections.add(const _PanelDivider());
      sections
          .add(Expanded(child: Center(child: _buildSection(layout.center))));
    } else {
      sections.add(const Expanded(child: SizedBox.shrink()));
    }

    if (layout.right.isNotEmpty) {
      if (layout.center.isNotEmpty || layout.left.isNotEmpty) {
        sections.add(const _PanelDivider());
      }
      sections.add(_buildSection(layout.right));
    }

    return DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'Ubuntu Sans',
        fontSize: 12,
        color: Color(0xFFE0E0E0),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.expand(
          child: CustomPaint(
            painter: PanelBackgroundPainter(
              anchor: widget.panelConfig.anchor,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  widget.panelConfig.paddingHorizontal.toDouble(),
                  0,
                  widget.panelConfig.paddingHorizontal.toDouble(),
                  0),
              child: Row(children: sections),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Container(
        width: 1,
        color: const Color(0x33FFFFFF),
      ),
    );
  }
}
