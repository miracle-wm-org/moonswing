import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// What a transient surface does to the others, and what they may do to it.
///
/// Two independent booleans rather than an enum, because the screen-share consent
/// prompt needs one of each: it must displace whatever is on screen and never be
/// displaced — dismissing it is a *denial*, so nothing may resolve it on the
/// user's behalf.
class TransientPolicy {
  const TransientPolicy({this.dismissesOthers = true, this.dismissable = true});

  /// Whether opening this surface dismisses the ones outside its chain.
  final bool dismissesOthers;

  /// Whether this surface may be dismissed by another opening, or by a click.
  final bool dismissable;

  /// Popups, context menus and module overlays: displace, and be displaced.
  static const TransientPolicy menu = TransientPolicy();

  /// Hover tooltips. Dismissed by anything, but opening one dismisses nothing:
  /// crossing the dock on the way to a menu must not tear that menu down.
  static const TransientPolicy tooltip =
      TransientPolicy(dismissesOthers: false);

  /// Consent prompts and pickers something is awaiting: they displace, and
  /// nothing displaces them.
  static const TransientPolicy modal = TransientPolicy(dismissable: false);
}

/// A registration in the [PopupCoordinator]: one open transient surface.
///
/// [parent] is what makes nesting work. A handle's *chain* is itself plus its
/// transitive parents, and nothing in a chain ever dismisses anything else in it
/// — so the app-directory popup survives its category flyout, and both survive
/// the pin-to-dock menu inside the flyout.
class TransientHandle {
  TransientHandle({
    required this.owner,
    required this.parent,
    required this.policy,
    required this.onDismiss,
  });

  /// The `State` (or root sentinel) that opened the surface. Identity only —
  /// the coordinator never calls into it except through [onDismiss].
  final Object owner;

  /// The handle this one is nested inside, or null for a top-level surface.
  final TransientHandle? parent;

  final TransientPolicy policy;

  /// The owner's *graceful* closer. For a window with an exit animation this
  /// is the callback that starts the animation, never the teardown — which is
  /// why the coordinator itself never destroys a window.
  final VoidCallback onDismiss;

  /// Set once [onDismiss] has been called, so a second dismissal arriving
  /// during a 300 ms fade-out does not restart it.
  bool closing = false;
}

/// Process-wide registry of open transient surfaces, and the one thing that
/// closes them.
///
/// The shell renders into many independent FlutterViews and no widget tree can
/// see another's popups: they share the root's [WindowRegistry], but a popup is a
/// sibling view of the panel that opened it. Nothing else dismisses them either —
/// the Linux popup controller takes no `gdk_seat_grab`, so the compositor never
/// sends `popup_done`, and there is no focus-lost callback anywhere in the stack.
class PopupCoordinator extends ChangeNotifier {
  PopupCoordinator._();

  static final PopupCoordinator instance = PopupCoordinator._();

  @visibleForTesting
  factory PopupCoordinator.forTesting() => PopupCoordinator._();

  final List<TransientHandle> _open = <TransientHandle>[];
  final Set<Object> _reopenGuard = <Object>{};

  /// The open handles, in open order. Exposed for tests.
  @visibleForTesting
  List<TransientHandle> get openHandles => List.unmodifiable(_open);

  /// Registers a newly opened surface, dismissing everything outside the chain
  /// it belongs to.
  ///
  /// Call this *before* the new surface is mapped, so the ones it displaces are
  /// already on their way out.
  TransientHandle open({
    required Object owner,
    TransientHandle? parent,
    TransientPolicy policy = TransientPolicy.menu,
    required VoidCallback onDismiss,
  }) {
    if (policy.dismissesOthers) dismissOutside(parent);
    final handle = TransientHandle(
      owner: owner,
      parent: parent,
      policy: policy,
      onDismiss: onDismiss,
    );
    _open.add(handle);
    notifyListeners();
    return handle;
  }

  /// Asks [handle] and everything nested inside it to close, children first.
  ///
  /// Children first because a parent's teardown destroys the window its child
  /// popup is parented to. The handles stay registered until their owners call
  /// [close] — an exit animation is still playing.
  void dismiss(TransientHandle? handle) {
    if (handle == null || handle.closing || !isDismissable(handle)) return;
    for (final child in _childrenOf(handle)) {
      dismiss(child);
    }
    handle.closing = true;
    handle.onDismiss();
    notifyListeners();
  }

  /// Whether [handle] may be dismissed by another surface opening or by a
  /// click. A surface nested inside a modal is part of the modal's group and
  /// inherits its refusal, so the whole chain has to consent.
  bool isDismissable(TransientHandle handle) {
    for (TransientHandle? h = handle; h != null; h = h.parent) {
      if (!h.policy.dismissable) return false;
    }
    return true;
  }

  /// Unregisters [handle]; its window is actually gone. Idempotent, and
  /// null-tolerant so a `closePopup` can call it unconditionally.
  void close(TransientHandle? handle) {
    if (handle == null) return;
    if (_open.remove(handle)) notifyListeners();
  }

  /// Dismisses every open surface that is not in [chainTip]'s chain.
  ///
  /// A null [chainTip] means the event came from a plain shell surface — a
  /// panel or the desktop — so everything goes.
  void dismissOutside(TransientHandle? chainTip) {
    final keep = _chainOf(chainTip);
    for (final handle in List<TransientHandle>.from(_open)) {
      if (keep.contains(handle)) continue;
      dismiss(handle);
    }
  }

  /// Dismisses everything, ignoring [TransientPolicy.dismissable].
  ///
  /// For session lock, which hides every other surface anyway: a popup left
  /// registered would be one the compositor has already taken off screen.
  void dismissAll() {
    // Reversed, so nested surfaces go before the windows they are parented to.
    // Registration order is open order, so a child is always after its parent.
    for (final handle in _open.reversed.toList()) {
      if (handle.closing) continue;
      handle.closing = true;
      handle.onDismiss();
    }
    notifyListeners();
  }

  /// Dismisses everything outside [within] in response to a raw pointer-down,
  /// arming the reopen guard for whatever a primary click just closed.
  ///
  /// [Listener] sits above every [GestureRecognizer] on the hit-test path, so this
  /// runs *before* the bar button under the pointer sees `onTapDown`. Without the
  /// guard, clicking the icon whose popup is open would close it here and
  /// immediately reopen it there.
  ///
  /// Only a primary click arms the guard: every popup toggle in the shell is a
  /// primary tap and every context menu is a secondary one, and a right-click that
  /// dismisses a popup must still be free to open its menu.
  void dismissFromPointerDown(
    PointerDownEvent event, {
    TransientHandle? within,
  }) {
    _reopenGuard.clear();
    final primary = event.buttons & kPrimaryButton != 0;
    final keep = _chainOf(within);
    for (final handle in List<TransientHandle>.from(_open)) {
      if (keep.contains(handle)) continue;
      final guardable = !handle.closing &&
          isDismissable(handle) &&
          handle.policy.dismissesOthers;
      dismiss(handle);
      if (primary && guardable) _reopenGuard.add(handle.owner);
    }
  }

  /// Whether [owner]'s surface was closed by the click currently being
  /// dispatched, in which case the open it is about to attempt is a re-open and
  /// must be swallowed. True at most once per click.
  bool consumeReopenGuard(Object owner) => _reopenGuard.remove(owner);

  Set<TransientHandle> _chainOf(TransientHandle? tip) {
    final chain = <TransientHandle>{};
    for (var h = tip; h != null; h = h.parent) {
      chain.add(h);
    }
    return chain;
  }

  List<TransientHandle> _childrenOf(TransientHandle handle) =>
      _open.where((h) => h.parent == handle).toList();
}
