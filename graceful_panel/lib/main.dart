import 'package:flutter/material.dart';
import 'layer_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final windowingOwner = ExtendedWindowingOwnerLinux();
  WidgetsBinding.instance.windowingOwner = windowingOwner;
  final bar = windowingOwner.createLayerShellWindowController(
      delegate: LayershellWindowControllerDelegate());
  runWidget(LayerShellWindow(controller: bar, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    print(view.physicalSize);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.red,
        child: SizedBox(width: 1920, height: 48),
      ),
    );
  }
}
