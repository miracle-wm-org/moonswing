// The GitHub notification list for the whole shell.
//
// The singleton-`ChangeNotifier`-with-leases shape `WeatherStore` and
// `MprisStore` have, and for the same reason: one poller for the machine, so a
// bar module on each of two monitors is one request per interval rather than
// two. The requests exist only while something holds a lease — an idle shell
// with the module off its panels never touches the network.
//
// The account is not here. The sign-in, the token and a rejected token's
// sign-out are `GithubAccountStore`'s, behind Settings › Accounts, so that any
// module or desktop widget reading GitHub shares the one linkage; this store
// listens there for the account coming and going and asks it for the token per
// request.
//
// It has no widgets of its own, and the one import that is not `dart:` or
// `ChangeNotifier` is `app_info.dart`: a click opens a page through GIO's
// `g_app_info_launch_default_for_uri` — `xdg-open` with this process's launch
// context — so the browser is adopted into a systemd scope of its own rather
// than left in the shell's cgroup. Tests inject an opener and never reach it.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/github/github_account_store.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_config.dart';

export 'package:moonswing/github/github_account_store.dart'
    show GithubAccountStore, GithubAuthStage;

/// The notification list, and the poll behind it.
class GithubStore extends ChangeNotifier {
  GithubStore._({
    GithubAccountStore? account,
    bool Function(String url)? opener,
  })  : account = account ?? GithubAccountStore.instance,
        _open = opener ?? openUriWithDefault {
    _token = this.account.token;
    this.account.addListener(_onAccount);
  }

  static final GithubStore instance = GithubStore._();

  /// A detached store for tests: an injected account (itself holding a fake
  /// client and a token file under a temporary directory), and an opener that
  /// records rather than launching a browser.
  @visibleForTesting
  factory GithubStore.forTesting({
    required GithubAccountStore account,
    bool Function(String url)? opener,
    GithubConfig config = const GithubConfig(),
  }) {
    final store = GithubStore._(
      account: account,
      opener: opener ?? (_) => true,
    );
    store._config = config;
    return store;
  }

  /// The account every request is made as. Public so a surface showing this
  /// store's list can say whose it is without a second lookup.
  final GithubAccountStore account;
  final bool Function(String url) _open;

  GithubClient get _client => account.client;

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
    // The account's half of `[modules.github]`: which OAuth app the next
    // sign-in runs against, and what it asks for.
    account.configure(clientId: config.clientId, scopes: config.scopes);

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

  /// How far along the account's sign-in is — [account]'s, repeated here so a
  /// surface listening to this store alone renders the right state.
  GithubAuthStage get stage => account.stage;

  /// The signed-in account, once `/user` has answered. Empty before that, and
  /// the header simply says "GitHub" until it lands.
  String get login => account.login;

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

  /// True while a refresh or a mark-read is in flight — what the popup's
  /// spinner and disabled buttons read.
  bool get busy => _loading || _fetchInFlight || _writesInFlight > 0;

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
      ..write(stage.name)
      ..write('|')
      ..write(login)
      ..write('|')
      ..write(account.error)
      ..write('|')
      ..write(_error)
      ..write('|')
      ..write(_loading)
      ..write('|')
      ..write(busy);
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

  /// The token the list on screen was fetched with. Compared with [account]'s
  /// on every change there, so a list fetched as one account is never shown as
  /// the next, and a sign-in landing while a bar holds a lease fetches at once.
  String? _token;

  /// The previous page's `Last-Modified`, echoed back as `If-Modified-Since`.
  /// An unchanged list then comes back as a 304, which costs no rate-limit
  /// quota — this is what lets the module poll at GitHub's own cadence.
  String? _lastModified;

  /// What the server asked for in `X-Poll-Interval`, in seconds. The interval
  /// actually used is the longer of this and the configured one: GitHub's
  /// number is a floor it enforces, not a suggestion.
  int? _serverInterval;

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
  }

  @visibleForTesting
  int get leaseCount => _leases;

  @visibleForTesting
  bool get polling => _timer != null;

  Future<void> _start() async {
    await account.load();
    if (_leases == 0 || _token == null) return;
    // The timer is armed by the fetch itself, from its `finally` — including
    // when this one is a no-op because the account landing got there first.
    await refresh();
  }

  /// The account came, went, or changed.
  ///
  /// A different token is a different inbox: what was fetched under the old
  /// one goes, and with a lease held the new one is read at once rather than an
  /// interval later — a sign-in finished in Settings shows up in the bar the
  /// moment it lands.
  void _onAccount() {
    final token = account.token;
    if (token != _token) {
      _token = token;
      _items = const [];
      _lastModified = null;
      _serverInterval = null;
      _updatedAt = null;
      _error = '';
      _loading = false;
      _stopTimer();
      if (token != null && _leases > 0) unawaited(refresh());
    }
    _publish();
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
    if (_items.isEmpty && !_loading) {
      _loading = true;
      _publish();
    }
    try {
      final page = await account.withToken(
        (token) => _client.fetchNotifications(
          token: token,
          lastModified: _lastModified,
          participating: _config.participatingOnly,
          includeRead: _config.includeRead,
        ),
      );
      // Signed out, or in as somebody else, while it was in flight: this is
      // an answer about an inbox that is no longer the one on screen.
      if (_token != token) return;
      _serverInterval = page.pollInterval ?? _serverInterval;
      _lastModified = page.lastModified ?? _lastModified;
      _updatedAt = DateTime.now();
      _error = '';
      // A 304 is the common answer and means the list on screen is current.
      // Nothing changed, so nothing is published: every panel on every monitor
      // listens to this, and a notify a minute for a list nobody touched is the
      // wakeup an idle shell exists to avoid.
      if (!page.notModified) _items = page.items;
    } on GithubAuthException {
      // The token is gone rather than the network. The account has already
      // signed out, with the reason, and [_onAccount] has emptied the list —
      // a retry here could only fail.
    } on GithubException catch (e) {
      // The last list stays on screen through a failed refresh, with the reason
      // under it — a five-minute-old list beats an empty card.
      if (_token == token) _error = e.message;
    } catch (e) {
      if (_token == token) _error = 'GitHub unavailable';
      debugPrint('github: $e');
    } finally {
      if (_token == token) _loading = false;
      _fetchInFlight = false;
      _publish();
      // Re-armed from here rather than from a periodic timer, so a slow request
      // cannot stack the next one on top of it, and so the server's revised
      // interval takes effect immediately.
      if (_leases > 0 && _token != null) _armTimer();
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
      await account.withToken(
        (token) => _client.markThreadRead(token: token, id: item.id),
      );
      // The unread thread is gone from the server's default list, so the
      // cached validator no longer describes what a fetch would return.
      _lastModified = null;
    } on GithubAuthException {
      // Signed out by the account; the list went with it.
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
      await account.withToken(
        (token) => _client.markAllRead(token: token, lastReadAt: _updatedAt),
      );
      _lastModified = null;
    } on GithubAuthException {
      // Signed out by the account; the list went with it.
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

  /// Seeds a store for a widget test, with no client and no timer behind it.
  /// The account half — [stage], [login], [deviceCode] — is seeded into
  /// [account], which is where it lives.
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
    // Test-only on both ends: this method is itself @visibleForTesting.
    // ignore: invalid_use_of_visible_for_testing_member
    account.seed(
      stage: stage,
      login: login,
      deviceCode: deviceCode,
      token: token,
    );
    _items = items;
    _error = error;
    _loading = loading;
    if (items.isNotEmpty) _updatedAt = DateTime.now();
    _publish();
  }

  @override
  void dispose() {
    _stopTimer();
    account.removeListener(_onAccount);
    super.dispose();
  }
}
