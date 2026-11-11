#ifndef MOONSWING_PAM_HELPER_H_
#define MOONSWING_PAM_HELPER_H_

// The first argument that turns the shell binary into the lock screen's PAM
// helper. Spelled out in lib/lock/pam_authenticator.dart as well.
constexpr char kPamHelperFlag[] = "--moonswing-pam-authenticate";

// Exit codes, read back by lib/lock/pam_authenticator.dart.
constexpr int kPamHelperAccepted = 0;
constexpr int kPamHelperRejected = 1;
constexpr int kPamHelperUnavailable = 2;

// Runs one pam_authenticate() exchange and returns the exit code to leave with.
//
// argv is `<binary> --moonswing-pam-authenticate <service> <username>`; the
// password is read from stdin, never argv, where any user could read it in
// /proc.
//
// Why this is a process of its own rather than FFI in the shell: pam_unix
// verifies a password by forking the setuid unix_chkpwd and waitpid()ing it.
// Inside the shell, dart:io's exit-code thread sits in a bare wait() for as
// long as any Process it started is running, which the clipboard watcher is all
// session, so it could reap unix_chkpwd first. pam_unix then sees ECHILD and
// answers PAM_AUTH_ERR, and a correct password reads as a wrong one. Here
// nothing else waits on this process's children.
int run_pam_helper(int argc, char** argv);

#endif  // MOONSWING_PAM_HELPER_H_
