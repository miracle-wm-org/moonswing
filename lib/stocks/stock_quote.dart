// What a quote is, and how one is read out of Yahoo Finance's answer.
//
// The same source and the same arithmetic as `ticker`
// (github.com/achannarasappa/ticker): its `/v7/finance/quote` request, and its
// rule for which of the regular, pre-market and post-market prices is "the"
// price. A watchlist that disagreed with the terminal beside it about what a
// stock did today would be a bug report whichever of the two was right.
//
// Flutter-free and pure, for the reason `weather_api.dart` is: the parse is
// where a shape change at Yahoo turns into a crash, so it is a function over a
// decoded map a test can hand it — and it degrades per field and per row, never
// per response. An unknown `quoteType`, a missing `fiftyTwoWeekHigh`, one
// malformed entry in twenty: each costs that field or that row.

/// What kind of thing a symbol names. Decides how many decimals a price gets
/// and whether the market it trades on ever closes.
enum StockAssetClass {
  stock,
  cryptocurrency,
  currency;

  /// `ticker`'s `getAssetClass`: everything that is not a coin or a currency
  /// pair is priced like a stock, ETFs, indices and futures included.
  static StockAssetClass parse(String quoteType) => switch (quoteType) {
        'CRYPTOCURRENCY' => cryptocurrency,
        'CURRENCY' => currency,
        _ => stock,
      };
}

/// One symbol's price, as the bar and the desktop widget show it.
class StockQuote {
  const StockQuote({
    required this.symbol,
    required this.price,
    required this.change,
    required this.changePercent,
    this.name = '',
    this.currency = '',
    this.exchange = '',
    this.marketState = '',
    this.assetClass = StockAssetClass.stock,
    this.previousClose,
    this.open,
    this.dayHigh,
    this.dayLow,
    this.volume,
    this.marketCap,
    this.fiftyTwoWeekHigh,
    this.fiftyTwoWeekLow,
    this.isActive = true,
    this.isRegularSession = true,
    this.delayMinutes = 0,
  });

  /// As Yahoo spells it — `AAPL`, `BTC-USD`, `^GSPC`, `EURUSD=X`.
  final String symbol;

  /// The short name, e.g. `Apple Inc.`; empty when Yahoo sends none, which it
  /// does for some indices and most currency pairs.
  final String name;

  /// The price the strip shows — the extended-hours one when the market is in
  /// an extended session and has traded in it. See [StockQuote.fromYahoo].
  final double price;

  /// Today's change against the previous close, in [currency], and as a
  /// percentage of it. Already includes after-hours movement when [price] does.
  final double change;
  final double changePercent;

  final String currency;
  final String exchange;

  /// Yahoo's own word for the session: `REGULAR`, `PRE`, `POST`, `CLOSED`,
  /// `PREPRE`, `POSTPOST`. Kept raw so a new value costs nothing.
  final String marketState;

  final StockAssetClass assetClass;

  final double? previousClose;
  final double? open;
  final double? dayHigh;
  final double? dayLow;
  final double? volume;
  final double? marketCap;
  final double? fiftyTwoWeekHigh;
  final double? fiftyTwoWeekLow;

  /// Whether the price is still moving: false once the session it came from
  /// has ended. `ticker`'s `Exchange.IsActive`.
  final bool isActive;

  /// Whether [price] is the regular session's. False is what the "after hours"
  /// and "pre-market" labels are drawn from.
  final bool isRegularSession;

  /// How late the exchange's feed is, in minutes. Zero for real time.
  final int delayMinutes;

  /// Whether this quote moved up, down, or not at all today. Exactly zero is
  /// flat — a currency pair that has not traded since the open is.
  int get direction => change > 0 ? 1 : (change < 0 ? -1 : 0);

  /// Whether the market this trades on can be said to be shut. Coins and
  /// currency pairs never are; their `marketState` is `REGULAR` around the
  /// clock.
  bool get isClosed => !isActive && isRegularSession;

  /// The word for an extended session, or null in the regular one.
  String? get sessionLabel {
    if (isRegularSession) return null;
    return switch (marketState) {
      'PRE' || 'PREPRE' => 'Pre-market',
      'POST' || 'POSTPOST' => 'After hours',
      // An extended price from a market that has since closed is the
      // after-hours close, which is what the last session was.
      _ => 'After hours',
    };
  }

  /// The quote as Yahoo answers it, or null for an entry with no symbol or no
  /// price — neither of which is a row anybody can read.
  ///
  /// Accepts both shapes `/v7/finance/quote` comes in: `formatted=true` wraps
  /// every number as `{raw, fmt}`, and without it they are bare. `ticker` asks
  /// for the first; reading either means a change to the request cannot quietly
  /// zero every price.
  static StockQuote? fromYahoo(Object? json) {
    if (json is! Map) return null;
    final symbol = _string(json['symbol']).trim();
    final regularPrice = _number(json['regularMarketPrice']);
    if (symbol.isEmpty || regularPrice == null) return null;

    final regularChange = _number(json['regularMarketChange']) ?? 0;
    final regularPercent = _number(json['regularMarketChangePercent']) ?? 0;
    final postPrice = _number(json['postMarketPrice']) ?? 0;
    final postChange = _number(json['postMarketChange']) ?? 0;
    final postPercent = _number(json['postMarketChangePercent']) ?? 0;
    final prePrice = _number(json['preMarketPrice']) ?? 0;
    final marketState = _string(json['marketState']);

    StockQuote build({
      double? price,
      double? change,
      double? percent,
      bool active = true,
      bool regular = true,
    }) =>
        StockQuote(
          symbol: symbol,
          name: _string(json['shortName']).trim().isNotEmpty
              ? _string(json['shortName']).trim()
              : _string(json['longName']).trim(),
          price: price ?? regularPrice,
          change: change ?? regularChange,
          changePercent: percent ?? regularPercent,
          currency: _string(json['currency']),
          exchange: _string(json['fullExchangeName']),
          marketState: marketState,
          assetClass: StockAssetClass.parse(_string(json['quoteType'])),
          previousClose: _number(json['regularMarketPreviousClose']),
          open: _number(json['regularMarketOpen']),
          dayHigh: _number(json['regularMarketDayHigh']),
          dayLow: _number(json['regularMarketDayLow']),
          volume: _number(json['regularMarketVolume']),
          marketCap: _number(json['marketCap']),
          fiftyTwoWeekHigh: _number(json['fiftyTwoWeekHigh']),
          fiftyTwoWeekLow: _number(json['fiftyTwoWeekLow']),
          isActive: active,
          isRegularSession: regular,
          delayMinutes: (_number(json['exchangeDataDelayedBy']) ?? 0)
              .round()
              .clamp(0, 24 * 60),
        );

    // From here down is `ticker`'s `transformResponseQuote`, branch for
    // branch and in its order, because the order is the rule: which price wins
    // depends on which test is asked first.
    const postStates = {'POST', 'POSTPOST'};

    if (marketState == 'REGULAR') return build();

    // After the close, before anything has traded after it: the regular
    // session's numbers, flagged as no longer regular.
    if (postStates.contains(marketState) && postPrice == 0) {
      return build(regular: false);
    }

    // Before the open, before anything has traded before it: yesterday's
    // numbers, and nothing moving.
    if (marketState == 'PRE' && prePrice == 0) {
      return build(active: false, regular: false);
    }

    // After hours, with trades: the after-hours price, and the day's change is
    // the regular session's plus what has happened since.
    if (postStates.contains(marketState)) {
      return build(
        price: postPrice,
        change: postChange + regularChange,
        percent: postPercent + regularPercent,
        regular: false,
      );
    }

    // Pre-market, with trades: the pre-market price against yesterday.
    if (marketState == 'PRE') {
      return build(
        price: prePrice,
        change: _number(json['preMarketChange']) ?? 0,
        percent: _number(json['preMarketChangePercent']) ?? 0,
        regular: false,
      );
    }

    // Closed, with an after-hours print from the last session: that print is
    // where it will open.
    if (postPrice != 0) {
      return build(
        price: postPrice,
        change: postChange + regularChange,
        percent: postPercent + regularPercent,
        active: false,
        regular: false,
      );
    }

    return build(active: false, regular: false);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockQuote &&
          other.symbol == symbol &&
          other.name == name &&
          other.price == price &&
          other.change == change &&
          other.changePercent == changePercent &&
          other.currency == currency &&
          other.exchange == exchange &&
          other.marketState == marketState &&
          other.assetClass == assetClass &&
          other.previousClose == previousClose &&
          other.open == open &&
          other.dayHigh == dayHigh &&
          other.dayLow == dayLow &&
          other.volume == volume &&
          other.marketCap == marketCap &&
          other.fiftyTwoWeekHigh == fiftyTwoWeekHigh &&
          other.fiftyTwoWeekLow == fiftyTwoWeekLow &&
          other.isActive == isActive &&
          other.isRegularSession == isRegularSession &&
          other.delayMinutes == delayMinutes;

  @override
  int get hashCode => Object.hashAll([
        symbol,
        name,
        price,
        change,
        changePercent,
        currency,
        exchange,
        marketState,
        assetClass,
        previousClose,
        open,
        dayHigh,
        dayLow,
        volume,
        marketCap,
        fiftyTwoWeekHigh,
        fiftyTwoWeekLow,
        isActive,
        isRegularSession,
        delayMinutes,
      ]);

  @override
  String toString() => 'StockQuote($symbol $price $change)';
}

/// Every quote in a `/v7/finance/quote` response, malformed entries dropped.
///
/// Throws [FormatException] only when the envelope itself is not the shape —
/// that is a changed API, and a silently empty list would read as "none of your
/// symbols exist".
List<StockQuote> parseYahooQuotes(Object? json) {
  if (json is! Map) throw const FormatException('quote response is not an object');
  final envelope = json['quoteResponse'];
  if (envelope is! Map) {
    throw const FormatException('quote response has no quoteResponse');
  }
  final result = envelope['result'];
  if (result is! List) return const [];
  return [for (final entry in result) ?StockQuote.fromYahoo(entry)];
}

/// One row of a symbol search: enough to tell two "Apple"s apart before
/// adding one.
class StockSearchResult {
  const StockSearchResult({
    required this.symbol,
    this.name = '',
    this.exchange = '',
    this.kind = '',
  });

  final String symbol;
  final String name;

  /// `NASDAQ`, `NYSE`, `CCC` — Yahoo's `exchDisp`.
  final String exchange;

  /// `Equity`, `ETF`, `Index`, `Cryptocurrency` — Yahoo's `typeDisp`.
  final String kind;

  static StockSearchResult? fromYahoo(Object? json) {
    if (json is! Map) return null;
    final symbol = _string(json['symbol']).trim();
    if (symbol.isEmpty) return null;
    // News, people and lists come back in the same array on some queries;
    // only an entry Yahoo itself would quote is something to watch.
    if (json['isYahooFinance'] == false) return null;
    final short = _string(json['shortname']).trim();
    final long = _string(json['longname']).trim();
    return StockSearchResult(
      symbol: symbol,
      name: long.isNotEmpty ? long : short,
      exchange: _string(json['exchDisp']).trim(),
      kind: _string(json['typeDisp']).trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StockSearchResult &&
      other.symbol == symbol &&
      other.name == name &&
      other.exchange == exchange &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(symbol, name, exchange, kind);
}

/// Every match in a `/v1/finance/search` response, malformed entries and
/// duplicate symbols dropped.
List<StockSearchResult> parseYahooSearch(Object? json) {
  if (json is! Map) return const [];
  final quotes = json['quotes'];
  if (quotes is! List) return const [];
  final seen = <String>{};
  return [
    for (final entry in quotes)
      if (StockSearchResult.fromYahoo(entry) case final result?)
        if (seen.add(result.symbol)) result,
  ];
}

/// [symbol] as a watchlist stores it, or null when it cannot be one.
///
/// Upper-cased because Yahoo is case-blind and a list holding `aapl` and
/// `AAPL` would quote Apple twice. The character set is every one Yahoo uses
/// — `^GSPC`, `BRK-B`, `EURUSD=X`, `RDS.A`, `ES=F`, `M&M.NS` — and nothing
/// else; in particular no comma, which is the separator of the request's own
/// symbol list, and no space, which is what a company name has and a symbol
/// does not.
String? normalizeSymbol(String symbol) {
  final trimmed = symbol.trim().toUpperCase();
  if (trimmed.isEmpty || trimmed.length > 24) return null;
  if (!RegExp(r'^[A-Z0-9.^=&_\-]+$').hasMatch(trimmed)) return null;
  return trimmed;
}

String _string(Object? value) {
  if (value is String) return value;
  if (value is Map) {
    final raw = value['raw'];
    if (raw is String) return raw;
  }
  return '';
}

/// A number, bare or as `{raw, fmt}`; null for anything else, and for the
/// non-finite values a JSON decoder can hand back for an out-of-range literal.
double? _number(Object? value) {
  final raw = value is Map ? value['raw'] : value;
  if (raw is! num) return null;
  final v = raw.toDouble();
  return v.isFinite ? v : null;
}
