import 'package:flutter/foundation.dart';

import 'package:moonswing/request_controller.dart';

/// The seam between anything that wants the notification panel open and
/// `_MoonswingRootState`, which owns every window.
///
/// Two things ask for it and neither can create the window: the bell module,
/// deep inside a panel's widget tree, and the floating badge, a root-owned
/// surface with no widget ancestry in common with the bell at all. The panel
/// used to be the bell's, which is exactly what a second trigger cannot reach.
///
/// Making the root the owner is also what makes there be *one* panel: two hosts
/// each opening their own copy would put two full-height surfaces on the same
/// output edge.
class NotificationPanelController extends SignalController {
  NotificationPanelController._();

  static final NotificationPanelController instance =
      NotificationPanelController._();

  @visibleForTesting
  factory NotificationPanelController.forTesting() =>
      NotificationPanelController._();

  final ValueNotifier<bool> _open = ValueNotifier(false);

  /// Whether the root currently has the panel up.
  ///
  /// A `ValueListenable` of its own rather than state on this notifier, and that
  /// separation is load-bearing: the root *listens* to this controller for the
  /// toggle, so publishing the open state through the same `notifyListeners`
  /// would have the root's own write come back in as a second toggle.
  ValueListenable<bool> get isOpen => _open;

  /// Root-only. Called when the panel's window is created and again once its
  /// exit animation has torn it down — never by a trigger, which asks with
  /// [toggle] and lets the root decide.
  void setOpen(bool value) => _open.value = value;

  /// Asks the shell to open the panel, or to close it if it is already up.
  /// The root decides which — the controller carries no window state beyond
  /// the flag it is *told*.
  void toggle() => signal();

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }
}
