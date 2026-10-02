// Shared fakes for the stock market tests: an offline [StockClient] and a quote
// builder.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it. Every stock
// test takes a real lease on a real store, and none may reach for Yahoo.

import 'dart:async';

import 'package:moonswing/stocks/stock_api.dart';
import 'package:moonswing/stocks/stock_quote.dart';

StockQuote testQuote(
  String symbol, {
  double price = 100,
  double change = 1.5,
  double? percent,
  String name = '',
  String marketState = 'REGULAR',
  bool active = true,
  double? low,
  double? high,
  double? open,
}) {
  return StockQuote(
    symbol: symbol,
    name: name,
    price: price,
    change: change,
    changePercent: percent ?? change / (price - change) * 100,
    marketState: marketState,
    isActive: active,
    dayLow: low,
    dayHigh: high,
    open: open,
    currency: 'USD',
  );
}

/// A client that answers from a table, counts its calls, and opens nothing.
class FakeStockClient implements StockClient {
  FakeStockClient({
    Map<String, StockQuote>? table,
    this.results = const [],
    this.failWith,
    this.searchFailWith,
  }) : table = table ?? {};

  /// The quotes it knows, by symbol. A symbol not here is "not found".
  final Map<String, StockQuote> table;

  /// What every search answers.
  List<StockSearchResult> results;

  /// When set, [quotes] throws it.
  StockException? failWith;

  /// When set, [search] throws it.
  StockException? searchFailWith;

  /// When set, [quotes] waits on it — the only way to hold a fetch in flight.
  Completer<void>? gate;

  int quoteCalls = 0;
  final List<List<String>> asked = [];
  final List<String> queries = [];

  @override
  Future<List<StockQuote>> quotes(List<String> symbols) async {
    quoteCalls++;
    asked.add(List.of(symbols));
    final wait = gate;
    if (wait != null) await wait.future;
    final failure = failWith;
    if (failure != null) throw failure;
    return [for (final s in symbols) ?table[s]];
  }

  @override
  Future<List<StockSearchResult>> search(String query) async {
    queries.add(query);
    final failure = searchFailWith;
    if (failure != null) throw failure;
    return results;
  }
}
