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
import 'polkit_log.dart';
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

/// How a run that ended with neither `SUCCESS` nor `FAILURE` is worded.
///
/// Pure, so every shape it takes is a plain unit test. The helper's own
/// last stderr line leads where there is one — `pam_authenticate failed:
/// Authentication failure`, `wrong number of arguments`, `needs to be setuid
/// root` — because it names the actual fault and this file's guess cannot.
/// [prompted] is the difference between a conversation cut short and a stack
/// that never opened its mouth, which are two different things to go and look
/// at.
String helperDiedMessage({
  required int exitCode,
  required bool prompted,
  String? detail,
}) {
  final complaint = detail?.trim();
  final status = exitCode < 0
      ? 'It stopped without an exit status.'
      : 'It exited with status $exitCode.';
  final why = complaint == null || complaint.isEmpty ? status : complaint;
  return prompted
      ? 'The polkit helper stopped before the prompt could be answered. $why'
      : 'The polkit helper stopped before asking for anything, so nothing was '
          'checked. $why';
}

/// How a `FAILURE` for a run nobody typed into is worded.
///
/// Pure, so both shapes are a plain unit test.
String refusedWithoutAskingMessage({String? detail}) {
  final complaint = detail?.trim();
  final why = complaint == null || complaint.isEmpty
      ? 'Its polkit-1 PAM stack denied the request outright.'
      : complaint;
  return 'This machine refused before asking for anything, so no password '
      'was checked. $why';
}

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

  /// Whether the running helper has asked the user anything at all.
  bool _prompted = false;

  /// Whether the user has answered the running helper.
  ///
  /// This is what separates a *failed attempt* from a *non-starter*, and both
  /// terminal paths turn on it rather than on what the helper called the end
  /// ([_onResult] for a `FAILURE`, [_onDied] for no word at all): PAM only
  /// ever refuses something it was given, so a run nobody typed into tested
  /// no password and cost the user no try.
  bool _answered = false;

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

  /// How the session ended, or null while it is still going.
  ///
  /// Written once and never rewritten — [retry] clears it back to null rather
  /// than replacing one answer with another, which is what keeps "the outcome
  /// the agent reports is the outcome the user gave" true.
  PolkitAuthOutcome? get outcome => _outcome;

  bool get isFinished => _outcome != null;

  /// Whether the user can be asked at all. False means no helper or no
  /// identity — a state the dialog reports rather than one it prompts in.
  bool get canPrompt => request.identities.isNotEmpty;

  /// Whether the card may offer another go.
  ///
  /// Only over [PolkitAuthOutcome.unavailable], which is precisely the
  /// outcome that means *nothing was checked*. Every cause of it can be gone
  /// by the time the user has finished reading the card — a `pam_faillock`
  /// window expiring, polkit being installed, a stack being fixed in another
  /// terminal — and the shell can see none of them happen, so the retry is
  /// the user's to trigger. `NotificationStore.retryDaemon` is the same rule
  /// at the other end of the shell, for the same reason.
  ///
  /// Deliberately not offered over [PolkitAuthOutcome.failed]: that is PAM
  /// having weighed as many answers as the dialog allows and refused every
  /// one, and a button that sent it round again would leave a password oracle
  /// on the screen of a machine somebody has walked away from.
  bool get canRetry =>
      _outcome == PolkitAuthOutcome.unavailable && canPrompt;

  /// Starts the conversation over after an [PolkitAuthOutcome.unavailable].
  ///
  /// The one place [outcome] goes back to null, and it is safe because
  /// nothing has been told about it yet: the agent is awaiting
  /// [PolkitAuthController], which the root only answers once the *window*
  /// has come down. The attempt count resets with it — the user has not
  /// failed at anything, since nothing was ever checked.
  void retry() {
    if (!canRetry) return;
    _outcome = null;
    _error = null;
    _info = null;
    _attempt = 0;
    polkitLog('${request.actionId}: retrying at the user\'s request');
    _beginAttempt();
  }

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
    _answered = true;
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
    _prompted = false;
    _answered = false;
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
        _prompted = true;
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
      case PolkitHelperResult(:final authenticated, :final detail):
        _onResult(authenticated, detail);
      case PolkitHelperDied(:final exitCode, :final detail):
        _onDied(exitCode, detail);
    }
  }

  void _onResult(bool authenticated, [String? detail]) {
    unawaited(_endAttempt());
    if (authenticated) {
      // Nothing is sent to polkitd here, and nothing may be: the helper made
      // the privileged response call itself before printing SUCCESS.
      _finish(PolkitAuthOutcome.authenticated);
      return;
    }
    if (!_answered) {
      // **The bug this dialog used to have.** `FAILURE` is the helper's
      // answer to its own early refusals as well as to a password PAM
      // weighed and rejected: a `polkit-1` stack that denies before it
      // opens its mouth (`pam_faillock` on a locked-out account, a
      // `pam_deny`, a helper that cannot run where it is) prints exactly the
      // same word, with the reason on stderr. PAM cannot have refused an
      // answer it was never given, so this tested no password and cost the
      // user no try — and treating it as one is what made the prompt flash:
      // three refusals arrive inside a couple of milliseconds, the count runs
      // out, and the card reports "authentication failed" and takes itself
      // off the screen before anything could be read, let alone typed. Worse,
      // on a stack with `pam_faillock` in it those three are themselves what
      // locks the account, so the shell manufactured the state that makes the
      // next prompt fail the same way.
      //
      // [PolkitAuthOutcome.unavailable] instead: it lingers, it carries the
      // helper's own words, and it offers [retry] rather than taking two more
      // swings by itself.
      _finish(
        PolkitAuthOutcome.unavailable,
        // PAM's own line where one arrived, the helper's stderr otherwise.
        error: refusedWithoutAskingMessage(detail: _error ?? detail),
      );
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

  /// The helper's run ended without PAM ever saying what it thought.
  ///
  /// Whether that is an attempt turns on one question: **was anything typed
  /// into it?** If it was, PAM had something to weigh and the helper died
  /// before reporting the verdict — worth the attempt, and worth another go.
  /// If it was not, the run tested no password at all, and counting it as a
  /// wrong one is both a lie and a trap. A helper that refuses before it
  /// prompts refuses the same way every time, so the retry loop burns all
  /// three attempts in about as many milliseconds and closes the dialog on
  /// "Authentication failed" — which is the whole of what the user sees: a
  /// prompt that flashes and is gone before it can be read, let alone typed
  /// into. Worse, on a stack with `pam_faillock` in it those three refusals
  /// are themselves what locks the account out, so the shell would be
  /// manufacturing the very state that makes the next prompt fail the same
  /// way.
  ///
  /// So it is [PolkitAuthOutcome.unavailable] — the outcome that *lingers*,
  /// with the helper's own words on the card — and it retries nothing.
  void _onDied(int exitCode, String? detail) {
    if (_answered) {
      // Something was checked and the verdict never came back. That is an
      // attempt, and the count is what stops it repeating for ever — but not
      // a refusal, so it does not borrow the refusal's words.
      _error ??= 'The check did not finish. Try again.';
      _onResult(false);
      return;
    }
    unawaited(_endAttempt());
    _finish(
      PolkitAuthOutcome.unavailable,
      error: helperDiedMessage(
        exitCode: exitCode,
        prompted: _prompted,
        // PAM's own words where any reached us, the helper's stderr
        // otherwise: `PAM_ERROR_MSG Account locked due to 3 failed logins` is
        // what the user has to act on, and `pam_authenticate failed: …` is
        // only what the helper made of it.
        detail: _error ?? detail,
      ),
    );
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
    polkitLog('${request.actionId}: ${outcome.name} after $_attempt attempt(s)');
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
