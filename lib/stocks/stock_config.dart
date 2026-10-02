// `[modules.stocks]`, as a typed object.
//
// Beside the store rather than in `modules/stocks.dart` for the reason
// `weather_config.dart` sits beside its store: two surfaces read these
// settings — the bar's crawl and the desktop widget — and neither is the other.

import 'package:flutter/foundation.dart';

import 'package:moonswing/config_reader.dart';
import 'package:moonswing/stocks/stock_quote.dart';

/// What the empty watchlist offers to start with, one click away: the three US
/// indices a market report opens with.
///
/// An offer rather than a default. A default list would crawl while the
/// settings row for it — which reads the file — showed nothing, and a user
/// who emptied the list would have it come back.
const List<String> kSuggestedStockSymbols = ['^GSPC', '^DJI', '^IXIC'];

class StockConfig {
  const StockConfig({
    this.symbols = const [],
    this.refreshSeconds = 15,
    this.scrollSpeed = 40,
    this.width = 320,
  });

  /// The watchlist, in the order the strip crawls it. The popup's add and
  /// remove buttons write this key; it is also an ordinary list in the file.
  final List<String> symbols;

  /// How often quotes are re-read while a market on the list is open.
  ///
  /// `ticker` polls every five seconds; three times that is still a price
  /// that moves on screen during a session, at a third of the requests to an
  /// API nobody here is paying for. While every market on the list is shut
  /// the store polls far less often — see `StockStore`.
  final int refreshSeconds;

  /// How fast the strip crawls, in logical pixels a second.
  final double scrollSpeed;

  /// How wide the strip is in a horizontal bar. A crawl needs a window to
  /// crawl through, and sized to its content it would be the width of the
  /// whole watchlist.
  final double width;

  factory StockConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const StockConfig();
    // Normalized and de-duplicated on the way in, so a hand-written `aapl`
    // and a popup-added `AAPL` are one row, and a typo with a space in it
    // costs that entry rather than a request Yahoo rejects whole.
    final seen = <String>{};
    final symbols = <String>[
      for (final raw in map.stringListOr('symbols'))
        if (normalizeSymbol(raw) case final symbol?)
          if (seen.add(symbol)) symbol,
    ];
    return StockConfig(
      symbols: List.unmodifiable(symbols),
      // Bounded below: this is a timer period against somebody else's API,
      // and `refresh_seconds = 0` is a tight loop.
      refreshSeconds: map.intOr('refresh_seconds', 15, min: 5, max: 3600),
      scrollSpeed: map.doubleOr('scroll_speed', 40, min: 5, max: 400),
      width: map.doubleOr('width', 320, min: 80, max: 2000),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockConfig &&
          listEquals(other.symbols, symbols) &&
          other.refreshSeconds == refreshSeconds &&
          other.scrollSpeed == scrollSpeed &&
          other.width == width;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(symbols), refreshSeconds, scrollSpeed, width);
}
