import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/polkit/agent_helper.dart';
import 'package:graceful_shell/polkit/auth_dialog.dart';
import 'package:graceful_shell/polkit/auth_session.dart';
import 'package:graceful_shell/polkit/polkit_types.dart';
import 'package:graceful_shell/scopes.dart';

import 'polkit_fakes.dart';

Widget _host(
  PolkitAuthSession session, {
  required ValueNotifier<bool> closing,
  required VoidCallback onClosed,
}) =>
    ThemeScope(
      theme: const ThemeConfig(),
      child: PolkitAuthDialog(
        session: session,
        closingNotifier: closing,
        onClosed: onClosed,
      ),
    );

/// Pumps a dialog over [session] and returns its closing notifier plus a
/// counter the teardown increments.
Future<({ValueNotifier<bool> closing, List<int> closed})> _pump(
  WidgetTester tester,
  PolkitAuthSession session,
) async {
  final closing = ValueNotifier(false);
  final closed = <int>[];
  await tester.pumpWidget(
    _host(session, closing: closing, onClosed: () => closed.add(1)),
  );
  await tester.pump();
  return (closing: closing, closed: closed);
}

void main() {
  testWidgets('starts the helper only once it is on screen', (tester) async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);

    // A request nobody is showing must never spawn a setuid process, which is
    // why `start()` is the dialog's to call and not the agent's.
    expect(runner.attempts, isEmpty);

    final host = await _pump(tester, session);
    addTearDown(host.closing.dispose);
    await tester.pump();
    expect(runner.attempts.length, 1);
  });

  testWidgets('renders the message polkit sent and the account', (tester) async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);
    final host = await _pump(tester, session);
    addTearDown(host.closing.dispose);

    expect(find.text('Authentication required'), findsOneWidget);
    expect(
      find.text('Authentication is required to set the keyboard layout.'),
      findsOneWidget,
    );
    expect(find.text('Authenticating as Ada Lovelace'), findsOneWidget);
    expect(find.text('org.freedesktop.locale1.set-keyboard'), findsOneWidget);
  });

  // PAM's own words, because a stack with a fingerprint or an OTP module is
  // not asking for a password and a hard-coded label would say it was.
  testWidgets('labels the field with the prompt PAM sent', (tester) async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);
    final host = await _pump(tester, session);
    addTearDown(host.closing.dispose);

    await tester.pump();
    runner.last.send(const PolkitHelperPrompt('One-time code: ', echo: true));
    await tester.pump();
    await tester.pump();
    expect(find.text('One-time code'), findsOneWidget);
  });

  testWidgets('Enter sends the typed answer to the helper', (tester) async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);
    final host = await _pump(tester, session);
    addTearDown(host.closing.dispose);

    await tester.pump();
    runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'hunter2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(runner.last.responses, ['hunter2']);
    // The answer must not still be sitting in the box behind the spinner.
    expect(session.stage, PolkitAuthStage.checking);
  });

  testWidgets('Escape refuses, and the refusal reaches the session',
      (tester) async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);
    final host = await _pump(tester, session);
    addTearDown(host.closing.dispose);

    await tester.pump();
    runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(session.outcome, PolkitAuthOutcome.cancelled);

    // The window comes down through the closing handshake, never by the
    // dialog tearing it down itself.
    expect(host.closing.value, isTrue);
    await tester.pumpAndSettle();
    expect(host.closed.length, 1);
  });

  // The shell has no input-region support, so this surface swallows every
  // click on the monitor: without dismiss-on-backdrop a mouse-only user has
  // no way out of a prompt they did not ask for.
  testWidgets('a click on the backdrop refuses', (tester) async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);
    final host = await _pump(tester, session);
    addTearDown(host.closing.dispose);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(session.outcome, PolkitAuthOutcome.cancelled);
  });

  testWidgets('a success closes the dialog through the handshake',
      (tester) async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);
    final host = await _pump(tester, session);
    addTearDown(host.closing.dispose);

    await tester.pump();
    runner.last.send(const PolkitHelperPrompt('Password: ', echo: false));
    await tester.pump();
    await tester.pump();
    runner.last.send(const PolkitHelperResult(authenticated: true));
    await tester.pump();
    await tester.pump();

    expect(session.outcome, PolkitAuthOutcome.authenticated);
    await tester.pumpAndSettle();
    expect(host.closed.length, 1);
  });

  // The reported bug, from the surface it was reported at: a helper that ends
  // before it prompts used to be read as a wrong password, so the dialog
  // retried it to exhaustion and closed on "authentication failed" inside a
  // few milliseconds — it flashed, and there was nothing to read and nothing
  // to type into. It stays up, and it says what happened.
  testWidgets('a helper that ends before prompting does not flash away',
      (tester) async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);
    final host = await _pump(tester, session);
    addTearDown(host.closing.dispose);

    await tester.pump();
    runner.last.send(const PolkitHelperDied(
      exitCode: 1,
      detail: 'polkit-agent-helper-1: pam_authenticate failed',
    ));
    await tester.pumpAndSettle();

    expect(session.outcome, PolkitAuthOutcome.unavailable);
    expect(host.closing.value, isFalse);
    expect(host.closed, isEmpty);
    expect(runner.attempts.length, 1, reason: 'and no second helper ran');
    expect(
      find.textContaining('pam_authenticate failed'),
      findsOneWidget,
    );
    // Its ways out are deliberate: read it, then close it or have another go
    // once whatever caused it has been dealt with.
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(runner.attempts.length, 2);
    expect(session.outcome, isNull);
    expect(find.byType(EditableText), findsOneWidget);
    expect(host.closed, isEmpty, reason: 'and the window never came down');
  });

  // Nothing the user typed caused this and no password would change it, so
  // the card stays up long enough to say so — the one outcome that does.
  testWidgets('a missing helper stays on screen with its reason',
      (tester) async {
    final runner = FakeHelperRunner(
      failure: const PolkitHelperUnavailable('polkit-agent-helper-1 missing'),
    );
    final session = PolkitAuthSession(request: polkitRequest(), runner: runner);
    addTearDown(session.dispose);
    final host = await _pump(tester, session);
    addTearDown(host.closing.dispose);
    await tester.pumpAndSettle();

    expect(session.outcome, PolkitAuthOutcome.unavailable);
    expect(host.closed, isEmpty);
    expect(find.text('polkit-agent-helper-1 missing'), findsOneWidget);
    // No field to answer with, and no Authenticate button to press.
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('Authenticate'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('several identities are offered as a row of choices',
      (tester) async {
    final runner = FakeHelperRunner();
    final session = PolkitAuthSession(
      request: polkitRequest(identities: const [root, ada]),
      runner: runner,
      currentUid: 1000,
    );
    addTearDown(session.dispose);
    final host = await _pump(tester, session);
    addTearDown(host.closing.dispose);
    await tester.pump();

    expect(find.text('Authenticate as'), findsOneWidget);
    expect(find.text('root'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(runner.usernames, ['ada']);

    await tester.tap(find.text('root'));
    await tester.pump();
    await tester.pump();
    expect(runner.usernames, ['ada', 'root']);
  });
}
