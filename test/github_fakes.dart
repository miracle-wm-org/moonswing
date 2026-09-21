// Shared fakes for the GitHub tests: an offline [GithubClient], an in-memory
// token store, and the builders that make a notification.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it. The point
// is `weather_fakes.dart`'s: every store test here takes a real lease on a real
// store, and none of them may reach for a network the runner does not have.

import 'dart:async';

import 'package:graceful_shell/github/github_api.dart';
import 'package:graceful_shell/github/github_token_store.dart';

/// A client that answers from what it was handed, counts its calls, and opens
/// nothing.
class FakeGithubClient implements GithubClient {
  FakeGithubClient({
    this.deviceCode = const GithubDeviceCode(
      deviceCode: 'device-code',
      userCode: 'ABCD-1234',
      verificationUri: 'https://github.com/login/device',
      // Zero, so a test's poll loop runs at the speed of the event queue rather
      // than of a real sign-in.
      interval: 0,
      expiresIn: 900,
    ),
    List<GithubNotificationPage>? pages,
    List<GithubTokenResult>? tokenResults,
    this.login = 'octocat',
  })  : pages = pages ?? [const GithubNotificationPage(items: [])],
        tokenResults =
            tokenResults ?? [const GithubTokenGranted('access-token')];

  /// What [requestDeviceCode] answers, or the failure it throws instead.
  GithubDeviceCode deviceCode;
  GithubException? failDeviceCodeWith;

  /// Successive answers from [pollAccessToken]; the last one repeats.
  List<GithubTokenResult> tokenResults;
  GithubException? failTokenWith;

  /// Successive answers from [fetchNotifications]; the last one repeats.
  List<GithubNotificationPage> pages;
  GithubException? failFetchWith;

  /// When set, [fetchNotifications] never completes — the only way a test can
  /// hold the store in its loading state.
  bool pending = false;

  String login;
  GithubException? failWriteWith;

  int deviceCodeCalls = 0;
  int tokenCalls = 0;
  int fetchCalls = 0;
  int loginCalls = 0;
  final List<String> markedRead = [];
  int markAllCalls = 0;

  /// What the last fetch was asked for, so a test can pin that a config change
  /// reached the request rather than only the store.
  String? lastModifiedSeen;
  bool participatingSeen = false;
  bool includeReadSeen = false;

  @override
  Future<GithubDeviceCode> requestDeviceCode({
    required String clientId,
    required String scopes,
  }) async {
    deviceCodeCalls++;
    final failure = failDeviceCodeWith;
    if (failure != null) throw failure;
    return deviceCode;
  }

  @override
  Future<GithubTokenResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) async {
    tokenCalls++;
    final failure = failTokenWith;
    if (failure != null) throw failure;
    return tokenResults.length == 1
        ? tokenResults.first
        : tokenResults.removeAt(0);
  }

  @override
  Future<String> fetchLogin(String token) async {
    loginCalls++;
    return login;
  }

  @override
  Future<GithubNotificationPage> fetchNotifications({
    required String token,
    String? lastModified,
    bool participating = false,
    bool includeRead = false,
  }) {
    fetchCalls++;
    lastModifiedSeen = lastModified;
    participatingSeen = participating;
    includeReadSeen = includeRead;
    if (pending) return Completer<GithubNotificationPage>().future;
    final failure = failFetchWith;
    if (failure != null) return Future.error(failure);
    return Future.value(pages.length == 1 ? pages.first : pages.removeAt(0));
  }

  @override
  Future<void> markThreadRead({
    required String token,
    required String id,
  }) async {
    final failure = failWriteWith;
    if (failure != null) throw failure;
    markedRead.add(id);
  }

  @override
  Future<void> markAllRead({
    required String token,
    DateTime? lastReadAt,
  }) async {
    markAllCalls++;
    final failure = failWriteWith;
    if (failure != null) throw failure;
  }
}

/// A notification with everything filled in, for the fields a test does not
/// care about.
GithubNotification testNotification({
  String id = '1',
  String title = 'Fix the thing',
  String repository = 'miracle-wm-org/graceful-shell',
  GithubSubjectType type = GithubSubjectType.pullRequest,
  String reason = 'review_requested',
  bool unread = true,
  DateTime? updatedAt,
  String url = 'https://github.com/miracle-wm-org/graceful-shell/pull/1',
}) =>
    GithubNotification(
      id: id,
      title: title,
      repository: repository,
      repositoryUrl: 'https://github.com/$repository',
      type: type,
      reason: reason,
      unread: unread,
      updatedAt: updatedAt,
      url: url,
    );

/// Lets everything the store started off an `unawaited` call finish.
///
/// The store's `acquire()` is fire-and-forget by design — a widget's
/// `initState` cannot await a token read — so a test that wants to see what it
/// did has to let the event queue drain. Turns rather than a delay, so this
/// costs no wall-clock time.
///
/// **A turn drains the microtask queue and nothing else.** It does not wait on
/// Dart's I/O thread pool, so a real file anywhere under one of those
/// `unawaited` calls makes this return early on a loaded runner however many
/// turns it is given — which is exactly what [FakeGithubTokenStore] exists to
/// keep out of these tests.
Future<void> settle([int turns = 24]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A token store that keeps the token in memory.
///
/// The real one is `dart:io`, and that is what [settle] cannot wait for: a
/// single [GithubTokenStore.read] is a `File.exists` and a `File.readAsString`,
/// two round trips through Dart's I/O thread pool, and a pool under load
/// delivers them some unbounded number of event-loop turns later. [settle]
/// counts turns, so on a loaded runner it returned while the store was still
/// signing in and whichever assertion came next failed. Which test that was
/// moved from run to run, because which files the pool was busy with did —
/// several tests in one run, none in the next, and never once on an idle
/// machine.
///
/// So nothing a `settle()` covers may touch a real file. The file itself —
/// the round trip, the 0700 directory and the 0600 mode — is
/// `github_token_store_test.dart`'s subject, where it is awaited directly and
/// no turn-counting is involved.
///
/// [directory] is a path that does not exist and never will, so a call that
/// reaches the filesystem after all fails loudly rather than quietly writing
/// somewhere real.
class FakeGithubTokenStore extends GithubTokenStore {
  FakeGithubTokenStore() : super(directory: '/nonexistent/graceful-shell-test');

  /// The saved token, as the real store's file would hold it.
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<bool> write(String token) async {
    this.token = token;
    return true;
  }

  @override
  Future<void> clear() async => token = null;
}
