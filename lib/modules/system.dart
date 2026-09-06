import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/power/power_actions.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';

class System extends StatefulWidget {
  const System({super.key});

  @override
  SystemState createState() => SystemState();
}

class SystemState extends State<System>
    with PopupHost<System>, LayerShellHost<System> {

  @override
  void dispose() {
    closeLayerWindow();
    closePopup();
    super.dispose();
  }

  /// Runs [action], with a confirmation for the four that end the session or the
  /// uptime.
  ///
  /// The half the power *menu* deliberately does not have: that surface opens
  /// because the power button was pressed, so answering it is already a second
  /// deliberate act. A bar icon is one small target in a row of them.
  void _runAction(PowerAction action) {
    if (!action.needsConfirmation) {
      closePopup();
      unawaited(PowerActions.run(action));
      return;
    }
    _showConfirmation(action);
  }

  void _showConfirmation(PowerAction action) {
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
    // Register into the root's WindowRegistry via the state's own context —
    // the System bar widget is mounted inside the root's WindowManager, like
    // everything else the shell draws.
    openLayerWindow(
      context,
      controller: controller,
      // Modal: this dialog holds a pending shutdown or reboot, so a click
      // elsewhere must not answer it. It resolves through Cancel, Confirm,
      // Escape, or its own timeout.
      policy: TransientPolicy.modal,
      child: ThemeProvider(
        child: _ConfirmationDialog(
          label: action.label,
          action: () => PowerActions.run(action),
          onClose: _closeConfirmation,
        ),
      ),
    );
  }

  void _closeConfirmation() {
    closeLayerWindow();
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }

    openBarPopup(
      context,
      // Loose, so the menu hugs its buttons instead of the hand-computed
      // 200x202 this used to pin. The maxima are a runaway guard, not a size.
      preferredConstraints: const BoxConstraints(maxWidth: 320, maxHeight: 400),
      child: ThemeProvider(
        child: SystemPopupContent(onAction: _runAction),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return BarButton(
      active: isPopupOpen,
      onTapDown: (_) => _togglePopup(context),
      child: FaIcon(
            FontAwesomeIcons.powerOff,
            size: 12,
            color: theme.foreground,
          ),
    );
  }
}

/// The bar's power menu: one row per [PowerAction], in [kPowerMenuActions]'
/// order.
///
/// The rows used to be four hand-written buttons carrying their own labels, icons
/// and closures, which is why this menu had no Restart. It and the power menu the
/// physical button opens are now the same list of verbs drawn two ways.
class SystemPopupContent extends StatelessWidget {
  const SystemPopupContent({
    super.key,
    required this.onAction,
    this.actions = kPowerMenuActions,
  });

  /// Performs the chosen verb — including whatever confirmation the host
  /// wants around it, which is the module's business rather than this
  /// widget's.
  final void Function(PowerAction action) onAction;

  final List<PowerAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(color: theme.popupForeground, fontSize: 13),
        child: PopupCard(
          padding: const EdgeInsets.all(8),
          // The popup is sized to content, so the menu is only as wide as its
          // widest label. [_SystemButton] is a Row holding an [Expanded] label,
          // though, so left to itself each button would fill whatever maximum the
          // constraints allow. IntrinsicWidth measures the widest button and
          // `stretch` gives every button that width, which keeps the Expanded
          // bounded and the hover highlights flush with each other.
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, action) in actions.indexed) ...[
                  if (index > 0) const SizedBox(height: 4),
                  _SystemButton(
                    icon: action.icon,
                    label: action.label,
                    onTap: () => onAction(action),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemButton extends StatelessWidget {
  const _SystemButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        decoration: BoxDecoration(
          color: hovered ? theme.surfaceHover : null,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            FaIcon(
              icon,
              size: 14,
              color: theme.popupForeground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label),
            ),
          ],
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
            child: SizedBox(
              width: 380,
              child: PopupCard(
                padding: const EdgeInsets.all(28),
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
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: primary
              ? (hovered
                  ? Color.lerp(theme.accent, const Color(0xFFFFFFFF), 0.15)!
                  : theme.accent)
              : (hovered ? theme.surfaceHover : const Color(0x00000000)),
          borderRadius: BorderRadius.circular(6),
          border: primary
              ? null
              : Border.all(
                  color: theme.popupForeground.withValues(alpha: 0.3),
                ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: theme.popupForeground,
            fontSize: 13,
            fontFamily: theme.fontFamily,
            decoration: TextDecoration.none,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}


final Module systemModule = Module.plain(
  configKey: 'system',
  builder: (_) => const System(),
);
