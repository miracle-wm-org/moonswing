import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/lock/pam_authenticator.dart';

/// A stand-in for the shell binary in helper mode: checks it was started the
/// way `linux/runner/main.cc` expects, then accepts `hunter2` for `alice`.
///
/// It waits on a child of its own first, as `pam_unix` waits on `unix_chkpwd`.
Future<Process> _fakeHelper(String executable, List<String> arguments) =>
    Process.start('sh', [
      '-c',
      r'''
[ "$1" = --moonswing-pam-authenticate ] && [ "$2" = moonswing ] || exit 2
true & wait $! || exit 2
[ "$(cat)" = hunter2 ] && [ "$3" = alice ] && exit 0
exit 1
''',
      'sh',
      ...arguments,
    ]);

Future<PamResult> _check(
  String password, {
  PamHelperStarter start = _fakeHelper,
}) => runPamHelper(
  service: 'moonswing',
  username: 'alice',
  password: password,
  executable: '/unused',
  start: start,
);

void main() {
  test('the helper is started in helper mode with the password on stdin', () async {
    final seen = <List<String>>[];
    final result = await _check(
      'hunter2',
      start: (executable, arguments) {
        seen.add([executable, ...arguments]);
        return _fakeHelper(executable, arguments);
      },
    );
    expect(result, PamResult.success);
    expect(seen, [
      ['/unused', kPamHelperFlag, 'moonswing', 'alice'],
    ]);
    // Never on the command line, where /proc shows it to everybody.
    expect(seen.single, isNot(contains('hunter2')));
  });

  test('a wrong password is incorrect', () async {
    expect(await _check('hunter3'), PamResult.incorrect);
  });

  test('an empty password never reaches PAM', () async {
    var started = false;
    final result = await _check(
      '',
      start: (executable, arguments) {
        started = true;
        return _fakeHelper(executable, arguments);
      },
    );
    expect(result, PamResult.incorrect);
    expect(started, isFalse);
  });

  test('a helper that cannot start is unavailable, not a wrong password', () async {
    final result = await _check(
      'hunter2',
      start: (_, _) => throw const ProcessException('moonswing', []),
    );
    expect(result, PamResult.unavailable);
  });

  test('the exit codes map as pam_helper.h defines them', () {
    expect(pamResultForExitCode(0), PamResult.success);
    expect(pamResultForExitCode(1), PamResult.incorrect);
    expect(pamResultForExitCode(2), PamResult.unavailable);
    // A crash: dart:io reports a signal as its negated number.
    expect(pamResultForExitCode(-11), PamResult.unavailable);
  });

  test('a helper that dies before reading the password is unavailable', () async {
    final result = await _check(
      'hunter2',
      start: (_, _) => Process.start('sh', ['-c', 'exec 0<&-; kill -9 \$\$']),
    );
    expect(result, PamResult.unavailable);
  });

  // The bug: in-process, `pam_unix`'s `waitpid` on `unix_chkpwd` raced
  // dart:io's exit-code thread, which reaps every child while any Process is
  // running. With the helper a process of its own, its child is its own.
  test('a correct password holds while another Process is running', () async {
    final sleeper = await Process.start('sleep', ['60']);
    addTearDown(sleeper.kill);
    for (var i = 0; i < 20; i++) {
      expect(await _check('hunter2'), PamResult.success, reason: 'attempt $i');
    }
  });
}
