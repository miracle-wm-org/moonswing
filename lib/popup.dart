// Windowing infrastructure built on Flutter's regular (experimental) windowing
// API. Two things live here:
//   * [PopupHost] — compositor-positioned popups (xdg_popup) created by the
//     default WindowingOwnerLinux that layer_shell's initLayerShell() installs;
//     the compositor places the popup from the parent-local [anchorRect] and
//     [WindowPositioner].
//   * [LayerShellHost] — full layer-shell windows (panels/overlays/dialogs)
//     whose [LayershellWindowController] the module creates itself.
// Both register a [WindowEntry] into the panel's [WindowRegistry] (supplied by
// the per-panel [PanelWindowManager]), so they share one windowing mechanism.

// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
// Only _window_linux.dart is imported directly: layer_shell re-exports the
// windowing and positioner pieces this file needs, but not the Linux-specific
// BaseWindowControllerLinux.
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/window_manager.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:layer_shell/src/gtk.dart';

/// Minimum size floor applied to every popup/tooltip so a sized-to-content
/// window never collapses to a degenerate size.
const BoxConstraints kMinPopupConstraints =
    BoxConstraints(minWidth: 48, minHeight: 24);

/// Every popup and tooltip is anchored to a widget in a bar that may sit near a
/// screen edge, so let the compositor translate the window along both axes to
/// keep it on-screen. Slide (rather than flip) preserves the popup's side of the
/// bar, which is what the anchor pair from [popupAnchorsForBar] encodes.
const WindowPositionerConstraintAdjustment kPopupSlide =
    WindowPositionerConstraintAdjustment(slideX: true, slideY: true);

/// Adjustment for a flyout submenu anchored to the side of its parent: flip to
/// the opposite side when the preferred side would run off-screen, and slide
/// vertically to stay on-screen. Used for the app-directory category submenus.
const WindowPositionerConstraintAdjustment kPopupFlipX =
    WindowPositionerConstraintAdjustment(flipX: true, slideY: true);

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

/// Tells the compositor not to shrink [controller]'s surface to make room for
/// other layer-shell surfaces' exclusive zones.
///
/// gtk-layer-shell defaults the exclusive zone to 0, and per wlr-layer-shell a
/// zone of 0 means "move me so I don't occlude surfaces that reserved space" —
/// so a full-screen surface is shrunk to the gap *between* the panels. -1 means
/// "leave me alone and extend me to the edges I'm anchored to".
///
/// This is what makes a translucent panel show the wallpaper: without it there
/// is no wallpaper behind a bar at all, only the compositor's empty background,
/// and a see-through bar reveals a flat black strip. It went unnoticed while
/// every panel was opaque.
void spanFullOutput(LayershellWindowController controller) {
  controller.setExclusiveZone(-1);
}

/// Floats a panel [margin] px off each screen edge it is anchored to.
///
/// This is a native layer-shell margin rather than a Flutter inset because the
/// shell has no input-region support: padding inside a full-size surface would
/// leave the surface swallowing every click in the gap, whereas a real margin
/// shrinks it and lets those clicks reach the desktop.
///
/// The exclusive zone is deliberately untouched. Per wlr-layer-shell's
/// `set_margin`, "the exclusive zone includes the margin" — the compositor adds
/// the anchored edge's margin to the zone the surface already asked for, so
/// windows stop below a floating bar without us sending anything. Reserving
/// `height + margin` here as well would reserve it twice and leave a dead strip
/// the size of the gap that no window would occupy.
void setPanelMargin(
  LayershellWindowController controller, {
  required String anchor,
  required int margin,
}) {
  for (final edge in anchorEdgesForPosition(anchor)) {
    controller.setMargin(edge, margin);
  }
  // Once the surface is mapped a margin change only queues a resize, so a live
  // theme edit would otherwise sit unsent until something else forced a frame.
  controller.tryForceCommit();
}

/// Carries the [TransientHandle] of the popup a subtree is rendered inside.
///
/// This is what makes nesting work without a single call site passing a parent.
/// [PopupHost.openPopup] wraps every popup's content in one, so a module that
/// opens a popup from *inside* another popup's content — the app-directory
/// category flyout, and the pin-to-dock menu inside that — resolves its parent
/// from `context`, the same walk that already finds [WindowScope] and the
/// panel's [WindowRegistry] from three levels deep.
class TransientScope extends InheritedWidget {
  const TransientScope({
    super.key,
    required this.handle,
    required super.child,
  });

  final TransientHandle handle;

  /// The enclosing popup's handle, or null in a panel or the desktop surface.
  ///
  /// Deliberately not a `dependOnInheritedWidgetOfExactType`: this is read from
  /// tap handlers, not from `build`, so there is nothing to rebuild.
  static TransientHandle? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<TransientScope>()
      ?.handle;

  @override
  bool updateShouldNotify(TransientScope oldWidget) => false;
}

/// Dismisses every open transient surface when a pointer goes down on [child].
///
/// Wrapped around the two surfaces that cover real screen area and are not
/// themselves transient — a panel and the desktop/background surface — because
/// nothing else can tell us the user clicked elsewhere: the Linux popup
/// controller takes no `gdk_seat_grab`, so the compositor never sends
/// `popup_done`, and no layer-shell surface reports focus loss.
///
/// Translucent, so a click on a panel's empty space dismisses too. It cannot
/// catch a click on an ordinary application window; nothing available to the
/// shell can.
class PopupDismissArea extends StatelessWidget {
  const PopupDismissArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) =>
          PopupCoordinator.instance.dismissFromPointerDown(event),
      child: child,
    );
  }
}

/// Mixin for [State] classes that own a single popup window.
///
/// Encapsulates the controller/view lifecycle and WindowRegistry registration
/// so each module only needs to compute its anchor geometry and call [openPopup].
mixin PopupHost<T extends StatefulWidget> on State<T> {
  PopupWindowController? _popupController;
  WindowRegistry? _registry;
  WindowEntry? _entry;
  VoidCallback? _onClosed;
  TransientHandle? _handle;

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
    TransientPolicy policy = TransientPolicy.menu,
    Object? ownerKey,
  }) {
    final (parentAnchor, childAnchor) =
        popupAnchorsForBar(BarScope.of(context));
    openPopup(
      context,
      child: child,
      preferredConstraints: preferredConstraints,
      anchorRect: popupAnchorRect(context),
      parentAnchor: parentAnchor,
      childAnchor: childAnchor,
      policy: policy,
      ownerKey: ownerKey,
    );
  }

  void openPopup(
    BuildContext context, {
    required Widget child,
    required BoxConstraints preferredConstraints,
    required Rect anchorRect,
    required WindowPositionerAnchor parentAnchor,
    required WindowPositionerAnchor childAnchor,
    WindowPositionerConstraintAdjustment constraintAdjustment = kPopupSlide,
    VoidCallback? onClosed,
    TransientPolicy policy = TransientPolicy.menu,
    Object? ownerKey,
  }) {
    if (isPopupOpen) return;
    // Identity for the reopen guard, defaulting to the host State because one
    // State owns one popup. A host that opens a *different* popup per trigger —
    // the tray, whose one State serves every icon — passes something finer, or
    // clicking the second icon would be mistaken for re-clicking the first.
    final owner = ownerKey ?? this;
    // The click that opened this is the same one that just dismissed our own
    // popup from [PopupDismissArea], which runs first: a [Listener] sits above
    // every recognizer on the hit-test path. Without this the toggle would
    // close and immediately reopen, and no bar popup could ever be dismissed
    // by clicking its own icon.
    if (PopupCoordinator.instance.consumeReopenGuard(owner)) return;
    _onClosed = onClosed;
    final parentController = WindowScope.of(context);
    final constraints = preferredConstraints.enforce(kMinPopupConstraints);
    PopupWindowController? thisController;
    _popupController = thisController = PopupWindowController(
      parent: parentController,
      anchorRect: anchorRect,
      positioner: WindowPositioner(
        parentAnchor: parentAnchor,
        childAnchor: childAnchor,
        constraintAdjustment: constraintAdjustment,
      ),
      constraints: constraints,
      delegate: PopupDelegate(onDestroyed: () {
        if (_popupController == thisController) closePopup();
      }),
    );
    // The popup surface defaults to opaque black (fl_view_renderer paints the
    // view background unless it is exactly #00000000), so make it transparent
    // the same way LayershellWindowController does for panels.
    // BaseWindowControllerLinux, not WindowControllerLinux: the latter is the
    // *regular*-window controller, and a popup's controller only implements the
    // base interface. Casting to the wrong one compiles and then throws on the
    // first popup opened.
    final native = thisController as BaseWindowControllerLinux;
    final gtkWindow = GtkWindow.fromHandle(native.windowHandle);
    gtkWindow.setAppPaintable(true);
    FlView.fromHandle(native.flutterViewHandle).setBackgroundColor('#00000000');
    // A sized-to-content popup has to be told its size before it maps, or it is
    // positioned as though it were some other size.
    //
    // PopupWindowControllerLinux resolves the placement exactly once, from its
    // own constructor, and GTK3 does not set the positioner's reactive flag —
    // so `gdk_window_move_to_rect` is evaluated against whatever size the GTK
    // window has at map time and is never revisited. The window is mapped from
    // the engine's first-frame callback, but fl_view_renderer only applies the
    // content size when it *presents* a frame, which is after that. So the
    // popup maps at GTK's default 200x200 and shrinks to its content
    // afterwards, having already been placed as a 200x200 window.
    //
    // That matters because [popupAnchorsForBar] returns edge-*centred* anchors:
    // on a top or bottom bar the popup is centred horizontally on its trigger,
    // so its x is `anchorCentre - width / 2` and a wrong width offsets it by
    // half the error. A 128-wide system menu placed as though it were 200 wide
    // lands 36px to the side of its button, which is far enough that the
    // constraint adjustment then slides it somewhere else entirely.
    //
    // This was invisible for as long as every call site passed
    // `BoxConstraints.tightFor(...)`: those windows really were the size GTK
    // had mapped them at, and the ones that were near 200x200 were simply
    // lucky. A post-frame callback runs after the frame that laid the content
    // out but before that frame is presented — the last moment at which the
    // size can still reach GTK ahead of the map.
    final contentKey = GlobalKey();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (thisController!.isDestroyed) return;
      final size = contentKey.currentContext?.size;
      if (size == null) return;
      gtkWindow.resize(size.width.ceil(), size.height.ceil());
    });
    _registry = PanelWindowManager.registryOf(context);
    // Registered before the surface maps, so whatever this displaces is already
    // on its way out. The parent comes from the context: null in a panel, and
    // the enclosing popup's handle when a popup opens from inside another's
    // content.
    final handle = _handle = PopupCoordinator.instance.open(
      owner: owner,
      parent: TransientScope.maybeOf(context),
      policy: policy,
      onDismiss: closePopup,
    );
    // The content is laid out directly under the popup's View, so this box is
    // what actually gives a sized-to-content window its size: tight
    // constraints make the content fill the popup exactly, loose ones are
    // floored at [kMinPopupConstraints].
    //
    // The popup renders into its own FlutterView, so the panel's
    // [PopupDismissArea] never sees a click that lands in here — hence its own
    // Listener, which spares this popup's chain and dismisses everything else.
    _entry = WindowEntry(
      controller: _popupController!,
      builder: (_) => TransientScope(
        handle: handle,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) => PopupCoordinator.instance
              .dismissFromPointerDown(event, within: handle),
          // Keyed so the post-frame callback above can measure what the
          // content actually laid out to and hand that size to GTK.
          child: ConstrainedBox(
              key: contentKey, constraints: constraints, child: child),
        ),
      ),
    );
    _registry!.register(_entry!);
    setState(() {});
  }

  /// Closes and destroys the current popup, if any.
  void closePopup() {
    PopupCoordinator.instance.close(_handle);
    _handle = null;
    if (_entry != null) {
      _registry?.unregister(_entry!);
      _entry = null;
    }
    _registry = null;
    final ctrl = _popupController;
    _popupController = null;
    final onClosed = _onClosed;
    _onClosed = null;
    if (ctrl != null) {
      // Defer destroy to avoid tearing the window down mid-frame; destroy() is
      // idempotent so a second call (e.g. from onWindowDestroyed) is harmless.
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.destroy());
    }
    if (mounted) setState(() {});
    // Fires once per open, whether closed explicitly or dismissed by the
    // compositor (whose destroy routes through the delegate to closePopup).
    onClosed?.call();
  }
}

/// Mixin for [State] classes that own a single full layer-shell window
/// (a panel, overlay, or dialog) whose surface they configure themselves.
///
/// The module creates the [LayershellWindowController] with its own
/// layer/anchor parameters and hands it to [openLayerWindow]; this mixin owns
/// the [WindowRegistry] registration + teardown so each module only decides
/// when to open and what content to show.
mixin LayerShellHost<T extends StatefulWidget> on State<T> {
  LayershellWindowController? _lsController;
  WindowRegistry? _lsRegistry;
  WindowEntry? _lsEntry;
  TransientHandle? _lsHandle;

  /// Whether a layer-shell window is currently open.
  bool get isLayerWindowOpen => _lsController != null;

  /// Registers [controller] (already created by the caller with its
  /// layer/anchor params) into the panel's [WindowRegistry], rendering [child].
  ///
  /// If a window is already open this is a no-op — call [closeLayerWindow]
  /// first.
  /// [onDismissRequested] is what the [PopupCoordinator] calls when something
  /// else needs this window gone. Windows with an exit animation pass the
  /// callback that *starts* it — the coordinator must never call
  /// [closeLayerWindow] itself, or a panel that should slide out would vanish.
  void openLayerWindow(
    BuildContext context, {
    required LayershellWindowController controller,
    required Widget child,
    TransientPolicy policy = TransientPolicy.menu,
    VoidCallback? onDismissRequested,
  }) {
    if (isLayerWindowOpen) return;
    _lsController = controller;
    _lsRegistry = PanelWindowManager.registryOf(context);
    _lsHandle = PopupCoordinator.instance.open(
      owner: this,
      parent: TransientScope.maybeOf(context),
      policy: policy,
      onDismiss: onDismissRequested ?? closeLayerWindow,
    );
    _lsEntry = WindowEntry(controller: controller, builder: (_) => child);
    _lsRegistry!.register(_lsEntry!);
    setState(() {});
  }

  /// Unregisters and destroys the current layer-shell window, if any.
  void closeLayerWindow() {
    PopupCoordinator.instance.close(_lsHandle);
    _lsHandle = null;
    if (_lsEntry != null) {
      _lsRegistry?.unregister(_lsEntry!);
      _lsEntry = null;
    }
    _lsRegistry = null;
    final ctrl = _lsController;
    _lsController = null;
    ctrl?.destroy();
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

/// Text label rendered inside a hover tooltip popup.
///
/// Popup content is built in its own window, outside the panel's [ThemeScope],
/// so callers must wrap this in a `ThemeProvider` — which is also what keeps a
/// tooltip that is still on screen in step with a theme change.
class TooltipLabel extends StatelessWidget {
  const TooltipLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      // The background is the theme's, at the alpha the theme chose. This used
      // to force .withAlpha(100) on top of it, which under a translucent theme
      // compounded into the least legible surface in the shell.
      child: PopupCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Center(
          child: Text(
            text,
            style: TextStyle(color: theme.popupForeground, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
