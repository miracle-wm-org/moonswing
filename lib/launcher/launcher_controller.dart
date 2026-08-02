import 'package:flutter/foundation.dart';

/// The seam between anything that wants the launcher open and the shell root.
///
/// Two things ask for it: the global shortcut (via the ext-input-trigger
/// service) and the magnifier bar module, which lives deep inside a panel's
/// widget tree. Neither can create a window — `_GracefulShellRootState` owns
/// them all — so both poke this singleton and the root reacts. Same shape as
/// [LockController], for the same reason.
///
/// Deliberately not `InputTriggerStore`: that store reports *compositor*
/// triggers, and its listener toggles on any notification, so a second signal
/// there would open the settings overlay instead. The bar button is also not a
/// compositor event, and should not have to pretend to be one.
class LauncherController extends ChangeNotifier {
  LauncherController._();

  static final LauncherController instance = LauncherController._();

  @visibleForTesting
  factory LauncherController.forTesting() => LauncherController._();

  int _toggleCount = 0;

  /// Monotonic count of toggle requests. Exposed for tests; the root reacts to
  /// [notifyListeners], not to this value.
  int get toggleCount => _toggleCount;

  /// Asks the shell to open the launcher, or to close it if it is already up.
  /// The root decides which — the controller carries no window state.
  void toggle() {
    _toggleCount++;
    notifyListeners();
  }
}
