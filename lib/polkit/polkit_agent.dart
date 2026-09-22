// The shell as a polkit authentication agent.
//
// polkitd never prompts anybody itself: when an application asks for a privileged
// operation whose policy says `auth_admin` or `auth_self`, polkitd looks for an
// agent registered for the caller's session and calls `BeginAuthentication` on
// it. With no agent there is no prompt and no privilege — every such call comes
// straight back as `AccessDenied`.
//
// Flutter-free, so the whole wire surface can be reasoned about and tested
// without an engine. The dialog reaches it through [PolkitAuthController].

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

import 'package:moonswing/dbus_service_object.dart';
import 'package:moonswing/lock/user_identity.dart';

import 'agent_helper.dart';
import 'auth_session.dart';
import 'polkit_log.dart';
import 'polkit_types.dart';

// `polkitLog` moved to its own file so the layers below this one can report
// too; re-exported because it is set from `main()`, which knows this file.
export 'polkit_log.dart' show polkitLog;

/// polkitd's own bus name, on the **system** bus. Authentication is a
/// system-wide question; the session bus has nothing to do with it.
const String kPolkitAuthorityName = 'org.freedesktop.PolicyKit1';
const String kPolkitAuthorityPath = '/org/freedesktop/PolicyKit1/Authority';
const String kPolkitAuthorityInterface =
    'org.freedesktop.PolicyKit1.Authority';

/// The interface polkitd calls back on, and the path the shell exports it at.
/// The path is conventional rather than required — polkitd is told it during
/// registration — but every agent uses this one, which makes a `busctl tree`
/// on a machine with a stuck prompt legible.
const String kPolkitAgentInterface =
    'org.freedesktop.PolicyKit1.AuthenticationAgent';
const String kPolkitAgentPath =
    '/org/freedesktop/PolicyKit1/AuthenticationAgent';

/// The two errors polkit understands from an agent. Anything else is reported
/// to the *caller* as an internal failure, which reads as a broken system
/// rather than as a refused password.
const String kPolkitCancelledError =
    'org.freedesktop.PolicyKit1.Error.Cancelled';
const String kPolkitFailedError = 'org.freedesktop.PolicyKit1.Error.Failed';

/// How a request reaches a surface that can ask the user.
///
/// The shell passes `PolkitAuthController.instance`; a headless harness passes a
/// stand-in. Required rather than defaulted, for [startScreencastService]'s
/// reason: an agent that could answer without a visible prompt is an agent that
/// approves privilege escalation silently.
typedef PolkitAuthPresenter = Future<PolkitAuthOutcome?> Function(
  PolkitAuthSession session,
);

PolkitAgentService? _service;

/// The running agent, if one came up.
PolkitAgentService? get polkitAgentService => _service;

/// Registers the shell as the authentication agent for this login session.
///
/// Two graceful declines, both of which log and return normally so
/// `ShellServices` settles `ready`:
///
/// * **Another agent is already registered for this session.** polkitd allows
///   exactly one, and a desktop already running `polkit-gnome` is one where
///   prompts already work. Fighting for the registration would leave whichever
///   agent lost the race silently unable to prompt.
/// * **`[polkit] enabled = false`.** Handled by `main.dart`, which skips the
///   service outright.
///
/// Everything else throws, so the status is truthful rather than "ready with no
/// prompts": an unreachable system bus, no polkitd, an export failure, or a
/// session id that cannot be resolved.
Future<void> startPolkitAgentService({
  required PolkitAuthPresenter presenter,
  int maxAttempts = kPolkitMaxAttempts,
  DBusClient? client,
  PolkitHelperRunner helperRunner = const ProcessPolkitHelperRunner(),
  Future<String?> Function(DBusClient client)? sessionIdReader,
}) async {
  // Its own connection rather than the shared `systemBus`: a
  // `BeginAuthentication` call is answered when the *user* is done, so this
  // object holds a D-Bus method call open for as long as somebody takes to
  // find their password. Nothing else on the machine may be behind that —
  // and the shared client is what the network and bluetooth pages query on.
  final bus = client ?? DBusClient.system();
  final ownsClient = client == null;
  try {
    final sessionId =
        await (sessionIdReader ?? resolvePolkitSessionId)(bus);
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError(
        'no logind session to register an authentication agent for '
        r'(neither $XDG_SESSION_ID nor logind named one)',
      );
    }

    final object = PolkitAgentObject(
      presenter: presenter,
      helperRunner: helperRunner,
      maxAttempts: maxAttempts,
      currentUid: currentUid(),
    );
    await bus.registerObject(object);

    final authority = DBusRemoteObject(
      bus,
      name: kPolkitAuthorityName,
      path: DBusObjectPath(kPolkitAuthorityPath),
    );
    final subject = unixSessionSubject(sessionId);
    try {
      await authority.callMethod(
        kPolkitAuthorityInterface,
        'RegisterAuthenticationAgent',
        [subject, DBusString(agentLocale()), DBusString(kPolkitAgentPath)],
        replySignature: DBusSignature(''),
      );
    } catch (error) {
      await bus.unregisterObject(object);
      // polkitd answers a session that already has an agent with a plain
      // `Failed` carrying that sentence — there is no distinct error name to
      // match on, so the message is the only thing there is to read.
      if (_isAlreadyRegistered(error)) {
        polkitLog('another authentication agent already serves this session');
        if (ownsClient) await bus.close();
        return;
      }
      rethrow;
    }

    _service = PolkitAgentService._(bus, object, subject, ownsClient);
    polkitLog('registered as the authentication agent for session $sessionId');
  } catch (_) {
    if (ownsClient) await bus.close();
    rethrow;
  }
}

bool _isAlreadyRegistered(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('already exists') ||
      text.contains('already registered');
}

/// The registration, and the re-registration that keeps it true.
class PolkitAgentService {
  PolkitAgentService._(
    this._client,
    this.object,
    this._subject,
    this._ownsClient,
  ) {
    // polkitd restarting drops every registration it held, and nothing tells
    // the agent — the shell would simply stop prompting, for the rest of the
    // session, with no error anywhere. Watching the name is the only signal
    // there is, and it is the same one `lib/media/mpris_store.dart` and the
    // screencast backend already use for a peer's death.
    _nameOwnerSub = _client.nameOwnerChanged.listen(_onNameOwnerChanged);
  }

  final DBusClient _client;
  final PolkitAgentObject object;
  final DBusValue _subject;
  final bool _ownsClient;
  StreamSubscription<DBusNameOwnerChangedEvent>? _nameOwnerSub;
  bool _disposed = false;

  void _onNameOwnerChanged(DBusNameOwnerChangedEvent event) {
    if (_disposed || event.name != kPolkitAuthorityName) return;
    final owner = event.newOwner;
    if (owner == null || owner.isEmpty) return;
    polkitLog('polkitd came back; re-registering');
    unawaited(_register());
  }

  Future<void> _register() async {
    try {
      await DBusRemoteObject(
        _client,
        name: kPolkitAuthorityName,
        path: DBusObjectPath(kPolkitAuthorityPath),
      ).callMethod(
        kPolkitAuthorityInterface,
        'RegisterAuthenticationAgent',
        [_subject, DBusString(agentLocale()), DBusString(kPolkitAgentPath)],
        replySignature: DBusSignature(''),
      );
    } catch (error) {
      polkitLog('re-registration failed: $error');
    }
  }

  /// Hands the registration back and answers anything still pending.
  ///
  /// Unregistering is best-effort: polkitd drops an agent whose connection
  /// goes away, so a shell that dies without getting here leaves nothing
  /// stale — but a shell shutting down deliberately says so, which is the
  /// rule `PowerKeyService.shutdown` follows for its inhibitor.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _nameOwnerSub?.cancel();
    _nameOwnerSub = null;
    object.cancelAll();
    try {
      await DBusRemoteObject(
        _client,
        name: kPolkitAuthorityName,
        path: DBusObjectPath(kPolkitAuthorityPath),
      ).callMethod(
        kPolkitAuthorityInterface,
        'UnregisterAuthenticationAgent',
        [_subject, DBusString(kPolkitAgentPath)],
        replySignature: DBusSignature(''),
      );
    } catch (_) {}
    try {
      await _client.unregisterObject(object);
    } catch (_) {}
    if (_ownsClient) await _client.close();
    if (identical(_service, this)) _service = null;
  }
}

/// `org.freedesktop.PolicyKit1.AuthenticationAgent`, exported at
/// [kPolkitAgentPath].
class PolkitAgentObject extends DBusServiceObject {
  PolkitAgentObject({
    required this.presenter,
    required this.helperRunner,
    this.maxAttempts = kPolkitMaxAttempts,
    this.currentUid,
    this.userLookup = lookupPolkitUser,
  }) : super(DBusObjectPath(kPolkitAgentPath));

  final PolkitAuthPresenter presenter;
  final PolkitHelperRunner helperRunner;
  final int maxAttempts;

  /// Whose prompt to open on when polkit offers a choice. Null only in tests.
  final int? currentUid;

  final PolkitUserLookup userLookup;

  /// The authentications in flight, by cookie — `CancelAuthentication` names
  /// one this way and nothing else identifies it.
  final Map<String, PolkitAuthSession> _sessions = {};

  @override
  late final List<DBusServiceInterface> interfaces = [
    DBusServiceInterface(
      kPolkitAgentInterface,
      methods: {
        'BeginAuthentication': DBusServiceMethod(
          _beginAuthentication,
          args: [
            DBusIntrospectArgument(
                DBusSignature('s'), DBusArgumentDirection.in_,
                name: 'action_id'),
            DBusIntrospectArgument(
                DBusSignature('s'), DBusArgumentDirection.in_,
                name: 'message'),
            DBusIntrospectArgument(
                DBusSignature('s'), DBusArgumentDirection.in_,
                name: 'icon_name'),
            DBusIntrospectArgument(
                DBusSignature('a{ss}'), DBusArgumentDirection.in_,
                name: 'details'),
            DBusIntrospectArgument(
                DBusSignature('s'), DBusArgumentDirection.in_,
                name: 'cookie'),
            DBusIntrospectArgument(
                DBusSignature('a(sa{sv})'), DBusArgumentDirection.in_,
                name: 'identities'),
          ],
        ),
        'CancelAuthentication': DBusServiceMethod(
          _cancelAuthentication,
          args: [
            DBusIntrospectArgument(
                DBusSignature('s'), DBusArgumentDirection.in_,
                name: 'cookie'),
          ],
        ),
      },
    ),
  ];

  /// polkitd asking the user for a password.
  ///
  /// The call is answered when the *user* is done, which is the whole shape
  /// of this method: it may sit here for a minute while somebody finds their
  /// password, and polkitd is waiting on exactly that. Returning early —
  /// with success or with an error — is what tells polkitd nothing more is
  /// coming.
  Future<DBusMethodResponse> _beginAuthentication(DBusMethodCall call) async {
    if (call.values.length < 6) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    final String cookie;
    final PolkitAuthRequest request;
    try {
      cookie = call.values[4].asString();
      request = PolkitAuthRequest(
        actionId: call.values[0].asString(),
        message: call.values[1].asString(),
        iconName: call.values[2].asString(),
        details: _readDetails(call.values[3]),
        cookie: cookie,
        identities:
            parsePolkitIdentities(call.values[5], lookup: userLookup),
      );
    } catch (_) {
      return DBusMethodErrorResponse.invalidArgs();
    }

    if (request.identities.isEmpty) {
      polkitLog('no usable identity for ${request.actionId}');
      return DBusMethodErrorResponse(
        kPolkitFailedError,
        [const DBusString('No account this agent can authenticate.')],
      );
    }

    // A cookie already in flight is polkitd re-asking (a frontend retry, or
    // this agent having been re-registered mid-prompt). The prompt on screen
    // is the answer to it, so the second call is refused rather than opening
    // a second dialog for one question.
    if (_sessions.containsKey(cookie)) {
      return DBusMethodErrorResponse(
        kPolkitFailedError,
        [const DBusString('That authentication is already in progress.')],
      );
    }

    final session = PolkitAuthSession(
      request: request,
      runner: helperRunner,
      currentUid: currentUid,
      maxAttempts: maxAttempts,
    );
    _sessions[cookie] = session;
    polkitLog('prompting for ${request.actionId}');
    try {
      final outcome = await presenter(session);
      switch (outcome) {
        case PolkitAuthOutcome.authenticated:
          // Deliberately empty: the helper already made the privileged
          // response call to polkitd. All this return says is "the agent is
          // finished", which is what releases the caller.
          return DBusMethodSuccessResponse();
        case PolkitAuthOutcome.failed:
          return DBusMethodErrorResponse(
            kPolkitFailedError,
            [const DBusString('Authentication failed.')],
          );
        case PolkitAuthOutcome.unavailable:
          return DBusMethodErrorResponse(
            kPolkitFailedError,
            [DBusString(session.error ?? 'Authentication is unavailable.')],
          );
        case PolkitAuthOutcome.cancelled:
        case null:
          // Null is the decline: nothing was listening, or a later request
          // displaced this one. Cancelled either way — it is the one answer
          // that does not make the caller try again straight away.
          return DBusMethodErrorResponse(
            kPolkitCancelledError,
            [const DBusString('Cancelled.')],
          );
      }
    } finally {
      _sessions.remove(cookie);
      session.dispose();
    }
  }

  /// polkitd withdrawing a question — the caller went away, or another agent
  /// answered it. The prompt comes down and its `BeginAuthentication` returns
  /// `Cancelled`; the reply here is immediate and unconditional, because an
  /// unknown cookie means the prompt is already gone.
  Future<DBusMethodResponse> _cancelAuthentication(DBusMethodCall call) async {
    if (call.values.isNotEmpty) {
      final cookie = call.values.first.asString();
      _sessions[cookie]?.cancel();
    }
    return DBusMethodSuccessResponse();
  }

  /// Cancels everything in flight — shell shutdown. Each session's own
  /// `BeginAuthentication` answers `Cancelled` from its `await` above.
  void cancelAll() {
    for (final session in _sessions.values.toList()) {
      session.cancel();
    }
  }

  /// `a{ss}` — polkit's action details plus whatever the caller attached.
  /// Read defensively and per entry, the rule [parsePolkitIdentities] states:
  /// this is a trailing informational line, and nothing on it is worth
  /// refusing a prompt over.
  static Map<String, String> _readDetails(DBusValue value) {
    final details = <String, String>{};
    if (value is! DBusDict) return details;
    value.children.forEach((key, entry) {
      try {
        details[key.asString()] = entry.asString();
      } catch (_) {}
    });
    return details;
  }
}

/// polkit's `unix-session` subject: `("unix-session", {"session-id": <id>})`.
///
/// A *session* subject rather than a `unix-process` one, and the difference
/// is the whole feature: a process subject would register the shell as the
/// agent for its own authorizations alone, so every other application on the
/// desktop would keep getting `AccessDenied` with a prompt sitting one window
/// away. There is deliberately no fallback to one.
DBusValue unixSessionSubject(String sessionId) => DBusStruct([
      const DBusString('unix-session'),
      DBusDict.stringVariant({'session-id': DBusString(sessionId)}),
    ]);

/// The locale polkitd should localize its messages into. polkitd reads the
/// usual environment itself when handed an empty string, which is the right
/// answer more often than a value assembled here would be — but an explicit
/// `LANG` is honoured where the session sets one.
String agentLocale() {
  for (final key in const ['LC_ALL', 'LC_MESSAGES', 'LANG']) {
    final value = Platform.environment[key];
    if (value != null && value.isNotEmpty) return value;
  }
  return '';
}

/// Which login session the shell is in.
///
/// `XDG_SESSION_ID` first — set by logind's PAM module for every graphical
/// session, and free. logind's own answer second, for a shell started
/// somewhere that env var did not survive.
Future<String?> resolvePolkitSessionId(DBusClient client) async {
  final fromEnv = Platform.environment['XDG_SESSION_ID'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();
  try {
    final manager = DBusRemoteObject(
      client,
      name: 'org.freedesktop.login1',
      path: DBusObjectPath('/org/freedesktop/login1'),
    );
    final reply = await manager.callMethod(
      'org.freedesktop.login1.Manager',
      'GetSessionByPID',
      [DBusUint32(pid)],
      replySignature: DBusSignature('o'),
    );
    final session = DBusRemoteObject(
      client,
      name: 'org.freedesktop.login1',
      path: reply.returnValues.first.asObjectPath(),
    );
    final id = await session.getProperty(
      'org.freedesktop.login1.Session',
      'Id',
    );
    return id.asString();
  } catch (error) {
    polkitLog('could not resolve the logind session: $error');
    return null;
  }
}

/// Resolves a uid to the passwd entry the dialog names and the helper
/// authenticates.
///
/// Through `lib/lock/user_identity.dart` rather than a second `getpwuid`
/// binding beside it: the lock screen already asks the passwd database this
/// question, and one FFI declaration for it is one place for it to be wrong.
({String username, String displayName})? lookupPolkitUser(int uid) {
  final entry = UserIdentity.forUid(uid);
  if (entry == null) return null;
  return (username: entry.username, displayName: entry.displayName);
}
