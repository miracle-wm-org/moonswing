// The one layer of the polkit feature that forks something.
//
// Everything above this is driven through [PolkitHelperRunner], which spawns
// nothing — which is why the pipe handling here is worth its own tests: the
// hazards are all about the *order* two descriptors and a process exit are
// delivered in, and no fake can reproduce that. The helper is stood in for by a
// shell script speaking the same line protocol, so these run on a machine with
// no polkit installed.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/polkit/agent_helper.dart';
import 'package:moonswing/polkit/auth_session.dart';
import 'package:moonswing/polkit/polkit_types.dart';

late Directory _dir;

/// Writes an executable stand-in for `polkit-agent-helper-1`.
String _helper(String name, String body) {
  final file = File('${_dir.path}/$name');
  file.writeAsStringSync('#!/bin/sh\n$body\n');
  Process.runSync('chmod', ['+x', file.path]);
  return file.path;
}

Future<List<PolkitHelperMessage>> _run(String path) async {
  final attempt = await ProcessPolkitHelperRunner(path: path)
      .start(username: 'ada', cookie: 'cookie-1');
  return attempt.messages.toList();
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('polkit-helper'));
  tearDown(() => _dir.deleteSync(recursive: true));

  test('reads the cookie from stdin and never from argv', () async {
    // The CVE-2015-3255 rule, from the child's side: a cookie on the command
    // line is world-readable through `/proc`.
    final path = _helper('argv', r'''
      echo "PAM_TEXT_INFO argv=$*"
      read -r line
      echo "PAM_TEXT_INFO stdin=$line"
      echo FAILURE
    ''');
    final messages = await _run(path);
    final info = messages.whereType<PolkitHelperInfo>().map((m) => m.text);
    expect(info, ['argv=ada', 'stdin=cookie-1']);
  });

  // The regression this file was written for. The exit pipe and stdout are two
  // descriptors and nothing orders them, so completing the run on the exit would
  // throw away a `SUCCESS` still sitting in the stdout buffer — an authenticated
  // user reported as a wrong password, on a race that only loses on somebody
  // else's machine. Repeated, because winning it once proves nothing.
  test('a SUCCESS written just before exit is never lost', () async {
    final path = _helper('quick', 'read -r c\necho SUCCESS');
    for (var i = 0; i < 25; i++) {
      final messages = await _run(path);
      expect(
        messages.whereType<PolkitHelperResult>().map((m) => m.authenticated),
        [true],
        reason: 'run $i',
      );
      expect(messages.whereType<PolkitHelperDied>(), isEmpty, reason: 'run $i');
    }
  });

  test('a prompt is answered down the same pipe', () async {
    final path = _helper('prompt', r'''
      read -r c
      printf 'PAM_PROMPT_ECHO_OFF Password: \n'
      read -r answer
      if [ "$answer" = "hunter2" ]; then echo SUCCESS; else echo FAILURE; fi
    ''');
    final attempt = await ProcessPolkitHelperRunner(path: path)
        .start(username: 'ada', cookie: 'cookie-1');
    final seen = <PolkitHelperMessage>[];
    final done = Completer<void>();
    attempt.messages.listen((message) {
      seen.add(message);
      if (message is PolkitHelperPrompt) attempt.respond('hunter2');
    }, onDone: done.complete);
    await done.future;

    expect(seen.first, isA<PolkitHelperPrompt>());
    // Right-trimmed by [parseHelperLine]: PAM's prompts are written for a
    // terminal line, and the trailing space belongs to the line rather than
    // to the label the dialog sets above its field.
    expect((seen.first as PolkitHelperPrompt).text, 'Password:');
    expect(seen.last, isA<PolkitHelperResult>());
    expect((seen.last as PolkitHelperResult).authenticated, isTrue);
  });

  // A stack that refuses before the conversation starts — `pam_faillock` on a
  // locked-out account is the everyday one. Reported as a death rather than
  // as a `FAILURE`, because nothing was checked: see [PolkitHelperDied].
  test('a helper that refuses without prompting reports its death', () async {
    final path = _helper('refuse', r'''
      read -r c
      echo "polkit-agent-helper-1: pam_authenticate failed" 1>&2
      echo FAILURE
      exit 1
    ''');
    // The explicit FAILURE is still a result, so only a helper that says
    // *nothing* dies. This one talks; the next one does not.
    final talked = await _run(path);
    final refusal = talked.whereType<PolkitHelperResult>().single;
    expect(refusal.authenticated, isFalse);
    // The reason travels with the refusal: `FAILURE` on stdout and the actual
    // fault on stderr are two descriptors with no ordering between them, and
    // without the wait the dialog is left saying "authentication failed"
    // about a machine that never asked anything.
    expect(refusal.detail, contains('pam_authenticate failed'));
    expect(talked.whereType<PolkitHelperDied>(), isEmpty);

    final silent = _helper('silent', r'''
      read -r c
      echo "polkit-agent-helper-1: needs to be setuid root" 1>&2
      exit 127
    ''');
    final messages = await _run(silent);
    final died = messages.whereType<PolkitHelperDied>().single;
    expect(died.exitCode, 127);
    expect(died.detail, contains('needs to be setuid root'));
    expect(messages.whereType<PolkitHelperResult>(), isEmpty);
  });

  test('a helper that dies silently still ends the run', () async {
    final path = _helper('mute', 'read -r c\nexit 3');
    final died = (await _run(path)).whereType<PolkitHelperDied>().single;
    expect(died.exitCode, 3);
    expect(died.detail, isNull);
  });

  test('cancelling kills the helper and says nothing more', () async {
    final path = _helper('hang', r'''
      read -r c
      printf 'PAM_PROMPT_ECHO_OFF Password: \n'
      read -r answer
    ''');
    final attempt = await ProcessPolkitHelperRunner(path: path)
        .start(username: 'ada', cookie: 'cookie-1');
    final seen = <PolkitHelperMessage>[];
    attempt.messages.listen(seen.add);
    // Let the prompt arrive, so the run is cancelled mid-conversation.
    while (seen.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await attempt.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(seen, hasLength(1));
    expect(seen.single, isA<PolkitHelperPrompt>());
    // Idempotent: the dialog's dispose cancels a run its own teardown may
    // already have ended.
    await attempt.cancel();
  });

  // The reported bug, end to end and through a real child process: a helper
  // that refuses the way the real one refuses — `FAILURE` on stdout, the
  // reason on stderr, gone in a millisecond — must leave one card the user
  // can read, not three runs and a dialog that has already closed.
  test('an instant refusal is one run, one reason, and no flash', () async {
    final path = _helper('deny', r"""
      read -r c
      echo "polkit-agent-helper-1: pam_authenticate failed: Authentication failure" 1>&2
      echo FAILURE
      exit 1
    """);
    final runner = ProcessPolkitHelperRunner(path: path);
    final session = PolkitAuthSession(
      request: const PolkitAuthRequest(
        actionId: 'org.freedesktop.locale1.set-keyboard',
        message: 'Authentication is required to set the keyboard layout.',
        iconName: '',
        details: {},
        cookie: 'cookie-1',
        identities: [
          PolkitIdentity(uid: 1000, username: 'ada', displayName: 'Ada'),
        ],
      ),
      runner: runner,
    );
    addTearDown(session.dispose);

    session.start();
    final done = Completer<void>();
    session.addListener(() {
      if (session.isFinished && !done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(seconds: 10));

    expect(session.outcome, PolkitAuthOutcome.unavailable);
    expect(session.attempt, 1, reason: 'nothing was checked, so nothing to retry');
    expect(session.canRetry, isTrue, reason: 'and the card is not a dead end');
    expect(session.error, contains('pam_authenticate failed'));
  });

  test('a helper that cannot be started is unavailable, not a death',
      () async {
    await expectLater(
      ProcessPolkitHelperRunner(path: '${_dir.path}/nothing-here')
          .start(username: 'ada', cookie: 'c'),
      throwsA(isA<PolkitHelperUnavailable>()),
    );
  });
}
