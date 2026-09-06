import 'package:flutter/foundation.dart';

import 'package:graceful_shell/request_controller.dart';

import 'auth_session.dart';
import 'polkit_types.dart';

/// The seam between the polkit agent (a D-Bus object with no widget tree under
/// it, blocked inside `BeginAuthentication`) and `_GracefulShellRootState`.
///
/// [RequestController]'s three rules are all load-bearing here, and the first is
/// a security posture rather than a convenience:
///
/// * **No listener means an immediate decline.** A shell with no root state
///   listening answers polkit `Cancelled` rather than awaiting a dialog that will
///   not appear — and since [PolkitAuthSession.start] is called by the *dialog*,
///   a request nobody is showing never spawns a setuid helper at all.
/// * **A second request supersedes the first**, which resolves as cancelled. Two
///   prompts at once is not a state a modal surface can render, and the
///   superseded caller gets an answer it can retry rather than a hang.
/// * **Teardown answers the pending request.** An unanswered
///   `BeginAuthentication` blocks the application that asked for privileges for
///   as long as its own timeout allows.
class PolkitAuthController
    extends RequestController<PolkitAuthSession, PolkitAuthOutcome> {
  PolkitAuthController._();

  static final PolkitAuthController instance = PolkitAuthController._();

  @visibleForTesting
  factory PolkitAuthController.forTesting() => PolkitAuthController._();

  /// Raises the dialog for [session] and resolves with what the user did.
  /// Null is a decline — nothing was listening, or a later request displaced
  /// this one — and the agent answers polkit `Cancelled` either way.
  Future<PolkitAuthOutcome?> present(PolkitAuthSession session) =>
      pick(session);

  /// Answers [session], and only [session].
  ///
  /// The root calls this once the dialog has finished animating out, by which time
  /// a *superseding* request may already be pending — and answering that one with
  /// the outcome of the dialog the user was looking at would resolve a prompt
  /// nobody has seen. Guarding on identity is what keeps supersession safe.
  void finish(PolkitAuthSession session, PolkitAuthOutcome outcome) {
    if (!identical(pending, session)) return;
    complete(outcome);
  }
}
