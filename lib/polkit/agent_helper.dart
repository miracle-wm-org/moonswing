// `polkit-agent-helper-1`: the only way an unprivileged agent can prove an
// authentication to polkitd.
//
// The shell already talks to PAM directly for the lock screen
// (`lib/lock/pam_authenticator.dart`), and that is deliberately *not* what
// happens here. A polkit authentication is not "did this password check out"
// — it is "tell polkitd that the holder of this cookie authenticated", and
// only the setuid-root helper can say so: it runs the `polkit-1` PAM stack
// itself and then makes the privileged `AuthenticationAgentResponse2` call on
// the agent's behalf. An agent that ran PAM itself would have authenticated
// the user and still have nothing polkitd would accept.
//
// Flutter-free, so the line protocol below is a plain unit test.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'polkit_log.dart';

/// One line from the helper.
///
/// The helper's conversation function writes `"<PREFIX> <text>\n"` for each
/// PAM message and a bare `SUCCESS` or `FAILURE` when `pam_authenticate` and
/// `pam_acct_mgmt` are done. Verified against polkit 124's helper binary,
/// which contains exactly these five tokens.
sealed class PolkitHelperMessage {
  const PolkitHelperMessage();
}

/// PAM is asking something and the helper is blocked on stdin until it is
/// answered — so every prompt must be replied to, including the ones the
/// dialog would rather not show.
final class PolkitHelperPrompt extends PolkitHelperMessage {
  const PolkitHelperPrompt(this.text, {required this.echo});

  /// PAM's own prompt, e.g. `Password: `. Rendered as the field's label
  /// rather than assumed: a machine with a fingerprint or OTP module in its
  /// `polkit-1` stack asks for something that is not a password, and an agent
  /// that hard-coded the word would be lying about what it wanted.
  final String text;

  /// `PAM_PROMPT_ECHO_ON` — the answer is not a secret (a one-time code, a
  /// username), so the field must not obscure it.
  final bool echo;
}

/// `PAM_TEXT_INFO` — advisory, needs no answer.
final class PolkitHelperInfo extends PolkitHelperMessage {
  const PolkitHelperInfo(this.text);
  final String text;
}

/// `PAM_ERROR_MSG` — the module's own words for what went wrong (an expired
/// password, a locked account). Worth more than the agent's own guess, so the
/// dialog prefers it.
final class PolkitHelperError extends PolkitHelperMessage {
  const PolkitHelperError(this.text);
  final String text;
}

/// `SUCCESS` / `FAILURE` — the end of this attempt. On success polkitd has
/// *already* been told by the helper; there is nothing left for the agent to
/// send.
final class PolkitHelperResult extends PolkitHelperMessage {
  const PolkitHelperResult({required this.authenticated, this.detail});

  final bool authenticated;

  /// The helper's last stderr line, attached to a **refusal** only.
  ///
  /// The helper answers `FAILURE` to every one of its own early refusals as
  /// well as to a password PAM weighed and rejected — `wrong number of
  /// arguments`, `needs to be setuid root`, `pam_authenticate failed: …` are
  /// all `FAILURE` on stdout with the actual reason on stderr, and dropping
  /// it leaves the agent unable to tell a broken machine from a typo. Null on
  /// a success, which needs no diagnosis, and null where the helper went
  /// quietly.
  final String? detail;
}

/// The run ended with neither `SUCCESS` nor `FAILURE`: the helper exited, or
/// its stdout closed, before it said what PAM made of anything.
///
/// Deliberately **not** a synthesised `FAILURE`, which is what this used to
/// be. The two are indistinguishable at the wire and could not be more
/// different to the user: a `FAILURE` is PAM having weighed an answer and
/// refused it, and this is the helper never getting that far — the `polkit-1`
/// stack denying before it opens its mouth (`pam_faillock` on a locked-out
/// account is the common one), a binary that cannot run where it is, a PAM
/// module that aborted. Reported as its own message so
/// [PolkitAuthSession] can tell an attempt from a non-starter; see the rule
/// there, and note that three non-starters take a couple of milliseconds
/// end to end, which is the whole of what the user sees.
final class PolkitHelperDied extends PolkitHelperMessage {
  const PolkitHelperDied({required this.exitCode, this.detail});

  /// The helper's exit status, or -1 where the run ended without one.
  final int exitCode;

  /// Its last stderr line, if it complained — `pam_authenticate failed: …`
  /// and friends. Null when it went quietly.
  final String? detail;
}

/// Parses one line of the helper's stdout, or null for anything else.
///
/// Unknown lines are dropped rather than thrown for: the helper is a program
/// on the host, not something this repo ships, and a version that grows a
/// sixth token must cost that line and never the prompt.
PolkitHelperMessage? parseHelperLine(String line) {
  final trimmed = line.trimRight();
  if (trimmed.isEmpty) return null;
  const promptOff = 'PAM_PROMPT_ECHO_OFF';
  const promptOn = 'PAM_PROMPT_ECHO_ON';
  const errorMsg = 'PAM_ERROR_MSG';
  const textInfo = 'PAM_TEXT_INFO';
  if (trimmed == 'SUCCESS') {
    return const PolkitHelperResult(authenticated: true);
  }
  if (trimmed == 'FAILURE') {
    return const PolkitHelperResult(authenticated: false);
  }
  // The prefix and its payload are separated by one space, and the payload may
  // be empty — `PAM_PROMPT_ECHO_OFF` with no message is a prompt with no
  // words, not an unknown line, because the helper prints the prefix and its
  // trailing space before it has looked at `msg`.
  String? payloadOf(String prefix) {
    if (trimmed == prefix) return '';
    if (trimmed.startsWith('$prefix ')) {
      return trimmed.substring(prefix.length + 1);
    }
    return null;
  }

  if (payloadOf(promptOff) case final text?) {
    return PolkitHelperPrompt(text, echo: false);
  }
  if (payloadOf(promptOn) case final text?) {
    return PolkitHelperPrompt(text, echo: true);
  }
  if (payloadOf(errorMsg) case final text?) return PolkitHelperError(text);
  if (payloadOf(textInfo) case final text?) return PolkitHelperInfo(text);
  return null;
}

/// There is no helper on this machine, or it could not be started. No
/// password the user types would change that, which is why it is its own
/// state rather than a failed attempt.
class PolkitHelperUnavailable implements Exception {
  const PolkitHelperUnavailable(this.message);

  /// A sentence for the dialog, not a stack trace.
  final String message;

  @override
  String toString() => 'PolkitHelperUnavailable: $message';
}

/// One run of the helper: one PAM conversation, ending in exactly one
/// [PolkitHelperResult] — or, where the helper never got that far, one
/// [PolkitHelperDied].
///
/// A run is single-shot by construction — the helper calls `pam_authenticate`
/// once and exits — so a retry is a *new* attempt, not a second password down
/// the same pipe.
abstract class PolkitHelperAttempt {
  /// Closes after the result, or after the helper died without sending one.
  Stream<PolkitHelperMessage> get messages;

  /// Answers the outstanding prompt. Writing when nothing is being asked is a
  /// no-op rather than an error: a dialog whose submit raced the helper's
  /// exit must not throw out of a button callback.
  void respond(String response);

  /// Ends the run early — the user cancelled, or polkitd withdrew the
  /// request. Idempotent.
  Future<void> cancel();
}

/// Starts helper runs. Injected into [PolkitAuthSession] so the whole session
/// — prompts, retries, cancellation — is a unit test that spawns nothing.
abstract class PolkitHelperRunner {
  Future<PolkitHelperAttempt> start({
    required String username,
    required String cookie,
  });
}

/// The real thing: `polkit-agent-helper-1` as a child process.
class ProcessPolkitHelperRunner implements PolkitHelperRunner {
  const ProcessPolkitHelperRunner({this.path});

  /// The binary to run, or null to take the first of [helperCandidates] that
  /// exists.
  ///
  /// A seam for tests, and the only one this class has: every other layer of
  /// the feature is exercised through [PolkitHelperRunner], which forks
  /// nothing — so the pipe handling below, which is where the ordering
  /// hazards live, is the one part with no coverage at all unless a test can
  /// point it at a program of its own.
  final String? path;

  /// Where the helper lives, most likely first.
  ///
  /// It is not on `PATH` anywhere — it is a setuid-root helper in a libexec
  /// directory, and which one depends on the distribution's layout rather
  /// than on its polkit version. `lib/fortune/fortune_reader.dart` states the
  /// same rule about `/usr/games`: a program that is present but unreachable
  /// must not be reported as missing.
  static const List<String> helperCandidates = <String>[
    // Fedora, Arch, openSUSE, Debian/Ubuntu with polkitd >= 121.
    '/usr/lib/polkit-1/polkit-agent-helper-1',
    // Debian/Ubuntu multiarch and lib64 layouts.
    '/usr/lib/x86_64-linux-gnu/polkit-1/polkit-agent-helper-1',
    '/usr/lib64/polkit-1/polkit-agent-helper-1',
    // Debian/Ubuntu before the policykit-1 → polkitd rename.
    '/usr/lib/policykit-1/polkit-agent-helper-1',
    // Where a from-source build with the default prefix lands it.
    '/usr/libexec/polkit-agent-helper-1',
    '/usr/local/lib/polkit-1/polkit-agent-helper-1',
  ];

  /// The first candidate that exists, or null.
  static String? resolveHelperPath() {
    for (final candidate in helperCandidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  @override
  Future<PolkitHelperAttempt> start({
    required String username,
    required String cookie,
  }) async {
    final path = this.path ?? resolveHelperPath();
    if (path == null) {
      throw const PolkitHelperUnavailable(
        'polkit-agent-helper-1 is not installed, so the shell cannot ask for '
        'administrator rights. Install polkit and restart the shell.',
      );
    }
    final Process process;
    try {
      // Exactly one argument, which is what every helper since the CVE-2015-3255
      // fix accepts: `argc != 2` is refused outright, with the cookie read from
      // stdin instead.
      process = await Process.start(path, <String>[username]);
    } catch (error) {
      throw PolkitHelperUnavailable('could not start $path: $error');
    }
    // The username, never the cookie: one is a passwd name and the other is
    // the authentication itself.
    polkitLog('started $path for $username (pid ${process.pid})');
    return _ProcessAttempt(process, path, cookie);
  }
}

/// How long a run whose stdout has closed waits for the exit status, and how
/// long one whose *process* has gone waits for the last of its stdout.
///
/// Both are the same imperceptible beat and both exist for the same reason:
/// the exit and the end of stdout are two separate events on two separate
/// descriptors, and nothing orders them.
const Duration _kExitGrace = Duration(milliseconds: 250);

class _ProcessAttempt implements PolkitHelperAttempt {
  _ProcessAttempt(this._process, this._path, String cookie) {
    // The cookie goes on **stdin**, never in `argv`: CVE-2015-3255 is exactly
    // that — a cookie on a command line is world-readable through `/proc`, so
    // any process on the machine could have claimed somebody else's pending
    // authentication. The helper has read it from stdin ever since, and the
    // argv form is not offered as a fallback here: a helper old enough to
    // need it is one with the vulnerability.
    _write(cookie);
    _stdout = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: (Object _) {}, onDone: _onStdoutClosed);
    // The helper logs its refusals (`stdin is a tty`, `wrong number of
    // arguments`, `pam_authenticate failed: …`) to stderr and syslog. Drained
    // rather than ignored: an unread pipe fills, and a helper blocked writing
    // to it would never answer — and its last line is the only account of a
    // run that ended without saying anything.
    _stderr = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStderr, onError: (Object _) {}, onDone: _onStderrClosed);
    unawaited(_process.exitCode.then(_onExit));
  }

  final Process _process;
  final String _path;
  final StreamController<PolkitHelperMessage> _messages =
      StreamController<PolkitHelperMessage>();
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;

  /// The last thing the helper complained about, if anything. Only ever used
  /// to explain a refusal or a run that ended with no result at all.
  String? _stderrTail;

  int? _exitCode;
  Timer? _exitGrace;
  bool _stdoutClosed = false;
  bool _dying = false;
  bool _closed = false;

  /// Completes when stderr reaches EOF, which is when [_stderrTail] can be
  /// trusted to be the helper's *last* word rather than whichever line the
  /// event loop happened to have delivered.
  final Completer<void> _stderrDone = Completer<void>();

  @override
  Stream<PolkitHelperMessage> get messages => _messages.stream;

  void _onLine(String line) {
    final message = parseHelperLine(line);
    if (message == null || _closed) return;
    if (message is PolkitHelperResult) {
      // A success needs no diagnosis and must not wait for one: polkitd has
      // already been told, and the only thing left is to let the dialog go.
      if (message.authenticated) {
        _messages.add(message);
        _finish();
        return;
      }
      unawaited(_refused());
      return;
    }
    _messages.add(message);
  }

  /// `FAILURE`, held back just long enough to say why.
  ///
  /// The helper prints it to stdout and its reason to stderr, and those are
  /// two descriptors with no ordering between them — so forwarding the
  /// refusal the instant its line arrives throws the reason away most of the
  /// time. The wait is bounded for [_settleDiagnostics]'s reason.
  Future<void> _refused() async {
    if (_closed || _dying) return;
    _dying = true;
    await _settleDiagnostics();
    if (_closed) return;
    _messages.add(
      PolkitHelperResult(authenticated: false, detail: _stderrTail),
    );
    _finish();
  }

  /// Waits, briefly, for the two descriptors that carry a run's diagnosis.
  ///
  /// The exit status and the last stderr line are delivered independently of
  /// stdout and of each other, and between them they are the whole account of
  /// a run that went wrong. Both waits are bounded, because a pipe that never
  /// closes has to cost the wording and never the run.
  Future<void> _settleDiagnostics() async {
    _exitCode ??=
        await _process.exitCode.timeout(_kExitGrace, onTimeout: () => -1);
    if (!_stderrDone.isCompleted) {
      await _stderrDone.future.timeout(_kExitGrace, onTimeout: () {});
    }
  }

  void _onStderr(String line) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) _stderrTail = trimmed;
  }

  void _onStderrClosed() {
    if (!_stderrDone.isCompleted) _stderrDone.complete();
  }

  /// The helper's stdout reached EOF — which is the *only* event that means
  /// everything it wrote has been delivered.
  void _onStdoutClosed() {
    _stdoutClosed = true;
    _exitGrace?.cancel();
    _exitGrace = null;
    unawaited(_die());
  }

  /// The process is gone. **Not** the end of the run on its own.
  ///
  /// The exit pipe and stdout are two descriptors and the event loop is free
  /// to deliver either first, so finishing here would throw away a `SUCCESS`
  /// still sitting in the stdout buffer — an authenticated user reported as a
  /// wrong password, on a race that only ever shows up on somebody else's
  /// machine. Stdout's own EOF ([_onStdoutClosed]) is what ends a run; this is
  /// the status for the message, plus a safety net for a run whose stdout
  /// never closes at all.
  void _onExit(int code) {
    _exitCode = code;
    if (_closed || _stdoutClosed) return;
    _exitGrace = Timer(_kExitGrace, () {
      if (!_stdoutClosed) unawaited(_die());
    });
  }

  /// Reports a run that ended with neither `SUCCESS` nor `FAILURE`.
  Future<void> _die() async {
    if (_closed || _dying) return;
    _dying = true;
    await _settleDiagnostics();
    if (_closed) return;
    final code = _exitCode ?? -1;
    final complaint = _stderrTail;
    polkitLog(
      '$_path ended without a result (status $code)'
      '${complaint == null ? '' : ': $complaint'}',
    );
    _messages.add(PolkitHelperDied(exitCode: code, detail: complaint));
    _finish();
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    _exitGrace?.cancel();
    _exitGrace = null;
    unawaited(_stdout.cancel());
    unawaited(_stderr.cancel());
    unawaited(_messages.close());
  }

  @override
  void respond(String response) => _write(response);

  void _write(String line) {
    if (_closed) return;
    try {
      _process.stdin.write('$line\n');
      // Unawaited on purpose: the flush completes when the helper reads, and
      // the helper is blocked on exactly that read. Awaiting it here would
      // block the caller — a button callback — on a child process.
      unawaited(_process.stdin.flush().catchError((Object _) {}));
    } catch (_) {
      // A closed pipe means the helper is already gone; the stdout EOF that
      // follows reports it.
    }
  }

  @override
  Future<void> cancel() async {
    if (_closed) {
      // Still kill it: a run whose result arrived is over, but one closed by
      // a superseding request may have a helper sitting on a prompt.
      _process.kill(ProcessSignal.sigterm);
      return;
    }
    _finish();
    _process.kill(ProcessSignal.sigterm);
    try {
      await _process.stdin.close();
    } catch (_) {}
  }
}
