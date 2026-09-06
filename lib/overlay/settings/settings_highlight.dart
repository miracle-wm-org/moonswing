// "Take me to that field", from the settings search bar to the row itself.
//
// The settings body is an `IndexedStack` whose tab and sidebar category are
// private state, and the Shell pane owns a nested `Navigator`. So a result cannot
// simply be *rendered*: picking one has to move three separate pieces of state
// and then reach a row several scroll views down, which is what this controller
// is the seam for — `request_controller.dart`'s shape, scoped to one open
// settings overlay rather than to the process.

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:graceful_shell/overlay/settings/settings_search.dart';

/// How long a target waits to be claimed before it is dropped.
///
/// Nothing guarantees a claimant: a page-level result highlights no row at all,
/// and a field whose row is behind a `ConfigValue` that is not rendering has none
/// to claim it. The category view holds its whole page mounted while a target for
/// it is pending, so an unclaimed one has to expire rather than sit there.
const Duration kSettingsHighlightTimeout = Duration(seconds: 2);

/// How long a claimed row pulses once it has been scrolled to.
const Duration kSettingsHighlightFlash = Duration(milliseconds: 1400);

/// One "jump here" request.
@immutable
class SettingsHighlightTarget {
  const SettingsHighlightTarget({required this.field, required this.serial});

  final SettingsField field;

  /// Monotonic, so picking the same result twice is two jumps. A row records
  /// the serial it acted on, which is what stops a still-mounted row from
  /// re-flashing on every unrelated notify.
  final int serial;
}

/// Holds the pending jump, and hands it to exactly one row.
class SettingsHighlightController extends ChangeNotifier {
  SettingsHighlightTarget? _target;
  int _serial = 0;
  bool _claimed = false;
  Timer? _expiry;

  SettingsHighlightTarget? get target => _target;

  /// Whether a row has taken [target] already.
  ///
  /// Several rows can legitimately carry one id — every panel in Panels & Layout
  /// renders a "Height" — so the *first* to mount wins the scroll and the flash.
  /// Without this the last one to build would decide where the pane scrolled to,
  /// which is the bottom of the page rather than the top.
  bool get claimed => _claimed;

  /// Asks for [field]'s row to be scrolled to and flashed.
  void jumpTo(SettingsField field) {
    _expiry?.cancel();
    _serial++;
    _claimed = false;
    _target = SettingsHighlightTarget(field: field, serial: _serial);
    _expiry = Timer(kSettingsHighlightTimeout, clear);
    notifyListeners();
  }

  /// Taken by the first row whose id matches, once per [jumpTo].
  ///
  /// Returns false for every later caller, so the rest of the matching rows
  /// render exactly as they always did.
  bool claim(String id) {
    final target = _target;
    if (target == null || _claimed || target.field.id != id) return false;
    _claimed = true;
    // Deliberately no notify: the claimant is mid-build when it calls this,
    // and what changed is bookkeeping no widget renders. [clear] is what tells
    // the pane the jump is over.
    return true;
  }

  /// Drops the pending target — called by the claimant once it has scrolled,
  /// and by [kSettingsHighlightTimeout] when nothing claimed it.
  void clear() {
    _expiry?.cancel();
    _expiry = null;
    if (_target == null) return;
    _target = null;
    _claimed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }
}

/// Hands the open overlay's [SettingsHighlightController] to the pane below it.
///
/// An `InheritedNotifier` rather than a plain `InheritedWidget`, so a page that
/// has to *react* to a jump simply depends on it. A row does not: it subscribes
/// to the controller directly and rebuilds itself alone, because a jump must not
/// re-lay every row on the page it is jumping into.
class SettingsHighlightScope
    extends InheritedNotifier<SettingsHighlightController> {
  const SettingsHighlightScope({
    super.key,
    required SettingsHighlightController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, or null outside a settings overlay — which is what a page
  /// pumped alone in a widget test is, and why every read of this is
  /// null-tolerant.
  static SettingsHighlightController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SettingsHighlightScope>()
      ?.notifier;

  /// The controller without subscribing to it — for a row, which watches the
  /// controller itself and must not rebuild with the pane.
  static SettingsHighlightController? readOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsHighlightScope>()?.notifier;
}
