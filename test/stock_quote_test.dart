import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/stocks/stock_config.dart';
import 'package:moonswing/stocks/stock_quote.dart';

/// A `/v7/finance/quote` entry as `formatted=true` returns it: every number
/// wrapped as `{raw, fmt}`.
Map<String, dynamic> yahooEntry({
  String symbol = 'AAPL',
  String marketState = 'REGULAR',
  double price = 200,
  double change = 2,
  double percent = 1.01,
  double? postPrice,
  double? postChange,
  double? postPercent,
  double? prePrice,
  double? preChange,
  double? prePercent,
  String quoteType = 'EQUITY',
}) {
  Map<String, dynamic> f(double v) => {'raw': v, 'fmt': v.toStringAsFixed(2)};
  return {
    'symbol': symbol,
    'shortName': 'Apple Inc.',
    'quoteType': quoteType,
    'currency': 'USD',
    'fullExchangeName': 'NasdaqGS',
    'marketState': marketState,
    'exchangeDataDelayedBy': 0,
    'regularMarketPrice': f(price),
    'regularMarketChange': f(change),
    'regularMarketChangePercent': f(percent),
    'regularMarketPreviousClose': f(price - change),
    'regularMarketOpen': f(price - 1),
    'regularMarketDayHigh': f(price + 3),
    'regularMarketDayLow': f(price - 4),
    'regularMarketVolume': f(51234567),
    'marketCap': f(3.1e12),
    'fiftyTwoWeekHigh': f(260),
    'fiftyTwoWeekLow': f(164),
    if (postPrice != null) 'postMarketPrice': f(postPrice),
    if (postChange != null) 'postMarketChange': f(postChange),
    if (postPercent != null) 'postMarketChangePercent': f(postPercent),
    if (prePrice != null) 'preMarketPrice': f(prePrice),
    if (preChange != null) 'preMarketChange': f(preChange),
    if (prePercent != null) 'preMarketChangePercent': f(prePercent),
  };
}

void main() {
  group('StockQuote.fromYahoo', () {
    test('reads the formatted {raw, fmt} shape ticker asks for', () {
      final quote = StockQuote.fromYahoo(yahooEntry())!;
      expect(quote.symbol, 'AAPL');
      expect(quote.name, 'Apple Inc.');
      expect(quote.price, 200);
      expect(quote.change, 2);
      expect(quote.changePercent, closeTo(1.01, 1e-9));
      expect(quote.dayHigh, 203);
      expect(quote.dayLow, 196);
      expect(quote.volume, 51234567);
      expect(quote.marketCap, 3.1e12);
      expect(quote.exchange, 'NasdaqGS');
      expect(quote.isActive, isTrue);
      expect(quote.isRegularSession, isTrue);
      expect(quote.sessionLabel, isNull);
    });

    test('reads bare numbers too', () {
      final quote = StockQuote.fromYahoo({
        'symbol': 'MSFT',
        'regularMarketPrice': 410.5,
        'regularMarketChange': -3,
        'regularMarketChangePercent': -0.72,
        'marketState': 'REGULAR',
      })!;
      expect(quote.price, 410.5);
      expect(quote.change, -3);
      expect(quote.direction, -1);
    });

    test('an entry with no symbol or no price is no row', () {
      expect(StockQuote.fromYahoo({'regularMarketPrice': 1}), isNull);
      expect(StockQuote.fromYahoo({'symbol': 'X'}), isNull);
      expect(StockQuote.fromYahoo('nope'), isNull);
      expect(
        StockQuote.fromYahoo({'symbol': 'X', 'regularMarketPrice': 'NaN'}),
        isNull,
      );
    });

    test('a wrongly-typed field costs that field, not the quote', () {
      final quote = StockQuote.fromYahoo({
        ...yahooEntry(),
        'fiftyTwoWeekHigh': 'soon',
        'regularMarketVolume': {'fmt': 'lots'},
        'shortName': 12,
      })!;
      expect(quote.price, 200);
      expect(quote.fiftyTwoWeekHigh, isNull);
      expect(quote.volume, isNull);
      expect(quote.name, '');
    });

    // ticker's `transformResponseQuote`, branch for branch.
    group('which price wins', () {
      test('after the close with no after-hours trade: the regular numbers',
          () {
        final quote = StockQuote.fromYahoo(
          yahooEntry(marketState: 'POST', postPrice: 0),
        )!;
        expect(quote.price, 200);
        expect(quote.change, 2);
        expect(quote.isRegularSession, isFalse);
        expect(quote.isActive, isTrue);
        expect(quote.sessionLabel, 'After hours');
      });

      test('after hours with trades: the after-hours price, the changes summed',
          () {
        final quote = StockQuote.fromYahoo(yahooEntry(
          marketState: 'POST',
          postPrice: 203,
          postChange: 3,
          postPercent: 1.5,
        ))!;
        expect(quote.price, 203);
        expect(quote.change, 5);
        expect(quote.changePercent, closeTo(2.51, 1e-9));
        expect(quote.isActive, isTrue);
        expect(quote.isRegularSession, isFalse);
      });

      test('pre-market with no trade: yesterday, and nothing moving', () {
        final quote = StockQuote.fromYahoo(
          yahooEntry(marketState: 'PRE', prePrice: 0),
        )!;
        expect(quote.price, 200);
        expect(quote.isActive, isFalse);
        expect(quote.isRegularSession, isFalse);
        expect(quote.sessionLabel, 'Pre-market');
      });

      test('pre-market with trades: the pre-market price against yesterday',
          () {
        final quote = StockQuote.fromYahoo(yahooEntry(
          marketState: 'PRE',
          prePrice: 199,
          preChange: -1,
          prePercent: -0.5,
        ))!;
        expect(quote.price, 199);
        expect(quote.change, -1);
        expect(quote.changePercent, -0.5);
        expect(quote.isActive, isTrue);
      });

      test('closed with an after-hours print: that print, and not moving', () {
        final quote = StockQuote.fromYahoo(yahooEntry(
          marketState: 'CLOSED',
          postPrice: 201,
          postChange: 1,
          postPercent: 0.5,
        ))!;
        expect(quote.price, 201);
        expect(quote.change, 3);
        expect(quote.isActive, isFalse);
      });

      test('closed with nothing after hours: the close, and not moving', () {
        final quote =
            StockQuote.fromYahoo(yahooEntry(marketState: 'CLOSED'))!;
        expect(quote.price, 200);
        expect(quote.isActive, isFalse);
        expect(quote.isRegularSession, isFalse);
      });
    });

    test('quoteType picks the asset class, and anything else is a stock', () {
      expect(
        StockQuote.fromYahoo(yahooEntry(quoteType: 'CRYPTOCURRENCY'))!
            .assetClass,
        StockAssetClass.cryptocurrency,
      );
      expect(
        StockQuote.fromYahoo(yahooEntry(quoteType: 'CURRENCY'))!.assetClass,
        StockAssetClass.currency,
      );
      expect(
        StockQuote.fromYahoo(yahooEntry(quoteType: 'SOMETHING_NEW'))!
            .assetClass,
        StockAssetClass.stock,
      );
    });
  });

  group('parseYahooQuotes', () {
    test('drops a malformed row and keeps the rest', () {
      final quotes = parseYahooQuotes({
        'quoteResponse': {
          'result': [
            yahooEntry(symbol: 'AAPL'),
            {'symbol': 'BROKEN'},
            42,
            yahooEntry(symbol: 'MSFT'),
          ],
          'error': null,
        },
      });
      expect(quotes.map((q) => q.symbol), ['AAPL', 'MSFT']);
    });

    test('a changed envelope is an error, not an empty list', () {
      expect(() => parseYahooQuotes({'data': []}), throwsFormatException);
      expect(() => parseYahooQuotes('nope'), throwsFormatException);
      expect(
        parseYahooQuotes({
          'quoteResponse': {'result': null},
        }),
        isEmpty,
      );
    });
  });

  group('parseYahooSearch', () {
    test('reads symbols, names, exchanges and kinds', () {
      final results = parseYahooSearch({
        'quotes': [
          {
            'symbol': 'AAPL',
            'shortname': 'Apple Inc.',
            'longname': 'Apple Inc.',
            'exchDisp': 'NASDAQ',
            'typeDisp': 'Equity',
            'isYahooFinance': true,
          },
          {
            'symbol': 'APLE',
            'shortname': 'Apple Hospitality REIT, Inc.',
            'exchDisp': 'NYSE',
            'typeDisp': 'Equity',
          },
          // Not something Yahoo quotes, a duplicate, and junk.
          {'symbol': 'NEWS1', 'isYahooFinance': false},
          {'symbol': 'AAPL', 'shortname': 'again'},
          'junk',
        ],
        'news': [],
      });
      expect(results.map((r) => r.symbol), ['AAPL', 'APLE']);
      expect(results.first.exchange, 'NASDAQ');
      expect(results.first.kind, 'Equity');
      expect(results.last.name, 'Apple Hospitality REIT, Inc.');
    });

    test('a shape it does not know is no results', () {
      expect(parseYahooSearch(null), isEmpty);
      expect(parseYahooSearch({'quotes': 'x'}), isEmpty);
    });
  });

  test('normalizeSymbol upper-cases and refuses what is not a symbol', () {
    expect(normalizeSymbol(' aapl '), 'AAPL');
    expect(normalizeSymbol('^gspc'), '^GSPC');
    expect(normalizeSymbol('brk-b'), 'BRK-B');
    expect(normalizeSymbol('eurusd=x'), 'EURUSD=X');
    expect(normalizeSymbol('rds.a'), 'RDS.A');
    expect(normalizeSymbol(''), isNull);
    expect(normalizeSymbol('apple inc'), isNull);
    expect(normalizeSymbol('AAPL,MSFT'), isNull);
    expect(normalizeSymbol('m&m.ns'), 'M&M.NS');
    expect(normalizeSymbol('a b'), isNull);
  });

  group('StockConfig.fromMap', () {
    test('defaults: an empty watchlist, and the documented cadence', () {
      const config = StockConfig();
      expect(StockConfig.fromMap(null), config);
      expect(config.symbols, isEmpty);
      expect(config.refreshSeconds, 15);
      expect(config.scrollSpeed, 40);
      expect(config.width, 320);
    });

    test('normalizes, de-duplicates and drops what is not a symbol', () {
      final config = StockConfig.fromMap({
        'symbols': ['aapl', 'AAPL', 'not a symbol', 7, '^gspc'],
      });
      expect(config.symbols, ['AAPL', '^GSPC']);
    });

    test('clamps the timer and the strip, and survives wrong types', () {
      final config = StockConfig.fromMap({
        'symbols': 'AAPL',
        'refresh_seconds': 0,
        'scroll_speed': 10000.0,
        'width': 'wide',
      });
      expect(config.symbols, isEmpty);
      expect(config.refreshSeconds, 5);
      expect(config.scrollSpeed, 400);
      expect(config.width, 320);
    });

    test('has value equality, so a keystroke elsewhere is not a change', () {
      expect(
        StockConfig.fromMap({
          'symbols': ['AAPL'],
        }),
        StockConfig.fromMap({
          'symbols': ['aapl'],
        }),
      );
      expect(
        StockConfig.fromMap({
          'symbols': ['AAPL'],
        }),
        isNot(StockConfig.fromMap({
          'symbols': ['MSFT'],
        })),
      );
    });
  });
}
