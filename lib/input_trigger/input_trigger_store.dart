import 'package:flutter/foundation.dart';

/// Signals raised by the compositor's global input triggers that the widget tree
/// acts on.
///
/// [OsdStore]'s shape: a singleton [ChangeNotifier] that a start-up service pokes
/// and a window watches. The store carries no policy — it only reports that the
/// "open settings" shortcut fired; the root decides whether that opens or closes
/// the overlay, which keeps the two layers independently testable.
class InputTriggerStore extends ChangeNotifier {
  InputTriggerStore._();

  static final InputTriggerStore instance = InputTriggerStore._();

  @visibleForTesting
  factory InputTriggerStore.forTesting() => InputTriggerStore._();

  int _settingsShortcutCount = 0;

  /// Monotonic count of times the "open settings" shortcut has fired. Exposed
  /// for tests; the root reacts to [notifyListeners], not to this value.
  int get settingsShortcutCount => _settingsShortcutCount;

  /// Called when the settings shortcut (Ctrl+Shift+S by default) fires. Each
  /// call is one toggle from the root's point of view.
  void triggerSettings() {
    _settingsShortcutCount++;
    notifyListeners();
  }
}
