import 'package:flutter/widgets.dart';
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
  final MiracleConnection connection = MiracleConnection();
  await connection.connect();
  await connection.subscribe([SubscriptionType.workspace]);

  final monitors = listMonitors();

  final WaylandClient waylandClient = WaylandClient();
  await waylandClient.connect();

  const int kPanelSizePx = 32;

  WidgetsFlutterBinding.ensureInitialized();
  final windowingOwner = ExtendedWindowingOwnerLinux();
  WidgetsBinding.instance.windowingOwner = windowingOwner;
  final bar = windowingOwner.createLayerShellWindowController(
      delegate: LayershellWindowControllerDelegate(),
      height: kPanelSizePx,
      layer: GtkLayerShellLayer.top,
      anchorEdges: [
        GtkLayerShellEdge.top,
        GtkLayerShellEdge.left,
        GtkLayerShellEdge.right
      ],
      exclusiveZone: kPanelSizePx,
      monitor: monitors.first.gdkMonitor);
  runWidget(LayerShellWindow(
      controller: bar, child: PanelMain(connection: connection)));
}

class PanelMain extends StatefulWidget {
  const PanelMain({super.key, required this.connection});

  final MiracleConnection connection;

  @override
  _PanelMainState createState() => _PanelMainState();
}

class _PanelMainState extends State<PanelMain> {
  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 0),
              child: Row(
                children: [
                  Workspaces(connection: widget.connection),
                  const _PanelDivider(),
                  const Expanded(child: Center(child: MediaPlayer())),
                  const _PanelDivider(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SoundControl(),
                      const SizedBox(width: 8),
                      Battery(),
                      const SizedBox(width: 8),
                      Weather(),
                      const SizedBox(width: 8),
                      Clock(),
                    ],
                  ),
                ],
              ),
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
