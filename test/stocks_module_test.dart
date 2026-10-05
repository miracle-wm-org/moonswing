import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/modules/stocks.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/stocks/stock_api.dart';
import 'package:moonswing/stocks/stock_crawl.dart';
import 'package:moonswing/stocks/stock_quote.dart';
import 'package:moonswing/stocks/stock_store.dart';

import 'stock_fakes.dart';

/// The bar's crawl and the card behind it, pumped the way the shell builds
/// them.
void main() {
  late FakeStockClient client;
  late List<List<String>> written;

  final quotes = {
    'AAPL': testQuote(
      'AAPL',
      name: 'Apple Inc.',
      price: 227.52,
      change: 2.31,
      percent: 1.03,
    ),
    'MSFT': testQuote(
      'MSFT',
      name: 'Microsoft',
      price: 415.1,
      change: -3.2,
      percent: -0.76,
    ),
    '^GSPC': testQuote('^GSPC', name: 'S&P 500', price: 5634.5, change: 0),
  };

  setUp(() {
    written = [];
    client = FakeStockClient(table: Map.of(quotes));
  });

  StockStore seeded(List<String> symbols, {String error = ''}) {
    final store = StockStore.forTesting(
      client: client,
      config: StockConfig(symbols: symbols),
      writer: written.add,
    )..seed(
        quotes: [for (final s in symbols) ?quotes[s]],
        error: error,
      );
    addTearDown(store.dispose);
    return store;
  }

  Future<void> pumpBar(
    WidgetTester tester,
    StockStore store, {
    StockConfig config = const StockConfig(),
    String anchor = 'top',
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: BarScope(
            anchor: anchor,
            child: Center(child: StockTicker(store: store, config: config)),
          ),
        ),
      ),
    );
    // The lease's fetch, then the post-frame metrics that start the ticker.
    await tester.pump();
    await tester.pump();
  }

  group('the bar strip', () {
    testWidgets('crawls every ticker: label, price, and the day\'s move',
        (tester) async {
      final store = seeded(['AAPL', 'MSFT', '^GSPC']);
      await pumpBar(tester, store);

      // The strip is laid out twice, end to end, so the loop has no seam.
      expect(find.text('AAPL'), findsNWidgets(2));
      expect(find.text('227.52'), findsNWidgets(2));
      expect(find.text('+1.03%'), findsNWidgets(2));
      expect(find.text('-0.76%'), findsNWidgets(2));
      // An index by its name, not its caret-prefixed symbol.
      expect(find.text('S&P 500'), findsNWidgets(2));
      expect(find.text('^GSPC'), findsNothing);
      expect(store.leaseCount, 1, reason: 'the strip holds the lease');
    });

    testWidgets('scrolls only when the watchlist is wider than its window',
        (tester) async {
      final store = seeded(['AAPL', 'MSFT', '^GSPC']);
      await pumpBar(tester, store, config: const StockConfig(width: 120));
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: 'an overflowing strip runs a ticker');
      expect(tester.getSize(find.byType(TickerCrawl)).width, 120);

      // A window wider than the strip: it sits still, sized to itself, and
      // nothing ticks.
      await pumpBar(tester, store, config: const StockConfig(width: 2000));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.getSize(find.byType(TickerCrawl)).width, lessThan(2000));
    });

    testWidgets('hovering holds the strip still', (tester) async {
      final store = seeded(['AAPL', 'MSFT', '^GSPC']);
      await pumpBar(tester, store, config: const StockConfig(width: 120));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(TickerCrawl)));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      await gesture.moveTo(Offset.zero);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('the crawl moves by whole pixels, and only while running',
        (tester) async {
      final store = seeded(['AAPL', 'MSFT', '^GSPC']);
      await pumpBar(
        tester,
        store,
        config: const StockConfig(width: 120, scrollSpeed: 40),
      );
      final first = tester.getTopLeft(find.text('AAPL').first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      final later = tester.getTopLeft(find.text('AAPL').first);
      final moved = first.dx - later.dx;
      expect(moved, closeTo(40, 1.01), reason: 'a second at 40px/s');
      expect(moved, moved.roundToDouble());
    });

    testWidgets('a side bar shows the mark, not a crawl', (tester) async {
      final store = seeded(['AAPL', 'MSFT']);
      await pumpBar(tester, store, anchor: 'left');
      expect(find.byType(TickerCrawl), findsNothing);
      expect(_faIcon(FontAwesomeIcons.chartLine), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('an empty watchlist is a mark that says so on hover',
        (tester) async {
      final store = seeded(const []);
      await pumpBar(tester, store);
      expect(find.byType(TickerCrawl), findsNothing);
      expect(find.text('Add tickers'), findsNothing);

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(
        tester.getCenter(_faIcon(FontAwesomeIcons.chartLine)),
      );
      await tester.pump();
      expect(find.text('Add tickers'), findsOneWidget);
    });
  });

  group('the card', () {
    late List<String> opened;
    late int closed;

    setUp(() {
      opened = [];
      closed = 0;
    });

    /// Under a [ThemeScope] and nothing else: popup content lays out under its
    /// own FlutterView, with no Directionality above it.
    Future<void> pumpPopup(WidgetTester tester, StockStore store) async {
      await tester.pumpWidget(
        ThemeScope(
          theme: const ThemeConfig(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: kStockPopupWidth,
              height: kStockPopupHeight,
              child: StockPopup(
                store: store,
                onClose: () => closed++,
                openUrl: (url) {
                  opened.add(url);
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder byTooltip(String tooltip) => find.byWidgetPredicate(
          (w) => w is SettingsIconButton && w.tooltip == tooltip,
        );

    testWidgets('lists the watchlist with prices and moves', (tester) async {
      final store = seeded(['AAPL', 'MSFT']);
      await pumpPopup(tester, store);

      expect(tester.takeException(), isNull);
      expect(find.text('Markets'), findsOneWidget);
      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text('Apple Inc.'), findsOneWidget);
      expect(find.text('227.52'), findsOneWidget);
      expect(find.text('+2.31 (+1.03%)'), findsOneWidget);
      expect(find.text('-3.20 (-0.76%)'), findsOneWidget);
      expect(find.text('Trading'), findsOneWidget);
    });

    testWidgets('a symbol Yahoo does not know says so', (tester) async {
      final store = seeded(['AAPL', 'ZZZZ'])..seed(missing: {'ZZZZ'});
      await pumpPopup(tester, store);
      expect(find.text('ZZZZ'), findsOneWidget);
      expect(find.text('Not found on Yahoo Finance'), findsOneWidget);
    });

    testWidgets('clicking a quote opens its page and closes the card',
        (tester) async {
      final store = seeded(['AAPL']);
      await pumpPopup(tester, store);
      await tester.tap(find.text('Apple Inc.'));
      await tester.pump();
      expect(opened, ['https://finance.yahoo.com/quote/AAPL']);
      expect(closed, 1);
    });

    testWidgets('the remove button takes a ticker off the list',
        (tester) async {
      final store = seeded(['AAPL', 'MSFT']);
      await pumpPopup(tester, store);
      await tester.tap(byTooltip('Remove from watchlist').first);
      await tester.pumpAndSettle();
      expect(store.symbols, ['MSFT']);
      expect(written.last, ['MSFT']);
      expect(find.text('Apple Inc.'), findsNothing);
    });

    testWidgets('an empty watchlist offers the major indices', (tester) async {
      final store = seeded(const []);
      await pumpPopup(tester, store);
      expect(find.text('Your watchlist is empty'), findsOneWidget);

      await tester.tap(find.text('Start with the S&P 500, Dow and Nasdaq'));
      await tester.pumpAndSettle();
      expect(store.symbols, ['^GSPC', '^DJI', '^IXIC']);
      expect(written.single, ['^GSPC', '^DJI', '^IXIC']);
    });

    testWidgets('searching by name and clicking a result adds it',
        (tester) async {
      client.results = const [
        StockSearchResult(
          symbol: 'NVDA',
          name: 'NVIDIA Corporation',
          exchange: 'NASDAQ',
          kind: 'Equity',
        ),
      ];
      client.table['NVDA'] = testQuote('NVDA', name: 'NVIDIA', price: 120);
      final store = seeded(['AAPL']);
      await pumpPopup(tester, store);

      await tester.enterText(find.byType(EditableText), 'nvidia');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(client.queries, ['nvidia']);
      expect(find.text('NVIDIA Corporation'), findsOneWidget);
      expect(find.text('NASDAQ · Equity'), findsOneWidget);
      expect(find.text('Add the symbol exactly as typed'), findsNothing,
          reason: 'a name is not offered as a symbol beside real results');

      await tester.tap(find.text('NVIDIA Corporation'));
      await tester.pumpAndSettle();
      expect(store.symbols, ['AAPL', 'NVDA']);
      // Back to the list, where the new ticker is.
      expect(find.text('NVIDIA Corporation'), findsNothing);
      expect(find.text('NVDA'), findsOneWidget);
    });

    testWidgets('typing waits for a pause before it searches', (tester) async {
      final store = seeded(['AAPL']);
      await pumpPopup(tester, store);
      await tester.enterText(find.byType(EditableText), 'a');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(EditableText), 'ap');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(EditableText), 'app');
      await tester.pump(const Duration(milliseconds: 300));
      expect(client.queries, ['app']);
    });

    testWidgets('a ticker already watched reads as added', (tester) async {
      client.results = const [
        StockSearchResult(symbol: 'AAPL', name: 'Apple Inc.'),
      ];
      final store = seeded(['AAPL']);
      await pumpPopup(tester, store);
      await tester.enterText(find.byType(EditableText), 'apple');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Added'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(store.symbols, ['AAPL'], reason: 'no duplicate');
    });

    testWidgets('with search down, Enter adds the symbol as typed',
        (tester) async {
      client.searchFailWith =
          const StockException('Yahoo Finance could not be reached');
      final store = seeded(['AAPL']);
      await pumpPopup(tester, store);
      await tester.enterText(find.byType(EditableText), 'brk-b');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('Add the symbol exactly as typed'), findsOneWidget);
      expect(find.text('Yahoo Finance could not be reached'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(store.symbols, ['AAPL', 'BRK-B']);
    });

    testWidgets('Escape clears the query, then closes', (tester) async {
      final store = seeded(['AAPL']);
      await pumpPopup(tester, store);
      await tester.enterText(find.byType(EditableText), 'x');
      await tester.pump(const Duration(milliseconds: 300));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Apple Inc.'), findsOneWidget);
      expect(closed, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('a failed poll keeps the prices and offers a retry',
        (tester) async {
      final store = seeded(['AAPL'], error: 'Yahoo Finance answered 503');
      await pumpPopup(tester, store);
      expect(find.text('227.52'), findsOneWidget);
      expect(
        find.text('Yahoo Finance answered 503 — showing the last prices'),
        findsOneWidget,
      );
      final before = client.quoteCalls;
      await tester.tap(byTooltip('Try again'));
      await tester.pump();
      expect(client.quoteCalls, before + 1);
    });
  });
}

Finder _faIcon(FaIconData icon) =>
    find.byWidgetPredicate((w) => w is FaIcon && w.icon == icon.data);
