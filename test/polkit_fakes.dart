// Shared stand-ins for the polkit agent's two seams: the helper runner (so no
// test forks a setuid binary) and the request it is answering.

import 'dart:async';

import 'package:graceful_shell/polkit/agent_helper.dart';
import 'package:graceful_shell/polkit/polkit_types.dart';

const PolkitIdentity ada =
    PolkitIdentity(uid: 1000, username: 'ada', displayName: 'Ada Lovelace');
const PolkitIdentity root =
    PolkitIdentity(uid: 0, username: 'root', displayName: 'root');

PolkitAuthRequest polkitRequest({
  List<PolkitIdentity> identities = const [ada],
  String cookie = 'cookie-1',
}) =>
    PolkitAuthRequest(
      actionId: 'org.freedesktop.locale1.set-keyboard',
      message: 'Authentication is required to set the keyboard layout.',
      iconName: '',
      details: const {},
      cookie: cookie,
      identities: identities,
    );

/// A helper that never forks anything: every prompt and result is scripted by
/// the test, which is the whole reason [PolkitHelperRunner] is an interface.
class FakeHelperRunner implements PolkitHelperRunner {
  FakeHelperRunner({this.failure});

  /// Thrown instead of starting, for the "no helper installed" case.
  final PolkitHelperUnavailable? failure;

  final List<FakeHelperAttempt> attempts = [];

  /// Which accounts runs were started for, in order — the identity switch
  /// asserts on this.
  final List<String> usernames = [];

  FakeHelperAttempt get last => attempts.last;

  @override
  Future<PolkitHelperAttempt> start({
    required String username,
    required String cookie,
  }) async {
    final failed = failure;
    if (failed != null) throw failed;
    usernames.add(username);
    final attempt = FakeHelperAttempt(cookie);
    attempts.add(attempt);
    return attempt;
  }
}

class FakeHelperAttempt implements PolkitHelperAttempt {
  FakeHelperAttempt(this.cookie);

  final String cookie;
  final StreamController<PolkitHelperMessage> _controller =
      StreamController<PolkitHelperMessage>();
  final List<String> responses = [];
  bool cancelled = false;

  @override
  Stream<PolkitHelperMessage> get messages => _controller.stream;

  @override
  void respond(String response) => responses.add(response);

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_controller.isClosed) await _controller.close();
  }

  void send(PolkitHelperMessage message) {
    if (!_controller.isClosed) _controller.add(message);
  }
}


/// Lets the session's own `await`s and its helper's stream events land.
Future<void> settleSession() => Future<void>.delayed(Duration.zero);
