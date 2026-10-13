// The consent request/answer types, shared by the portal backend (which asks)
// and the consent dialog (which answers). Flutter-free and in their own file
// for `pick_types.dart`'s reason: everything below the UI imports these.

import 'eis_server.dart';

/// What an application asked to capture.
class InputCaptureConsentRequest {
  const InputCaptureConsentRequest({
    required this.appId,
    required this.capabilities,
  });

  /// The requesting application id (empty for unsandboxed callers).
  final String appId;

  /// Portal capability bits: [captureCapKeyboard], [captureCapPointer].
  final int capabilities;

  bool get keyboard => capabilities & captureCapKeyboard != 0;
  bool get pointer => capabilities & captureCapPointer != 0;
}

/// How the backend asks the user. The shell answers with the consent dialog;
/// tests and the spike tool answer directly. There is deliberately no default:
/// a backend that could start capturing without asking would be a keylogger.
abstract class InputCaptureConsent {
  /// Resolves false when the user (or the portal) declines.
  Future<bool> ask(InputCaptureConsentRequest request);

  /// Cancels an in-flight [ask] — the frontend closed the Request.
  void cancel();
}
