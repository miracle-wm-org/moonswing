import 'package:flutter/foundation.dart';

import 'package:moonswing/docked_panel.dart';
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
/// The side the panel docks against when `[modules.notifications]` names none:
/// the right, where it has always been, and opposite the clipboard history's
/// default, so the two open side by side on separate edges.
const DockSide kDefaultNotificationPanelSide = DockSide.right;

/// Its width when none is named: room for a two-word summary on one line and
/// a row of action buttons.
const int kDefaultNotificationPanelWidth = 400;

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

  /// The connector name of the output the last [toggle] came from, or null
  /// when the caller did not know it — a shortcut, or a bar whose output is
  /// still being enumerated — and the compositor then picks the focused one.
  String? get output => _output;
  String? _output;

  /// The edge the panel docks against, `[modules.notifications] side`.
  DockSide get side => _side;
  DockSide _side = kDefaultNotificationPanelSide;

  /// How wide it is, `[modules.notifications] width` — and so how much of the
  /// windows beneath it it covers.
  int get width => _width;
  int _width = kDefaultNotificationPanelWidth;

  /// How it flies out and back, `[modules.notifications] animation*`.
  DockedPanelAnimation get animation => _animation;
  DockedPanelAnimation _animation = const DockedPanelAnimation();

  /// Pushed by the module's `fromMap`, which runs whether or not any bar
  /// carries the bell: the floating badge opens the same panel. Read by the
  /// root when it creates the window, so an edit moves the next panel, not
  /// the one already docked. Never signals — it is not a request.
  void configure({
    required DockSide side,
    required int width,
    DockedPanelAnimation animation = const DockedPanelAnimation(),
  }) {
    _side = side;
    _width = width;
    _animation = animation;
  }

  /// Asks the shell to open the panel on [output], or to close it if it is
  /// already up. The root decides which — the controller carries no window
  /// state beyond the flag it is *told*.
  void toggle({String? output}) {
    _output = output;
    signal();
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }
}
