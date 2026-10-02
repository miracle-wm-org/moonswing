// The bar's stock market strip: the watchlist crawling past the way it does
// along the bottom of a financial news channel, and the list itself behind a
// click — searchable by symbol or by name, so a ticker can be added without
// knowing exactly how Yahoo spells it.
//
// Everything that is not rendering is `lib/stocks/`: one leased poll for the
// machine, read by this and by the desktop widget alike, from `ticker`'s source
// by `ticker`'s rules. The crawl's own mechanics — a moving layer, not a moving
// picture — are `stock_crawl.dart`'s.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/app_info.dart' show openUriWithDefault;
import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/overlay/settings/controls.dart'
    show SettingsIconButton;
import 'package:moonswing/overlay_search_field.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/shell_text_root.dart';
import 'package:moonswing/stocks/stock_config.dart';
import 'package:moonswing/stocks/stock_crawl.dart';
import 'package:moonswing/stocks/stock_format.dart';
import 'package:moonswing/stocks/stock_quote.dart';
import 'package:moonswing/stocks/stock_store.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/tokens.dart';

export 'package:moonswing/stocks/stock_config.dart' show StockConfig;

/// The popup's size. Both axes pinned, for the GitHub card's reason: a
/// popup's surface is measured once, when it opens, and this card's content
/// is the one that changes most while it is up — a search replaces the whole
/// list on every keystroke. Sized to content, the window would chase it.
const double kStockPopupWidth = 400;
const double kStockPopupHeight = 480;

/// The height of every row in the card. Fixed, so the lists are
/// `itemExtent` lists and a scroll measures nothing.
const double _rowHeight = 46;

/// How long typing has to pause before a search goes out. Yahoo's own symbol
/// box waits about this long, and a request per keystroke is a rate limit
/// waiting to happen.
const Duration _searchDebounce = Duration(milliseconds: 250);

/// Where a quote's own page is: the source the numbers came from, so the
/// chart and the news are one click from the price.
String stockQuoteUrl(String symbol) =>
    'https://finance.yahoo.com/quote/${Uri.encodeComponent(symbol)}';

/// The bar module.
class StockTicker extends StatefulWidget {
  // Not const: the default store is the process-wide singleton.
  StockTicker({
    super.key,
    StockStore? store,
    this.config = const StockConfig(),
    this.openUrl,
  }) : store = store ?? StockStore.instance;

  /// Injected by tests, which seed a store rather than reaching the network.
  final StockStore store;

  /// `[modules.stocks]` — the crawl's window and pace.
  final StockConfig config;

  /// Opens a quote's page. Injected by tests; the default is the desktop's
  /// browser.
  final bool Function(String url)? openUrl;

  @override
  State<StockTicker> createState() => _StockTickerState();
}

class _StockTickerState extends State<StockTicker>
    with PopupHost<StockTicker> {
  /// Whether the pointer is over the strip — which holds it still, so a price
  /// can be read without chasing it.
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    widget.store
      ..acquire()
      ..addListener(_onChanged);
  }

  @override
  void didUpdateWidget(StockTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) return;
    oldWidget.store
      ..removeListener(_onChanged)
      ..release();
    widget.store
      ..acquire()
      ..addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store
      ..removeListener(_onChanged)
      ..release();
    closePopup();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    openBarPopup(
      context,
      preferredConstraints: const BoxConstraints.tightFor(
        width: kStockPopupWidth,
        height: kStockPopupHeight,
      ),
      // The search field is an `EditableText` on a popup of the panel, which
      // inherits the panel's keyboard interactivity — and a panel takes none.
      needsKeyboard: true,
      child: ThemeProvider(
        child: StockPopup(
          store: widget.store,
          onClose: closePopup,
          openUrl: widget.openUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = widget.store;
    final anchor = BarScope.maybeOf(context);
    final vertical = anchor == 'left' || anchor == 'right';

    if (store.loading && !store.hasQuotes && store.symbols.isNotEmpty) {
      // A fixed box, so the modules beside it do not shuffle when the quotes
      // land — the weather module's placeholder, for its reason.
      return SizedBox(
        width: 16,
        height: 16,
        child: Center(
          child: LoadingIndicator(color: theme.foreground, size: 14),
        ),
      );
    }

    final quotes = store.quotes;
    final Widget content;
    if (vertical || quotes.isEmpty) {
      // A crawl needs a window wider than it is tall, and a side bar has none:
      // there the strip is its mark, coloured by how the first ticker is doing,
      // and the list is a click away. The same mark stands in when there is
      // nothing to crawl — dimmed, with the reason a hover away.
      content = _BarMark(
        quote: quotes.isEmpty ? null : quotes.first,
        message: quotes.isNotEmpty
            ? null
            : store.symbols.isEmpty
                ? 'Add tickers'
                : (store.error.isNotEmpty ? store.error : 'No quotes'),
        hovered: _hovered,
      );
    } else {
      content = TickerCrawl(
        maxWidth: widget.config.width,
        speed: widget.config.scrollSpeed,
        paused: _hovered || isPopupOpen,
        child: _CrawlStrip(quotes: quotes, theme: theme),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: BarButton(
        active: isPopupOpen,
        onTapDown: (_) => _togglePopup(context),
        child: content,
      ),
    );
  }
}

/// The glyph a bar shows in place of the crawl.
class _BarMark extends StatelessWidget {
  const _BarMark({
    required this.quote,
    required this.message,
    required this.hovered,
  });

  final StockQuote? quote;

  /// Why there is nothing to crawl, shown beside the mark on hover only: it is
  /// a sentence, and a sentence in the bar pushes every module along.
  final String? message;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final quote = this.quote;
    final color = quote == null
        ? theme.muted
        : stockChangeColor(
            quote.direction,
            surface: theme.panelBackground,
            flat: theme.foreground,
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(
          FontAwesomeIcons.chartLine,
          size: ShellFontSizes.title,
          color: color,
        ),
        if (hovered && message != null) ...[
          const SizedBox(width: 6),
          Text(
            message!,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              color: theme.muted,
            ),
          ),
        ],
      ],
    );
  }
}

/// One pass of the crawl: every quote, end to end.
class _CrawlStrip extends StatelessWidget {
  const _CrawlStrip({required this.quotes, required this.theme});

  final List<StockQuote> quotes;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < quotes.length; i++) ...[
          if (i > 0) _CrawlSeparator(color: theme.muted),
          _CrawlItem(quote: quotes[i], theme: theme),
        ],
      ],
    );
  }
}

/// The dot between two tickers, which is what keeps one quote's change from
/// reading as the next quote's price.
class _CrawlSeparator extends StatelessWidget {
  const _CrawlSeparator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: color.atMostAlpha(0.6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// `AAPL 227.52 ▲ +1.23%` — a ticker as a news channel prints one: the name
/// in the bar's own colour, the move in green or red.
class _CrawlItem extends StatelessWidget {
  const _CrawlItem({required this.quote, required this.theme});

  final StockQuote quote;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final change = stockChangeColor(
      quote.direction,
      surface: theme.panelBackground,
      flat: theme.muted,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stockLabel(quote),
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            fontWeight: FontWeight.w700,
            color: theme.foreground,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          formatStockPrice(quote),
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            color: theme.foreground,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 6),
        _DirectionGlyph(direction: quote.direction, color: change, size: 9),
        const SizedBox(width: 3),
        Text(
          formatStockPercent(quote),
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            color: change,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// ▲, ▼ or a flat bar. A glyph from the icon font rather than a text
/// character, which the theme's font may not have.
class _DirectionGlyph extends StatelessWidget {
  const _DirectionGlyph({
    required this.direction,
    required this.color,
    required this.size,
  });

  final int direction;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FaIcon(
      direction > 0
          ? FontAwesomeIcons.caretUp
          : direction < 0
              ? FontAwesomeIcons.caretDown
              : FontAwesomeIcons.minus,
      size: size,
      color: color,
    );
  }
}

/// The card behind the strip: the watchlist, and a search that adds to it.
///
/// Takes the store rather than a snapshot of it, so the prices in an open card
/// keep moving with the poll behind them.
class StockPopup extends StatefulWidget {
  const StockPopup({
    super.key,
    required this.store,
    this.onClose,
    this.openUrl,
  });

  final StockStore store;
  final VoidCallback? onClose;
  final bool Function(String url)? openUrl;

  @override
  State<StockPopup> createState() => _StockPopupState();
}

class _StockPopupState extends State<StockPopup> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'stock-search');

  Timer? _debounce;

  /// Bumped per search sent, so an answer that arrives after a later one was
  /// asked for is dropped rather than painted over it.
  int _searchSeq = 0;

  List<StockSearchResult> _results = const [];
  bool _searching = false;
  String _searchError = '';

  /// The keyboard's row in the results, so Enter adds what the arrows chose.
  int _selected = 0;

  String get _text => _query.text.trim();

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _searchSeq++;
      setState(() {
        _results = const [];
        _searching = false;
        _searchError = '';
        _selected = 0;
      });
      return;
    }
    setState(() {
      _searching = true;
      _selected = 0;
    });
    _debounce = Timer(_searchDebounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    final seq = ++_searchSeq;
    List<StockSearchResult> results = const [];
    var error = '';
    try {
      results = await widget.store.search(query);
    } catch (e) {
      error = '$e';
    }
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = results;
      _searchError = error;
      _searching = false;
      _selected = 0;
    });
  }

  /// The symbol the typed text names, when search has settled with nothing
  /// to offer — the escape hatch for a search that is down, or a symbol
  /// Yahoo's search does not surface. Not offered beside real results: every
  /// one-word company name is also a well-formed symbol, and "APPLE" under
  /// Apple Inc. is noise.
  String? get _typedSymbol {
    if (_searching || _results.isNotEmpty) return null;
    return normalizeSymbol(_text);
  }

  /// The rows the search shows, in order: the results, then the typed symbol.
  List<_Candidate> get _candidates => [
        for (final result in _results)
          _Candidate(result.symbol.toUpperCase(), result),
        if (_typedSymbol case final symbol?) _Candidate(symbol, null),
      ];

  void _add(String symbol) {
    widget.store.addSymbol(symbol);
    // Back to the list, where the new ticker is: the search has done its job.
    _query.clear();
    _onQueryChanged('');
    _focus.requestFocus();
  }

  void _open(String symbol) {
    (widget.openUrl ?? openUriWithDefault)(stockQuoteUrl(symbol));
    widget.onClose?.call();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final candidates = _candidates;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        if (_text.isNotEmpty) {
          _query.clear();
          _onQueryChanged('');
        } else {
          widget.onClose?.call();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (candidates.isEmpty) return KeyEventResult.ignored;
        setState(() => _selected = (_selected + 1) % candidates.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (candidates.isEmpty) return KeyEventResult.ignored;
        setState(() => _selected =
            (_selected - 1 + candidates.length) % candidates.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (candidates.isEmpty) return KeyEventResult.ignored;
        final pick = candidates[_selected.clamp(0, candidates.length - 1)];
        if (!widget.store.symbols.contains(pick.symbol)) _add(pick.symbol);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final theme = ThemeScope.of(context);
        final store = widget.store;
        final searching = _text.isNotEmpty;

        // [ShellTextRoot] because popup content lays out under its own
        // FlutterView, with no Directionality above it; and
        // [DefaultTextEditingShortcuts] because no WidgetsApp is mounted to
        // supply the field's key bindings. Focus nests inside them, so it gets
        // first refusal on Up/Down/Enter/Escape.
        return ShellTextRoot(
          style: TextStyle(
            color: theme.popupForeground,
            fontSize: ShellFontSizes.secondary,
          ),
          child: DefaultTextEditingShortcuts(
            child: Focus(
              onKeyEvent: _onKey,
              child: PopupCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(store: store, theme: theme),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.controlSurface,
                          borderRadius:
                              BorderRadius.circular(ShellRadii.control),
                        ),
                        child: OverlaySearchField(
                          controller: _query,
                          focusNode: _focus,
                          theme: theme,
                          hint: 'Add a ticker — symbol or company name',
                          onChanged: _onQueryChanged,
                        ),
                      ),
                    ),
                    Container(height: 1, color: theme.divider),
                    Expanded(
                      child: searching
                          ? _SearchResults(
                              candidates: _candidates,
                              searching: _searching,
                              error: _searchError,
                              selected: _selected,
                              watched: store.symbols.toSet(),
                              theme: theme,
                              onAdd: _add,
                            )
                          : _Watchlist(
                              store: store,
                              theme: theme,
                              onOpen: _open,
                            ),
                    ),
                    if (store.error.isNotEmpty) ...[
                      Container(height: 1, color: theme.divider),
                      _ErrorLine(store: store, theme: theme),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A search row: the symbol, and the result it came from — null for the
/// symbol exactly as typed.
class _Candidate {
  const _Candidate(this.symbol, this.result);

  final String symbol;
  final StockSearchResult? result;
}

class _Header extends StatelessWidget {
  const _Header({required this.store, required this.theme});

  final StockStore store;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final updated = store.updatedAt;
    final open = store.anyMarketOpen;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
      child: Row(
        children: [
          FaIcon(
            FontAwesomeIcons.chartLine,
            size: ShellFontSizes.title,
            color: theme.accentText,
          ),
          const SizedBox(width: 10),
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
            _MarketDot(open: open, theme: theme),
            const SizedBox(width: 4),
            Text(
              open ? 'Trading' : 'Closed',
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                color: theme.muted,
              ),
            ),
          ],
          // Expanded rather than a Spacer and a fixed label: at a large
          // `font_size` the timestamp is what gives way, never the buttons.
          Expanded(
            child: updated == null
                ? const SizedBox.shrink()
                : Text(
                    'Updated ${formatStockTime(updated)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: ShellFontSizes.caption,
                      color: theme.muted,
                    ),
                  ),
          ),
          SettingsIconButton(
            icon: FontAwesomeIcons.rotate,
            tooltip: 'Refresh',
            onTap: store.refresh,
          ),
        ],
      ),
    );
  }
}

/// The dot beside "Trading": green while a market on the list is, muted when
/// none is.
class _MarketDot extends StatelessWidget {
  const _MarketDot({required this.open, required this.theme});

  final bool open;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: open
            ? stockChangeColor(1, surface: theme.popupBackground, flat: theme.muted)
            : theme.muted.atMostAlpha(0.6),
      ),
    );
  }
}

/// The watchlist, one row per symbol on it — quoted, not found, or waiting
/// for its first quote.
class _Watchlist extends StatelessWidget {
  const _Watchlist({
    required this.store,
    required this.theme,
    required this.onOpen,
  });

  final StockStore store;
  final ThemeConfig theme;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final symbols = store.symbols;
    if (symbols.isEmpty) {
      return _Hint(
        icon: FontAwesomeIcons.magnifyingGlassDollar,
        title: 'Your watchlist is empty',
        body: 'Search above by symbol or company name to add a ticker.',
        theme: theme,
        action: 'Start with the S&P 500, Dow and Nasdaq',
        onAction: () => store.addSymbols(kSuggestedStockSymbols),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemExtent: _rowHeight,
      itemCount: symbols.length,
      itemBuilder: (context, index) {
        final symbol = symbols[index];
        return _WatchRow(
          symbol: symbol,
          quote: store.quoteFor(symbol),
          missing: store.missing.contains(symbol),
          first: index == 0,
          last: index == symbols.length - 1,
          theme: theme,
          onOpen: () => onOpen(symbol),
          onUp: () => store.moveSymbol(symbol, -1),
          onDown: () => store.moveSymbol(symbol, 1),
          onRemove: () => store.removeSymbol(symbol),
        );
      },
    );
  }
}

class _WatchRow extends StatelessWidget {
  const _WatchRow({
    required this.symbol,
    required this.quote,
    required this.missing,
    required this.first,
    required this.last,
    required this.theme,
    required this.onOpen,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final String symbol;
  final StockQuote? quote;
  final bool missing;
  final bool first;
  final bool last;
  final ThemeConfig theme;
  final VoidCallback onOpen;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final quote = this.quote;
    final subtitle = quote != null
        ? [
            if (quote.name.isNotEmpty && stockLabel(quote) != quote.name)
              quote.name,
            ?quote.sessionLabel,
          ].join(' · ')
        : missing
            ? 'Not found on Yahoo Finance'
            : 'Waiting for a quote…';

    // A boundary per row: hovering one tints one row, not the card.
    return RepaintBoundary(
      child: HoverRegion(
        onTap: quote == null ? null : onOpen,
        builder: (context, hovered) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.only(left: 8, right: 2),
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
                      quote == null ? symbol : stockLabel(quote),
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
                          color: missing ? kErrorColor : theme.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (quote != null) ...[
                const SizedBox(width: 8),
                _PriceColumn(quote: quote, theme: theme),
              ] else if (!missing)
                const LoadingIndicator(size: 12),
              const SizedBox(width: 4),
              // Kept in the layout while hidden, so the price column does not
              // jump sideways as the pointer moves down the list — and not
              // interactive while hidden, which `Visibility.maintain` would be.
              Visibility(
                visible: hovered,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SettingsIconButton(
                      icon: FontAwesomeIcons.chevronUp,
                      tooltip: 'Move earlier',
                      size: 10,
                      box: ShellSizes.minTapTarget,
                      enabled: !first,
                      onTap: onUp,
                    ),
                    SettingsIconButton(
                      icon: FontAwesomeIcons.chevronDown,
                      tooltip: 'Move later',
                      size: 10,
                      box: ShellSizes.minTapTarget,
                      enabled: !last,
                      onTap: onDown,
                    ),
                  ],
                ),
              ),
              SettingsIconButton(
                icon: FontAwesomeIcons.xmark,
                tooltip: 'Remove from watchlist',
                box: ShellSizes.minTapTarget,
                color: theme.muted,
                hoverColor: kErrorColor,
                onTap: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The price over the day's move, the move in a pill of its own colour.
class _PriceColumn extends StatelessWidget {
  const _PriceColumn({required this.quote, required this.theme});

  final StockQuote quote;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        StockChangePill(quote: quote, surface: theme.popupBackground),
      ],
    );
  }
}

/// What [StockChangePill] says, for a layout that measures it.
String stockPillText(StockQuote quote, {bool showAbsolute = true}) =>
    showAbsolute
        ? '${formatStockChange(quote)} (${formatStockPercent(quote)})'
        : formatStockPercent(quote);

/// Everything a [StockChangePill] is wider than its text at the caption size:
/// its padding, its glyph and the gap after it.
const double kStockPillChrome =
    5 * 2 + (ShellFontSizes.caption - 3) + 3;

/// `▲ +1.23 (+0.54%)` on a wash of its own colour — the one place a quote's
/// direction is a fill rather than just a hue, so it reads at a glance down a
/// column. Shared with the desktop widget.
class StockChangePill extends StatelessWidget {
  const StockChangePill({
    super.key,
    required this.quote,
    required this.surface,
    this.showAbsolute = true,
    this.fontSize = ShellFontSizes.caption,
  });

  final StockQuote quote;

  /// What the pill sits on, so its text is lifted to read there.
  final Color surface;

  /// Whether the move in currency goes before the percentage. The narrow
  /// layouts drop it.
  final bool showAbsolute;

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = stockChangeColor(
      quote.direction,
      surface: surface,
      flat: theme.muted,
    );
    final text = stockPillText(quote, showAbsolute: showAbsolute);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(ShellRadii.barButton),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DirectionGlyph(
            direction: quote.direction,
            color: color,
            size: fontSize - 3,
          ),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.candidates,
    required this.searching,
    required this.error,
    required this.selected,
    required this.watched,
    required this.theme,
    required this.onAdd,
  });

  final List<_Candidate> candidates;
  final bool searching;
  final String error;
  final int selected;
  final Set<String> watched;
  final ThemeConfig theme;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      if (searching) {
        return const Center(child: LoadingIndicator());
      }
      return _Hint(
        icon: FontAwesomeIcons.circleQuestion,
        title: error.isNotEmpty ? 'Search unavailable' : 'No matches',
        body: error.isNotEmpty
            ? error
            : 'Try the company name, or the symbol as Yahoo Finance spells '
                'it — BRK-B, ^GSPC, BTC-USD.',
        theme: theme,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemExtent: _rowHeight,
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              return _ResultRow(
                candidate: candidate,
                added: watched.contains(candidate.symbol),
                selected: index == selected,
                theme: theme,
                onAdd: () => onAdd(candidate.symbol),
              );
            },
          ),
        ),
        if (searching || error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: searching
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: LoadingIndicator(size: 12),
                  )
                : Text(
                    error,
                    style: const TextStyle(
                      fontSize: ShellFontSizes.caption,
                      color: kErrorColor,
                    ),
                  ),
          ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.candidate,
    required this.added,
    required this.selected,
    required this.theme,
    required this.onAdd,
  });

  final _Candidate candidate;
  final bool added;
  final bool selected;
  final ThemeConfig theme;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final result = candidate.result;
    final detail = result == null
        ? 'Add the symbol exactly as typed'
        : [result.exchange, result.kind].where((s) => s.isNotEmpty).join(' · ');
    return RepaintBoundary(
      child: HoverRegion(
        enabled: !added,
        onTap: onAdd,
        builder: (context, hovered) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: (hovered || selected) && !added
                ? theme.surfaceHover.atMostAlpha(0.16)
                : null,
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                child: Text(
                  candidate.symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.body,
                    fontWeight: FontWeight.w700,
                    color: theme.popupForeground,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result == null || result.name.isEmpty
                          ? candidate.symbol
                          : result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ShellFontSizes.secondary,
                        color: theme.popupForeground,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
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
              const SizedBox(width: 8),
              if (added)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(
                      FontAwesomeIcons.check,
                      size: 11,
                      color: theme.accentText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Added',
                      style: TextStyle(
                        fontSize: ShellFontSizes.caption,
                        color: theme.accentText,
                      ),
                    ),
                  ],
                )
              else
                FaIcon(
                  FontAwesomeIcons.plus,
                  size: 12,
                  color: hovered || selected ? theme.accentText : theme.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An empty state: a glyph, a line, and a sentence saying what to do.
class _Hint extends StatelessWidget {
  const _Hint({
    required this.icon,
    required this.title,
    required this.body,
    required this.theme,
    this.action,
    this.onAction,
  });

  final FaIconData icon;
  final String title;
  final String body;
  final ThemeConfig theme;

  /// A button under the sentence, when there is one obvious thing to do.
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    // Scrolled rather than overflowed: this is prose at the user's own
    // `font_size`, in a card of one fixed height.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, size: 22, color: theme.muted),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.label,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                color: theme.muted,
              ),
            ),
            if (action case final label?) ...[
              const SizedBox(height: 14),
              StockActionButton(label: label, onTap: onAction ?? () {}),
            ],
          ],
        ),
      ),
    );
  }
}

/// The accent-filled button an empty state offers. Shared with the desktop
/// widget, whose empty board offers one too.
class StockActionButton extends StatelessWidget {
  const StockActionButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        constraints: const BoxConstraints(minHeight: ShellSizes.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? theme.accent : theme.accent.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: ShellFontSizes.secondary,
            fontWeight: FontWeight.w600,
            color: kOnAccent,
          ),
        ),
      ),
    );
  }
}

/// The poll's failure, under quotes that are still the last good ones.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.store, required this.theme});

  final StockStore store;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      child: Row(
        children: [
          const FaIcon(
            FontAwesomeIcons.triangleExclamation,
            size: 11,
            color: kErrorColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              store.hasQuotes
                  ? '${store.error} — showing the last prices'
                  : store.error,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: ShellFontSizes.caption,
                color: kErrorColor,
              ),
            ),
          ),
          SettingsIconButton(
            icon: FontAwesomeIcons.rotateRight,
            tooltip: 'Try again',
            onTap: store.refresh,
          ),
        ],
      ),
    );
  }
}

final Module stocksModule = Module.simple<StockConfig>(
  configKey: 'stocks',
  fromMap: (map) {
    final config = StockConfig.fromMap(map);
    // The store, not the widget, owns the watchlist: the desktop widget reads
    // it too, and the poll outlives any one crawl.
    StockStore.instance.configure(config);
    return config;
  },
  builder: (context, config) => StockTicker(config: config),
);
