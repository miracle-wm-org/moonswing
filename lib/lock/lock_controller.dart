import 'package:flutter/foundation.dart';

/// The seam between the Lock button and the shell root.
///
/// The button lives inside a panel module while the lock windows have to be
/// created by `_MoonswingRootState`, which owns every other window. Rather
/// than thread a callback down, the module pokes this singleton and the root
/// reacts — the singleton-`ChangeNotifier` shape.
class LockController extends ChangeNotifier {
  LockController._();

  static final LockController instance = LockController._();

  bool _requested = false;
  bool _active = false;
  String? _lastError;

  /// True once [lock] has been called and until the lock is torn down.
  bool get isRequested => _requested;

  /// True while the lock windows exist.
  @visibleForTesting
  bool get isActive => _active;

  /// Why the last lock attempt failed, if it did.
  @visibleForTesting
  String? get lastError => _lastError;

  /// Asks the shell to lock the session. Ignored when already locking.
  void lock() {
    if (_requested) return;
    _requested = true;
    _lastError = null;
    notifyListeners();
  }

  /// Marks the lock as up. Called by the root once the windows exist.
  void markActive() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  /// Records a failed lock attempt and clears the request.
  void markFailed(String message) {
    _requested = false;
    _active = false;
    _lastError = message;
    notifyListeners();
  }

  /// Clears the lock state after the windows have been torn down.
  void clear() {
    if (!_requested && !_active) return;
    _requested = false;
    _active = false;
    notifyListeners();
  }
}
