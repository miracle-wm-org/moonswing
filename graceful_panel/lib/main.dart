import 'package:flutter/material.dart';
import 'layer_shell.dart';

void main() {
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
      exclusiveZone: kPanelSizePx);
  runWidget(LayerShellWindow(controller: bar, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox.expand(
        child: Container(
          color: Colors.red.withOpacity(0.5),
        ),
      ),
    );
  }
}
