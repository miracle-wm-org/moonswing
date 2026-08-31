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
  const PolkitHelperResult({required this.authenticated});
  final bool authenticated;
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
/// [PolkitHelperResult].
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
  const ProcessPolkitHelperRunner();

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
    final path = resolveHelperPath();
    if (path == null) {
      throw const PolkitHelperUnavailable(
        'polkit-agent-helper-1 is not installed, so the shell cannot ask for '
        'administrator rights. Install polkit and restart the shell.',
      );
    }
    final Process process;
    try {
      process = await Process.start(path, <String>[username]);
    } catch (error) {
      throw PolkitHelperUnavailable('could not start $path: $error');
    }
    return _ProcessAttempt(process, cookie);
  }
}

class _ProcessAttempt implements PolkitHelperAttempt {
  _ProcessAttempt(this._process, String cookie) {
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
        .listen(_onLine, onError: (Object _) {}, onDone: _onDone);
    // The helper logs its refusals (`stdin is a tty`, `wrong number of
    // arguments`) to stderr and syslog. Drained rather than ignored: an
    // unread pipe fills, and a helper blocked writing to it would never
    // answer.
    _stderr = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStderr, onError: (Object _) {});
    unawaited(_process.exitCode.then((_) => _onDone()));
  }

  final Process _process;
  final StreamController<PolkitHelperMessage> _messages =
      StreamController<PolkitHelperMessage>();
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;

  /// The last thing the helper complained about, if anything. Only ever used
  /// to explain a run that ended with no result.
  String? _stderrTail;

  bool _closed = false;

  @override
  Stream<PolkitHelperMessage> get messages => _messages.stream;

  void _onLine(String line) {
    final message = parseHelperLine(line);
    if (message == null || _closed) return;
    _messages.add(message);
    if (message is PolkitHelperResult) _finish();
  }

  void _onStderr(String line) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) _stderrTail = trimmed;
  }

  /// The helper exited (or its stdout closed) without a `SUCCESS`/`FAILURE`.
  ///
  /// That is a failed attempt, not a crash of ours: the run is reported as
  /// unauthenticated so the session can retry or give up, and the helper's own
  /// last words become the message the dialog shows.
  void _onDone() {
    if (_closed) return;
    final complaint = _stderrTail;
    if (complaint != null) _messages.add(PolkitHelperError(complaint));
    _messages.add(const PolkitHelperResult(authenticated: false));
    _finish();
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
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
      // A closed pipe means the helper is already gone; `_onDone` reports it.
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
    _closed = true;
    unawaited(_stdout.cancel());
    unawaited(_stderr.cancel());
    unawaited(_messages.close());
    _process.kill(ProcessSignal.sigterm);
    try {
      await _process.stdin.close();
    } catch (_) {}
  }
}
