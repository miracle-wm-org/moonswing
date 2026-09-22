// The GitHub notification list for the whole shell.
//
// The singleton-`ChangeNotifier`-with-leases shape `WeatherStore` and
// `MprisStore` have, and for the same reason: one poller for the machine, so a
// bar module on each of two monitors is one request per interval rather than
// two. The requests exist only while something holds a lease — an idle shell
// with the module off its panels never touches the network.
//
// It also owns the sign-in, because the device flow is a *state machine with a
// timer in it* rather than a dialog: ask for a code, show it, poll until the
// user has typed it into a browser, save the token. A widget that owned that
// would lose it the moment its popup closed.
//
// It has no widgets of its own, and the one import that is not `dart:` or
// `ChangeNotifier` is `app_info.dart`: a click opens a page through GIO's
// `g_app_info_launch_default_for_uri` — `xdg-open` with this process's launch
// context — so the browser is adopted into a systemd scope of its own rather
// than left in the shell's cgroup. Tests inject an opener and never reach it.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_config.dart';
import 'package:moonswing/github/github_token_store.dart';

/// How far along the sign-in is.
enum GithubAuthStage {
  /// No token. The popup offers a **Sign in** button.
  signedOut,

  /// Asking GitHub for a user code.
  requestingCode,

  /// The code is on screen and the shell is polling for the user to type it in
  /// at github.com/login/device.
  awaitingAuthorization,

  /// There is a token; the list is what the popup shows.
  signedIn,
}

/// The notification list, the sign-in, and the poll behind both.
class GithubStore extends ChangeNotifier {
  GithubStore._({
    GithubClient? client,
    GithubTokenStore? tokens,
    bool Function(String url)? opener,
  })  : _client = client ?? const HttpGithubClient(),
        _tokens = tokens ?? const GithubTokenStore(),
        _open = opener ?? openUriWithDefault;

  static final GithubStore instance = GithubStore._();

  /// A detached store for tests: an injected client, a token file under a
  /// temporary directory, and an opener that records rather than launching a
  /// browser. Nothing here opens a socket unless [client] does.
  @visibleForTesting
  factory GithubStore.forTesting({
    required GithubClient client,
    required GithubTokenStore tokens,
    bool Function(String url)? opener,
    GithubConfig config = const GithubConfig(),
  }) {
    final store = GithubStore._(
      client: client,
      tokens: tokens,
      opener: opener ?? (_) => true,
    );
    store._config = config;
    return store;
  }

  final GithubClient _client;
  final GithubTokenStore _tokens;
  final bool Function(String url) _open;

  // --- configuration -------------------------------------------------------

  GithubConfig _config = const GithubConfig();
  GithubConfig get config => _config;

  /// Applies [config]; the module's `fromMap` pushes it here.
  ///
  /// A cadence change re-arms the timer, and a change to *what is listed* —
  /// participating-only, read threads — refetches, because waiting out an
  /// interval reads as the setting not working. The cached `Last-Modified` goes
  /// with it: it describes the answer to the old question.
  void configure(GithubConfig config) {
    final previous = _config;
    if (previous == config) return;
    _config = config;

    final relist = config.participatingOnly != previous.participatingOnly ||
        config.includeRead != previous.includeRead;
    if (relist) _lastModified = null;

    // Nothing is running, so there is nothing to re-arm: the next acquire()
    // picks the new values up.
    if (_leases == 0) return;

    if (relist) {
      unawaited(refresh());
    } else if (config.refreshSeconds != previous.refreshSeconds) {
      _armTimer();
    }
    // The count in the bar comes and goes with `show_count`, and the module
    // rebuilds on `Module.configChanges` for that; nothing here has moved.
  }

  // --- published state -----------------------------------------------------

  GithubAuthStage _stage = GithubAuthStage.signedOut;
  GithubAuthStage get stage => _stage;

  /// The code the user types, while [stage] is
  /// [GithubAuthStage.awaitingAuthorization]. Null otherwise.
  GithubDeviceCode? _deviceCode;
  GithubDeviceCode? get deviceCode => _deviceCode;

  /// The signed-in account, once `/user` has answered. Empty before that, and
  /// the header simply says "GitHub" until it lands — a login is a nicety and
  /// must not gate the list on a second request.
  String _login = '';
  String get login => _login;

  List<GithubNotification> _items = const [];

  /// The threads, newest first.
  List<GithubNotification> get items => List.unmodifiable(_items);

  /// How many of them are unread — the number the bar shows.
  int get unreadCount => _items.where((item) => item.unread).length;

  /// True until the first fetch of a session settles, one way or the other.
  bool _loading = false;
  bool get loading => _loading;

  /// Why there is no list, or empty when there is one.
  ///
  /// A failure is a visible state, not a silence: an empty popup and a broken
  /// one look identical otherwise, and every failure here recovers without a
  /// restart, which is why the popup offers a retry.
  String _error = '';
  String get error => _error;

  /// True while a refresh, a mark-read or the sign-in's first request is in
  /// flight — what the popup's spinner and disabled buttons read.
  bool get busy =>
      _loading ||
      _fetchInFlight ||
      _writesInFlight > 0 ||
      _stage == GithubAuthStage.requestingCode;

  DateTime? _updatedAt;

  /// When the list last came back current — including a 304, which says the
  /// list on screen *is* current.
  ///
  /// Deliberately absent from [_signature]: it moves on every poll, and a poll
  /// that found nothing new must not wake a single surface.
  DateTime? get updatedAt => _updatedAt;

  /// Everything a surface renders, as one comparable string.
  ///
  /// The store's rule: **a read that finds nothing new must not notify.** A bar
  /// module on every monitor listens to this and rebuilds when it fires, and
  /// the common answer from the API is a 304 saying the list has not changed —
  /// so publishing on every poll would be the shell waking once a minute to
  /// redraw what is already on screen.
  String get _signature {
    final buffer = StringBuffer()
      ..write(_stage.name)
      ..write('|')
      ..write(_login)
      ..write('|')
      ..write(_error)
      ..write('|')
      ..write(_loading)
      ..write('|')
      ..write(busy)
      ..write('|')
      ..write(_deviceCode?.userCode ?? '');
    for (final item in _items) {
      buffer
        ..write('|')
        ..write(item.id)
        ..write(item.unread)
        ..write(item.title)
        ..write(item.repository)
        ..write(item.reason)
        ..write(item.type.name)
        ..write(item.updatedAt);
    }
    return buffer.toString();
  }

  /// What the last notify said. Empty until the first one, so that one always
  /// happens.
  String _published = '';

  /// Notifies, unless nothing a surface renders has moved.
  void _publish() {
    final signature = _signature;
    if (signature == _published) return;
    _published = signature;
    notifyListeners();
  }


  // --- polling -------------------------------------------------------------

  int _leases = 0;
  Timer? _timer;
  bool _fetchInFlight = false;
  int _writesInFlight = 0;

  /// The token, once read off disk or granted by a sign-in. Held in memory so
  /// every request is not a file read.
  String? _token;

  /// The previous page's `Last-Modified`, echoed back as `If-Modified-Since`.
  /// An unchanged list then comes back as a 304, which costs no rate-limit
  /// quota — this is what lets the module poll at GitHub's own cadence.
  String? _lastModified;

  /// What the server asked for in `X-Poll-Interval`, in seconds. The interval
  /// actually used is the longer of this and the configured one: GitHub's
  /// number is a floor it enforces, not a suggestion.
  int? _serverInterval;

  /// Bumped by [signOut] and [cancelSignIn]; the device-flow loop compares it
  /// and gives up when it has moved. A cancelled sign-in must not finish half
  /// a minute later and log the user in anyway.
  int _signInGeneration = 0;

  /// Guards the one-time token read, which is async: two panels acquiring in
  /// the same turn must not both read the file and both start a poll.
  Future<void>? _loadingToken;

  /// Take a lease. The first one loads the saved token and, if there is one,
  /// fetches immediately rather than making the first consumer wait an interval.
  void acquire() {
    _leases++;
    if (_leases == 1) unawaited(_start());
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases > 0) return;
    _stopTimer();
    // A sign-in the user walked away from: the module is off the bar and
    // nothing can show the code any more, so the poll must not outlive it.
    if (_stage != GithubAuthStage.signedIn) cancelSignIn();
  }

  @visibleForTesting
  int get leaseCount => _leases;

  @visibleForTesting
  bool get polling => _timer != null;

  Future<void> _start() async {
    await _loadToken();
    if (_leases == 0 || _token == null) return;
    // The timer is armed by the fetch itself, from its `finally` — including
    // when this one is a no-op because a `configure` got there first.
    await refresh();
  }

  Future<void> _loadToken() {
    if (_token != null) return Future.value();
    return _loadingToken ??= _tokens.read().then((token) {
      _loadingToken = null;
      if (token == null || _token != null) return;
      _token = token;
      _stage = GithubAuthStage.signedIn;
      _loading = true;
      _publish();
      unawaited(_fetchLogin());
    });
  }

  /// The interval to wait before the next poll: the configured cadence, or the
  /// server's if it wants a longer one.
  Duration get _interval {
    final seconds = [
      _config.refreshSeconds,
      _serverInterval ?? 0,
      kGithubMinPollSeconds,
    ].reduce((a, b) => a > b ? a : b);
    return Duration(seconds: seconds);
  }

  /// One-shot and re-armed after each fetch rather than [Timer.periodic],
  /// because the interval is not a constant: GitHub revises it per response.
  void _armTimer() {
    _timer?.cancel();
    _timer = Timer(_interval, () {
      if (_leases == 0) return;
      unawaited(refresh());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // --- the list ------------------------------------------------------------

  /// Fetch now. Public because the popup offers a retry — a rate limit lifts and
  /// a network comes back, and the shell cannot notice either happening.
  Future<void> refresh() async {
    final token = _token;
    if (token == null || _fetchInFlight) return;
    _fetchInFlight = true;
    // A loader, but only with nothing to show: a refresh behind a list that is
    // already up would replace it with a spinner for no reason.
    if (_items.isEmpty) _loading = true;
    try {
      final page = await _client.fetchNotifications(
        token: token,
        lastModified: _lastModified,
        participating: _config.participatingOnly,
        includeRead: _config.includeRead,
      );
      _serverInterval = page.pollInterval ?? _serverInterval;
      _lastModified = page.lastModified ?? _lastModified;
      _updatedAt = DateTime.now();
      _error = '';
      // A 304 is the common answer and means the list on screen is current.
      // Nothing changed, so nothing is published: every panel on every monitor
      // listens to this, and a notify a minute for a list nobody touched is the
      // wakeup an idle shell exists to avoid.
      if (!page.notModified) _items = page.items;
    } on GithubAuthException catch (e) {
      // The token is gone rather than the network: drop it and go back to
      // signed out, or the popup would offer a retry that can only fail.
      await _forgetToken();
      _error = e.message;
    } on GithubException catch (e) {
      // The last list stays on screen through a failed refresh, with the reason
      // under it — a five-minute-old list beats an empty card.
      _error = e.message;
    } catch (e) {
      _error = 'GitHub unavailable';
      debugPrint('github: $e');
    } finally {
      _loading = false;
      _fetchInFlight = false;
      _publish();
      // Re-armed from here rather than from a periodic timer, so a slow request
      // cannot stack the next one on top of it, and so the server's revised
      // interval takes effect immediately.
      if (_leases > 0 && _token != null) _armTimer();
    }
  }

  Future<void> _fetchLogin() async {
    final token = _token;
    if (token == null) return;
    try {
      final login = await _client.fetchLogin(token);
      if (login.isEmpty || login == _login || _token != token) return;
      _login = login;
      _publish();
    } on GithubAuthException {
      // Handled where it matters — the notification fetch running beside this
      // hits the same wall and is what drops the token.
    } catch (e) {
      debugPrint('github: could not read the account name: $e');
    }
  }

  // --- opening and marking read -------------------------------------------

  /// Opens [item] in the user's browser and, unless `mark_read_on_open` says
  /// otherwise, marks its thread read — which is what clicking a notification on
  /// github.com does.
  ///
  /// A thread with no URL to open — GitHub sends a few, a Discussion among them
  /// — is still marked read rather than doing nothing at all.
  Future<void> open(GithubNotification item) async {
    if (item.url.isNotEmpty && !_open(item.url)) {
      _error = 'Could not open a browser';
      _publish();
      return;
    }
    // Clears a previous failure to open: the one on screen would otherwise
    // outlive the browser coming back.
    _error = '';
    if (_config.markReadOnOpen && item.unread) await markRead(item);
    _publish();
  }

  /// Opens the page the user types their code into.
  ///
  /// Also called for them the moment the code arrives — which is what
  /// `gh auth login` does — so the button beside the code is a second chance
  /// rather than the only one. A browser that will not open is said out loud:
  /// the code on screen is useless without one.
  void openVerificationPage() {
    final code = _deviceCode;
    if (code == null) return;
    if (_open(code.verificationUri)) return;
    _error = 'Could not open a browser. Go to ${code.verificationUri}';
    _publish();
  }

  /// Marks one thread read, on the server and here.
  ///
  /// The row dims the moment it is asked, not when the server answers: the
  /// request is a round trip the user did not ask to wait for, and a failure
  /// puts the row back.
  Future<void> markRead(GithubNotification item) async {
    final token = _token;
    if (token == null || !item.unread) return;
    final previous = _items;
    _items = [
      for (final entry in _items)
        if (entry.id == item.id) _asRead(entry) else entry,
    ];
    _publish();
    _writesInFlight++;
    try {
      await _client.markThreadRead(token: token, id: item.id);
      // The unread thread is gone from the server's default list, so the
      // cached validator no longer describes what a fetch would return.
      _lastModified = null;
    } on GithubAuthException catch (e) {
      await _forgetToken();
      _error = e.message;
    } on GithubException catch (e) {
      _items = previous;
      _error = e.message;
    } catch (e) {
      _items = previous;
      _error = 'Could not mark that read';
      debugPrint('github: $e');
    } finally {
      _writesInFlight--;
      _publish();
    }
  }

  /// Marks everything currently listed read.
  ///
  /// Bounded by [updatedAt] rather than "now": a thread that arrived between the
  /// last fetch and this click is not on screen, and clearing something the user
  /// never saw is how a notification gets lost.
  Future<void> markAllRead() async {
    final token = _token;
    if (token == null || unreadCount == 0) return;
    final previous = _items;
    _items = [for (final entry in _items) _asRead(entry)];
    _publish();
    _writesInFlight++;
    try {
      await _client.markAllRead(token: token, lastReadAt: _updatedAt);
      _lastModified = null;
    } on GithubAuthException catch (e) {
      await _forgetToken();
      _error = e.message;
    } on GithubException catch (e) {
      _items = previous;
      _error = e.message;
    } catch (e) {
      _items = previous;
      _error = 'Could not mark those read';
      debugPrint('github: $e');
    } finally {
      _writesInFlight--;
      _publish();
    }
    // The default list is unread threads only, so with `include_read` off
    // everything just marked read should leave the popup.
    if (!_config.includeRead && _error.isEmpty) await refresh();
  }

  static GithubNotification _asRead(GithubNotification item) =>
      GithubNotification(
        id: item.id,
        title: item.title,
        repository: item.repository,
        repositoryUrl: item.repositoryUrl,
        type: item.type,
        reason: item.reason,
        unread: false,
        updatedAt: item.updatedAt,
        url: item.url,
      );

  // --- the sign-in ---------------------------------------------------------

  /// Runs the device flow: ask for a code, publish it for the popup to show,
  /// then poll until the user has typed it in at github.com.
  ///
  /// Awaitable but not meant to be awaited by a widget — it runs for as long as
  /// the user takes, which is the whole point of publishing the code as state.
  Future<void> signIn() async {
    if (_stage == GithubAuthStage.requestingCode ||
        _stage == GithubAuthStage.awaitingAuthorization ||
        _stage == GithubAuthStage.signedIn) {
      return;
    }
    final generation = ++_signInGeneration;
    _stage = GithubAuthStage.requestingCode;
    _error = '';
    _publish();

    final GithubDeviceCode code;
    try {
      code = await _client.requestDeviceCode(
        clientId: _config.clientId,
        scopes: _config.scopes,
      );
    } on GithubException catch (e) {
      _failSignIn(generation, e.message);
      return;
    } catch (e) {
      debugPrint('github: $e');
      _failSignIn(generation, 'Could not reach GitHub');
      return;
    }
    if (generation != _signInGeneration) return;

    _deviceCode = code;
    _stage = GithubAuthStage.awaitingAuthorization;
    _publish();
    // The code is published first: the browser is about to take the focus, and
    // the card behind it must already say what to type into it.
    openVerificationPage();
    await _pollForToken(code, generation);
  }

  /// The poll loop, at the interval GitHub asked for and no faster: `slow_down`
  /// is the API saying it will start refusing otherwise, and the spec's answer
  /// is five more seconds per occurrence.
  Future<void> _pollForToken(GithubDeviceCode code, int generation) async {
    var interval = Duration(seconds: code.interval);
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));

    while (generation == _signInGeneration) {
      await Future<void>.delayed(interval);
      if (generation != _signInGeneration) return;
      if (DateTime.now().isAfter(deadline)) {
        _failSignIn(generation, 'The sign-in code expired. Try again.');
        return;
      }

      final GithubTokenResult result;
      try {
        result = await _client.pollAccessToken(
          clientId: _config.clientId,
          deviceCode: code.deviceCode,
        );
      } on GithubException catch (e) {
        _failSignIn(generation, e.message);
        return;
      } catch (e) {
        debugPrint('github: $e');
        _failSignIn(generation, 'Could not reach GitHub');
        return;
      }
      if (generation != _signInGeneration) return;

      switch (result) {
        case GithubTokenPending(slowDown: final slowDown):
          if (slowDown) interval += const Duration(seconds: 5);
        case GithubTokenGranted(token: final token):
          await _completeSignIn(token, generation);
          return;
      }
    }
  }

  Future<void> _completeSignIn(String token, int generation) async {
    final saved = await _tokens.write(token);
    if (generation != _signInGeneration) return;
    _token = token;
    _deviceCode = null;
    _stage = GithubAuthStage.signedIn;
    _loading = true;
    // A token that could not be saved still signs this session in: the user did
    // the work, and losing it at the next start-up is better than losing it now.
    // It is not silent, because the sign-in will not have stuck.
    _error = saved ? '' : 'Signed in, but the token could not be saved';
    _publish();
    unawaited(_fetchLogin());
    await refresh();
    if (_leases > 0) _armTimer();
  }

  void _failSignIn(int generation, String message) {
    if (generation != _signInGeneration) return;
    _stage = GithubAuthStage.signedOut;
    _deviceCode = null;
    _error = message;
    _publish();
  }

  /// Abandons a sign-in in progress. The poll loop notices on its next turn.
  void cancelSignIn() {
    if (_stage != GithubAuthStage.requestingCode &&
        _stage != GithubAuthStage.awaitingAuthorization) {
      return;
    }
    _signInGeneration++;
    _stage = GithubAuthStage.signedOut;
    _deviceCode = null;
    _publish();
  }

  /// Forgets the token and everything it fetched.
  ///
  /// It does *not* revoke the grant — only github.com can do that, under
  /// Settings › Applications — so the popup says so rather than implying the
  /// authorisation is gone.
  Future<void> signOut() async {
    _stopTimer();
    await _forgetToken();
    _error = '';
    _publish();
  }

  /// The half of a sign-out that a rejected token triggers as well: drop it,
  /// forget the list, and stop polling for something that can only fail.
  Future<void> _forgetToken() async {
    _signInGeneration++;
    _stopTimer();
    _token = null;
    _login = '';
    _items = const [];
    _lastModified = null;
    _serverInterval = null;
    _updatedAt = null;
    _loading = false;
    _deviceCode = null;
    _stage = GithubAuthStage.signedOut;
    await _tokens.clear();
  }

  /// Seeds a store for a widget test, with no client and no timer behind it.
  @visibleForTesting
  void seed({
    GithubAuthStage stage = GithubAuthStage.signedIn,
    List<GithubNotification> items = const [],
    String login = '',
    String error = '',
    bool loading = false,
    GithubDeviceCode? deviceCode,
    String token = 'seeded-token',
  }) {
    _stage = stage;
    _items = items;
    _login = login;
    _error = error;
    _loading = loading;
    _deviceCode = deviceCode;
    _token = stage == GithubAuthStage.signedIn ? token : null;
    if (items.isNotEmpty) _updatedAt = DateTime.now();
    _publish();
  }

  @override
  void dispose() {
    _stopTimer();
    _signInGeneration++;
    super.dispose();
  }
}
