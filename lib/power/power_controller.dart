import 'package:flutter/foundation.dart';

import 'package:moonswing/request_controller.dart';

/// The seam between "the physical power button was pressed" and
/// `_MoonswingRootState`, which owns every window.
///
/// The compositor delivers the press to the input-trigger service, a
/// Wayland-layer object with no widget tree under it; what the press *means* is
/// `[power] key_action`, which is live config the root already holds. So the
/// service reports the press and nothing else, and the root resolves the action —
/// which is what makes changing it in Settings take effect without a restart even
/// though the key *binding* latched at start-up.
///
/// A [SignalController] rather than a second signal on [InputTriggerStore], for
/// the reason the base class gives: that store's listener toggles the settings
/// overlay on any notification.
class PowerController extends SignalController {
  PowerController._();

  static final PowerController instance = PowerController._();

  @visibleForTesting
  factory PowerController.forTesting() => PowerController._();

  /// The compositor reported the power key. The root decides what that means.
  void pressPowerKey() => signal();
}
