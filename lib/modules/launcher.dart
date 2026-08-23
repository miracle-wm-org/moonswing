// The magnifier button that opens the application launcher.
//
// It creates no window of its own: it pokes [LauncherController], exactly as
// the global shortcut does, so both entry points end up in the same code path
// and there can only ever be one launcher.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/launcher/launcher_controller.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';

class LauncherButton extends StatefulWidget {
  const LauncherButton({super.key, this.iconSize = 18});

  final int iconSize;

  @override
  State<LauncherButton> createState() => _LauncherButtonState();
}

class _LauncherButtonState extends State<LauncherButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    Color color = const Color(0x00000000);
    if (_pressed) {
      color = theme.surfacePressed;
    } else if (_hovered) {
      color = theme.surfaceHover;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          LauncherController.instance.toggle();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SizedBox(
            width: widget.iconSize.toDouble(),
            height: widget.iconSize.toDouble(),
            child: Center(
              child: FaIcon(
                FontAwesomeIcons.magnifyingGlass,
                size: widget.iconSize * 0.72,
                color: theme.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `[modules.launcher]`.
class LauncherConfig {
  /// Rendered icon width/height, in logical pixels.
  final int iconSize;

  const LauncherConfig({this.iconSize = 18});

  factory LauncherConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const LauncherConfig();
    return LauncherConfig(
      iconSize: map.intOr('icon_size', 18),
    );
  }
}

final Module launcherModule = Module.simple(
  configKey: 'launcher',
  fromMap: LauncherConfig.fromMap,
  builder: (context, config) => LauncherButton(iconSize: config.iconSize),
);
