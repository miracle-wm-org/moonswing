import 'package:flutter/foundation.dart';

import 'package:moonswing/request_controller.dart';

import 'consent_types.dart';

export 'consent_types.dart';

/// The seam between the InputCapture backend (blocked inside `CreateSession` or
/// `Start`, awaiting an answer) and `_MoonswingRootState`, which owns every
/// window.
///
/// [RequestController]'s rules, of which the first is the one that matters
/// here: with no root listening the answer is an immediate *no*, so nothing can
/// be granted the keyboard and mouse without a prompt the user saw.
class InputCaptureConsentController
    extends RequestController<InputCaptureConsentRequest, bool>
    implements InputCaptureConsent {
  InputCaptureConsentController._();

  static final InputCaptureConsentController instance =
      InputCaptureConsentController._();

  @visibleForTesting
  factory InputCaptureConsentController.forTesting() =>
      InputCaptureConsentController._();

  @override
  Future<bool> ask(InputCaptureConsentRequest request) async =>
      (await pick(request)) ?? false;

  /// A dismissal, or the portal's `Request.Close`: a refusal either way.
  @override
  void cancel() => complete(null);
}
