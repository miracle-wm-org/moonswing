// The headlines, for the whole shell.
//
// `StockStore`'s shape: a singleton `ChangeNotifier` that reads nothing while
// no surface holds a lease, so two news cards — or one on each monitor — share
// one read of each feed rather than making one apiece.
//
// Three things that are its own:
//
// - **Each feed succeeds or fails alone.** The card is a merge of several
//   outlets, and one of them refusing is not a reason to blank the others; a
//   feed that fails keeps its last good stories on the card and is named
//   under them, with a retry.
// - **When the next read is due is derived from when the last one was**, not
//   from a timer's own count. A card added a minute after the last read waits
//   out the rest of the period rather than reading again; one coming back
//   after an hour off screen — or after a suspend, which a `Timer` does not
//   count — reads at once.
// - **A read that changed nothing does not notify.** Most do: a headline list
//   moves a few times an hour.
//
// Flutter-free apart from `ChangeNotifier`.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/news/news_client.dart';
import 'package:moonswing/news/news_config.dart';
import 'package:moonswing/news/news_feed.dart';
import 'package:moonswing/news/news_source.dart';

/// The most headlines the card is handed, newest first. A wire service's day
/// is several hundred; nobody scrolls a desktop card that far.
const int kNewsMaxHeadlines = 60;

/// How soon a read that failed everywhere is tried again, when the configured
/// period is longer: a network that was not up yet at login should not cost
/// the user an hour of an empty card.
const Duration kNewsRetryDelay = Duration(minutes: 5);

/// One feed that could not be read this time round.
typedef NewsFailure = ({String source, String message});

class NewsStore extends ChangeNotifier {
  NewsStore._({NewsClient? client, DateTime Function()? clock})
    : _client = client ?? HttpNewsClient(),
      _now = clock ?? DateTime.now;

  static final NewsStore instance = NewsStore._();

  /// A detached store with an injected client and clock, so a test can take a
  /// lease and read feeds with no network behind it.
  @visibleForTesting
  factory NewsStore.forTesting({
    required NewsClient client,
    NewsConfig config = const NewsConfig(),
    DateTime Function()? clock,
  }) {
    final store = NewsStore._(client: client, clock: clock);
    store._config = config;
    store._feeds = config.feeds;
    return store;
  }

  final NewsClient _client;
  final DateTime Function() _now;

  NewsConfig _config = const NewsConfig();
  NewsConfig get config => _config;

  List<NewsSource> _feeds = const NewsConfig().feeds;

  /// The feeds the config names, resolved, in its order.
  List<NewsSource> get feeds => _feeds;

  /// Applies [config]; `startNewsService` pushes it here on every config
  /// change, so an equal one is the common case and does nothing.
  ///
  /// A change of sources reads at once, because a feed the user has just
  /// switched on is one they are looking at the card for. A change of period
  /// re-arms the timer against the last read.
  void configure(NewsConfig config) {
    final previous = _config;
    if (previous == config) return;
    _config = config;
    if (!listEquals(previous.sources, config.sources)) {
      _feeds = config.feeds;
      final keep = {for (final feed in _feeds) feed.id};
      _bySource.removeWhere((id, _) => !keep.contains(id));
      _failures.removeWhere((id, _) => !keep.contains(id));
      _merge();
      notifyListeners();
      if (_leases > 0) unawaited(refresh());
    } else if (config.refreshMinutes != previous.refreshMinutes) {
      _schedule();
    }
  }

  // --- published state -------------------------------------------------------

  /// The last good stories from each feed, by [NewsSource.id].
  final Map<String, List<NewsHeadline>> _bySource = {};

  /// Why each feed that failed its last read failed, by [NewsSource.id].
  final Map<String, String> _failures = {};

  List<NewsHeadline> _headlines = const [];

  /// Every feed's stories merged, newest first, a story two feeds both
  /// carried shown once, at most [kNewsMaxHeadlines].
  List<NewsHeadline> get headlines => _headlines;

  bool get hasHeadlines => _headlines.isNotEmpty;

  bool _loading = true;

  /// True until the first read settles.
  bool get loading => _loading;

  /// The feeds whose last read failed, in config order.
  List<NewsFailure> get failures => [
    for (final feed in _feeds)
      if (_failures[feed.id] case final message?)
        (source: feed.name, message: message),
  ];

  /// Whether every feed failed — the case the card replaces its list with a
  /// retry for, when there is no list left to show.
  bool get allFailed =>
      _feeds.isNotEmpty && _feeds.every((f) => _failures.containsKey(f.id));

  /// One line for the failures: the reason itself when one feed failed, a
  /// count otherwise. Empty when nothing did.
  String get error {
    final failed = failures;
    if (failed.isEmpty) return '';
    if (failed.length == 1) return failed.single.message;
    if (allFailed) return 'No news source could be reached';
    return '${failed.length} news sources could not be reached';
  }

  DateTime? _updatedAt;

  /// When a read last brought anything back.
  DateTime? get updatedAt => _updatedAt;

  /// When a read was last *attempted*, successful or not — what the next one
  /// is timed from.
  DateTime? _attemptedAt;

  // --- polling ---------------------------------------------------------------

  int _leases = 0;
  Timer? _timer;
  bool _fetchInFlight = false;
  bool _refetchQueued = false;

  /// Take a lease. The first reads at once if the last read is older than the
  /// period, and otherwise arms the timer for the rest of it.
  ///
  /// Does not notify: it runs inside the acquirer's `initState`.
  void acquire() {
    _leases++;
    if (_leases == 1) scheduleMicrotask(_catchUp);
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// The machine woke from a suspend, during which the timer did not run.
  void resumed() {
    if (_leases > 0) _catchUp();
  }

  @visibleForTesting
  int get leaseCount => _leases;

  @visibleForTesting
  bool get polling => _timer != null;

  Duration get _period {
    final configured = Duration(minutes: _config.refreshMinutes);
    if (allFailed && configured > kNewsRetryDelay) return kNewsRetryDelay;
    return configured;
  }

  /// How long since the last attempt, or null when there has been none — or
  /// when the clock has stepped back past it, which is read as "due" rather
  /// than as a negative wait.
  Duration? get _sinceAttempt {
    final at = _attemptedAt;
    if (at == null) return null;
    final elapsed = _now().difference(at);
    return elapsed.isNegative ? null : elapsed;
  }

  void _catchUp() {
    if (_leases == 0) return;
    final since = _sinceAttempt;
    if (since == null || since >= _period) {
      unawaited(refresh());
    } else {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_leases == 0) return;
    final since = _sinceAttempt ?? Duration.zero;
    var delay = _period - since;
    if (delay.isNegative) delay = Duration.zero;
    _timer = Timer(delay, () => unawaited(refresh()));
  }

  /// Read every feed now. Public because the card offers a retry: a failure
  /// here recovers without a restart, and the shell cannot see it happen.
  Future<void> refresh() async {
    if (_fetchInFlight) {
      _refetchQueued = true;
      return;
    }
    _fetchInFlight = true;
    final asked = _feeds;
    final before = _headlines;
    final failuresBefore = Map.of(_failures);
    final wasLoading = _loading;
    try {
      final results = await Future.wait([
        for (final feed in asked) _read(feed),
      ]);
      // The config may have moved while the reads were out; an answer for a
      // feed no longer on the list is dropped.
      final current = {for (final feed in _feeds) feed.id};
      var anyGood = false;
      for (var i = 0; i < asked.length; i++) {
        final id = asked[i].id;
        if (!current.contains(id)) continue;
        switch (results[i]) {
          case (headlines: final headlines?, error: _):
            _bySource[id] = headlines;
            _failures.remove(id);
            anyGood = true;
          case (headlines: _, error: final error?):
            _failures[id] = error;
          case _:
            break;
        }
      }
      final now = _now();
      _attemptedAt = now;
      if (anyGood) _updatedAt = now;
    } finally {
      _fetchInFlight = false;
    }
    _loading = false;
    _merge();
    if (wasLoading ||
        !listEquals(before, _headlines) ||
        !mapEquals(failuresBefore, _failures)) {
      notifyListeners();
    }
    if (_refetchQueued) {
      _refetchQueued = false;
      unawaited(refresh());
      return;
    }
    _schedule();
  }

  Future<({List<NewsHeadline>? headlines, String? error})> _read(
    NewsSource feed,
  ) async {
    try {
      final document = await _client.fetch(feed.url);
      final parsed = parseNewsFeed(
        document,
        sourceName: feed.name,
        preferItemSource: !feed.preset,
      );
      return (headlines: parsed.headlines, error: null);
    } on NewsException catch (e) {
      return (headlines: null, error: '${feed.name}: ${e.message}');
    } on NewsFeedFormatException catch (e) {
      debugPrint('news: ${feed.url}: ${e.message}');
      return (
        headlines: null,
        error: '${feed.name} sent something that is not a news feed',
      );
    } catch (e) {
      debugPrint('news: ${feed.url}: $e');
      return (headlines: null, error: '${feed.name} could not be read');
    }
  }

  /// [_headlines] rebuilt from [_bySource].
  void _merge() {
    _headlines = mergeNewsHeadlines([
      for (final feed in _feeds) _bySource[feed.id] ?? const <NewsHeadline>[],
    ]);
  }

  /// Seeds a store for a widget test, as if a read had just landed.
  @visibleForTesting
  void seed({
    List<NewsHeadline> headlines = const [],
    Map<String, String> failures = const {},
    bool loading = false,
    DateTime? updatedAt,
  }) {
    _bySource
      ..clear()
      ..[_feeds.isEmpty ? '' : _feeds.first.id] = headlines;
    _failures
      ..clear()
      ..addAll(failures);
    _loading = loading;
    _updatedAt = updatedAt ?? (headlines.isEmpty ? null : _now());
    // Seeded is fresh: a lease taken next arms the timer rather than reading
    // over what the test put here.
    _attemptedAt = _now();
    _headlines = mergeNewsHeadlines([headlines]);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// [perFeed] merged into one list: newest first, a story with no date after
/// every dated one (in feed order, then document order), a story carried by
/// two feeds — the same link, or the same headline — kept once, and at most
/// [limit] of them.
List<NewsHeadline> mergeNewsHeadlines(
  List<List<NewsHeadline>> perFeed, {
  int limit = kNewsMaxHeadlines,
}) {
  final indexed = <(int, NewsHeadline)>[];
  for (final feed in perFeed) {
    for (final headline in feed) {
      indexed.add((indexed.length, headline));
    }
  }
  // `List.sort` is not stable, so the original position is the tie-break.
  indexed.sort((a, b) {
    final at = a.$2.published;
    final bt = b.$2.published;
    if (at != null && bt != null) {
      final byTime = bt.compareTo(at);
      if (byTime != 0) return byTime;
    } else if (at != null) {
      return -1;
    } else if (bt != null) {
      return 1;
    }
    return a.$1.compareTo(b.$1);
  });
  final seenLinks = <String>{};
  final seenTitles = <String>{};
  final merged = <NewsHeadline>[];
  for (final (_, headline) in indexed) {
    final titleKey = _titleKey(headline.title);
    if (!seenLinks.add(headline.link)) continue;
    if (titleKey.isNotEmpty && !seenTitles.add(titleKey)) continue;
    merged.add(headline);
    if (merged.length >= limit) break;
  }
  return List.unmodifiable(merged);
}

/// A headline with case, punctuation and spacing taken out — what makes the
/// same wire story under two outlets' feeds one row.
String _titleKey(String title) => title.toLowerCase().replaceAll(_nonWord, '');

final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
