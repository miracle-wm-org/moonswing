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
  final config = await PanelConfig.load();

  MiracleConnection? connection;
  if (config.layout.enabledModules.contains(ModuleName.workspaces)) {
    connection = MiracleConnection();
    await connection.connect();
    await connection.subscribe([SubscriptionType.workspace]);
  }

  final monitors = listMonitors();

  final WaylandClient waylandClient = WaylandClient();
  await waylandClient.connect();

  WidgetsFlutterBinding.ensureInitialized();
  final windowingOwner = ExtendedWindowingOwnerLinux();
  WidgetsBinding.instance.windowingOwner = windowingOwner;
  final bar = windowingOwner.createLayerShellWindowController(
      delegate: LayershellWindowControllerDelegate(),
      height: config.height,
      layer: GtkLayerShellLayer.top,
      anchorEdges: [
        GtkLayerShellEdge.top,
        GtkLayerShellEdge.left,
        GtkLayerShellEdge.right
      ],
      exclusiveZone: config.height,
      monitor: monitors.first.gdkMonitor);
  runWidget(LayerShellWindow(
      controller: bar,
      child: PanelMain(config: config, connection: connection)));
}

class PanelMain extends StatefulWidget {
  const PanelMain({super.key, required this.config, this.connection});

  final PanelConfig config;
  final MiracleConnection? connection;

  @override
  _PanelMainState createState() => _PanelMainState();
}

class _PanelMainState extends State<PanelMain> {
  Widget _buildModule(ModuleName name) {
    switch (name) {
      case ModuleName.workspaces:
        if (widget.connection == null) return const SizedBox.shrink();
        return Workspaces(connection: widget.connection!);
      case ModuleName.mediaPlayer:
        return MediaPlayer(config: widget.config.mediaPlayer);
      case ModuleName.soundControl:
        return const SoundControl();
      case ModuleName.battery:
        return Battery(config: widget.config.battery);
      case ModuleName.weather:
        return Weather(config: widget.config.weather);
      case ModuleName.clock:
        return Clock(config: widget.config.clock);
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
    final layout = widget.config.layout;

    final sections = <Widget>[];

    if (layout.left.isNotEmpty) {
      sections.add(_buildSection(layout.left));
    }

    if (layout.center.isNotEmpty) {
      if (sections.isNotEmpty) sections.add(const _PanelDivider());
      sections.add(Expanded(child: Center(child: _buildSection(layout.center))));
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
            painter: const PanelBackgroundPainter(),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  widget.config.paddingHorizontal.toDouble(), 0,
                  widget.config.paddingHorizontal.toDouble(), 0),
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
