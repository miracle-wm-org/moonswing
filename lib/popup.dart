// Popup infrastructure built on Flutter's regular (experimental) windowing
// API. Popups are real compositor-positioned windows (xdg_popup) created by the
// default WindowingOwnerLinux that layer_shell's initLayerShell() installs — no
// hand-rolled positioning: the compositor places the popup from the parent-local
// [anchorRect] and [WindowPositioner].

// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
import 'package:graceful_shell/scopes.dart';

/// Shared delegate that forwards [onWindowDestroyed] to a callback.
class PopupDelegate extends PopupWindowControllerDelegate {
  PopupDelegate({required this.onDestroyed});
  final VoidCallback onDestroyed;

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    onDestroyed();
  }
}

/// Maps a panel's anchor edge to the (parentAnchor, childAnchor) pair that makes
/// a popup appear flush against the inner edge of the bar.
///
/// The popup's [anchorRect] is the triggering widget's rect in the parent
/// window's coordinate space, so only the anchor pair varies per edge.
(WindowPositionerAnchor, WindowPositionerAnchor) popupAnchorsForBar(
    String anchor) {
  switch (anchor) {
    case 'bottom':
      return (WindowPositionerAnchor.top, WindowPositionerAnchor.bottom);
    case 'left':
      return (WindowPositionerAnchor.right, WindowPositionerAnchor.left);
    case 'right':
      return (WindowPositionerAnchor.left, WindowPositionerAnchor.right);
    default: // 'top'
      return (WindowPositionerAnchor.bottom, WindowPositionerAnchor.top);
  }
}

/// Computes the parent-window-local anchor rect for the widget behind [context].
Rect popupAnchorRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Mixin for [State] classes that own a single popup window.
///
/// Encapsulates the controller/view lifecycle and WindowRegistry registration
/// so each module only needs to compute its anchor geometry and call [openPopup].
mixin PopupHost<T extends StatefulWidget> on State<T> {
  PopupWindowController? _popupController;
  WindowRegistry? _registry;
  WindowEntry? _entry;

  /// Whether a popup is currently open.
  bool get isPopupOpen => _popupController != null;

  /// Opens a popup positioned relative to the given anchor geometry.
  ///
  /// If a popup is already open this is a no-op — call [closePopup] first.
  /// Opens a popup anchored to the triggering widget, choosing the anchor pair
  /// from the panel's [BarScope] edge. This is the common case; use [openPopup]
  /// directly only when custom anchor geometry is needed.
  void openBarPopup(
    BuildContext context, {
    required Widget child,
    required BoxConstraints preferredConstraints,
  }) {
    final (parentAnchor, childAnchor) =
        popupAnchorsForBar(BarScope.of(context).anchor);
    openPopup(
      context,
      child: child,
      preferredConstraints: preferredConstraints,
      anchorRect: popupAnchorRect(context),
      parentAnchor: parentAnchor,
      childAnchor: childAnchor,
    );
  }

  void openPopup(
    BuildContext context, {
    required Widget child,
    required BoxConstraints preferredConstraints,
    required Rect anchorRect,
    required WindowPositionerAnchor parentAnchor,
    required WindowPositionerAnchor childAnchor,
  }) {
    if (isPopupOpen) return;
    final parentController = WindowScope.of(context);
    PopupWindowController? thisController;
    _popupController = thisController = PopupWindowController(
      parent: parentController,
      anchorRect: anchorRect,
      positioner: WindowPositioner(
        parentAnchor: parentAnchor,
        childAnchor: childAnchor,
      ),
      preferredConstraints: preferredConstraints,
      delegate: PopupDelegate(onDestroyed: () {
        if (_popupController == thisController) closePopup();
      }),
    );
    _registry = WindowRegistry.of(context);
    _entry = WindowEntry(controller: _popupController!, builder: (_) => child);
    _registry!.register(_entry!);
    setState(() {});
  }

  /// Closes and destroys the current popup, if any.
  void closePopup() {
    if (_entry != null) {
      _registry?.unregister(_entry!);
      _entry = null;
    }
    _registry = null;
    final ctrl = _popupController;
    _popupController = null;
    if (ctrl != null) {
      // Defer destroy to avoid tearing the window down mid-frame; destroy() is
      // idempotent so a second call (e.g. from onWindowDestroyed) is harmless.
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.destroy());
    }
    if (mounted) setState(() {});
  }
}

/// Wraps [child] with a scale + fade bounce-in animation.
///
/// Place this inside any popup content widget (inside Directionality /
/// DefaultTextStyle) so the content springs into view when the popup opens.
class PopupBounceIn extends StatefulWidget {
  const PopupBounceIn({super.key, required this.child});
  final Widget child;

  @override
  State<PopupBounceIn> createState() => _PopupBounceInState();
}

class _PopupBounceInState extends State<PopupBounceIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}
