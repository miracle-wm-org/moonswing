// The titles behind GitHub links: what `https://github.com/o/r/pull/12` is
// called and whether it is still open, for any surface that would rather show
// that than an address — the todo board's cards first.
//
// The shape is the leased stores' with the lease turned per link. There is no
// poller: a link is read when something asks to show it, kept for
// [GithubLinkStore.freshFor], and read again only when something asks after
// that. A board nobody opens costs no request, and one opened twice in a minute
// costs one per link.
//
// Each link is a `ValueListenable` of its own, which is what keeps one title
// arriving from rebuilding every card on the board. The store itself notifies
// only when the account changes — every answer read under the old token is
// dropped then, since a private repository's title is that account's to see.
//
// Nothing here signs anyone in. Signed out, [GithubLinkStore.enabled] is false
// and a surface shows the address as it was typed.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:moonswing/github/github_account_store.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_links.dart';

/// What is known about one link.
@immutable
class GithubLinkState {
  const GithubLinkState({this.issue, this.error = '', this.loading = false});

  /// Not asked yet, or asked and not answered.
  static const GithubLinkState pending = GithubLinkState(loading: true);

  /// The last answer. Kept through a failed refresh: the last good value stays
  /// on screen.
  final GithubIssue? issue;

  /// Why the last read failed, or empty.
  final String error;

  /// True until the first answer, either way.
  final bool loading;

  @override
  bool operator ==(Object other) =>
      other is GithubLinkState &&
      other.issue == issue &&
      other.error == error &&
      other.loading == loading;

  @override
  int get hashCode => Object.hash(issue, error, loading);

  @override
  String toString() =>
      'GithubLinkState(${issue ?? '-'}, error: "$error", loading: $loading)';
}

class _Entry extends ValueNotifier<GithubLinkState> {
  _Entry(this.ref) : super(GithubLinkState.pending);

  final GithubRef ref;

  /// When the last answer — success or failure — came back.
  DateTime? answeredAt;
  bool queued = false;
}

/// Every GitHub link the shell has been asked to show, and its title.
class GithubLinkStore extends ChangeNotifier {
  GithubLinkStore._({
    GithubAccountStore? account,
    DateTime Function()? clock,
    this.freshFor = const Duration(minutes: 10),
    this.retryAfter = const Duration(minutes: 1),
  }) : account = account ?? GithubAccountStore.instance,
       _now = clock ?? DateTime.now {
    _token = this.account.token;
    this.account.addListener(_onAccount);
  }

  static final GithubLinkStore instance = GithubLinkStore._();

  /// A detached store over [account], whose client is the fake a test hands
  /// it, on a [clock] the test moves.
  @visibleForTesting
  factory GithubLinkStore.forTesting({
    required GithubAccountStore account,
    DateTime Function()? clock,
    Duration freshFor = const Duration(minutes: 10),
    Duration retryAfter = const Duration(minutes: 1),
  }) => GithubLinkStore._(
    account: account,
    clock: clock,
    freshFor: freshFor,
    retryAfter: retryAfter,
  );

  final GithubAccountStore account;
  final DateTime Function() _now;

  /// How long an answer is shown before the next look reads it again — long
  /// enough that opening the board twice is not twice the requests, short
  /// enough that a pull request merged this morning does not still say open.
  final Duration freshFor;

  /// How long a failure stands before the next look tries again. Short,
  /// because most of them are a network that has since come back.
  final Duration retryAfter;

  /// At most this many requests at once. A board with forty links on it is
  /// forty reads the moment it opens, and GitHub asks clients not to fire
  /// those all at the same time.
  static const int _maxInFlight = 4;

  final Map<String, _Entry> _entries = {};
  final Queue<_Entry> _queue = Queue();
  int _inFlight = 0;

  /// Bumped with the account, so an answer read under the old token is
  /// dropped rather than shown under the new one.
  int _generation = 0;
  String? _token;

  /// Whether links can be resolved at all: there is a GitHub account.
  bool get enabled => account.signedIn;

  /// What [ref] is, as a listenable that changes when the answer does.
  ///
  /// Asking is what reads it: the first time, and again once the last answer
  /// is older than [freshFor] (or [retryAfter], for a failure). The read is
  /// queued, never made here, so this is safe from `build` and never notifies
  /// before it returns.
  ValueListenable<GithubLinkState> watch(GithubRef ref) {
    final entry = _entries.putIfAbsent(ref.key, () => _Entry(ref));
    if (enabled && !entry.queued && _due(entry)) {
      entry.queued = true;
      _queue.add(entry);
      scheduleMicrotask(_pump);
    }
    return entry;
  }

  bool _due(_Entry entry) {
    final at = entry.answeredAt;
    if (at == null) return true;
    final state = entry.value;
    final wait = state.error.isNotEmpty ? retryAfter : freshFor;
    final age = _now().difference(at);
    // A clock stepped backwards makes every answer look fresh forever; read
    // that as stale instead.
    return age.isNegative || age >= wait;
  }

  void _pump() {
    while (_inFlight < _maxInFlight && _queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      _inFlight++;
      unawaited(_read(entry, _generation));
    }
  }

  Future<void> _read(_Entry entry, int generation) async {
    final ref = entry.ref;
    GithubLinkState next;
    try {
      final issue = await account.withToken(
        (token) => account.client.fetchIssue(
          token: token,
          owner: ref.owner,
          repo: ref.repo,
          number: ref.number,
        ),
      );
      next = GithubLinkState(issue: issue);
    } on GithubException catch (e) {
      next = GithubLinkState(issue: entry.value.issue, error: e.message);
    } catch (e) {
      debugPrint('github: could not read ${ref.fullLabel}: $e');
      next = GithubLinkState(
        issue: entry.value.issue,
        error: 'Could not reach GitHub',
      );
    } finally {
      _inFlight--;
    }
    if (generation == _generation) {
      entry
        ..queued = false
        ..answeredAt = _now()
        ..value = next;
    }
    _pump();
  }

  void _onAccount() {
    final token = account.token;
    if (token == _token) return;
    _token = token;
    _generation++;
    _queue.clear();
    // Dropped, not disposed: a chip still listening lets go of its entry when
    // the notify below rebuilds it onto a new one.
    _entries.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    account.removeListener(_onAccount);
    _generation++;
    _queue.clear();
    super.dispose();
  }
}
