import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/widgets/desktop_widget.dart';
import 'package:moonswing/desktop/widgets/stocks_widget.dart';
import 'package:moonswing/modules/stocks.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/stocks/stock_api.dart';
import 'package:moonswing/stocks/stock_store.dart';

import 'stock_fakes.dart';

/// The desktop board, pumped on the theme's own card the way the desktop
/// frame draws it.
void main() {
  late FakeStockClient client;

  final quotes = {
    'AAPL': testQuote(
      'AAPL',
      name: 'Apple Inc.',
      price: 227.52,
      change: 2.31,
      percent: 1.03,
      low: 224,
      high: 229,
      open: 225,
    ),
    'MSFT': testQuote(
      'MSFT',
      name: 'Microsoft',
      price: 415.1,
      change: -3.2,
      percent: -0.76,
      low: 412,
      high: 420,
      open: 418,
    ),
  };

  setUp(() {
    client = FakeStockClient(table: Map.of(quotes));
  });

  StockStore seeded(List<String> symbols, {String error = ''}) {
    final store = StockStore.forTesting(
      client: client,
      config: StockConfig(symbols: symbols),
      writer: (_) {},
    )..seed(quotes: [for (final s in symbols) ?quotes[s]], error: error);
    addTearDown(store.dispose);
    return store;
  }

  Future<void> pumpBoard(
    WidgetTester tester,
    StockStore store, {
    Size size = const Size(312, 312),
    VoidCallback? openSettings,
    List<String>? opened,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: size,
              child: PopupCard(
                child: StocksWidget(
                  span: (columns: 3, rows: 3),
                  store: store,
                  openSettings: openSettings,
                  openUrl: (url) {
                    opened?.add(url);
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Nothing on the board animates, so it settles.
    await tester.pumpAndSettle();
  }

  testWidgets('a row per ticker: price, move and the day\'s range',
      (tester) async {
    final store = seeded(['AAPL', 'MSFT']);
    await pumpBoard(tester, store, size: const Size(420, 312));

    expect(tester.takeException(), isNull);
    expect(find.text('Markets'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('Apple Inc.'), findsOneWidget);
    expect(find.text('227.52'), findsOneWidget);
    expect(find.text('+2.31 (+1.03%)'), findsOneWidget);
    expect(find.text('-3.20 (-0.76%)'), findsOneWidget);
    expect(find.byType(StockDayRange), findsNWidgets(2));
    expect(store.leaseCount, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a narrow card sheds the range, then the names, then the header',
      (tester) async {
    final store = seeded(['AAPL', 'MSFT']);

    await pumpBoard(tester, store, size: const Size(300, 312));
    expect(find.byType(StockDayRange), findsNothing);
    expect(find.text('Apple Inc.'), findsOneWidget);

    await pumpBoard(tester, store, size: const Size(204, 96));
    expect(tester.takeException(), isNull);
    expect(find.text('Apple Inc.'), findsNothing);
    expect(find.text('Markets'), findsNothing);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('+1.03%'), findsOneWidget, reason: 'percent alone');
  });

  testWidgets('clicking a row opens its page', (tester) async {
    final store = seeded(['AAPL', 'MSFT']);
    final opened = <String>[];
    await pumpBoard(tester, store, opened: opened);
    await tester.tap(find.text('Microsoft'));
    await tester.pump();
    expect(opened, ['https://finance.yahoo.com/quote/MSFT']);
  });

  testWidgets('an empty watchlist sends the user to add some', (tester) async {
    final store = seeded(const []);
    var settings = 0;
    await pumpBoard(tester, store, openSettings: () => settings++);
    expect(find.text('No tickers on your watchlist'), findsOneWidget);
    await tester.tap(find.text('Add tickers'));
    await tester.pump();
    expect(settings, 1);
  });

  testWidgets('a failure with nothing to show offers a retry', (tester) async {
    client.failWith = const StockException('Yahoo Finance could not be reached');
    final store = StockStore.forTesting(
      client: client,
      config: const StockConfig(symbols: ['AAPL']),
      writer: (_) {},
    );
    addTearDown(store.dispose);

    await pumpBoard(tester, store);
    expect(find.text('Yahoo Finance could not be reached'), findsOneWidget);

    client.failWith = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('227.52'), findsOneWidget);
  });

  testWidgets('a failed poll keeps the prices, with the reason under them',
      (tester) async {
    final store = seeded(['AAPL']);
    client.failWith = const StockException('Yahoo Finance answered 503');
    await pumpBoard(tester, store);

    expect(find.text('227.52'), findsOneWidget);
    expect(find.text('Yahoo Finance answered 503'), findsOneWidget);
  });

  testWidgets('the bar and the desktop read one store, one poll',
      (tester) async {
    final store = seeded(['AAPL', 'MSFT']);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Column(
            children: [
              StockTicker(store: store),
              SizedBox(
                width: 420,
                height: 312,
                child: StocksWidget(
                  span: (columns: 3, rows: 3),
                  store: store,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(store.leaseCount, 2);
    expect(client.quoteCalls, 1, reason: 'two surfaces, one request');

    // A ticker added from one surface is on the other on the same frame.
    client.table['NVDA'] = testQuote('NVDA', name: 'NVIDIA', price: 120);
    store.addSymbol('NVDA');
    await tester.pump();
    await tester.pump();
    expect(find.text('NVDA'), findsNWidgets(3),
        reason: 'twice in the crawl, once on the board');
  });

  test('registers as a desktop widget a user can add', () {
    expect(stocksDesktopWidget.type, 'stocks');
    expect(stocksDesktopWidget.name, 'Stock market');
    expect(stocksDesktopWidget.minSpan, (columns: 2, rows: 1));
    expect(stocksDesktopWidget.defaultSpan, (columns: 3, rows: 3));
    DesktopWidgetRegistry.register(stocksDesktopWidget);
    addTearDown(DesktopWidgetRegistry.clear);
    expect(DesktopWidgetRegistry.lookup('stocks'), stocksDesktopWidget);
  });
}
