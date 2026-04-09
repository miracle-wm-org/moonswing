// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:ubuntu_session/ubuntu_session.dart';
import 'package:graceful_shell/layer_shell.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';

class System extends StatefulWidget {
  const System({super.key});

  @override
  SystemState createState() => SystemState();
}

class SystemState extends State<System> {
  PopupWindowController? _popupController;
  PopupWindow? _popupView;
  bool _hovered = false;
  bool _popupHasBeenActive = false;

  @override
  void dispose() {
    _closePopup();
    super.dispose();
  }

  void _togglePopup(BuildContext context) {
    if (_popupController != null) {
      _closePopup();
      return;
    }

    final parentController = WindowScope.of(context);

    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final flutterView = View.of(context);
    final dpr = flutterView.devicePixelRatio;
    final barLogicalWidth = flutterView.physicalSize.width / dpr;
    final barLogicalHeight = flutterView.physicalSize.height / dpr;

    final anchor = BarScope.of(context).anchor;

    final Rect anchorRect;
    final WindowPositionerAnchor parentAnchor;
    final WindowPositionerAnchor childAnchor;

    switch (anchor) {
      case 'bottom':
        final screenH = getScreenSize().height;
        anchorRect =
            Rect.fromLTWH(offset.dx, screenH - barLogicalHeight, size.width, 0);
        parentAnchor = WindowPositionerAnchor.top;
        childAnchor = WindowPositionerAnchor.bottom;
      case 'left':
        anchorRect = Rect.fromLTWH(0, offset.dy, barLogicalWidth, size.height);
        parentAnchor = WindowPositionerAnchor.right;
        childAnchor = WindowPositionerAnchor.left;
      case 'right':
        final screenW = getScreenSize().width;
        anchorRect = Rect.fromLTWH(
            screenW - barLogicalWidth, offset.dy, barLogicalWidth, 0);
        parentAnchor = WindowPositionerAnchor.left;
        childAnchor = WindowPositionerAnchor.right;
      default: // 'top'
        anchorRect = Rect.fromLTWH(offset.dx, 0, size.width, 0);
        parentAnchor = WindowPositionerAnchor.bottom;
        childAnchor = WindowPositionerAnchor.top;
    }

    final theme = ThemeScope.of(context);

    PopupWindowController? thisController;
    _popupController = thisController = PopupWindowController(
      parent: parentController,
      anchorRect: anchorRect,
      positioner: WindowPositioner(
        parentAnchor: parentAnchor,
        childAnchor: childAnchor,
      ),
      preferredConstraints: const BoxConstraints.tightFor(width: 200, height: 154),
      delegate: _SystemPopupDelegate(onDestroyed: () {
        if (_popupController == thisController) _closePopup();
      }),
    );

    _popupView = PopupWindow(
      controller: _popupController!,
      child: ThemeScope(
        theme: theme,
        child: const _SystemPopupContent(),
      ),
    );
    _popupHasBeenActive = false;
    _popupController!.addListener(_onPopupStateChanged);
    PopupManager.instance.add(_popupView!);
    setState(() {});
  }

  void _onPopupStateChanged() {
    final ctrl = _popupController;
    if (ctrl == null) return;
    if (ctrl.isActivated) {
      _popupHasBeenActive = true;
    } else if (_popupHasBeenActive) {
      _popupHasBeenActive = false;
      _closePopup();
    }
  }

  void _closePopup() {
    _popupController?.removeListener(_onPopupStateChanged);
    if (_popupView != null) {
      PopupManager.instance.remove(_popupView!);
      _popupView = null;
    }
    final ctrl = _popupController;
    _popupController = null;
    if (ctrl is PopupGtkWindowController && !ctrl.isDestroyed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ctrl.isDestroyed) ctrl.destroy();
      });
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final isActive = _hovered || _popupController != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => _togglePopup(context),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? const Color(0x28FFFFFF) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: FaIcon(
            FontAwesomeIcons.powerOff,
            size: 12,
            color: theme.foreground,
          ),
        ),
      ),
    );
  }
}

class _SystemPopupDelegate extends PopupWindowControllerDelegate {
  _SystemPopupDelegate({required this.onDestroyed});
  final VoidCallback onDestroyed;

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    onDestroyed();
  }
}

class _SystemPopupContent extends StatelessWidget {
  const _SystemPopupContent();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(color: theme.popupForeground, fontSize: 13),
        child: Container(
          color: theme.popupBackground,
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SystemButton(
                icon: FontAwesomeIcons.arrowRightFromBracket,
                label: 'Log Out',
                onTap: () async {
                  final session = UbuntuSession();
                  await session.logout();
                },
              ),
              const SizedBox(height: 4),
              _SystemButton(
                icon: FontAwesomeIcons.powerOff,
                label: 'Shut Down',
                onTap: () async {
                  final session = UbuntuSession();
                  await session.shutdown();
                },
              ),
              const SizedBox(height: 4),
              _SystemButton(
                icon: FontAwesomeIcons.moon,
                label: 'Sleep',
                onTap: () async {
                  final manager = SystemdSessionManager();
                  await manager.connect();
                  await manager.suspend(false);
                  await manager.close();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemButton extends StatefulWidget {
  const _SystemButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  _SystemButtonState createState() => _SystemButtonState();
}

class _SystemButtonState extends State<_SystemButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hovered ? theme.surfaceHover : null,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              FaIcon(
                widget.icon,
                size: 14,
                color: theme.popupForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SystemModule extends Module {
  @override
  String get configKey => 'system';

  @override
  void loadConfig(Map<String, dynamic>? map) {}

  @override
  WidgetBuilder get builder => (_) => const System();
}
