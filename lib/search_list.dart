/// The anchored, searchable dropdown: a trigger that floats a filterable
/// list in the *root* overlay.
///
/// `SettingsFontField` and the calendar's time-zone picker were two
/// comment-identical copies of this whole arrangement; each is now a thin
/// wrapper supplying its trigger, its ranking, and its row content. Two
/// properties are load-bearing and documented at their origin
/// (`SettingsColorField`): the list floats in the **root** overlay, because
/// the settings content pane is a nested `Navigator` whose `Overlay` would
/// clip a list hanging below the row; and the items arrive **as a
/// parameter**, so widget tests never fork `fc-list` or load the IANA
/// tables.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// Scroll offset that brings row [index] (of height [rowHeight]) into view on
/// [position], or null when it already is. Pure, so the keyboard-navigation
/// math is unit-testable without a scroll view.
double? revealRowOffset(int index, double rowHeight, ScrollMetrics position) {
  final top = index * rowHeight;
  final bottom = top + rowHeight;
  if (top < position.pixels) return top;
  if (bottom > position.pixels + position.viewportDimension) {
    return (bottom - position.viewportDimension)
        .clamp(0.0, position.maxScrollExtent);
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
    required this.itemBuilder,
    required this.onSelected,
    required this.triggerBuilder,
    this.width = 240,
    this.maxHeight = 300,
    this.rowHeight = 30,
    this.emptyText = 'No matches',
    this.alignRight = false,
    this.initialHighlight,
    this.closeKey,
  }) : assert(filter != null || search != null,
            'a dropdown needs either a filter or a search');

  /// Ranks the items for a query, synchronously. Called with `''` when the list
  /// opens. Null when the items come from [search] instead.
  final List<T> Function(String query)? filter;

  /// Ranks the items for a query *asynchronously* — a network lookup rather
  /// than a ranking of a list already in memory.
  ///
  /// Supersedes [filter] when both are given, which is the shape a caller with
  /// a local list *and* a remote one wants: [filter] answers the first frame
  /// with what is already known, [search] replaces it when the request lands.
  ///
  /// Debounced by [searchDebounce], and answers are applied in request order —
  /// a slow response for "lon" must not land on top of a fast one for
  /// "london". A call that throws is reported as no matches; the dropdown is
  /// not the place to explain a failed HTTP request, and a list that stayed on
  /// the previous query's results would be showing the wrong ones.
  final Future<List<T>> Function(String query)? search;

  /// How long typing has to stop before [search] is called. A request per
  /// keystroke is a request per keystroke against somebody else's API.
  final Duration searchDebounce;

  /// Shown in place of [emptyText] while a [search] is in flight, so an empty
  /// list reads as "not yet" rather than "none" — the rule
  /// `ShellServicesScope` documents for the launcher.
  final String loadingText;

  /// The row's *content*; the generic supplies the row chrome (hover fill,
  /// highlight fill, tap target, fixed [rowHeight]).
  final Widget Function(BuildContext context, T item, bool highlighted)
      itemBuilder;

  final ValueChanged<T> onSelected;

  /// Builds the always-visible trigger. Call [toggle] to open/close;
  /// [open] reports whether the list is up (for a chevron, a border).
  final Widget Function(BuildContext context, bool open, VoidCallback toggle)
      triggerBuilder;

  final double width;
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

  @override
  void didUpdateWidget(AnchoredSearchDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.closeKey != oldWidget.closeKey) _close();
  }

  @override
  void dispose() {
    // Not _close(): that repaints the trigger, and this element is on its way
    // out of the tree.
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _toggle() => _entry != null ? _close() : _open();

  void _open() {
    if (_entry != null) return;
    final entry = OverlayEntry(builder: (_) => _buildPicker());
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    setState(() {});
  }

  void _close() {
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
    final anchor = widget.alignRight ? Alignment.bottomRight : Alignment.bottomLeft;
    final follower = widget.alignRight ? Alignment.topRight : Alignment.topLeft;
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
          offset: const Offset(0, 6),
          // Absorbs clicks on the card's own chrome, which would otherwise
          // fall through to the barrier above — see the colour picker.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            child: _DropdownPopup<T>(
              config: widget,
              onSelected: _select,
              onDismiss: _close,
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
    required this.onSelected,
    required this.onDismiss,
  });

  final AnchoredSearchDropdown<T> config;
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
        _highlighted, widget.config.rowHeight, _scroll.position);
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

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Focus(
      // Nested above the search field's node, so it only sees what the editor
      // declines — Escape and the arrows here, every editing key still in the
      // field.
      onKeyEvent: _onKey,
      child: Container(
        width: widget.config.width,
        constraints: BoxConstraints(maxHeight: widget.config.maxHeight),
        decoration: BoxDecoration(
          color: theme.popupBackground,
          borderRadius: BorderRadius.circular(ShellRadii.card),
          border: Border.all(color: theme.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSearchField(theme),
            if (_filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                  padding: const EdgeInsets.only(bottom: 6),
                  itemExtent: widget.config.rowHeight,
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) {
                    final item = _filtered[i];
                    final highlighted = i == _highlighted;
                    return HoverRegion(
                      builder: (context, hovered) => GestureDetector(
                        onTap: () => widget.onSelected(item),
                        child: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          color: highlighted
                              ? theme.accent.withValues(alpha: 0.15)
                              : hovered
                                  ? theme.surfaceHover
                                  : const Color(0x00000000),
                          child: widget.config
                              .itemBuilder(context, item, highlighted),
                        ),
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
            FaIcon(
              FontAwesomeIcons.magnifyingGlass,
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
                cursorColor: theme.accent,
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
