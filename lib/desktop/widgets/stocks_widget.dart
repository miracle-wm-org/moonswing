// The stock market desktop widget: the watchlist as a board — each ticker's
// price, its move today, and where in the day's range it is trading.
//
// The seventh entry in `DesktopWidgetRegistry`, reading exactly what the bar's
// crawl reads — `StockStore.instance`, leased. Same watchlist, same poll, same
// numbers: a ticker added from the bar's popup appears here on the same frame,
// and the two never disagree about a price, because there is only one price.
//
// Three things about it:
//
// - **It is drawn in the theme, not over a picture.** The weather and lunar
//   cards paint a sky because their subject is one; a quote board's subject is
//   numbers, and the theme's own card is the surface they read best on. So the
//   text is `popup_foreground` and `muted`, the board's marks are the
//   `accent`, and the green and red are lifted along their own lightness ramps
//   until they read on `popup_background` — a pale theme gets a darker green
//   rather than one that vanishes into the card.
// - **What it shows is chosen by pixels.** Every column past the symbol and
//   the price is shed in order as the card narrows — the name, then the day's
//   range — and the header goes before any row does. The rows are a
//   fixed-extent list, so a list longer than the card scrolls under the wheel
//   rather than overflowing it.
// - **Nothing on it moves at rest.** The quotes change when the poll lands and
//   not otherwise; there is no ticker here, so the card is `pumpAndSettle`-able.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/app_info.dart' show openUriWithDefault;
import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/desktop_layout.dart' show GridSpan;
import 'package:moonswing/desktop/widgets/desktop_widget.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/modules/stocks.dart'
    show
        StockActionButton,
        StockChangePill,
        kStockPillChrome,
        stockPillText,
        stockQuoteUrl;
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/stocks/stock_format.dart';
import 'package:moonswing/stocks/stock_quote.dart';
import 'package:moonswing/stocks/stock_store.dart';
import 'package:moonswing/theme/tokens.dart';

/// The card's inner inset.
const double _inset = 12;

/// The narrowest a row is before the company name goes, and before the day's
/// range does.
const double _nameMinWidth = 230;
const double _rangeMinWidth = 330;

/// The shortest card that keeps its header. Below it every pixel is a row.
const double _headerMinHeight = 120;

/// The widget's body. Store-injectable so a widget test can seed quotes and
/// pump it with nothing behind it.
class StocksWidget extends StatefulWidget {
  StocksWidget({
    super.key,
    required this.span,
    StockStore? store,
    this.openUrl,
    this.openSettings,
  }) : store = store ?? StockStore.instance;

  final GridSpan span;
  final StockStore store;

  /// Opens a quote's page. Injected by tests; the default is the browser.
  final bool Function(String url)? openUrl;

  /// Opens Settings at the watchlist. Injected by tests; the default asks the
  /// root through [SettingsController].
  final VoidCallback? openSettings;

  @override
  State<StocksWidget> createState() => _StocksWidgetState();
}

class _StocksWidgetState extends State<StocksWidget> {
  @override
  void initState() {
    super.initState();
    widget.store.acquire();
  }

  @override
  void didUpdateWidget(StocksWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) return;
    oldWidget.store.release();
    widget.store.acquire();
  }

  @override
  void dispose() {
    widget.store.release();
    super.dispose();
  }

  void _open(String symbol) =>
      (widget.openUrl ?? openUriWithDefault)(stockQuoteUrl(symbol));

  void _openSettings() {
    final open = widget.openSettings;
    if (open != null) {
      open();
    } else {
      SettingsController.instance.open(SettingsRoute.modules);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribed here and nowhere above: the frame, the grid and the desktop
    // surface are none of them interested in a price.
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final theme = ThemeScope.of(context);
        final store = widget.store;
        return LayoutBuilder(
          builder: (context, constraints) {
            final showHeader = constraints.maxHeight >= _headerMinHeight;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showHeader) _BoardHeader(store: store, theme: theme),
                Expanded(child: _body(store, theme, constraints.maxWidth)),
                if (store.error.isNotEmpty && store.hasQuotes)
                  _BoardError(store: store, theme: theme),
              ],
            );
          },
        );
      },
    );
  }

  Widget _body(StockStore store, ThemeConfig theme, double width) {
    if (store.symbols.isEmpty) {
      return _BoardHint(
        theme: theme,
        message: 'No tickers on your watchlist',
        action: 'Add tickers',
        onAction: _openSettings,
      );
    }
    if (!store.hasQuotes) {
      if (store.loading || store.error.isEmpty) {
        return Center(child: LoadingIndicator(color: theme.muted));
      }
      return _BoardHint(
        theme: theme,
        message: store.error,
        action: 'Try again',
        onAction: store.refresh,
      );
    }
    final quotes = store.quotes;
    final showName = width >= _nameMinWidth;
    final showRange = width >= _rangeMinWidth;
    // One width for every row's price column and every row's range, so the
    // ranges line up down the board — each row is its own layout, and a
    // column sized by its own price would put every range somewhere else.
    final priceWidth = _priceColumnWidth(
      context,
      quotes,
      showAbsolute: showName,
    );
    final rangeWidth = ((width - _inset * 2) * 0.3).clamp(70.0, 180.0);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 6),
      itemExtent: 44,
      itemCount: quotes.length,
      itemBuilder: (context, index) => _BoardRow(
        quote: quotes[index],
        theme: theme,
        showName: showName,
        rangeWidth: showRange ? rangeWidth : null,
        priceWidth: priceWidth,
        onTap: () => _open(quotes[index].symbol),
      ),
    );
  }

  /// The widest price or change pill on the board, measured in the font and at
  /// the scale they will be drawn in — the theme's `font_size` reaches them
  /// through the ambient scaler, so the measurement takes it too.
  double _priceColumnWidth(
    BuildContext context,
    List<StockQuote> quotes, {
    required bool showAbsolute,
  }) {
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final base = DefaultTextStyle.of(context).style.merge(
      const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    );
    double measure(String text, double size) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: base.copyWith(fontSize: size),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var widest = 0.0;
    for (final quote in quotes) {
      final price = measure(formatStockPrice(quote), ShellFontSizes.body);
      final pill =
          measure(
            stockPillText(quote, showAbsolute: showAbsolute),
            ShellFontSizes.caption,
          ) +
          kStockPillChrome;
      widest = [widest, price, pill].reduce((a, b) => a > b ? a : b);
    }
    // A pixel of slack for the rounding between a measurement and a layout.
    return widest.ceilToDouble() + 1;
  }
}

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({required this.store, required this.theme});

  final StockStore store;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final open = store.anyMarketOpen;
    final updated = store.updatedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_inset, 10, _inset, 6),
      child: Row(
        children: [
          FaIcon(FontAwesomeIcons.chartLine, size: 13, color: theme.accentText),
          const SizedBox(width: 8),
          Text(
            'Markets',
            style: TextStyle(
              fontSize: ShellFontSizes.label,
              fontWeight: FontWeight.w600,
              color: theme.popupForeground,
            ),
          ),
          if (store.hasQuotes) ...[
            const SizedBox(width: 10),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: open
                    ? stockChangeColor(
                        1,
                        surface: theme.popupBackground,
                        flat: theme.muted,
                      )
                    : theme.muted.atMostAlpha(0.6),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              open ? 'Trading' : 'Closed',
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                color: theme.muted,
              ),
            ),
          ],
          // The time takes the slack and gives way first, right-aligned, so
          // it stays against the rim the prices are aligned to.
          Expanded(
            child: updated == null
                ? const SizedBox.shrink()
                : Text(
                    formatStockTime(updated),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: ShellFontSizes.caption,
                      color: theme.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.quote,
    required this.theme,
    required this.showName,
    required this.rangeWidth,
    required this.priceWidth,
    required this.onTap,
  });

  final StockQuote quote;
  final ThemeConfig theme;
  final bool showName;

  /// The range column's width, or null when the card is too narrow for one.
  final double? rangeWidth;

  /// The price column's width — the board's widest, so columns align.
  final double priceWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final low = quote.dayLow;
    final high = quote.dayHigh;
    final rangeWidth = this.rangeWidth;
    final hasRange = low != null && high != null && high > low;
    final subtitle = [
      if (showName && quote.name.isNotEmpty && stockLabel(quote) != quote.name)
        quote.name,
      ?quote.sessionLabel,
    ].join(' · ');

    // A boundary per row: a hover tints one row, and the desktop surface has
    // no boundary of its own above this card.
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: _inset - 6),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover.atMostAlpha(0.16) : null,
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stockLabel(quote),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ShellFontSizes.body,
                        fontWeight: FontWeight.w700,
                        color: theme.popupForeground,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ShellFontSizes.caption,
                          color: theme.muted,
                        ),
                      ),
                  ],
                ),
              ),
              // The column is kept for a quote with no range — a coin
              // between sessions, say — so the rows under it stay aligned.
              if (rangeWidth != null) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: rangeWidth,
                  child: hasRange
                      ? StockDayRange(
                          low: low,
                          high: high,
                          price: quote.price,
                          open: quote.open,
                          direction: quote.direction,
                          theme: theme,
                        )
                      : null,
                ),
              ],
              const SizedBox(width: 10),
              SizedBox(
                width: priceWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatStockPrice(quote),
                      style: TextStyle(
                        fontSize: ShellFontSizes.body,
                        color: theme.popupForeground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    StockChangePill(
                      quote: quote,
                      surface: theme.popupBackground,
                      showAbsolute: showName,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where today's price sits between today's low and high: a track the width
/// of the range, the stretch from the open to now in the day's colour, and a
/// mark at the price in the theme's accent.
class StockDayRange extends StatelessWidget {
  const StockDayRange({
    super.key,
    required this.low,
    required this.high,
    required this.price,
    required this.direction,
    required this.theme,
    this.open,
  });

  final double low;
  final double high;
  final double price;
  final double? open;
  final int direction;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: CustomPaint(
        painter: _DayRangePainter(
          low: low,
          high: high,
          price: price,
          open: open,
          track: theme.divider,
          move: stockChangeColor(
            direction,
            surface: theme.popupBackground,
            flat: theme.muted,
          ),
          mark: theme.accent,
          ring: theme.popupBackground.withValues(alpha: 1),
        ),
      ),
    );
  }
}

class _DayRangePainter extends CustomPainter {
  const _DayRangePainter({
    required this.low,
    required this.high,
    required this.price,
    required this.open,
    required this.track,
    required this.move,
    required this.mark,
    required this.ring,
  });

  final double low;
  final double high;
  final double price;
  final double? open;
  final Color track;
  final Color move;
  final Color mark;
  final Color ring;

  /// The fraction of the way from [low] to [high] that [value] is — clamped,
  /// because an after-hours price can be outside the regular session's range.
  double _at(double value) => ((value - low) / (high - low)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    const thickness = 3.0;
    const radius = 4.0;
    final y = size.height / 2;
    final left = radius;
    final width = size.width - radius * 2;
    if (width <= 0) return;

    final cap = Paint()
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(left, y),
      Offset(left + width, y),
      cap..color = track,
    );

    final now = left + width * _at(price);
    final from = open;
    if (from != null) {
      final start = left + width * _at(from);
      if ((start - now).abs() > 0.5) {
        canvas.drawLine(Offset(start, y), Offset(now, y), cap..color = move);
      }
    }

    canvas
      ..drawCircle(Offset(now, y), radius + 1, Paint()..color = ring)
      ..drawCircle(Offset(now, y), radius, Paint()..color = mark);
  }

  /// A picture, not a target: the row around it takes the tap, and a
  /// `painter:` that answered every point would be the one thing in the shell
  /// claiming the hit for a decoration.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_DayRangePainter old) =>
      old.low != low ||
      old.high != high ||
      old.price != price ||
      old.open != open ||
      old.track != track ||
      old.move != move ||
      old.mark != mark ||
      old.ring != ring;
}

/// The poll's failure, under prices that are still the last good ones.
class _BoardError extends StatelessWidget {
  const _BoardError({required this.store, required this.theme});

  final StockStore store;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: store.refresh,
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.fromLTRB(_inset, 2, _inset, 8),
        child: Row(
          children: [
            const FaIcon(
              FontAwesomeIcons.triangleExclamation,
              size: 10,
              color: kErrorColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                store.error,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  color: kErrorColor,
                  decoration: hovered ? TextDecoration.underline : null,
                  decorationColor: kErrorColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An empty or failed board: one line, and the one thing to do about it.
class _BoardHint extends StatelessWidget {
  const _BoardHint({
    required this.theme,
    required this.message,
    required this.action,
    required this.onAction,
  });

  final ThemeConfig theme;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(_inset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                color: theme.muted,
              ),
            ),
            const SizedBox(height: 8),
            StockActionButton(label: action, onTap: onAction),
          ],
        ),
      ),
    );
  }
}

/// The "Add widget…" menu's icon for this type.
const FaIconData stocksDesktopWidgetIcon = FontAwesomeIcons.chartLine;

/// The registry entry. Registered from `main()` beside the others.
final DesktopWidgetSpec stocksDesktopWidget = DesktopWidgetSpec(
  type: 'stocks',
  name: 'Stock market',
  description: 'Your watchlist, live — the same tickers as the bar',
  icon: stocksDesktopWidgetIcon,
  // Two cells wide is the floor the other text-bearing cards take: one cell is
  // an icon, and a symbol beside a price does not fit in it. 3x3 is the
  // default because it is the smallest card that carries the header, the
  // names, the day's range and the index trio a fresh watchlist opens with.
  minSpan: (columns: 2, rows: 1),
  maxSpan: (columns: 6, rows: 6),
  defaultSpan: (columns: 3, rows: 3),
  // The rows' hover fill runs nearly to the rim, so the card's own inset is
  // the content's.
  padding: EdgeInsets.zero,
  builder: (context, widget) => StocksWidget(span: widget.span),
);
