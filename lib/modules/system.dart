// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:ubuntu_session/ubuntu_session.dart';
import 'package:graceful_shell/gtk.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/layer_shell.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';

class System extends StatefulWidget {
  const System({super.key});

  @override
  SystemState createState() => SystemState();
}

class SystemState extends State<System> with PopupHost<System> {
  bool _hovered = false;
  ThemeConfig? _storedTheme;
  LayershellWindowController? _confirmController;
  LayerShellWindow? _confirmView;

  @override
  void dispose() {
    _closeConfirmation();
    closePopup();
    super.dispose();
  }

  void _showConfirmation(String label, Future<void> Function() action) {
    closePopup();
    final owner =
        WidgetsBinding.instance.windowingOwner as ExtendedWindowingOwnerLinux;
    _confirmController = LayershellWindowController(
      owner: owner,
      delegate: RegularWindowControllerDelegate(),
      layer: GtkLayerShellLayer.overlay,
      anchorEdges: [
        GtkLayerShellEdge.top,
        GtkLayerShellEdge.bottom,
        GtkLayerShellEdge.left,
        GtkLayerShellEdge.right,
      ],
      keyboardMode: GtkLayerShellKeyboardMode.onDemand,
    );
    _confirmView = LayerShellWindow(
      controller: _confirmController!,
      child: ThemeScope(
        theme: _storedTheme!,
        child: _ConfirmationDialog(
          label: label,
          action: action,
          onClose: _closeConfirmation,
        ),
      ),
    );
    DynamicLayerShellViews.instance.add(_confirmView!);
    if (mounted) setState(() {});
  }

  void _closeConfirmation() {
    if (_confirmView != null) {
      DynamicLayerShellViews.instance.remove(_confirmView!);
      _confirmView = null;
    }
    final ctrl = _confirmController;
    _confirmController = null;
    ctrl?.destroy();
    if (mounted) setState(() {});
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }

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

    _storedTheme = ThemeScope.of(context);

    openPopup(
      context,
      anchorRect: anchorRect,
      parentAnchor: parentAnchor,
      childAnchor: childAnchor,
      preferredConstraints:
          const BoxConstraints.tightFor(width: 200, height: 154),
      child: ThemeScope(
        theme: _storedTheme!,
        child: _SystemPopupContent(onShowConfirmation: _showConfirmation),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final isActive = _hovered || isPopupOpen;
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

class _SystemPopupContent extends StatelessWidget {
  const _SystemPopupContent({required this.onShowConfirmation});

  final void Function(String, Future<void> Function()) onShowConfirmation;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(color: theme.popupForeground, fontSize: 13),
        child: PopupBounceIn(
          child: Container(
            color: theme.popupBackground,
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SystemButton(
                  icon: FontAwesomeIcons.arrowRightFromBracket,
                  label: 'Log Out',
                  onTap: () => onShowConfirmation('Log Out', () async {
                    final session = UbuntuSession();
                    await session.logout();
                  }),
                ),
                const SizedBox(height: 4),
                _SystemButton(
                  icon: FontAwesomeIcons.powerOff,
                  label: 'Shut Down',
                  onTap: () => onShowConfirmation('Shut Down', () async {
                    final session = UbuntuSession();
                    await session.shutdown();
                  }),
                ),
                const SizedBox(height: 4),
                _SystemButton(
                  icon: FontAwesomeIcons.moon,
                  label: 'Sleep',
                  onTap: () => onShowConfirmation('Sleep', () async {
                    final manager = SystemdSessionManager();
                    await manager.connect();
                    await manager.suspend(false);
                    await manager.close();
                  }),
                ),
              ],
            ),
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

class _ConfirmationDialog extends StatefulWidget {
  const _ConfirmationDialog({
    required this.label,
    required this.action,
    required this.onClose,
  });

  final String label;
  final Future<void> Function() action;
  final VoidCallback onClose;

  @override
  _ConfirmationDialogState createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<_ConfirmationDialog> {
  int _secondsRemaining = 60;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        _timer.cancel();
        widget.onClose();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _confirm() {
    _timer.cancel();
    widget.onClose();
    widget.action();
  }

  void _cancel() {
    _timer.cancel();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: const Color(0xAA000000),
          child: Center(
            child: Container(
              width: 380,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: theme.popupBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Are you sure that you want to ${widget.label.toLowerCase()}?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.popupForeground,
                      fontSize: 16,
                      fontFamily: theme.fontFamily,
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Cancels automatically in $_secondsRemaining seconds',
                    style: TextStyle(
                      color: theme.popupForeground.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontFamily: theme.fontFamily,
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _DialogButton(
                        label: 'Cancel',
                        onTap: _cancel,
                        primary: false,
                      ),
                      const SizedBox(width: 12),
                      _DialogButton(
                        label: widget.label,
                        onTap: _confirm,
                        primary: true,
                      ),
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

class _DialogButton extends StatefulWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  _DialogButtonState createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color bg;
    if (widget.primary) {
      bg = _hovered
          ? Color.lerp(theme.accent, const Color(0xFFFFFFFF), 0.15)!
          : theme.accent;
    } else {
      bg = _hovered ? theme.surfaceHover : const Color(0x00000000);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.primary
                ? null
                : Border.all(
                    color: theme.popupForeground.withValues(alpha: 0.3),
                  ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: theme.popupForeground,
              fontSize: 13,
              fontFamily: theme.fontFamily,
              decoration: TextDecoration.none,
              fontWeight: FontWeight.normal,
            ),
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
