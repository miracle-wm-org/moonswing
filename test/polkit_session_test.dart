import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/polkit/agent_helper.dart';
import 'package:graceful_shell/polkit/auth_session.dart';
import 'package:graceful_shell/polkit/polkit_types.dart';

import 'polkit_fakes.dart';

void main() {
  test('a prompt is shown in PAM\'s words, with the colon dropped', () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);

    session.start();
    expect(session.stage, PolkitAuthStage.starting);
    await settleSession();

    runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
    await settleSession();
    expect(session.stage, PolkitAuthStage.prompting);
    // The colon belongs to the terminal line PAM was written for, not to a
    // label above a field.
    expect(session.prompt, 'Password');
    expect(session.echo, isFalse);
  });

  test('a successful answer finishes authenticated', () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);

    session.start();
    await settleSession();
    runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
    await settleSession();

    session.submit('hunter2');
    expect(session.stage, PolkitAuthStage.checking);
    expect(runner.last.responses, ['hunter2']);

    runner.last.send(const PolkitHelperResult(authenticated: true));
    await settleSession();
    expect(session.outcome, PolkitAuthOutcome.authenticated);
    expect(runner.attempts.length, 1);
  });

  // A helper run is one `pam_authenticate` and then an exit, so a retry has to
  // be a whole new process rather than a second password down the same pipe.
  test('a refusal starts a fresh attempt, up to the limit', () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(
      request: polkitRequest(),
      runner: runner,
      maxAttempts: 3,
    );
    addTearDown(session.dispose);

    session.start();
    for (var i = 1; i <= 3; i++) {
      await settleSession();
      expect(runner.attempts.length, i);
      runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
      await settleSession();
      session.submit('wrong');
      runner.last.send(const PolkitHelperResult(authenticated: false));
      await settleSession();
    }

    expect(runner.attempts.length, 3, reason: 'no fourth attempt');
    expect(session.outcome, PolkitAuthOutcome.failed);
    expect(session.error, isNotNull);
  });

  // PAM's own reason beats the agent's guess: "Account locked" is worth more
  // than "that did not work".
  test("a PAM_ERROR_MSG becomes the message, not the agent's", () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(
      request: polkitRequest(),
      runner: runner,
      maxAttempts: 1,
    );
    addTearDown(session.dispose);

    session.start();
    await settleSession();
    runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
    await settleSession();
    session.submit('x');
    runner.last.send(const PolkitHelperError('Account locked'));
    runner.last.send(const PolkitHelperResult(authenticated: false));
    await settleSession();

    expect(session.outcome, PolkitAuthOutcome.failed);
    expect(session.error, 'Account locked');
  });

  test('a PAM_TEXT_INFO is surfaced without ending anything', () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);

    session.start();
    await settleSession();
    runner.last.send(const PolkitHelperInfo('Password expires in 3 days'));
    await settleSession();
    expect(session.info, 'Password expires in 3 days');
    expect(session.isFinished, isFalse);
  });

  // The helper exiting without SUCCESS/FAILURE is a failed attempt rather
  // than a crash of ours — the real runner synthesises the same result.
  test('a helper that dies mid-prompt costs the attempt', () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(
      request: polkitRequest(),
      runner: runner,
      maxAttempts: 1,
    );
    addTearDown(session.dispose);

    session.start();
    await settleSession();
    runner.last.send(const PolkitHelperResult(authenticated: false));
    await settleSession();
    expect(session.outcome, PolkitAuthOutcome.failed);
  });

  test('cancelling ends the run and kills the helper', () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);

    session.start();
    await settleSession();
    runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
    await settleSession();

    session.cancel();
    await settleSession();
    expect(session.outcome, PolkitAuthOutcome.cancelled);
    expect(runner.last.cancelled, isTrue);
    // Latched: a second cancel (Escape after the backdrop) is not a second
    // answer.
    session.cancel();
    expect(session.outcome, PolkitAuthOutcome.cancelled);
  });

  test('disposing an unanswered session records a cancellation', () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    session.start();
    await settleSession();

    session.dispose();
    expect(session.outcome, PolkitAuthOutcome.cancelled);
  });

  // No password the user types would change this, so it is its own state
  // rather than a failed attempt the dialog would ask them to repeat.
  test('a missing helper is unavailable, with the reason kept', () async {
    final runner = FakeHelperRunner(
      failure: const PolkitHelperUnavailable('no helper here'),
    );
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);

    session.start();
    await settleSession();
    expect(session.outcome, PolkitAuthOutcome.unavailable);
    expect(session.error, 'no helper here');
  });

  test('an identity polkit named nobody can answer is unavailable', () {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(
      request: polkitRequest(identities: const []),
      runner: runner,
    );
    addTearDown(session.dispose);

    session.start();
    expect(session.canPrompt, isFalse);
    expect(session.outcome, PolkitAuthOutcome.unavailable);
    expect(runner.attempts, isEmpty);
  });

  // Switching accounts abandons a helper that is authenticating somebody
  // else, and resets the count: the user has not failed three times at *this*
  // account.
  test('switching identity restarts the conversation', () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(
      request: polkitRequest(identities: const [root, ada]),
      runner: runner,
      currentUid: 1000,
      maxAttempts: 2,
    );
    addTearDown(session.dispose);

    // Opens on the current user, not on root.
    expect(session.identity, ada);
    session.start();
    await settleSession();
    expect(runner.usernames, ['ada']);

    runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
    await settleSession();
    session.submit('wrong');
    runner.last.send(const PolkitHelperResult(authenticated: false));
    await settleSession();
    expect(session.attempt, 2);

    final abandoned = runner.last;
    session.selectIdentity(0);
    await settleSession();
    expect(abandoned.cancelled, isTrue);
    expect(runner.usernames, ['ada', 'ada', 'root']);
    expect(session.attempt, 1, reason: 'the count is per account');
    expect(session.error, isNull);
  });

  test('submitting when nothing is being asked is a no-op', () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);

    session.submit('too early');
    session.start();
    await settleSession();
    // Still `starting` — no prompt has arrived.
    session.submit('still too early');
    expect(runner.last.responses, isEmpty);
  });
}
