// The news desktop widget: the latest headlines from the wire services and
// public broadcasters `[news] sources` names, newest first, each a click away
// from the story.
//
// The eighth entry in `DesktopWidgetRegistry`, built the way the stock market
// card is: a lease on a store nobody owns (`NewsStore.instance`), drawn in the
// theme rather than over a picture, a fixed-extent list that scrolls under
// the wheel rather than overflowing the card.
//
// Three things about it:
//
// - **The row height is measured, not chosen.** A headline is two lines of
//   prose and the theme's `font_size` scales it, so the list's extent is laid
//   out from the font and scaler the rows are actually drawn in; a fixed 60px
//   clipped the second line at any size above the default.
// - **One feed failing is a line under the list, not an empty card.** The
//   store keeps each feed's last good stories, so the card shows what it has
//   and names what it could not reach, with a retry.
// - **Nothing on it moves at rest.** The list changes when a read lands and
//   not otherwise — the times are clock times, not ages, so there is nothing
//   to tick — and the card is `pumpAndSettle`-able.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/app_info.dart' show openUriWithDefault;
import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/desktop_layout.dart' show GridSpan;
import 'package:moonswing/desktop/widgets/desktop_widget.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
// The accent pill every desktop card's empty state uses; it lives with the
// stock strip because that is where the first one was.
import 'package:moonswing/modules/stocks.dart' show StockActionButton;
import 'package:moonswing/news/news_feed.dart';
import 'package:moonswing/news/news_format.dart';
import 'package:moonswing/news/news_store.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/stocks/stock_format.dart' show formatStockTime;
import 'package:moonswing/theme/tokens.dart';

/// The card's inner inset.
const double _inset = 12;

/// The shortest card that keeps its header. Below it every pixel is a row.
const double _headerMinHeight = 110;

/// Below this a headline gets one line rather than two: a card one row tall
/// is a ticker of titles, and two lines of each would show one story.
const double _twoLineMinHeight = 90;

/// The vertical padding inside a row, above and below its text.
const double _rowPadding = 7;

/// The widget's body. Store-injectable so a widget test can seed headlines and
/// pump it with nothing behind it.
class NewsWidget extends StatefulWidget {
  NewsWidget({
    super.key,
    required this.span,
    NewsStore? store,
    this.openUrl,
    this.openSettings,
    this.now,
  }) : store = store ?? NewsStore.instance;

  final GridSpan span;
  final NewsStore store;

  /// Opens a story. Injected by tests; the default is the browser.
  final bool Function(String url)? openUrl;

  /// Opens Settings at the sources. Injected by tests; the default asks the
  /// root through [SettingsController].
  final VoidCallback? openSettings;

  /// The clock the story times are written against. Injected by tests.
  final DateTime Function()? now;

  @override
  State<NewsWidget> createState() => _NewsWidgetState();
}

class _NewsWidgetState extends State<NewsWidget> {
  @override
  void initState() {
    super.initState();
    widget.store.acquire();
  }

  @override
  void didUpdateWidget(NewsWidget oldWidget) {
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

  void _open(String url) => (widget.openUrl ?? openUriWithDefault)(url);

  void _openSettings() {
    final open = widget.openSettings;
    if (open != null) {
      open();
    } else {
      SettingsController.instance.open(SettingsRoute.desktop);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribed here and nowhere above: the frame, the grid and the desktop
    // surface are none of them interested in a headline.
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
                if (showHeader) _NewsHeader(store: store, theme: theme),
                Expanded(
                  child: _body(
                    store,
                    theme,
                    titleLines: constraints.maxHeight >= _twoLineMinHeight
                        ? 2
                        : 1,
                  ),
                ),
                if (store.error.isNotEmpty && store.hasHeadlines)
                  _NewsError(store: store),
              ],
            );
          },
        );
      },
    );
  }

  Widget _body(NewsStore store, ThemeConfig theme, {required int titleLines}) {
    if (store.feeds.isEmpty) {
      return _NewsHint(
        theme: theme,
        message: 'No news sources chosen',
        action: 'Choose sources',
        onAction: _openSettings,
      );
    }
    if (!store.hasHeadlines) {
      if (store.loading) {
        return Center(child: LoadingIndicator(color: theme.muted));
      }
      return _NewsHint(
        theme: theme,
        message: store.error.isEmpty ? 'No headlines right now' : store.error,
        action: 'Try again',
        onAction: store.refresh,
      );
    }
    final headlines = store.headlines;
    final now = (widget.now ?? DateTime.now)();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 6),
      itemExtent: _rowExtent(context, titleLines),
      // A few rows either side rather than the 250px default, which at these
      // heights is most of a screen of rows built for nobody.
      scrollCacheExtent: const ScrollCacheExtent.pixels(120),
      itemCount: headlines.length,
      itemBuilder: (context, index) => _NewsRow(
        headline: headlines[index],
        theme: theme,
        titleLines: titleLines,
        now: now,
        onTap: () => _open(headlines[index].link),
      ),
    );
  }

  /// One row's height: [titleLines] of the title and a line of caption, in
  /// the font and at the scale they will be drawn in.
  double _rowExtent(BuildContext context, int titleLines) {
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final base = DefaultTextStyle.of(context).style;
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final title = measure(
      List.filled(titleLines, 'Ag').join('\n'),
      _NewsRow.titleStyle,
    );
    final caption = measure('Ag', _NewsRow.captionStyle);
    return (title + _NewsRow.gap + caption + _rowPadding * 2).ceilToDouble();
  }
}

class _NewsHeader extends StatelessWidget {
  const _NewsHeader({required this.store, required this.theme});

  final NewsStore store;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final updated = store.updatedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_inset, 6, 4, 0),
      child: Row(
        children: [
          FaIcon(
            FontAwesomeIcons.solidNewspaper,
            size: 13,
            color: theme.accentText,
          ),
          const SizedBox(width: 8),
          Text(
            'Headlines',
            style: TextStyle(
              fontSize: ShellFontSizes.label,
              fontWeight: FontWeight.w600,
              color: theme.popupForeground,
            ),
          ),
          // The time takes the slack and gives way first, right-aligned, so
          // it stays beside the button it was last refreshed by.
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
          RepaintBoundary(
            child: HoverRegion(
              onTap: store.refresh,
              builder: (context, hovered) => SizedBox.square(
                dimension: ShellSizes.minTapTarget,
                child: Center(
                  child: FaIcon(
                    FontAwesomeIcons.arrowsRotate,
                    size: 11,
                    color: hovered ? theme.popupForeground : theme.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({
    required this.headline,
    required this.theme,
    required this.titleLines,
    required this.now,
    required this.onTap,
  });

  final NewsHeadline headline;
  final ThemeConfig theme;
  final int titleLines;
  final DateTime now;
  final VoidCallback onTap;

  /// The styles [_NewsWidgetState._rowExtent] measures, without their colours:
  /// one definition, so the measurement and the row cannot disagree.
  static const TextStyle titleStyle = TextStyle(
    fontSize: ShellFontSizes.body,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle captionStyle = TextStyle(
    fontSize: ShellFontSizes.caption,
  );
  static const double gap = 2;

  @override
  Widget build(BuildContext context) {
    final published = headline.published;
    final caption = [
      headline.source,
      if (published != null) formatNewsTime(published, now),
    ].join(' · ');

    // A boundary per row: a hover tints one row, and the desktop surface has
    // no boundary of its own above this card.
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(
            horizontal: _inset - 6,
            vertical: _rowPadding,
          ),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover.atMostAlpha(0.16) : null,
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline.title,
                maxLines: titleLines,
                overflow: TextOverflow.ellipsis,
                style: titleStyle.copyWith(color: theme.popupForeground),
              ),
              const SizedBox(height: gap),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: captionStyle.copyWith(color: theme.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The feeds that failed, under stories that are still the last good ones.
class _NewsError extends StatelessWidget {
  const _NewsError({required this.store});

  final NewsStore store;

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

/// An empty or failed card: one line, and the one thing to do about it.
class _NewsHint extends StatelessWidget {
  const _NewsHint({
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
const FaIconData newsDesktopWidgetIcon = FontAwesomeIcons.solidNewspaper;

/// The registry entry. Registered from `main()` beside the others.
final DesktopWidgetSpec newsDesktopWidget = DesktopWidgetSpec(
  type: 'news',
  name: 'News',
  description: 'The latest headlines from AP, Reuters and others',
  icon: newsDesktopWidgetIcon,
  // Two cells wide is the floor every text-bearing card takes. 3x3 is the
  // default because it holds the header and four or five two-line headlines
  // on the default grid — enough to read as a front page.
  minSpan: (columns: 2, rows: 1),
  maxSpan: (columns: 6, rows: 6),
  defaultSpan: (columns: 3, rows: 3),
  // The rows' hover fill runs nearly to the rim, so the card's own inset is
  // the content's.
  padding: EdgeInsets.zero,
  builder: (context, widget) => NewsWidget(span: widget.span),
);
