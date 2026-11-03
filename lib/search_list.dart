/// The anchored, searchable dropdown: a trigger that floats a filterable list in
/// the *root* overlay.
///
/// Every selector in the settings UI is a thin wrapper over this, supplying its
/// trigger, its ranking and its row content. Two properties are load-bearing and
/// documented at their origin (`SettingsColorField`): the list floats in the
/// **root** overlay, because the settings content pane is a nested `Navigator`
/// whose `Overlay` would clip a list hanging below the row; and the items arrive
/// **as a parameter**, so widget tests never fork `fc-list` or load the IANA
/// tables.
///
/// `matchTriggerWidth` sizes the card to the trigger, `contentWidth` widens it
/// to rows the trigger is narrower than, and `showSearch` lets a short list do
/// without a filter field.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The filter field's laid-out height (its padding, the row's own padding, a
/// line of [ShellFontSizes.body] and the border). Only the flip estimate needs
/// it — the card itself measures.
const double _kSearchFieldHeight = 48;

/// Gap between the trigger and the card it drops.
const double _kGap = 6;

/// The horizontal inset of a row's content inside the card, and the card's own
/// border width.
///
/// Public because a caller that *measures* its rows has to lay text out in the
/// width the card will actually give it — [dropdownContentWidth] is that
/// subtraction, spelled once so a padding change cannot silently make somebody
/// else's measurement wrong.
const double kDropdownRowInset = 12;
const double kDropdownCardBorder = 1;

/// The width a row's content is laid out in, inside a card [cardWidth] wide.
double dropdownContentWidth(double cardWidth) =>
    math.max(0, cardWidth - 2 * (kDropdownRowInset + kDropdownCardBorder));

/// The card width a row of content [contentWidth] wide needs: the inverse of
/// [dropdownContentWidth].
double dropdownCardWidth(double contentWidth) =>
    contentWidth + 2 * (kDropdownRowInset + kDropdownCardBorder);

/// The widest a card grows to fit its rows, under
/// [AnchoredSearchDropdown.contentWidth]. Past this a row ellipsises: a list
/// whose longest entry is a sentence is not a reason for a card the width of
/// the panel.
const double kDropdownMaxCardWidth = 480;

/// How close a card may come to the edge of the window it floats in, where it
/// is not simply following a trigger that is already closer.
const double kDropdownEdgeMargin = 8;

/// Where a card [cardWidth] wide hangs off a trigger spanning [triggerLeft] to
/// [triggerRight] in a window [overlayWidth] wide: which of the trigger's edges
/// it is anchored to, and how far it has to be nudged sideways to stay in the
/// window.
///
/// [alignRight] is the caller's preference and wins whenever it fits. When it
/// does not and the other edge does, the card flips — a card measured wider
/// than its trigger, dropping from a control at the right of a row, grows
/// leftwards rather than off the window. When neither fits it keeps the
/// preference and is slid back in. The margin never pushes a card off a
/// trigger that is itself closer to the edge than [margin]. Pure, so the
/// arithmetic is testable without an overlay.
({bool alignRight, double dx}) placeDropdownCard({
  required double triggerLeft,
  required double triggerRight,
  required double cardWidth,
  required double overlayWidth,
  required bool alignRight,
  double margin = kDropdownEdgeMargin,
}) {
  final lo = math.min(margin, triggerLeft);
  final hi = math.max(overlayWidth - margin, triggerRight);
  double leftOf(bool right) => right ? triggerRight - cardWidth : triggerLeft;
  bool fits(bool right) {
    final left = leftOf(right);
    return left >= lo && left + cardWidth <= hi;
  }

  var right = alignRight;
  if (!fits(right) && fits(!right)) right = !right;
  final left = leftOf(right);
  final clamped = left.clamp(lo, math.max(lo, hi - cardWidth));
  return (alignRight: right, dx: clamped - left);
}

/// The card's own vertical padding above and below its list, plus its border.
///
/// Public alongside [kDropdownRowInset]: a caller sizing a card to its rows
/// has to add what the card puts around them, and two spellings of that would
/// drift the first time the padding moved.
const double kDropdownCardPadding = 14;

/// Scroll offset that brings row [index] (of height [rowHeight]) into view on
/// [position], or null when it already is. Pure, so the keyboard-navigation
/// math is unit-testable without a scroll view.
double? revealRowOffset(int index, double rowHeight, ScrollMetrics position) {
  final top = index * rowHeight;
  final bottom = top + rowHeight;
  if (top < position.pixels) return top;
  if (bottom > position.pixels + position.viewportDimension) {
    return (bottom - position.viewportDimension).clamp(
      0.0,
      position.maxScrollExtent,
    );
  }
  return null;
}

class AnchoredSearchDropdown<T> extends StatefulWidget {
  const AnchoredSearchDropdown({
    super.key,
    this.filter,
    this.search,
    this.searchDebounce = const Duration(milliseconds: 300),
    this.loadingText = 'Searching…',
    this.showSearch = true,
    required this.itemBuilder,
    required this.onSelected,
    required this.triggerBuilder,
    this.width = 240,
    this.matchTriggerWidth = false,
    this.contentWidth,
    this.maxHeight = 300,
    this.rowHeight = 30,
    this.emptyText = 'No matches',
    this.alignRight = false,
    this.initialHighlight,
    this.closeKey,
  }) : assert(
         filter != null || search != null,
         'a dropdown needs either a filter or a search',
       );

  /// Ranks the items for a query, synchronously. Called with `''` when the list
  /// opens. Null when the items come from [search] instead.
  final List<T> Function(String query)? filter;

  /// Ranks the items for a query *asynchronously* — a network lookup rather than
  /// a ranking of a list already in memory.
  ///
  /// Supersedes [filter] when both are given, which is what a caller with a local
  /// list *and* a remote one wants: [filter] answers the first frame, [search]
  /// replaces it when the request lands.
  ///
  /// Debounced by [searchDebounce], and answers are applied in request order — a
  /// slow response for "lon" must not land on top of a fast one for "london". A
  /// call that throws is reported as no matches: the dropdown is not the place to
  /// explain a failed HTTP request, and a list left on the previous query's
  /// results would be showing the wrong ones.
  final Future<List<T>> Function(String query)? search;

  /// How long typing has to stop before [search] is called. A request per
  /// keystroke is a request per keystroke against somebody else's API.
  final Duration searchDebounce;

  /// Shown in place of [emptyText] while a [search] is in flight, so an empty
  /// list reads as "not yet" rather than "none" — the rule
  /// `ShellServicesScope` documents for the launcher.
  final String loadingText;

  /// Whether the card carries its filter field.
  ///
  /// A few hundred font families need one; the two output devices a machine has
  /// do not, and a search box over a list shorter than the box is chrome asking to
  /// be typed into. False keeps the rest of the card and moves the autofocus to
  /// the key handler, so Up/Down/Enter/Escape still drive the list.
  ///
  /// A [search] dropdown ignores this: its list *is* the query.
  final bool showSearch;

  /// The row's *content*; the generic supplies the row chrome (hover fill,
  /// highlight fill, tap target, fixed [rowHeight]).
  final Widget Function(BuildContext context, T item, bool highlighted)
  itemBuilder;

  final ValueChanged<T> onSelected;

  /// Builds the always-visible trigger. Call [toggle] to open/close;
  /// [open] reports whether the list is up (for a chevron, a border).
  final Widget Function(BuildContext context, bool open, VoidCallback toggle)
  triggerBuilder;

  /// The card's width, and the fallback when [matchTriggerWidth] cannot
  /// measure.
  final double width;

  /// Size the card to the trigger rather than to [width].
  ///
  /// What a selector spanning a settings row wants: a card narrower than the
  /// control it drops out of reads as a different control, and one wider
  /// overhangs the row. Measured at open, when the trigger has been laid out.
  final bool matchTriggerWidth;

  /// The width the widest row's *content* needs, asked at open; the card grows
  /// to hold it (up to [kDropdownMaxCardWidth]) where [width] or the trigger
  /// would be narrower.
  ///
  /// What a selector in a settings row needs. The row lays its control out at
  /// its content's width, so a trigger showing "Fill" is as wide as "Fill", and
  /// a card matched to it ellipsised "Contain" and "Natural" — every longer
  /// option the list existed to offer. The rows are the caller's, so only the
  /// caller can say how wide they are; asked at open rather than per build,
  /// because a page of key bindings is a page of seven-hundred-row lists.
  final double Function(BuildContext context)? contentWidth;

  final double maxHeight;

  /// Fixed row height — scrolling the highlight into view is arithmetic, not
  /// measurement.
  final double rowHeight;

  final String emptyText;

  /// Anchor the card's right edge to the trigger's (for a trigger at the
  /// right edge of a narrow column, where the card must grow leftwards).
  final bool alignRight;

  /// Where the highlight starts on open (e.g. the currently-selected item),
  /// given the unfiltered ranking. The list opens scrolled there. Null starts
  /// at the top.
  final int Function(List<T> items)? initialHighlight;

  /// When this value changes the open list closes — the font field uses the
  /// current family, so switching themes under an open list cannot write the
  /// old theme's pick into the new one.
  final Object? closeKey;

  @override
  State<AnchoredSearchDropdown<T>> createState() =>
      _AnchoredSearchDropdownState<T>();
}

class _AnchoredSearchDropdownState<T> extends State<AnchoredSearchDropdown<T>> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  /// The card's width, resolved at open: [matchTriggerWidth]'s trigger width
  /// or [AnchoredSearchDropdown.width], widened to [contentWidth] and narrowed
  /// to the window. The trigger is read from the render object rather than a
  /// `LayoutBuilder`, because the card is built into another subtree entirely
  /// and only the *host* element knows how wide the row let the trigger be.
  double _cardWidth = 0;

  /// Which edge of the trigger the card hangs from, and how far it is slid to
  /// stay in the window — [placeDropdownCard]'s answer for this open.
  bool _alignRight = false;
  double _dx = 0;

  /// Whether the card opens *upwards*, decided at open from the room under the
  /// trigger. A dropdown near the foot of the settings panel would otherwise
  /// hang its list off the bottom of the panel and over the desktop, which is
  /// where this control used to be safe: it expanded inline and scrolled with
  /// the pane.
  bool _above = false;

  /// The scroll position the trigger sits in, while a card is open.
  ///
  /// The card is anchored to a [CompositedTransformTarget] on the *trigger*, which
  /// lives in the page, while the card is in the root `Overlay`. If the page
  /// scrolls the trigger far enough away for a lazy `SliverList` to unmount it,
  /// the follower has no leader and paints nowhere — leaving an invisible card
  /// over a full-screen barrier. The barrier happening to block the wheel today
  /// is an accident of the barrier, not a guarantee.
  ScrollPosition? _hostScroll;

  void _watchScroll() {
    _hostScroll = Scrollable.maybeOf(context)?.position
      ?..isScrollingNotifier.addListener(_onHostScroll);
  }

  void _unwatchScroll() {
    _hostScroll?.isScrollingNotifier.removeListener(_onHostScroll);
    _hostScroll = null;
  }

  void _onHostScroll() {
    if (_entry != null) _close();
  }

  @override
  void didUpdateWidget(AnchoredSearchDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.closeKey != oldWidget.closeKey) _close();
  }

  @override
  void dispose() {
    _unwatchScroll();
    // Not _close(): that repaints the trigger, and this element is on its way
    // out of the tree.
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _toggle() => _entry != null ? _close() : _open();

  void _open() {
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final trigger = context.findRenderObject();
    final overlayBox = overlay.context.findRenderObject();
    // Reset first: these are answers about *this* open, and an unmeasurable
    // trigger must fall back to the defaults rather than to the last open's.
    _above = false;
    _alignRight = widget.alignRight;
    _dx = 0;
    final measured = trigger is RenderBox && trigger.hasSize ? trigger : null;
    var width = widget.matchTriggerWidth && measured != null
        ? measured.size.width
        : widget.width;
    final base = width;
    final content = widget.contentWidth?.call(context);
    if (content != null) {
      width = math.max(
        width,
        math.min(kDropdownMaxCardWidth, dropdownCardWidth(content)),
      );
    }
    if (measured != null) {
      _above = _opensUpwards(measured, overlayBox);
      if (overlayBox is RenderBox && overlayBox.hasSize) {
        final room = overlayBox.size.width - 2 * kDropdownEdgeMargin;
        // Never narrower than it would have been unmeasured: a trigger wider
        // than the window's margins already had a card that wide.
        width = math.min(width, math.max(base, room));
        final left = measured
            .localToGlobal(Offset.zero, ancestor: overlayBox)
            .dx;
        final place = placeDropdownCard(
          triggerLeft: left,
          triggerRight: left + measured.size.width,
          cardWidth: width,
          overlayWidth: overlayBox.size.width,
          alignRight: widget.alignRight,
        );
        _alignRight = place.alignRight;
        _dx = place.dx;
      }
    }
    _cardWidth = width;
    final entry = OverlayEntry(builder: (_) => _buildPicker());
    _entry = entry;
    overlay.insert(entry);
    _watchScroll();
    setState(() {});
  }

  /// True when the card does not fit under the trigger but does fit over it.
  ///
  /// Ties go downwards: that is where a dropdown belongs, and a control with
  /// room on neither side keeps the conventional side rather than flipping on
  /// a pixel.
  bool _opensUpwards(RenderBox trigger, RenderObject? overlayBox) {
    if (overlayBox is! RenderBox || !overlayBox.hasSize) return false;
    final top = trigger.localToGlobal(Offset.zero, ancestor: overlayBox).dy;
    final wanted = _estimatedHeight() + _kGap;
    final below = overlayBox.size.height - (top + trigger.size.height);
    return below < wanted && top >= below;
  }

  /// Rough card height, for the flip decision alone: the rows the card opens
  /// with plus the filter field it may carry, capped by
  /// [AnchoredSearchDropdown.maxHeight]. A [search] dropdown has no list yet,
  /// so it is measured at its maximum. The card lays itself out either way —
  /// this only picks the side.
  double _estimatedHeight() {
    final rows = widget.search != null ? null : widget.filter?.call('').length;
    if (rows == null) return widget.maxHeight;
    final search = widget.showSearch ? _kSearchFieldHeight : 0.0;
    return math.min(
      widget.maxHeight,
      search + rows * widget.rowHeight + kDropdownCardPadding,
    );
  }

  void _close() {
    _unwatchScroll();
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _select(T item) {
    // Closed *before* the callback: an OverlayEntry does not rebuild on the
    // host's setState, so a popup left open would keep showing stale row
    // state for the pick just made.
    _close();
    widget.onSelected(item);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: widget.triggerBuilder(context, _entry != null, _toggle),
    );
  }

  Widget _buildPicker() {
    final right = _alignRight;
    // The card hangs off whichever edge of the trigger it opens from, and
    // meets it with its own opposite edge.
    final anchor = _above
        ? (right ? Alignment.topRight : Alignment.topLeft)
        : (right ? Alignment.bottomRight : Alignment.bottomLeft);
    final follower = _above
        ? (right ? Alignment.bottomRight : Alignment.bottomLeft)
        : (right ? Alignment.topRight : Alignment.topLeft);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: anchor,
          followerAnchor: follower,
          offset: Offset(_dx, _above ? -_kGap : _kGap),
          // The root overlay has no repaint boundary of its own, so without
          // this every frame of a scroll through the list re-records the whole
          // window under it — the settings panel and all its rows.
          child: RepaintBoundary(
            // Absorbs clicks on the card's own chrome, which would otherwise
            // fall through to the barrier above — see the colour picker.
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: _DropdownPopup<T>(
                config: widget,
                width: _cardWidth,
                onSelected: _select,
                onDismiss: _close,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The floating list itself. Owns the filter text, so typing rebuilds this
/// widget rather than the [OverlayEntry] that hosts it.
class _DropdownPopup<T> extends StatefulWidget {
  const _DropdownPopup({
    required this.config,
    required this.width,
    required this.onSelected,
    required this.onDismiss,
  });

  final AnchoredSearchDropdown<T> config;

  /// Resolved once at open — [AnchoredSearchDropdown.width], or the trigger's
  /// own width under `matchTriggerWidth`, widened to the rows'
  /// [AnchoredSearchDropdown.contentWidth].
  final double width;
  final ValueChanged<T> onSelected;
  final VoidCallback onDismiss;

  @override
  State<_DropdownPopup<T>> createState() => _DropdownPopupState<T>();
}

class _DropdownPopupState<T> extends State<_DropdownPopup<T>> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  late List<T> _filtered;
  int _highlighted = 0;

  /// Monotonic request id. An async answer whose id is no longer the newest is
  /// dropped rather than applied — see [AnchoredSearchDropdown.search].
  int _requestId = 0;
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _filtered = widget.config.filter?.call('') ?? const [];
    if (widget.config.search != null) _runSearch('', immediate: true);
    final initial = widget.config.initialHighlight?.call(_filtered);
    if (initial != null && initial > 0 && initial < _filtered.length) {
      _highlighted = initial;
      // Open scrolled to the highlight rather than at the top of a few
      // hundred rows. After the first layout, not via initialScrollOffset: a
      // list shorter than the popup has no scroll extent to spend, and the
      // overscroll leaves every row above the offset built but off-stage.
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final filter = widget.config.filter;
    if (filter != null) {
      setState(() {
        _filtered = filter(query);
        _highlighted = 0;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    if (widget.config.search != null) _runSearch(query);
  }

  void _runSearch(String query, {bool immediate = false}) {
    _debounce?.cancel();
    // Bumped here rather than in the timer body, so an answer already in flight
    // for an earlier query is stale the moment the next keystroke lands — not
    // only once its replacement has been issued.
    final id = ++_requestId;
    setState(() => _searching = true);

    Future<void> run() async {
      List<T> results;
      try {
        results = await widget.config.search!(query);
      } catch (_) {
        results = const [];
      }
      if (!mounted || id != _requestId) return;
      setState(() {
        _filtered = results;
        _highlighted = 0;
        _searching = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }

    if (immediate) {
      unawaited(run());
      return;
    }
    _debounce = Timer(widget.config.searchDebounce, () => unawaited(run()));
  }

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, _filtered.length - 1);
    });
    _reveal();
  }

  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final offset = revealRowOffset(
      _highlighted,
      widget.config.rowHeight,
      _scroll.position,
    );
    if (offset != null) _scroll.jumpTo(offset);
  }

  void _accept() {
    if (_filtered.isEmpty) return;
    widget.onSelected(_filtered[_highlighted]);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        widget.onDismiss();
        // Must be handled: SettingsOverlay's KeyboardListener is an
        // autofocused ancestor that closes the *whole* overlay on Escape,
        // and only this stops the walk before it gets there.
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _accept();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Whether the filter field is drawn. A [search] dropdown always has one —
  /// without it there is no way to ask for anything, since nothing is ranked
  /// locally.
  bool get _searchable =>
      widget.config.showSearch || widget.config.search != null;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Focus(
      // Nested above the search field's node, so it only sees what the editor
      // declines — Escape and the arrows here, every editing key still in the
      // field. With no field below it this is the only node in the card, so it
      // takes the focus itself or the arrows would never reach the list.
      autofocus: !_searchable,
      onKeyEvent: _onKey,
      child: Container(
        width: widget.width,
        constraints: BoxConstraints(maxHeight: widget.config.maxHeight),
        decoration: BoxDecoration(
          // Opaque inside the settings page, whatever the theme's alpha: this
          // card floats over the pane's own form rows. See [OpaquePopupScope].
          color: OpaquePopupScope.fill(context, theme),
          borderRadius: BorderRadius.circular(ShellRadii.card),
          border: Border.all(color: theme.divider, width: kDropdownCardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_searchable) _buildSearchField(theme),
            if (_filtered.isEmpty)
              Padding(
                // The search field supplies the top padding when it is there.
                padding: _searchable
                    ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
                    : const EdgeInsets.all(12),
                child: Text(
                  _searching
                      ? widget.config.loadingText
                      : widget.config.emptyText,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    fontFamily: theme.fontFamily,
                    color: theme.muted,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  controller: _scroll,
                  padding: _searchable
                      ? const EdgeInsets.only(bottom: 6)
                      : const EdgeInsets.symmetric(vertical: 6),
                  itemExtent: widget.config.rowHeight,
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) {
                    final item = _filtered[i];
                    final highlighted = i == _highlighted;
                    // Built once and handed in, so a hover flip — which a
                    // scroll causes for every row passing under a still
                    // pointer — repaints the fill and skips the content.
                    final content = widget.config.itemBuilder(
                      context,
                      item,
                      highlighted,
                    );
                    return HoverRegion(
                      onTap: () => widget.onSelected(item),
                      builder: (context, hovered) => Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: kDropdownRowInset,
                        ),
                        color: highlighted
                            ? theme.accent.withValues(alpha: 0.15)
                            : hovered
                            ? theme.surfaceHover
                            : const Color(0x00000000),
                        child: content,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: theme.controlSurface,
          borderRadius: BorderRadius.circular(ShellRadii.control),
          border: Border.all(color: theme.divider),
        ),
        child: Row(
          children: [
            ShellIcon(
              ShellGlyph.search,
              size: 10,
              color: theme.popupForeground.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EditableText(
                controller: _search,
                focusNode: _searchFocus,
                autofocus: true,
                style: TextStyle(
                  fontSize: ShellFontSizes.body,
                  color: theme.popupForeground,
                  fontFamily: theme.fontFamily,
                ),
                cursorColor: theme.accentText,
                backgroundCursorColor: theme.divider,
                onChanged: _filter,
                // Enter takes the highlighted match, so a full name can be
                // typed without reaching for the mouse.
                onSubmitted: (_) => _accept(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
