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

  // An answered FAILURE is PAM having weighed something and refused it, so
  // the last one runs the count out.
  test('an answered FAILURE with no attempts left finishes failed', () async {
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
    session.submit('wrong');
    runner.last.send(const PolkitHelperResult(authenticated: false));
    await settleSession();
    expect(session.outcome, PolkitAuthOutcome.failed);
  });

  // The other half, and the one the reported bug was made of: the helper
  // answers `FAILURE` to its own early refusals too — `wrong number of
  // arguments`, `needs to be setuid root`, a `polkit-1` stack that denies
  // before it asks — and PAM cannot have refused an answer it was never
  // given. Retrying it burns every attempt in a couple of milliseconds and
  // closes the card on "authentication failed" before it can be read.
  test('a FAILURE nobody answered is unavailable, and retries nothing',
      () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);

    session.start();
    await settleSession();
    runner.last.send(const PolkitHelperResult(
      authenticated: false,
      detail: 'polkit-agent-helper-1: needs to be setuid root',
    ));
    await settleSession();

    expect(session.outcome, PolkitAuthOutcome.unavailable);
    expect(session.attempt, 1);
    expect(runner.attempts.length, 1, reason: 'and starts no second helper');
    expect(session.error, contains('needs to be setuid root'));
    expect(session.error, contains('no password was checked'));
    expect(session.canRetry, isTrue);
  });

  test('a bare FAILURE nobody answered still says what happened', () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);

    session.start();
    await settleSession();
    runner.last.send(const PolkitHelperResult(authenticated: false));
    await settleSession();
    expect(session.error, contains('polkit-1 PAM stack'));
  });

  // A prompt PAM sent and the user never answered is the same thing: nothing
  // was checked. `PAM_ERROR_MSG` is what the card should carry, because it
  // names the fault where the helper's stderr only reports it.
  test("an unanswered FAILURE keeps PAM's own words", () async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);

    session.start();
    await settleSession();
    runner.last.send(
      const PolkitHelperError('Account locked due to 3 failed logins'),
    );
    runner.last.send(const PolkitHelperResult(
      authenticated: false,
      detail: 'pam_authenticate failed: Authentication failure',
    ));
    await settleSession();

    expect(session.outcome, PolkitAuthOutcome.unavailable);
    expect(session.error, contains('Account locked'));
    expect(session.error, isNot(contains('pam_authenticate')));
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

  // The bug this pair exists for: a helper that ends before it prompts used
  // to be reported as a wrong password, so the dialog burned every attempt in
  // a couple of milliseconds and took itself off the screen — a prompt that
  // flashed and was gone. Nothing was checked, so nothing may be retried.
  group('a run that ends without a result', () {
    test('never prompted: unavailable, no retry, the reason kept', () async {
      final runner = FakeHelperRunner();
      final session =
          PolkitAuthSession(request: polkitRequest(), runner: runner);
      addTearDown(session.dispose);

      session.start();
      await settleSession();
      runner.last.send(const PolkitHelperDied(
        exitCode: 1,
        detail: 'polkit-agent-helper-1: pam_authenticate failed: '
            'Authentication failure',
      ));
      await settleSession();

      expect(session.outcome, PolkitAuthOutcome.unavailable);
      expect(session.attempt, 1, reason: 'a non-starter is not an attempt');
      expect(runner.attempts.length, 1, reason: 'and starts no second helper');
      expect(session.error, contains('pam_authenticate failed'));
      expect(session.error, contains('before asking for anything'));
    });

    test('prompted but unanswered: unavailable, and says so', () async {
      final runner = FakeHelperRunner();
      final session =
          PolkitAuthSession(request: polkitRequest(), runner: runner);
      addTearDown(session.dispose);

      session.start();
      await settleSession();
      runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
      await settleSession();
      runner.last.send(const PolkitHelperDied(exitCode: 15));
      await settleSession();

      expect(session.outcome, PolkitAuthOutcome.unavailable);
      expect(session.error, contains('before the prompt could be answered'));
      expect(runner.attempts.length, 1);
    });

    test("PAM's own words beat the helper's stderr", () async {
      final runner = FakeHelperRunner();
      final session =
          PolkitAuthSession(request: polkitRequest(), runner: runner);
      addTearDown(session.dispose);

      session.start();
      await settleSession();
      runner.last.send(
        const PolkitHelperError('Account locked due to 3 failed logins'),
      );
      runner.last.send(const PolkitHelperDied(
        exitCode: 1,
        detail: 'pam_authenticate failed: Authentication failure',
      ));
      await settleSession();

      expect(session.error, contains('Account locked'));
      expect(session.error, isNot(contains('pam_authenticate')));
    });

    // The other half: PAM *was* given something to check, so the answer never
    // coming back is a failed attempt and the count is what ends it.
    test('answered: costs the attempt', () async {
      final runner = FakeHelperRunner();
      final session = PolkitAuthSession(
        request: polkitRequest(),
        runner: runner,
        maxAttempts: 2,
      );
      addTearDown(session.dispose);

      session.start();
      await settleSession();
      runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
      await settleSession();
      session.submit('hunter2');
      runner.last.send(const PolkitHelperDied(exitCode: 1, detail: 'died'));
      await settleSession();

      expect(session.outcome, isNull, reason: 'one attempt left');
      expect(session.attempt, 2);
      expect(runner.attempts.length, 2);
    });
  });

  group('retry', () {
    test('offered over unavailable, and starts a fresh conversation',
        () async {
      final runner = FakeHelperRunner();
      final session =
          PolkitAuthSession(request: polkitRequest(), runner: runner);
      addTearDown(session.dispose);

      session.start();
      await settleSession();
      runner.last.send(const PolkitHelperDied(exitCode: 1, detail: 'locked'));
      await settleSession();
      expect(session.canRetry, isTrue);

      session.retry();
      await settleSession();
      expect(session.outcome, isNull);
      expect(session.error, isNull);
      expect(session.attempt, 1, reason: 'nothing was ever checked');
      expect(runner.attempts.length, 2);

      // And the fresh conversation is a real one.
      runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
      await settleSession();
      session.submit('hunter2');
      runner.last.send(const PolkitHelperResult(authenticated: true));
      await settleSession();
      expect(session.outcome, PolkitAuthOutcome.authenticated);
    });

    // Three refusals is PAM having weighed three answers; a button that sent
    // it round again is a password oracle on an unattended screen.
    test('never offered over failed or cancelled', () async {
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
      session.submit('wrong');
      runner.last.send(const PolkitHelperResult(authenticated: false));
      await settleSession();
      expect(session.outcome, PolkitAuthOutcome.failed);
      expect(session.canRetry, isFalse);
      session.retry();
      expect(session.outcome, PolkitAuthOutcome.failed);
      expect(runner.attempts.length, 1);
    });

    test('never offered when there is nobody to authenticate', () {
      final runner = FakeHelperRunner();
      final session = PolkitAuthSession(
        request: polkitRequest(identities: const []),
        runner: runner,
      );
      addTearDown(session.dispose);

      session.start();
      expect(session.outcome, PolkitAuthOutcome.unavailable);
      expect(session.canRetry, isFalse);
    });
  });

  group('helperDiedMessage', () {
    test('leads with the helper\'s own complaint', () {
      expect(
        helperDiedMessage(exitCode: 1, prompted: false, detail: '  boom  '),
        endsWith('boom'),
      );
    });

    test('falls back to the exit status', () {
      expect(
        helperDiedMessage(exitCode: 127, prompted: false),
        contains('status 127'),
      );
      expect(
        helperDiedMessage(exitCode: -1, prompted: true),
        contains('without an exit status'),
      );
    });
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
