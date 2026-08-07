import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:ubuntu_session/ubuntu_session.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:graceful_shell/lock/lock_controller.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';

class System extends StatefulWidget {
  const System({super.key});

  @override
  SystemState createState() => SystemState();
}

class SystemState extends State<System>
    with PopupHost<System>, LayerShellHost<System> {
  bool _hovered = false;

  @override
  void dispose() {
    closeLayerWindow();
    closePopup();
    super.dispose();
  }

  void _showConfirmation(String label, Future<void> Function() action) {
    closePopup();
    final controller = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: [
        LayerShellEdge.top,
        LayerShellEdge.bottom,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      keyboardMode: LayerShellKeyboardMode.onDemand,
    );
    // Full-screen means the whole output, panels included.
    spanFullOutput(controller);
    // Register into this panel's WindowRegistry via the state's own context —
    // the System bar widget is mounted inside the panel's PanelWindowManager.
    openLayerWindow(
      context,
      controller: controller,
      child: ThemeProvider(
        child: _ConfirmationDialog(
          label: label,
          action: action,
          onClose: _closeConfirmation,
        ),
      ),
    );
  }

  void _closeConfirmation() {
    closeLayerWindow();
  }

  /// Locking needs no confirmation — it is trivially reversible with a
  /// password, unlike the other three actions.
  void _lock() {
    closePopup();
    LockController.instance.lock();
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }

    openBarPopup(
      context,
      preferredConstraints:
          const BoxConstraints.tightFor(width: 200, height: 202),
      child: ThemeProvider(
        child: _SystemPopupContent(
          onShowConfirmation: _showConfirmation,
          onLock: _lock,
        ),
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
  const _SystemPopupContent({
    required this.onShowConfirmation,
    required this.onLock,
  });

  final void Function(String, Future<void> Function()) onShowConfirmation;
  final VoidCallback onLock;

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
                  icon: FontAwesomeIcons.lock,
                  label: 'Lock',
                  onTap: onLock,
                ),
                const SizedBox(height: 4),
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
