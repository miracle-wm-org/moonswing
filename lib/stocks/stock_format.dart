// How a quote is spelled and coloured: prices, changes, big numbers, and the
// green and red they are drawn in.
//
// Pure, so the arithmetic every surface agrees on is one table a test can read.
// No `intl`, for the reason the calendar refuses it: a thousands separator and
// a suffix are not formatting machinery.

import 'dart:ui';

import 'package:moonswing/stocks/stock_quote.dart';
import 'package:moonswing/theme/theme_config.dart' show readableOn;
import 'package:moonswing/theme/tokens.dart';

/// The green a gain is drawn in, before it is lifted to read on the surface
/// under it.
const Color kStockGain = Color(0xFF3FB950);

/// The red a loss is drawn in — the shell's one error red, because a loss and
/// an error should never be two different reds side by side.
const Color kStockLoss = kErrorColor;

/// The colour [direction]'s text takes on [surface]: green up, red down,
/// [flat] for no change. The theme decides the surface, and the hue is moved
/// along its own lightness ramp until it reads there, so a pale theme gets a
/// darker green rather than one that vanishes into its cards.
Color stockChangeColor(
  int direction, {
  required Color surface,
  required Color flat,
}) {
  if (direction == 0) return flat;
  // Translucent surfaces are composited over a wallpaper this cannot see; their
  // own colour, made opaque, is the only thing about them that is knowable.
  final opaque = surface.withValues(alpha: 1);
  return readableOn(direction > 0 ? kStockGain : kStockLoss, opaque);
}

/// What a news channel's ticker calls the indices it carries most — shorter
/// than Yahoo's `shortName`, which for `^DJI` is all four words of "Dow Jones
/// Industrial Average" and takes a third of the strip.
const Map<String, String> kIndexLabels = {
  '^GSPC': 'S&P 500',
  '^DJI': 'Dow',
  '^IXIC': 'Nasdaq',
  '^NDX': 'Nasdaq 100',
  '^RUT': 'Russell 2000',
  '^VIX': 'VIX',
  '^FTSE': 'FTSE 100',
  '^GDAXI': 'DAX',
  '^FCHI': 'CAC 40',
  '^STOXX50E': 'Euro Stoxx 50',
  '^N225': 'Nikkei 225',
  '^HSI': 'Hang Seng',
};

/// What a symbol is called on a strip with no room for a name.
///
/// The symbol, except for the two kinds whose symbol is not what anybody
/// calls them: an index (`^GSPC` is the S&P 500 — from [kIndexLabels], or
/// else its short name) and a currency pair (`EURUSD=X` reads as `EUR/USD`).
String stockLabel(StockQuote quote) {
  final symbol = quote.symbol;
  if (kIndexLabels[symbol] case final label?) return label;
  if (symbol.startsWith('^') && quote.name.isNotEmpty) return quote.name;
  final pair = RegExp(r'^([A-Z]{3})([A-Z]{3})=X$').firstMatch(symbol);
  if (pair != null) return '${pair.group(1)}/${pair.group(2)}';
  return symbol;
}

/// [quote]'s price, at the precision its kind is quoted in: four places for a
/// currency pair, two for anything worth a unit or more, and more for a coin
/// or a penny stock priced in fractions of a cent.
String formatStockPrice(StockQuote quote) =>
    formatPrice(quote.price, assetClass: quote.assetClass);

String formatPrice(
  double price, {
  StockAssetClass assetClass = StockAssetClass.stock,
}) {
  final magnitude = price.abs();
  final int decimals;
  if (assetClass == StockAssetClass.currency) {
    decimals = magnitude >= 100 ? 2 : 4;
  } else if (magnitude >= 1 || magnitude == 0) {
    decimals = 2;
  } else if (magnitude >= 0.01) {
    decimals = 4;
  } else {
    decimals = 6;
  }
  return _grouped(price, decimals);
}

/// `+1.23` / `-1.23`, at the price's own precision.
String formatStockChange(StockQuote quote) {
  final text = formatPrice(quote.change.abs(), assetClass: quote.assetClass);
  return '${_sign(quote.change)}$text';
}

/// `+1.23%` / `-1.23%`.
String formatStockPercent(StockQuote quote) =>
    formatPercent(quote.changePercent);

String formatPercent(double percent) =>
    '${_sign(percent)}${percent.abs().toStringAsFixed(2)}%';

/// `1.23K`, `45.6M`, `2.31B`, `3.04T` — a volume or a market cap.
String formatCompact(double value) {
  final magnitude = value.abs();
  const steps = [(1e12, 'T'), (1e9, 'B'), (1e6, 'M'), (1e3, 'K')];
  for (final (size, suffix) in steps) {
    if (magnitude >= size) {
      final scaled = value / size;
      final digits = scaled.abs() >= 100 ? 1 : 2;
      return '${scaled.toStringAsFixed(digits)}$suffix';
    }
  }
  return value.toStringAsFixed(0);
}

/// `14:32` — when the quotes on screen were read. 24-hour and local, the way
/// the rest of the shell's timestamps are.
String formatStockTime(DateTime time) {
  final local = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

String _sign(double value) => value > 0 ? '+' : (value < 0 ? '-' : '');

/// [value] to [decimals] places with thousands separated by commas.
String _grouped(double value, int decimals) {
  final fixed = value.abs().toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final whole = dot < 0 ? fixed : fixed.substring(0, dot);
  final fraction = dot < 0 ? '' : fixed.substring(dot);
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '${value < 0 ? '-' : ''}$buffer$fraction';
}
