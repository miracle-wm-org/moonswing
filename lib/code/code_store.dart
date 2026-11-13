// The Code tab's data for the whole shell: what every linked forge says is
// waiting on the user, read on one timer.
//
// The singleton-`ChangeNotifier`-with-leases shape `GithubStore` has, and for
// its reason: the reads exist only while something holds a lease, and the only
// thing that takes one is the Code tab while it is the tab showing — an
// overview open on the calendar, or a shell nobody has opened the tab in, never
// touches either forge.
//
// The accounts are not here. GitHub's sign-in and token are
// `GithubAccountStore`'s and GitLab's are `GitlabAccountStore`'s, behind
// Settings › Accounts; this store listens to both for the account coming and
// going and asks each for its token per request. GitHub's *notifications* are
// not here either: they are `GithubStore`'s, which the bar module already polls
// on GitHub's own cadence, and the tab leases that store beside this one rather
// than reading the same inbox twice. GitLab's inbox — its to-dos — has no other
// reader, so it is read here with the rest.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/code/code_config.dart';
import 'package:moonswing/code/code_github.dart';
import 'package:moonswing/code/code_model.dart';
import 'package:moonswing/github/github_account_store.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/gitlab/gitlab_account_store.dart';
import 'package:moonswing/gitlab/gitlab_api.dart';

/// One forge's half of the store.
class _Source {
  CodeSnapshot? snapshot;
  String error = '';
  bool fetching = false;

  /// The token [snapshot] was read with. A different one is a different
  /// account, and nothing read under the old one is shown under the new.
  String? token;

  void clear() {
    snapshot = null;
    error = '';
  }
}

/// Every linked forge's review requests, changes, issues and shipped work.
class CodeStore extends ChangeNotifier {
  CodeStore._({
    GithubAccountStore? github,
    GitlabAccountStore? gitlab,
    CodeGithubClient? githubClient,
    bool Function(String url)? opener,
    DateTime Function()? clock,
  }) : github = github ?? GithubAccountStore.instance,
       gitlab = gitlab ?? GitlabAccountStore.instance,
       _githubClient = githubClient ?? const HttpCodeGithubClient(),
       _open = opener ?? openUriWithDefault,
       _clock = clock ?? DateTime.now {
    _sources[CodeProvider.github]!.token = this.github.token;
    _sources[CodeProvider.gitlab]!.token = this.gitlab.token;
    this.github.addListener(_onGithub);
    this.gitlab.addListener(_onGitlab);
  }

  static final CodeStore instance = CodeStore._();

  /// A detached store for tests: injected accounts (each over a fake client),
  /// a fake GitHub reader, an opener that records, and a clock the test moves.
  @visibleForTesting
  factory CodeStore.forTesting({
    required GithubAccountStore github,
    required GitlabAccountStore gitlab,
    required CodeGithubClient githubClient,
    bool Function(String url)? opener,
    DateTime Function()? clock,
    CodeConfig config = const CodeConfig(),
  }) => CodeStore._(
    github: github,
    gitlab: gitlab,
    githubClient: githubClient,
    opener: opener ?? (_) => true,
    clock: clock,
  ).._config = config;

  final GithubAccountStore github;
  final GitlabAccountStore gitlab;
  final CodeGithubClient _githubClient;
  final bool Function(String url) _open;
  final DateTime Function() _clock;

  /// The time the tab measures ages against — the injected clock in a test.
  DateTime now() => _clock();

  // --- configuration -------------------------------------------------------

  CodeConfig _config = const CodeConfig();
  CodeConfig get config => _config;

  /// Applies `[code]`. A new cadence re-arms the timer; a new shipped window
  /// is a different question, so it is asked at once. A new staleness
  /// threshold changes nothing read — the tab re-derives it — but it changes
  /// what is drawn, so it publishes.
  void configure(CodeConfig config) {
    final previous = _config;
    if (previous == config) return;
    _config = config;
    if (_leases > 0) {
      if (config.shippedDays != previous.shippedDays) {
        unawaited(refresh());
      } else if (config.refreshMinutes != previous.refreshMinutes) {
        _armTimer();
      }
    }
    _publish();
  }

  // --- published state -----------------------------------------------------

  final Map<CodeProvider, _Source> _sources = {
    for (final p in CodeProvider.values) p: _Source(),
  };

  /// Whether [provider] has an account linked.
  bool linked(CodeProvider provider) => switch (provider) {
    CodeProvider.github => github.signedIn,
    CodeProvider.gitlab => gitlab.signedIn,
  };

  /// The forges with an account linked, in the order the tab draws them.
  List<CodeProvider> get linkedProviders => [
    for (final p in CodeProvider.values)
      if (linked(p)) p,
  ];

  /// Whether both accounts have been read off disk, so "not linked" is an
  /// answer rather than a guess.
  bool get accountsLoaded => github.loaded && gitlab.loaded;

  /// What [provider] last said, or null before its first answer.
  CodeSnapshot? snapshotOf(CodeProvider provider) =>
      linked(provider) ? _sources[provider]!.snapshot : null;

  /// Every linked forge's last answer.
  Map<CodeProvider, CodeSnapshot> get snapshots => {
    for (final p in linkedProviders) p: ?_sources[p]!.snapshot,
  };

  /// Why [provider]'s last read failed, or empty. The last good answer stays
  /// on screen under it.
  String errorOf(CodeProvider provider) =>
      linked(provider) ? _sources[provider]!.error : '';

  /// Whether [provider] is being read for the first time, with nothing to
  /// show yet — what a loader stands in for.
  bool loadingOf(CodeProvider provider) {
    final source = _sources[provider]!;
    return linked(provider) &&
        source.snapshot == null &&
        source.error.isEmpty &&
        (source.fetching || _leases > 0);
  }

  /// Whether any read or write is in flight — the refresh button's spinner.
  bool get busy =>
      _writes > 0 || _sources.values.any((source) => source.fetching);

  String _actionError = '';

  /// Why the last thing the user did — open a page, mark a to-do done — did
  /// not happen. Separate from a forge's read error, which is about the lists.
  String get actionError => _actionError;

  void clearActionError() {
    if (_actionError.isEmpty) return;
    _actionError = '';
    _publish();
  }

  /// Everything a surface renders, as one string.
  ///
  /// **A read that finds nothing new must not notify** — the common answer is
  /// the lists exactly as they were. The hour is in it because ages and
  /// staleness are derived against the clock when the tab builds: a poll that
  /// finds nothing new in a new hour is the one that moves "5h" to "6h", and
  /// at most one in twelve of them does.
  String get _signature {
    final buffer = StringBuffer()
      ..write(_config.hashCode)
      ..write('|')
      ..write(accountsLoaded)
      ..write('|')
      ..write(busy)
      ..write('|')
      ..write(_actionError)
      ..write('|')
      ..write(_clock().toUtc().toIso8601String().substring(0, 13));
    for (final p in CodeProvider.values) {
      buffer
        ..write('§')
        ..write(linked(p))
        ..write(loadingOf(p))
        ..write(errorOf(p))
        ..write(snapshotOf(p)?.signature);
    }
    return buffer.toString();
  }

  String _published = '';

  void _publish() {
    final signature = _signature;
    if (signature == _published) return;
    _published = signature;
    notifyListeners();
  }

  // --- leases and the timer -----------------------------------------------

  int _leases = 0;
  Timer? _timer;
  int _writes = 0;

  /// Take a lease. The first reads both accounts off disk and then both forges
  /// at once, rather than making the tab wait an interval.
  void acquire() {
    _leases++;
    if (_leases == 1) unawaited(_start());
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases > 0) return;
    _timer?.cancel();
    _timer = null;
  }

  @visibleForTesting
  int get leaseCount => _leases;

  @visibleForTesting
  bool get polling => _timer != null;

  Future<void> _start() async {
    await Future.wait([github.load(), gitlab.load()]);
    if (_leases == 0) return;
    await refresh();
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer(Duration(minutes: _config.refreshMinutes), () {
      if (_leases == 0) return;
      unawaited(refresh());
    });
  }

  void _onGithub() => _onAccount(CodeProvider.github, github.token);
  void _onGitlab() => _onAccount(CodeProvider.gitlab, gitlab.token);

  /// An account came, went, or changed. A different token is a different
  /// account: what was read under the old one goes, and with a lease held the
  /// new one is read at once.
  void _onAccount(CodeProvider provider, String? token) {
    final source = _sources[provider]!;
    if (token != source.token) {
      source
        ..token = token
        ..clear();
      if (token != null && _leases > 0) unawaited(_fetch(provider));
    }
    _publish();
  }

  // --- reading -------------------------------------------------------------

  /// Reads every linked forge now. Public because the tab offers a refresh, and
  /// a retry after a failure — a network coming back is not something the
  /// shell can see happen.
  Future<void> refresh() async {
    await Future.wait([
      for (final p in CodeProvider.values)
        if (linked(p)) _fetch(p),
    ]);
    if (_leases > 0) _armTimer();
  }

  Future<void> _fetch(CodeProvider provider) async {
    final source = _sources[provider]!;
    final token = source.token;
    if (token == null || source.fetching) return;
    source.fetching = true;
    _publish();
    final since = _clock().subtract(Duration(days: _config.shippedDays));
    try {
      final snapshot = switch (provider) {
        CodeProvider.github => await github.withToken(
          (token) => _githubClient.fetch(
            token: token,
            login: github.login,
            since: since,
          ),
        ),
        CodeProvider.gitlab => await gitlab.withToken(
          (instance, token) => gitlab.client.fetchDashboard(
            instance: instance,
            token: token,
            username: gitlab.username,
            since: since,
          ),
        ),
      };
      // Signed out, or in as somebody else, while it was in flight.
      if (source.token != token) return;
      source
        ..snapshot = snapshot
        ..error = '';
    } on GithubAuthException {
      // The account has signed out, with the reason on its card, and
      // [_onAccount] has emptied this half.
    } on GitlabAuthException {
      // Likewise.
    } on GithubException catch (e) {
      if (source.token == token) source.error = e.message;
    } on GitlabException catch (e) {
      if (source.token == token) source.error = e.message;
    } catch (e) {
      debugPrint('code: ${provider.name}: $e');
      if (source.token == token) source.error = '${provider.label} unavailable';
    } finally {
      source.fetching = false;
      _publish();
    }
  }

  // --- acting --------------------------------------------------------------

  /// Opens [url] in the browser. Says so when there is none.
  bool open(String url) {
    if (url.isNotEmpty && _open(url)) {
      clearActionError();
      return true;
    }
    _actionError = 'Could not open a browser';
    _publish();
    return false;
  }

  /// Marks one GitLab to-do done: gone from the list at once, put back if the
  /// instance refuses.
  Future<void> markTodoDone(CodeNotice notice) async {
    final source = _sources[CodeProvider.gitlab]!;
    final before = source.snapshot;
    if (before == null || notice.provider != CodeProvider.gitlab) return;
    source.snapshot = _withInbox(before, [
      for (final n in before.inbox)
        if (n.id != notice.id) n,
    ]);
    await _write(
      source,
      before,
      (instance, token) => gitlab.client.markTodoDone(
        instance: instance,
        token: token,
        id: notice.id,
      ),
    );
  }

  /// Marks every GitLab to-do done.
  Future<void> markAllTodosDone() async {
    final source = _sources[CodeProvider.gitlab]!;
    final before = source.snapshot;
    if (before == null || before.inbox.isEmpty) return;
    source.snapshot = _withInbox(before, const []);
    await _write(
      source,
      before,
      (instance, token) =>
          gitlab.client.markAllTodosDone(instance: instance, token: token),
    );
  }

  Future<void> _write(
    _Source source,
    CodeSnapshot before,
    Future<void> Function(Uri instance, String token) request,
  ) async {
    _writes++;
    _actionError = '';
    _publish();
    try {
      await gitlab.withToken(request);
    } on GitlabAuthException {
      // Signed out by the account.
    } on GitlabException catch (e) {
      source.snapshot = before;
      _actionError = e.message;
    } catch (e) {
      debugPrint('code: gitlab: $e');
      source.snapshot = before;
      _actionError = 'Could not mark that done';
    } finally {
      _writes--;
      _publish();
    }
  }

  static CodeSnapshot _withInbox(CodeSnapshot s, List<CodeNotice> inbox) =>
      CodeSnapshot(
        reviews: s.reviews,
        authored: s.authored,
        assigned: s.assigned,
        merged: s.merged,
        inbox: inbox,
        reviewsTotal: s.reviewsTotal,
        authoredTotal: s.authoredTotal,
        assignedTotal: s.assignedTotal,
      );

  /// Seeds a store for a widget test, with nothing behind it.
  @visibleForTesting
  void seed(
    CodeProvider provider, {
    CodeSnapshot? snapshot,
    String error = '',
  }) {
    final source = _sources[provider]!;
    source
      ..token = switch (provider) {
        CodeProvider.github => github.token,
        CodeProvider.gitlab => gitlab.token,
      }
      ..snapshot = snapshot
      ..error = error;
    _publish();
  }

  @override
  void dispose() {
    _timer?.cancel();
    github.removeListener(_onGithub);
    gitlab.removeListener(_onGitlab);
    super.dispose();
  }
}
