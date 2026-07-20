import 'package:flutter/foundation.dart';

/// Signals raised by the compositor's global input triggers (registered through
/// the ext-input-trigger protocols) that the widget tree acts on.
///
/// Same shape as [OsdStore] and [TrayStore]: a singleton [ChangeNotifier] that a
/// start-up service pokes and a window watches. The store carries no policy — it
/// only reports that the "open settings" shortcut fired; the root decides
/// whether that opens or closes the overlay, which keeps the Wayland layer and
/// the widget layer decoupled and independently testable.
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
