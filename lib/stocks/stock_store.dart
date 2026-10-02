// The watchlist's quotes, for the whole shell.
//
// The singleton-`ChangeNotifier`-with-leases shape of `WeatherStore`: requests
// exist only while some surface holds a lease, so a crawl on each of two
// monitors and a desktop card besides share one poll rather than making three.
// The bar module and the desktop widget read *this*, which is what "the same
// source" means — not the same URL fetched twice, the same answer read twice.
//
// Flutter-free apart from `ChangeNotifier`.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/config_store.dart';
import 'package:moonswing/stocks/stock_api.dart';
import 'package:moonswing/stocks/stock_config.dart';
import 'package:moonswing/stocks/stock_quote.dart';

/// How often the store polls while every market on the watchlist is shut.
///
/// Not "never": a closed market still opens, and the store cannot know when
/// from a quote alone — Yahoo's `marketState` says `CLOSED`, not until when.
/// Two minutes is a pre-market print noticed late by at most that, against a
/// night and a weekend of polling every fifteen seconds for the same numbers.
const Duration kStockIdlePoll = Duration(minutes: 2);

/// Where the watchlist is written when it is edited from a surface.
typedef StockSymbolsWriter = void Function(List<String> symbols);

class StockStore extends ChangeNotifier {
  StockStore._({StockClient? client, StockSymbolsWriter? writer})
      : _client = client ?? YahooFinanceClient(),
        _writer = writer ?? _writeConfig;

  static final StockStore instance = StockStore._();

  /// A detached store with an injected client, so a widget test can take a
  /// real lease without a network behind it, and an injected writer, so an
  /// add from the popup does not reach for a `config.toml`.
  @visibleForTesting
  factory StockStore.forTesting({
    required StockClient client,
    StockConfig config = const StockConfig(),
    StockSymbolsWriter? writer,
  }) {
    final store = StockStore._(client: client, writer: writer ?? (_) {});
    store._config = config;
    store._symbols = config.symbols;
    return store;
  }

  final StockClient _client;
  final StockSymbolsWriter _writer;

  /// The default writer: `[modules.stocks] symbols`, through the live config
  /// store. Its notify re-runs the module's `fromMap`, which hands the same
  /// list straight back to [configure] — where it is equal, and nothing moves.
  static void _writeConfig(List<String> symbols) {
    try {
      ConfigStore.instance.set(['modules', 'stocks', 'symbols'], symbols);
    } on StateError catch (e) {
      // Only before `initShared`, which is never in the running shell.
      debugPrint('stocks: could not save the watchlist: $e');
    }
  }

  StockConfig _config = const StockConfig();
  StockConfig get config => _config;

  /// The watchlist as it stands — the config's, until a surface edits it, and
  /// then the edit, ahead of the config write coming back round.
  List<String> _symbols = const [];
  List<String> get symbols => _symbols;

  /// Applies [config]; the module's `fromMap` pushes it here.
  ///
  /// A watchlist edit refetches at once, because a ticker the user has just
  /// typed into the file is one they are waiting to see; a cadence change
  /// re-arms the timer.
  void configure(StockConfig config) {
    final previous = _config;
    if (previous == config) return;
    _config = config;
    final listMoved = !listEquals(_symbols, config.symbols);
    if (listMoved) {
      _symbols = config.symbols;
      _reorder();
    }
    if (_leases == 0) {
      if (listMoved) notifyListeners();
      return;
    }
    if (listMoved) {
      notifyListeners();
      unawaited(refresh());
    } else if (config.refreshSeconds != previous.refreshSeconds) {
      _schedule();
    }
  }

  // --- published state -------------------------------------------------------

  List<StockQuote> _quotes = const [];

  /// The quotes for [symbols] that the source answered, in watchlist order.
  List<StockQuote> get quotes => _quotes;

  /// Every quote the source has ever answered for a symbol still on the list,
  /// so a removal and re-add does not blank a row until the next poll.
  final Map<String, StockQuote> _bySymbol = {};

  StockQuote? quoteFor(String symbol) => _bySymbol[symbol];

  /// Symbols on the list the last successful fetch did not answer for — a
  /// typo, a delisting, or a ticker that only exists on another exchange
  /// under a suffix. Shown, not dropped: a symbol that silently never
  /// appears reads as the strip being broken.
  Set<String> _missing = const {};
  Set<String> get missing => _missing;

  /// True until the first fetch settles. Both surfaces show a loader of their
  /// own size in its place, so nothing beside them shifts when quotes land.
  bool _loading = true;
  bool get loading => _loading;

  /// Why the quotes on screen are not fresh, or empty when they are. The last
  /// good quotes stay on screen under it.
  String _error = '';
  String get error => _error;

  bool get hasQuotes => _quotes.isNotEmpty;

  DateTime? _updatedAt;

  /// When the quotes on screen were fetched.
  DateTime? get updatedAt => _updatedAt;

  /// Whether anything on the list is trading — the test that picks between
  /// [StockConfig.refreshSeconds] and [kStockIdlePoll].
  bool get anyMarketOpen => _quotes.any((q) => q.isActive);

  // --- polling ---------------------------------------------------------------

  int _leases = 0;
  Timer? _timer;
  bool _fetchInFlight = false;

  /// A refresh asked for while one was in flight — after an add, say — runs
  /// once that one lands rather than being dropped, because the one in flight
  /// was asked for the list as it was.
  bool _refetchQueued = false;

  /// Take a lease. The first one fetches at once and starts the poll.
  ///
  /// Does not notify: it runs inside the acquirer's `initState`.
  void acquire() {
    _leases++;
    // A microtask rather than a call: with nothing to request, [refresh]
    // settles without awaiting anything, and its notify would land inside
    // the acquirer's `initState`.
    if (_leases == 1) scheduleMicrotask(() => unawaited(refresh()));
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @visibleForTesting
  int get leaseCount => _leases;

  @visibleForTesting
  bool get polling => _timer != null;

  /// One timer, re-armed after every fetch rather than periodic: the period
  /// depends on what the last fetch said about the markets.
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_leases == 0) return;
    final active = Duration(seconds: _config.refreshSeconds);
    final Duration delay;
    if (_error.isNotEmpty) {
      // Backed off rather than hammered: a rate limit answered every fifteen
      // seconds stays a rate limit.
      delay = active < const Duration(minutes: 1)
          ? const Duration(minutes: 1)
          : active;
    } else if (_quotes.isNotEmpty && !anyMarketOpen) {
      delay = active > kStockIdlePoll ? active : kStockIdlePoll;
    } else {
      delay = active;
    }
    _timer = Timer(delay, () => unawaited(refresh()));
  }

  /// Fetch now. Public because every surface offers a retry: a failure here
  /// recovers without a restart, and the shell cannot see it happen.
  Future<void> refresh() async {
    if (_fetchInFlight) {
      _refetchQueued = true;
      return;
    }
    _fetchInFlight = true;
    final asked = _symbols;
    try {
      if (asked.isEmpty) {
        _bySymbol.clear();
        _missing = const {};
        _error = '';
      } else {
        final answered = await _client.quotes(asked);
        for (final quote in answered) {
          _bySymbol[quote.symbol.toUpperCase()] = quote;
        }
        final got = {for (final q in answered) q.symbol.toUpperCase()};
        _missing = {for (final s in asked) if (!got.contains(s)) s};
        _updatedAt = DateTime.now();
        _error = '';
      }
    } on StockException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Quotes unavailable';
      debugPrint('stocks: $e');
    } finally {
      _fetchInFlight = false;
    }
    final before = _quotes;
    final wasLoading = _loading;
    _loading = false;
    _reorder();
    // A poll that changed nothing must not notify: every crawl on every
    // monitor listens, and the desktop card besides.
    if (wasLoading ||
        !listEquals(before, _quotes) ||
        _lastNotifiedError != _error ||
        !setEquals(_lastNotifiedMissing, _missing)) {
      _lastNotifiedError = _error;
      _lastNotifiedMissing = _missing;
      notifyListeners();
    }
    if (_refetchQueued) {
      _refetchQueued = false;
      unawaited(refresh());
      return;
    }
    _schedule();
  }

  String _lastNotifiedError = '';
  Set<String> _lastNotifiedMissing = const {};

  /// [_quotes] rebuilt from [_bySymbol] in [_symbols] order, and anything no
  /// longer on the list forgotten.
  void _reorder() {
    final keep = _symbols.toSet();
    _bySymbol.removeWhere((symbol, _) => !keep.contains(symbol));
    _missing = {for (final s in _missing) if (keep.contains(s)) s};
    _quotes = List.unmodifiable([
      for (final symbol in _symbols) ?_bySymbol[symbol],
    ]);
  }

  // --- editing the watchlist -------------------------------------------------

  /// Adds [symbol] to the end of the list, saves it, and fetches. Returns
  /// false when it is already there or is not a symbol at all.
  bool addSymbol(String symbol) {
    final normalized = normalizeSymbol(symbol);
    if (normalized == null || _symbols.contains(normalized)) return false;
    _setSymbols([..._symbols, normalized]);
    unawaited(refresh());
    return true;
  }

  /// Adds every one of [symbols] not already on the list, in order, with one
  /// save and one fetch.
  void addSymbols(Iterable<String> symbols) {
    final next = [..._symbols];
    for (final symbol in symbols) {
      final normalized = normalizeSymbol(symbol);
      if (normalized != null && !next.contains(normalized)) next.add(normalized);
    }
    if (next.length == _symbols.length) return;
    _setSymbols(next);
    unawaited(refresh());
  }

  /// Takes [symbol] off the list and saves it. Nothing to fetch: the other
  /// quotes have not changed.
  void removeSymbol(String symbol) {
    if (!_symbols.contains(symbol)) return;
    _setSymbols([for (final s in _symbols) if (s != symbol) s]);
  }

  /// Moves [symbol] one place earlier ([delta] -1) or later (+1) in the
  /// crawl.
  void moveSymbol(String symbol, int delta) {
    final from = _symbols.indexOf(symbol);
    if (from < 0) return;
    final to = (from + delta).clamp(0, _symbols.length - 1);
    if (to == from) return;
    final next = [..._symbols]..removeAt(from);
    next.insert(to, symbol);
    _setSymbols(next);
  }

  void _setSymbols(List<String> next) {
    _symbols = List.unmodifiable(next);
    _reorder();
    notifyListeners();
    _writer(_symbols);
  }

  /// Symbols matching [query], for the popup's search. No state of its own:
  /// the popup owns its query, its debounce and its results.
  Future<List<StockSearchResult>> search(String query) =>
      _client.search(query);

  /// Seeds a store for a widget test, with no client call and no timer.
  @visibleForTesting
  void seed({
    List<StockQuote> quotes = const [],
    Set<String> missing = const {},
    String error = '',
    bool loading = false,
  }) {
    for (final quote in quotes) {
      _bySymbol[quote.symbol.toUpperCase()] = quote;
    }
    _missing = missing;
    _error = error;
    _loading = loading;
    if (quotes.isNotEmpty) _updatedAt = DateTime.now();
    _reorder();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
