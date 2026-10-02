import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/stocks/stock_format.dart';
import 'package:moonswing/stocks/stock_quote.dart';

import 'stock_fakes.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

void main() {
  test('prices: separators, and precision by kind and size', () {
    expect(formatPrice(5634.5), '5,634.50');
    expect(formatPrice(42123456.789), '42,123,456.79');
    expect(formatPrice(227.5), '227.50');
    expect(formatPrice(0.4321), '0.4321');
    expect(formatPrice(0.00001234), '0.000012');
    expect(formatPrice(0), '0.00');
    expect(formatPrice(-1234.5), '-1,234.50');
    expect(formatPrice(1.08324, assetClass: StockAssetClass.currency), '1.0832');
    expect(formatPrice(149.8, assetClass: StockAssetClass.currency), '149.80');
  });

  test('changes carry their sign; no change carries none', () {
    expect(formatStockChange(testQuote('A', change: 1.234)), '+1.23');
    expect(formatStockChange(testQuote('A', change: -2.5)), '-2.50');
    expect(formatPercent(0.5432), '+0.54%');
    expect(formatPercent(-12.3), '-12.30%');
    expect(formatPercent(0), '0.00%');
  });

  test('compact numbers', () {
    expect(formatCompact(3.1e12), '3.10T');
    expect(formatCompact(51234567), '51.23M');
    expect(formatCompact(123456789012), '123.5B');
    expect(formatCompact(999), '999');
    expect(formatCompact(1500), '1.50K');
  });

  test('labels: an index by its name, a pair as a pair, the rest as is', () {
    expect(stockLabel(testQuote('^GSPC', name: 'S&P 500')), 'S&P 500');
    expect(
      stockLabel(testQuote('^DJI', name: 'Dow Jones Industrial Average')),
      'Dow',
    );
    expect(stockLabel(testQuote('^BVSP', name: 'IBOVESPA')), 'IBOVESPA');
    expect(stockLabel(testQuote('^XYZ')), '^XYZ', reason: 'no name to use');
    expect(stockLabel(testQuote('EURUSD=X', name: 'EUR/USD')), 'EUR/USD');
    expect(stockLabel(testQuote('AAPL', name: 'Apple Inc.')), 'AAPL');
  });

  test('time is 24-hour and zero-padded', () {
    expect(formatStockTime(DateTime(2026, 10, 2, 9, 5)), '09:05');
  });

  group('gain and loss colours', () {
    const dark = Color(0xFF2C2C2C);
    const light = Color(0xFFF7F7F7);
    const flat = Color(0xFF888888);

    test('read as text on a dark card and on a light one', () {
      for (final surface in [dark, light]) {
        for (final direction in [1, -1]) {
          final color =
              stockChangeColor(direction, surface: surface, flat: flat);
          expect(_contrast(color, surface), greaterThanOrEqualTo(4.4),
              reason: 'direction $direction on $surface');
        }
      }
    });

    test('stay green and red', () {
      final up = HSLColor.fromColor(
          stockChangeColor(1, surface: light, flat: flat));
      final down = HSLColor.fromColor(
          stockChangeColor(-1, surface: light, flat: flat));
      expect(up.hue, inInclusiveRange(90, 160));
      expect(down.hue < 20 || down.hue > 340, isTrue);
    });

    test('no change is the flat colour', () {
      expect(stockChangeColor(0, surface: dark, flat: flat), flat);
    });

    test('a translucent bar is judged by its own colour', () {
      const glassy = Color(0x332C2C2C);
      expect(
        stockChangeColor(1, surface: glassy, flat: flat),
        stockChangeColor(1, surface: dark, flat: flat),
      );
    });
  });
}
