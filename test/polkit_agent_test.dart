import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/polkit/auth_session.dart';
import 'package:graceful_shell/polkit/polkit_agent.dart';
import 'package:graceful_shell/polkit/polkit_types.dart';

import 'polkit_fakes.dart';

DBusValue _identities(List<int> uids) => DBusArray(
      DBusSignature('(sa{sv})'),
      [
        for (final uid in uids)
          DBusStruct([
            const DBusString('unix-user'),
            DBusDict.stringVariant({'uid': DBusUint32(uid)}),
          ]),
      ],
    );

DBusMethodCall _begin({
  String cookie = 'cookie-1',
  List<int> uids = const [1000],
  Map<String, DBusValue>? details,
  String actionId = 'org.freedesktop.locale1.set-keyboard',
}) =>
    DBusMethodCall(
      sender: ':1.42',
      interface: kPolkitAgentInterface,
      name: 'BeginAuthentication',
      values: [
        DBusString(actionId),
        const DBusString('Authentication is required.'),
        const DBusString(''),
        DBusDict(
          DBusSignature('s'),
          DBusSignature('s'),
          details?.map((k, v) => MapEntry(DBusString(k), v)) ?? {},
        ),
        DBusString(cookie),
        _identities(uids),
      ],
    );

DBusMethodCall _cancel(String cookie) => DBusMethodCall(
      sender: ':1.42',
      interface: kPolkitAgentInterface,
      name: 'CancelAuthentication',
      values: [DBusString(cookie)],
    );

/// A presenter that hands the session back to the test and waits to be told
/// what the user did — which is what the real one does, only with a window in
/// between.
class _FakePresenter {
  final List<PolkitAuthSession> shown = [];
  final List<Completer<PolkitAuthOutcome?>> _answers = [];

  int get shownCount => shown.length;

  Future<PolkitAuthOutcome?> present(PolkitAuthSession session) {
    shown.add(session);
    final completer = Completer<PolkitAuthOutcome?>();
    _answers.add(completer);
    return completer.future;
  }

  void answer(PolkitAuthOutcome? outcome, {int index = 0}) =>
      _answers[index].complete(outcome);
}

PolkitAgentObject _agent(_FakePresenter presenter) => PolkitAgentObject(
      presenter: presenter.present,
      helperRunner: FakeHelperRunner(),
      currentUid: 1000,
      // Never the host's passwd database: a test that resolved real uids
      // would pass or fail on which accounts the CI runner happens to have.
      userLookup: (uid) => switch (uid) {
        0 => (username: 'root', displayName: 'root'),
        1000 => (username: 'ada', displayName: 'Ada Lovelace'),
        _ => null,
      },
    );

String _errorName(DBusMethodResponse response) =>
    (response as DBusMethodErrorResponse).errorName;

void main() {
  test('an authenticated prompt returns success and sends nothing', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);

    final call = agent.handleMethodCall(_begin());
    await pumpEventQueue();
    expect(presenter.shownCount, 1);

    presenter.answer(PolkitAuthOutcome.authenticated);
    final response = await call;
    // Deliberately empty: the helper already made the privileged response
    // call to polkitd. All this says is that the agent is finished.
    expect(response, isA<DBusMethodSuccessResponse>());
    expect((response as DBusMethodSuccessResponse).values, isEmpty);
  });

  // Cancelled is the one answer that does not make the caller ask again
  // straight away, which is why a dismissal has to map to it exactly.
  test('a dismissal answers Cancelled', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);

    final call = agent.handleMethodCall(_begin());
    await pumpEventQueue();
    presenter.answer(PolkitAuthOutcome.cancelled);
    expect(_errorName(await call), kPolkitCancelledError);
  });

  // Null is the decline: nothing was listening, or a later request displaced
  // this one. The caller must not be left waiting either way.
  test('a declined presentation answers Cancelled too', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);

    final call = agent.handleMethodCall(_begin());
    await pumpEventQueue();
    presenter.answer(null);
    expect(_errorName(await call), kPolkitCancelledError);
  });

  test('running out of attempts answers Failed', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);

    final call = agent.handleMethodCall(_begin());
    await pumpEventQueue();
    presenter.answer(PolkitAuthOutcome.failed);
    expect(_errorName(await call), kPolkitFailedError);
  });

  test('the session carries what polkit said', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);

    final call = agent.handleMethodCall(_begin(
      uids: [0, 1000],
      details: {'polkit.gettext_domain': const DBusString('locale1')},
    ));
    await pumpEventQueue();

    final session = presenter.shown.single;
    expect(session.request.actionId, 'org.freedesktop.locale1.set-keyboard');
    expect(session.request.details['polkit.gettext_domain'], 'locale1');
    expect(session.request.identities.map((i) => i.username), ['root', 'ada']);
    // Opens on the current user rather than on root.
    expect(session.identity?.username, 'ada');

    presenter.answer(PolkitAuthOutcome.cancelled);
    await call;
  });

  // Nothing the user could type would help, and a prompt with no answerable
  // account is worse than an honest refusal.
  test('no usable identity is refused without a prompt', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);

    final response = await agent.handleMethodCall(_begin(uids: [4242]));
    expect(_errorName(response), kPolkitFailedError);
    expect(presenter.shownCount, 0);
  });

  // polkitd re-asking a cookie already on screen is the prompt the user is
  // looking at; a second dialog for one question is not an answer to it.
  test('a cookie already in flight opens no second prompt', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);

    final first = agent.handleMethodCall(_begin());
    await pumpEventQueue();
    final second = await agent.handleMethodCall(_begin());
    expect(_errorName(second), kPolkitFailedError);
    expect(presenter.shownCount, 1);

    presenter.answer(PolkitAuthOutcome.cancelled);
    await first;
  });

  test('CancelAuthentication takes the matching prompt down', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);

    final call = agent.handleMethodCall(_begin(cookie: 'abc'));
    await pumpEventQueue();
    final session = presenter.shown.single;

    // An unknown cookie is answered rather than errored — the prompt it names
    // is already gone.
    expect(
      await agent.handleMethodCall(_cancel('nope')),
      isA<DBusMethodSuccessResponse>(),
    );
    expect(session.isFinished, isFalse);

    expect(
      await agent.handleMethodCall(_cancel('abc')),
      isA<DBusMethodSuccessResponse>(),
    );
    expect(session.outcome, PolkitAuthOutcome.cancelled);

    // The dialog is what answers the presenter; the agent only asked.
    presenter.answer(PolkitAuthOutcome.cancelled);
    expect(_errorName(await call), kPolkitCancelledError);
  });

  test('cancelAll ends everything in flight', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);

    final call = agent.handleMethodCall(_begin(cookie: 'x'));
    await pumpEventQueue();
    agent.cancelAll();
    expect(presenter.shown.single.outcome, PolkitAuthOutcome.cancelled);

    presenter.answer(PolkitAuthOutcome.cancelled);
    await call;
  });

  test('a call on another interface is refused by the guard', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);
    final response = await agent.handleMethodCall(DBusMethodCall(
      sender: ':1.42',
      interface: 'org.freedesktop.DBus.Nonsense',
      name: 'BeginAuthentication',
      values: const [],
    ));
    expect(response, isA<DBusMethodErrorResponse>());
    expect(presenter.shownCount, 0);
  });

  test('too few arguments is invalid args, not a crash', () async {
    final presenter = _FakePresenter();
    final agent = _agent(presenter);
    final response = await agent.handleMethodCall(DBusMethodCall(
      sender: ':1.42',
      interface: kPolkitAgentInterface,
      name: 'BeginAuthentication',
      values: [const DBusString('only-one')],
    ));
    expect(response, isA<DBusMethodErrorResponse>());
    expect(presenter.shownCount, 0);
  });

  group('unixSessionSubject', () {
    // A *session* subject and never a process one: registering for the
    // process would make the shell the agent for its own authorizations
    // alone, so every other application would keep getting AccessDenied with
    // a prompt sitting one window away.
    test('names the session polkit is being asked about', () {
      final subject = unixSessionSubject('c2').asStruct();
      expect(subject[0].asString(), 'unix-session');
      expect(subject[1].asStringVariantDict()['session-id']?.asString(), 'c2');
    });
  });

  group('introspection', () {
    test('declares the interface polkitd calls back on', () {
      final agent = _agent(_FakePresenter());
      final iface = agent.introspect().single;
      expect(iface.name, kPolkitAgentInterface);
      expect(
        iface.methods.map((m) => m.name),
        containsAll(['BeginAuthentication', 'CancelAuthentication']),
      );
      expect(agent.path.value, kPolkitAgentPath);
    });
  });
}
