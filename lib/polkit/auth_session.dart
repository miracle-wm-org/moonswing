// One authentication dialog's worth of state: what polkit is asking, who may
// answer, what PAM wants typed, and how the attempt ended.
//
// The session is what the *dialog* drives and what the D-Bus agent awaits, so
// it is the only place that knows both halves — which is why the retry rule,
// the identity switch and the cancellation all live here rather than in a
// widget. A `ChangeNotifier` in the shape of the shell's stores, but one per
// request rather than a singleton: two authentications are two conversations
// with two cookies.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agent_helper.dart';
import 'polkit_types.dart';

/// What the dialog should be showing.
enum PolkitAuthStage {
  /// Waiting for the helper's first prompt. Brief — a `fork`/`exec` and a PAM
  /// stack initialising — but not instant, and a field that appeared already
  /// disabled would read as a broken dialog.
  starting,

  /// PAM has asked something and is blocked on the answer.
  prompting,

  /// The answer is with PAM. `pam_unix` deliberately delays a refusal by
  /// seconds, so this state is the one the user spends longest in on the
  /// attempt that fails.
  checking,

  /// Over — see [PolkitAuthSession.outcome].
  finished,
}

/// How many times PAM may refuse before the dialog gives up.
///
/// Three, which is what every polkit agent has settled on and what
/// `pam_unix`'s own retry count is: enough for a typo and a fumbled layout,
/// few enough that a dialog somebody walked away from is not an oracle left
/// sitting on the screen.
const int kPolkitMaxAttempts = 3;

/// The live state of one `BeginAuthentication` call.
class PolkitAuthSession extends ChangeNotifier {
  PolkitAuthSession({
    required this.request,
    required PolkitHelperRunner runner,
    int? currentUid,
    this.maxAttempts = kPolkitMaxAttempts,
  })  : _runner = runner,
        _selected = defaultIdentityIndex(
          request.identities,
          currentUid: currentUid,
        );

  final PolkitAuthRequest request;
  final PolkitHelperRunner _runner;
  final int maxAttempts;

  int _selected;
  int _attempt = 0;

  /// Which attempt a pending [_run] belongs to.
  ///
  /// A helper is started asynchronously, so an identity switched twice in
  /// quick succession has two starts in flight and only one of them is still
  /// wanted. Without this the loser would be adopted as `_live` and then
  /// forgotten — a setuid process left sitting on a PAM prompt for the life
  /// of the shell.
  int _generation = 0;

  PolkitHelperAttempt? _live;
  StreamSubscription<PolkitHelperMessage>? _sub;

  PolkitAuthStage _stage = PolkitAuthStage.starting;
  String _prompt = '';
  bool _echo = false;
  String? _error;
  String? _info;
  PolkitAuthOutcome? _outcome;

  /// Which of [PolkitAuthRequest.identities] the answer is for.
  int get selectedIndex => _selected;

  PolkitIdentity? get identity => request.identities.isEmpty
      ? null
      : request.identities[_selected.clamp(0, request.identities.length - 1)];

  PolkitAuthStage get stage => _stage;

  /// PAM's own words for what it wants, falling back to `Password` before the
  /// first prompt has arrived — the label is on screen from the first frame
  /// and an empty one would reflow the card the moment the helper answered.
  String get prompt {
    final trimmed = _prompt.trim();
    if (trimmed.isEmpty) return 'Password';
    // PAM prompts are written for a terminal: `Password: `, `PIN: `. The
    // colon belongs to the line it was going to be typed on, not to a label
    // above a field.
    return trimmed.endsWith(':')
        ? trimmed.substring(0, trimmed.length - 1).trim()
        : trimmed;
  }

  /// Whether what is typed should be visible — `PAM_PROMPT_ECHO_ON`.
  bool get echo => _echo;

  /// The last refusal, in PAM's words where it gave any. Cleared when the
  /// user starts a fresh attempt, because an error line left above a field
  /// somebody is retyping into reads as the *new* answer having failed.
  String? get error => _error;

  /// A `PAM_TEXT_INFO` line, e.g. an expiry warning.
  String? get info => _info;

  /// Which attempt is in flight, from 1. Shown once the first has failed, so
  /// the user knows the dialog is counting.
  int get attempt => _attempt;

  /// Set exactly once, when the session ends.
  PolkitAuthOutcome? get outcome => _outcome;

  bool get isFinished => _outcome != null;

  /// Whether the user can be asked at all. False means no helper or no
  /// identity — a state the dialog reports rather than one it prompts in.
  bool get canPrompt => request.identities.isNotEmpty;

  /// Begins the first attempt. Called from the dialog's `initState`, never
  /// from the agent: an authentication nobody is showing must never spawn a
  /// setuid helper, which is the [PolkitAuthController] decline-when-unheard
  /// rule reaching all the way down to the process table.
  void start() {
    // On [_attempt] rather than on [_live], which a start still in flight has
    // not set yet: two `start()`s in one frame would otherwise be two helpers.
    if (isFinished || _attempt > 0) return;
    if (!canPrompt) {
      _finish(
        PolkitAuthOutcome.unavailable,
        error: 'No account on this machine can approve this request.',
      );
      return;
    }
    _beginAttempt();
  }

  /// Answers the outstanding prompt.
  void submit(String response) {
    if (_stage != PolkitAuthStage.prompting) return;
    final live = _live;
    if (live == null) return;
    _error = null;
    _stage = PolkitAuthStage.checking;
    notifyListeners();
    live.respond(response);
  }

  /// Switches which account is being authenticated. The running attempt is
  /// abandoned — its helper is authenticating somebody else — and a fresh one
  /// starts, which is why the attempt counter resets: the user has not failed
  /// three times at *this* account.
  void selectIdentity(int index) {
    if (isFinished) return;
    if (index < 0 || index >= request.identities.length) return;
    if (index == _selected) return;
    _selected = index;
    _attempt = 0;
    _error = null;
    _info = null;
    unawaited(_endAttempt());
    _beginAttempt();
  }

  /// The user said no, or polkitd withdrew the request. Either way the answer
  /// is [PolkitAuthOutcome.cancelled], which is what stops the caller from
  /// asking again immediately.
  void cancel() {
    if (isFinished) return;
    unawaited(_endAttempt());
    _finish(PolkitAuthOutcome.cancelled);
  }

  void _beginAttempt() {
    final who = identity;
    if (who == null) return;
    _attempt++;
    _generation++;
    _stage = PolkitAuthStage.starting;
    _prompt = '';
    _echo = false;
    notifyListeners();
    unawaited(_run(who, _generation));
  }

  Future<void> _run(PolkitIdentity who, int generation) async {
    final PolkitHelperAttempt attempt;
    try {
      attempt = await _runner.start(
        username: who.username,
        cookie: request.cookie,
      );
    } on PolkitHelperUnavailable catch (e) {
      if (isFinished || generation != _generation) return;
      _finish(PolkitAuthOutcome.unavailable, error: e.message);
      return;
    } catch (e) {
      if (isFinished || generation != _generation) return;
      _finish(
        PolkitAuthOutcome.unavailable,
        error: 'The polkit helper could not be started: $e',
      );
      return;
    }
    if (isFinished || generation != _generation) {
      // Cancelled, or superseded by a newer attempt, while this helper was
      // starting. Nothing is going to read it, so it is killed rather than
      // adopted.
      unawaited(attempt.cancel());
      return;
    }
    _live = attempt;
    _sub = attempt.messages.listen(_onMessage);
  }

  void _onMessage(PolkitHelperMessage message) {
    if (isFinished) return;
    switch (message) {
      case PolkitHelperPrompt(:final text, :final echo):
        _prompt = text;
        _echo = echo;
        _stage = PolkitAuthStage.prompting;
        notifyListeners();
      case PolkitHelperInfo(:final text):
        _info = text;
        notifyListeners();
      case PolkitHelperError(:final text):
        // PAM's own words for the refusal, kept because they are worth more
        // than this file's guess — "Account locked" is actionable and "that
        // did not work" is not. It arrives *before* the FAILURE it explains,
        // so [_onResult] finds it already set and leaves it alone.
        _error = text;
        notifyListeners();
      case PolkitHelperResult(:final authenticated):
        _onResult(authenticated);
    }
  }

  void _onResult(bool authenticated) {
    unawaited(_endAttempt());
    if (authenticated) {
      // Nothing is sent to polkitd here, and nothing may be: the helper made
      // the privileged response call itself before printing SUCCESS.
      _finish(PolkitAuthOutcome.authenticated);
      return;
    }
    if (_attempt >= maxAttempts) {
      _finish(
        PolkitAuthOutcome.failed,
        error: _error ?? 'Authentication failed.',
      );
      return;
    }
    // PAM's own reason where it gave one — "Account locked" is worth more
    // than the agent's guess, and the count says the dialog is still asking.
    _error ??= 'Sorry, that did not work. Try again.';
    _beginAttempt();
  }

  Future<void> _endAttempt() async {
    final sub = _sub;
    final live = _live;
    _sub = null;
    _live = null;
    await sub?.cancel();
    await live?.cancel();
  }

  void _finish(PolkitAuthOutcome outcome, {String? error}) {
    if (_outcome != null) return;
    // Nothing in flight belongs to a finished session, and a generation
    // nothing matches is what makes a start still in flight kill its helper
    // rather than adopt it.
    _generation++;
    _outcome = outcome;
    if (error != null) _error = error;
    _stage = PolkitAuthStage.finished;
    notifyListeners();
  }

  /// Teardown. A session disposed before it ended records a cancellation —
  /// the dialog is gone, so nobody is going to answer the prompt, and the
  /// helper waiting on one has to be killed rather than left holding a PAM
  /// stack open. Recorded without notifying: a `ChangeNotifier` that told its
  /// listeners anything from `dispose` would be telling a dead widget.
  @override
  void dispose() {
    unawaited(_endAttempt());
    _outcome ??= PolkitAuthOutcome.cancelled;
    super.dispose();
  }
}
