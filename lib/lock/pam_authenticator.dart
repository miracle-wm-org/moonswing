import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'user_identity.dart';

/// Outcome of an unlock attempt.
enum PamResult {
  /// The password was accepted.
  success,

  /// The password was rejected.
  incorrect,

  /// PAM itself is unusable (no `libpam`, `pam_start` failed). The user cannot
  /// fix this by typing a different password, so the UI says so plainly.
  unavailable,
}

/// Starts the PAM helper. [Process.start]'s shape, and replaceable by tests.
typedef PamHelperStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// The first argument that turns the shell binary into its own PAM helper.
/// Matches `kPamHelperFlag` in `linux/runner/pam_helper.h`.
const String kPamHelperFlag = '--moonswing-pam-authenticate';

/// Verifies the user's login password with PAM.
///
/// **The exchange runs in a child process, never in the shell.** `pam_unix`
/// checks a password by forking the setuid `unix_chkpwd` and `waitpid`ing it.
/// While any `dart:io` [Process] is running, and the clipboard history's
/// `wl-paste --watch` runs all session, the VM's exit-code thread sits in a bare
/// `wait()` and reaps *every* child of the process. When it gets to
/// `unix_chkpwd` first, `pam_unix` gets `ECHILD` and answers `PAM_AUTH_ERR`, so
/// a correct password reads as "Incorrect password", sometimes and then often,
/// and the session cannot be unlocked. So the shell starts *itself* with
/// [kPamHelperFlag] (`linux/runner/pam_helper.cc`), a single-threaded process
/// whose children nothing else waits on. Being a `dart:io` child, its own exit
/// code comes back through the same exit-code thread.
///
/// The password goes to the helper on **stdin, never argv**, where any process
/// on the machine could read it from `/proc`. The verdict is the exit code.
///
/// This works without the shell being root because `pam_unix` shells out to the
/// setuid-root `unix_chkpwd` helper to read the shadow database.
class PamAuthenticator {
  const PamAuthenticator._();

  /// PAM service names to try, most preferred first.
  ///
  /// We ship `/etc/pam.d/moonswing`; `login` is the universally present
  /// fallback for installs that could not write to `/etc` (its `auth` stack
  /// includes `common-auth`, which is all we exercise — we never open a session).
  static const List<String> _serviceCandidates = <String>[
    'moonswing',
    'login',
  ];

  /// The PAM service this machine will actually use.
  static String resolveService() {
    for (final candidate in _serviceCandidates) {
      if (File('/etc/pam.d/$candidate').existsSync()) return candidate;
    }
    return _serviceCandidates.first;
  }

  /// Checks [password] against the current user's login credentials.
  static Future<PamResult> authenticate(String password) async {
    // Never hand an empty secret to PAM: an account configured with `nullok`
    // would otherwise unlock on a bare Enter press.
    if (password.isEmpty) return PamResult.incorrect;

    final identity = UserIdentity.current();
    if (identity.username.isEmpty) return PamResult.unavailable;

    return runPamHelper(
      service: resolveService(),
      username: identity.username,
      password: password,
    );
  }
}

/// Runs one exchange through the PAM helper and reads its verdict.
///
/// [executable] is the shell's own binary; the helper is started with the
/// shell's environment unchanged, so it resolves `libpam` and the PAM modules
/// exactly as the shell would — under the snap, the bundle's libraries are
/// what lets it start at all.
Future<PamResult> runPamHelper({
  required String service,
  required String username,
  required String password,
  String? executable,
  PamHelperStarter start = Process.start,
}) async {
  if (password.isEmpty) return PamResult.incorrect;
  final Process process;
  try {
    process = await start(executable ?? Platform.resolvedExecutable, [
      kPamHelperFlag,
      service,
      username,
    ]);
  } on Object {
    return PamResult.unavailable;
  }

  // Nothing is expected on either, but an undrained pipe that fills blocks the
  // writer, and a PAM module is free to print.
  unawaited(process.stdout.drain<void>().catchError((Object _) {}));
  unawaited(process.stderr.drain<void>().catchError((Object _) {}));

  // A helper that exited before reading has broken the pipe, which surfaces
  // here rather than as an uncaught error; its exit code still says why.
  unawaited(process.stdin.done.catchError((Object _) {}));
  try {
    process.stdin.add(utf8.encode(password));
    await process.stdin.close();
  } on Object {
    // As above.
  }

  final int code;
  try {
    code = await process.exitCode;
  } on Object {
    return PamResult.unavailable;
  }
  return pamResultForExitCode(code);
}

/// The helper's exit code as a [PamResult]: `kPamHelperAccepted`,
/// `kPamHelperRejected` and `kPamHelperUnavailable` in `pam_helper.h`, and
/// anything else (a crash, a signal) as unavailable.
PamResult pamResultForExitCode(int code) => switch (code) {
  0 => PamResult.success,
  1 => PamResult.incorrect,
  _ => PamResult.unavailable,
};
