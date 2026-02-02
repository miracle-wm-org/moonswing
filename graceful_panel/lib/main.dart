import 'package:flutter/widgets.dart';
import 'package:graceful_panel/modules/battery.dart';
import 'package:graceful_panel/modules/clock.dart';
import 'package:graceful_panel/modules/weather.dart';
import 'package:graceful_panel/modules/workspaces.dart';
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
          color: Color(0xFF000000),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
              child: Container(
                  child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Row(
              children: [
                Container(
                  color: const Color(0x11000000),
                  child: Workspaces(connection: widget.connection),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0x111A1A1A),
                  ),
                ),
                Container(
                  color: const Color(0x001A1A1A),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Battery(),
                      const SizedBox(width: 8),
                      Weather(),
                      const SizedBox(width: 8),
                      Clock(),
                    ],
                  ),
                ),
              ],
            ),
          ))),
        ));
  }
}
