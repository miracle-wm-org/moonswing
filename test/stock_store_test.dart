import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/stocks/stock_api.dart';
import 'package:moonswing/stocks/stock_config.dart';
import 'package:moonswing/stocks/stock_store.dart';

import 'stock_fakes.dart';

/// Lets every pending microtask — a fake fetch is a chain of them — land.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeStockClient client;
  late List<List<String>> written;

  StockStore make({List<String> symbols = const ['AAPL', 'MSFT']}) {
    final store = StockStore.forTesting(
      client: client,
      config: StockConfig(symbols: symbols),
      writer: written.add,
    );
    addTearDown(store.dispose);
    return store;
  }

  setUp(() {
    written = [];
    client = FakeStockClient(table: {
      'AAPL': testQuote('AAPL', price: 200),
      'MSFT': testQuote('MSFT', price: 400, change: -2),
      'NVDA': testQuote('NVDA', price: 120),
      '^GSPC': testQuote('^GSPC', name: 'S&P 500', price: 5600),
      '^DJI': testQuote('^DJI', name: 'Dow 30', price: 42000),
      '^IXIC': testQuote('^IXIC', name: 'Nasdaq', price: 17800),
    });
  });

  test('nothing is fetched until a lease is taken, and once for many', () async {
    final store = make();
    await settle();
    expect(client.quoteCalls, 0, reason: 'no lease, no request');

    store
      ..acquire()
      ..acquire();
    await settle();
    expect(client.quoteCalls, 1, reason: 'two surfaces share one fetch');
    expect(store.quotes.map((q) => q.symbol), ['AAPL', 'MSFT']);
    expect(store.loading, isFalse);
    expect(store.polling, isTrue);

    store.release();
    expect(store.polling, isTrue, reason: 'one lease is still held');
    store.release();
    expect(store.polling, isFalse, reason: 'the last release stops the poll');
  });

  test('acquire does not notify synchronously', () {
    final store = make();
    var notified = 0;
    store.addListener(() => notified++);
    store.acquire();
    expect(notified, 0, reason: 'it runs inside the acquirer\'s initState');
    store.release();
  });

  test('nor with nothing to fetch, when the fetch has nothing to await', () {
    final store = make(symbols: const []);
    var notified = 0;
    store.addListener(() => notified++);
    store.acquire();
    expect(notified, 0);
    store.release();
  });

  test('a symbol the source does not know is reported, not dropped', () async {
    final store = make(symbols: ['AAPL', 'ZZZZ']);
    store.acquire();
    addTearDown(store.release);
    await settle();
    expect(store.quotes.map((q) => q.symbol), ['AAPL']);
    expect(store.missing, {'ZZZZ'});
  });

  test('a failed poll keeps the last quotes and says why', () async {
    final store = make();
    store.acquire();
    addTearDown(store.release);
    await settle();
    expect(store.quotes, hasLength(2));

    client.failWith = const StockException('Yahoo Finance answered 503');
    await store.refresh();
    expect(store.error, 'Yahoo Finance answered 503');
    expect(store.quotes, hasLength(2), reason: 'the last good prices stay');

    client.failWith = null;
    await store.refresh();
    expect(store.error, isEmpty);
  });

  test('a poll that changes nothing does not notify', () async {
    final store = make();
    store.acquire();
    addTearDown(store.release);
    await settle();

    var notified = 0;
    store.addListener(() => notified++);
    await store.refresh();
    expect(notified, 0);

    client.table['AAPL'] = testQuote('AAPL', price: 201);
    await store.refresh();
    expect(notified, 1);
  });

  group('editing the watchlist', () {
    test('add normalizes, saves, notifies and fetches', () async {
      final store = make();
      store.acquire();
      addTearDown(store.release);
      await settle();

      var notified = 0;
      store.addListener(() => notified++);
      expect(store.addSymbol(' nvda '), isTrue);
      expect(store.symbols, ['AAPL', 'MSFT', 'NVDA']);
      expect(written.last, ['AAPL', 'MSFT', 'NVDA']);
      expect(notified, greaterThan(0), reason: 'the row appears at once');

      await settle();
      expect(store.quoteFor('NVDA')?.price, 120);
      expect(client.asked.last, ['AAPL', 'MSFT', 'NVDA']);
    });

    test('add refuses a duplicate and a non-symbol', () {
      final store = make();
      expect(store.addSymbol('aapl'), isFalse);
      expect(store.addSymbol('apple inc'), isFalse);
      expect(written, isEmpty);
    });

    test('addSymbols adds the starter set in one save', () async {
      final store = make(symbols: const []);
      store.addSymbols(kSuggestedStockSymbols);
      expect(store.symbols, ['^GSPC', '^DJI', '^IXIC']);
      expect(written, hasLength(1));
      store.addSymbols(kSuggestedStockSymbols);
      expect(written, hasLength(1), reason: 'nothing new, nothing saved');
    });

    test('remove and move save the list and keep quotes in order', () async {
      final store = make(symbols: ['AAPL', 'MSFT', 'NVDA']);
      store.acquire();
      addTearDown(store.release);
      await settle();

      store.moveSymbol('NVDA', -1);
      expect(store.symbols, ['AAPL', 'NVDA', 'MSFT']);
      expect(store.quotes.map((q) => q.symbol), ['AAPL', 'NVDA', 'MSFT']);

      store.moveSymbol('AAPL', -1);
      expect(written, hasLength(1), reason: 'already first is no move');

      store.removeSymbol('NVDA');
      expect(store.symbols, ['AAPL', 'MSFT']);
      expect(store.quotes.map((q) => q.symbol), ['AAPL', 'MSFT']);
      expect(written.last, ['AAPL', 'MSFT']);
    });

    test('the config write coming back round moves nothing', () async {
      final store = make();
      store.acquire();
      addTearDown(store.release);
      await settle();
      store.addSymbol('NVDA');
      await settle();
      final calls = client.quoteCalls;

      // What `[modules.stocks]` re-parses to once the writer has saved.
      store.configure(StockConfig(symbols: written.last));
      await settle();
      expect(client.quoteCalls, calls);
    });

    test('an add while a fetch is in flight is fetched after it', () async {
      final store = make();
      final gate = client.gate = Completer<void>();
      store.acquire();
      addTearDown(store.release);
      await settle();
      expect(client.quoteCalls, 1);

      store.addSymbol('NVDA');
      await settle();
      expect(client.quoteCalls, 1, reason: 'one fetch at a time');

      client.gate = null;
      gate.complete();
      await settle();
      await settle();
      expect(client.quoteCalls, 2);
      expect(client.asked.last, contains('NVDA'));
      expect(store.quoteFor('NVDA'), isNotNull);
    });
  });

  test('a hand-edited watchlist refetches at once while leased', () async {
    final store = make();
    store.acquire();
    addTearDown(store.release);
    await settle();

    store.configure(const StockConfig(symbols: ['^GSPC']));
    expect(store.symbols, ['^GSPC']);
    await settle();
    expect(client.asked.last, ['^GSPC']);
    expect(store.quotes.single.name, 'S&P 500');
  });

  group('cadence', () {
    testWidgets('polls at refresh_seconds while a market is trading',
        (tester) async {
      final store = make();
      store.acquire();
      await tester.pump();
      expect(client.quoteCalls, 1);

      await tester.pump(const Duration(seconds: 14));
      expect(client.quoteCalls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(client.quoteCalls, 2);

      store.release();
    });

    testWidgets('slows to the idle poll while every market is shut',
        (tester) async {
      client.table
        ..['AAPL'] = testQuote('AAPL', marketState: 'CLOSED', active: false)
        ..['MSFT'] = testQuote('MSFT', marketState: 'CLOSED', active: false);
      final store = make();
      store.acquire();
      await tester.pump();
      expect(store.anyMarketOpen, isFalse);

      await tester.pump(const Duration(seconds: 60));
      expect(client.quoteCalls, 1, reason: 'a closed market is not re-read');
      await tester.pump(kStockIdlePoll - const Duration(seconds: 60));
      expect(client.quoteCalls, 2);

      store.release();
    });

    testWidgets('backs off after a failure', (tester) async {
      client.failWith = const StockException('Yahoo Finance answered 503');
      final store = make();
      store.acquire();
      await tester.pump();
      expect(store.error, isNotEmpty);

      await tester.pump(const Duration(seconds: 15));
      expect(client.quoteCalls, 1, reason: 'not hammered at the active pace');
      await tester.pump(const Duration(seconds: 45));
      expect(client.quoteCalls, 2);

      store.release();
    });

    testWidgets('an empty watchlist makes no request at all', (tester) async {
      final store = make(symbols: const []);
      store.acquire();
      await tester.pump();
      expect(client.quoteCalls, 0);
      expect(store.loading, isFalse);
      store.release();
    });
  });
}
