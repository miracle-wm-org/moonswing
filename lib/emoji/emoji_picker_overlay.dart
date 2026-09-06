// The emoji picker: a centred search card over a scrim, in its own full-screen
// layer-shell window, opened by Ctrl+Shift+E.
//
// Everything it acts on is injected — the table it ranks and the copy itself —
// so widget tests drive the whole thing without forking `wl-copy`.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show PointerEnterEvent;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/emoji/emoji_data.dart';
import 'package:graceful_shell/emoji/emoji_search.dart';
import 'package:graceful_shell/overlay_fade_scaffold.dart';
import 'package:graceful_shell/overlay_search_field.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// Cells across the grid.
///
/// A *count* rather than a width, which makes every keyboard move in this file
/// plain arithmetic (`emojiGridMove`) and therefore a unit test with no canvas
/// behind it. A grid that reflowed to its width would put Down on a different
/// emoji per monitor.
const int kEmojiColumns = 10;

/// One cell, square. The glyph inside is smaller ([kEmojiGlyphSize]) — this is
/// the pointer target, `ShellSizes`' rule that hover and tap are one box.
const double kEmojiCellSize = 46;

/// The rendered emoji. Comfortably readable, and small enough that a cell has
/// room for the selection ring around it.
const double kEmojiGlyphSize = 26;

/// The selected emoji, redrawn in the footer beside its name. Smaller than
/// the grid's ([kEmojiGlyphSize]) because the footer's subject is the *name*
/// — the glyph there is only the anchor that says which cell it belongs to.
const double kEmojiFooterGlyphSize = 20;

/// Rows visible at once. Fixed, not a maximum: the card must not resize on
/// every keystroke, and a query matching two emoji must not shrink it to a
/// strip — the launcher's rule for its own results area.
const int kEmojiVisibleRows = 7;

/// The grid viewport.
const double kEmojiGridHeight = kEmojiCellSize * kEmojiVisibleRows;

/// Padding inside the card, and so the difference between the card's width and
/// the grid's.
const double kEmojiCardPadding = 12;

/// The card. Derived rather than chosen, so the columns always divide the grid
/// exactly and no half cell is ever clipped at the right-hand edge.
const double kEmojiCardWidth =
    kEmojiColumns * kEmojiCellSize + kEmojiCardPadding * 2;

/// The colour-emoji families a glyph is drawn from, in the order they are
/// tried. A name this machine has no font for costs one cached lookup and
/// falls through to the next; a codepoint none of them covers still reaches
/// the engine's own last resort.
const List<String> kEmojiFontFamilies = <String>[
  'Noto Color Emoji',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Twemoji',
  'JoyPixels',
  'EmojiOne Color',
  'Noto Emoji',
];

/// The grid's glyph, and **the single largest cost the picker used to carry.**
///
/// `ShellTextRoot` seeds every window with the theme's `fontFamily` — a UI font
/// with no emoji coverage — and this style named none of its own, so the engine
/// missed on the primary and resolved a fallback typeface **per codepoint**,
/// which on Linux is a fontconfig charset query run inside
/// `RenderParagraph.layout` on the UI thread. Naming a colour-emoji family means
/// the primary hits and no fallback runs.
///
/// It also settles a picture the theme could otherwise change: the handful of
/// codepoints a UI font *does* cover (⚙, ★, ✓, ✉) were drawn as monochrome
/// glyphs beside neighbours drawn in colour.
///
/// It **inherits**, and naming the family is what makes that safe: `TextStyle.merge`
/// takes the family and fallback list from the style merged *in*, so these win
/// over the theme's while everything else the ambient `DefaultTextStyle` decides
/// still reaches the glyph. `inherit: false` would throw the rest out with it.
const TextStyle kEmojiGridGlyphStyle = TextStyle(
  fontSize: kEmojiGlyphSize,
  fontFamily: 'Noto Color Emoji',
  fontFamilyFallback: kEmojiFontFamilies,
);

/// [kEmojiGridGlyphStyle] at the footer's size.
const TextStyle kEmojiFooterGlyphStyle = TextStyle(
  fontSize: kEmojiFooterGlyphSize,
  fontFamily: 'Noto Color Emoji',
  fontFamilyFallback: kEmojiFontFamilies,
);

/// Where a keyboard move lands, given [count] results laid out [kEmojiColumns]
/// wide.
///
/// Pure and public so `test/emoji_picker_test.dart` can pin rules that are easy
/// to get wrong and invisible in a screenshot. A **horizontal** move clamps, so
/// Right at the end of a row steps to the start of the next. A **vertical** one
/// that would leave the grid lands in the nearest row it can, *in the same
/// column* — one rule serving both Up/Down and PageUp/PageDown. The column is
/// given up only for a ragged last row with no cell in it, where the last cell
/// is the landing: arriving nowhere reads as the key being broken.
int emojiGridMove(int selected, int count, {int columns = 0, int rows = 0}) {
  if (count <= 0) return 0;
  final clamped = selected.clamp(0, count - 1);
  if (rows != 0) {
    final target = clamped + rows * kEmojiColumns;
    if (target >= 0 && target < count) return target;
    final column = clamped % kEmojiColumns;
    if (target < 0) return column;
    final lastRowStart = ((count - 1) ~/ kEmojiColumns) * kEmojiColumns;
    // Already on the last row: there is nowhere further down to go.
    if (clamped >= lastRowStart) return clamped;
    final sameColumn = lastRowStart + column;
    return sameColumn < count ? sameColumn : count - 1;
  }
  return (clamped + columns).clamp(0, count - 1);
}

/// The emoji picker card and its backdrop.
///
/// Follows the [FadeOverlayScaffold] close handshake: the owner flips
/// [closingNotifier], this plays its exit animation, then calls [onClosed].
class EmojiPickerOverlay extends StatefulWidget {
  const EmojiPickerOverlay({
    super.key,
    required this.closingNotifier,
    required this.onClosed,
    required this.onCopy,
    this.emoji,
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// Puts the chosen character on the clipboard. Injected rather than called
  /// directly so a widget test never forks a helper, and so the *reporting* of
  /// a failed copy stays with the root, which owns the notification store.
  final void Function(String char) onCopy;

  /// The table to rank. Defaults to the shell's own, folded once and lazily
  /// (see [searchableEmoji]); tests pass a small one.
  final List<SearchableEmoji>? emoji;

  @override
  State<EmojiPickerOverlay> createState() => _EmojiPickerOverlayState();
}

class _EmojiPickerOverlayState extends State<EmojiPickerOverlay> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'emoji-search');
  final _scrollController = ScrollController();

  /// Which cell Enter would copy, as a notifier rather than a field.
  ///
  /// **This is what keeps a pointer moving over the grid from rebuilding the
  /// card** — the `_SelectedIcon` rule the desktop grid states. The selection
  /// follows the pointer, and a `MouseRegion` fires enter and exit as the
  /// *content* moves under a stationary cursor, so a scroll over the grid moves
  /// the selection every frame. Written with `setState`, each of those frames
  /// rebuilt the [OverlaySearchField], its [EditableText] and all seventy-odd
  /// cells; through a notifier it rebuilds the two cells whose flag flipped.
  final _selection = ValueNotifier<int>(0);

  /// What the grid draws, as a notifier for [_selection]'s reason: typing changes
  /// what the grid holds but not the search field, and a `setState` here rebuilt
  /// [OverlaySearchField] and its [EditableText] on every character.
  final _results = ValueNotifier<List<Emoji>>(const []);

  /// The folded table, or null while the fold has not been forced.
  ///
  /// Null is the default state on open: [searchableEmoji] is a lazy top-level
  /// `final`, so *touching* it folds six hundred rows — and doing that in
  /// [initState] put the whole fold inside the frame that has to paint. The
  /// picker opens on the empty query, which is the table in its own order. See
  /// [_tableNow].
  List<SearchableEmoji>? _table;

  /// The last ranking, kept so the next keystroke can narrow from it rather
  /// than rescan the table — see [rankEmojiFrom]. Bookkeeping the grid never
  /// reads, so it is a field and not part of [_results].
  EmojiRanking? _ranking;

  /// The table, folding it if that has not happened yet.
  ///
  /// Every path that needs the folded rows goes through here, so the fold lands
  /// on the first frame that ranks rather than the first that paints.
  List<SearchableEmoji> get _tableNow =>
      _table ??= widget.emoji ?? searchableEmoji;

  @override
  void initState() {
    super.initState();
    if (widget.emoji != null) {
      // An injected table is already folded, so there is nothing to defer.
      _table = widget.emoji;
      _ranking = rankEmojiFrom(widget.emoji!, '');
      _results.value = _ranking!.results;
    } else {
      // The empty query answers the table in its own order, so the grid has
      // everything it needs before a single row has been lowercased. The fold
      // happens on the frame after the one that had to paint, or on the first
      // keystroke if that comes first (see [_tableNow]).
      _results.value = kEmoji;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _table ??= searchableEmoji;
      });
    }
  }

  @override
  void didUpdateWidget(EmojiPickerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.emoji, oldWidget.emoji)) {
      // The survivors are indices into the table that is going away, so the
      // narrowing cache cannot outlive it.
      _table = widget.emoji;
      _ranking = rankEmojiFrom(_tableNow, _searchController.text);
      _results.value = _ranking!.results;
      _selection.value = 0;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    _selection.dispose();
    _results.dispose();
    super.dispose();
  }

  /// Escape, and the backdrop: leave with nothing copied, playing the exit.
  void _requestClose() => widget.closingNotifier.value = true;

  void _onQueryChanged(String value) {
    _ranking = rankEmojiFrom(_tableNow, value, previous: _ranking);
    _results.value = _ranking!.results;
    _selection.value = 0;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  /// Enter, and a click: copy the selection and go.
  ///
  /// Closes *without* the exit animation, the launcher's call: this window exists
  /// to put something on the clipboard and get out of the way of the field the
  /// user is about to paste into, and every fading frame is one that surface does
  /// not have the keyboard back.
  void _copySelected() {
    final selected = _selection.value;
    final results = _results.value;
    if (selected < 0 || selected >= results.length) return;
    widget.onCopy(results[selected].char);
    widget.onClosed();
  }

  /// A cell was clicked: take it, whichever one was under the ring.
  void _copyAt(int index) {
    _selection.value = index;
    _copySelected();
  }

  /// The pointer entered a cell. Bound once on this state rather than closed
  /// over per cell, so a rebuilt grid hands every cell the same callback.
  void _selectAt(int index) => _selection.value = index;

  void _move({int columns = 0, int rows = 0}) {
    if (_results.value.isEmpty) return;
    final next = emojiGridMove(
      _selection.value,
      _results.value.length,
      columns: columns,
      rows: rows,
    );
    if (next == _selection.value) return;
    _selection.value = next;
    _scrollSelectedIntoView();
  }

  void _moveTo(int index) {
    if (_results.value.isEmpty) return;
    final next = index.clamp(0, _results.value.length - 1);
    if (next == _selection.value) return;
    _selection.value = next;
    _scrollSelectedIntoView();
  }

  /// Rows have a fixed extent, so this is arithmetic against the scroll
  /// offset — no `Scrollable.ensureVisible`, which animates and would fight a
  /// held arrow key.
  void _scrollSelectedIntoView() {
    if (!_scrollController.hasClients) return;
    final row = _selection.value ~/ kEmojiColumns;
    final top = row * kEmojiCellSize;
    final bottom = top + kEmojiCellSize;
    final offset = _scrollController.offset;
    final viewport = _scrollController.position.viewportDimension;
    if (top < offset) {
      _scrollController.jumpTo(top);
    } else if (bottom > offset + viewport) {
      _scrollController.jumpTo(
        (bottom - viewport).clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        // One press leaves with nothing copied — a picker opened by accident
        // should not need two.
        _requestClose();
        return KeyEventResult.handled;
      // Enter is the copy key, and Space deliberately is not: a key this handler
      // takes never reaches the field at all (the Linux embedder forwards a key
      // to the input method only when the framework did not take it), so binding
      // Space would cost every query its spaces.
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _copySelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _move(columns: 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _move(columns: -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _move(rows: 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(rows: -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageDown:
        _move(rows: kEmojiVisibleRows);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageUp:
        _move(rows: -kEmojiVisibleRows);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _moveTo(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _moveTo(_results.value.length - 1);
        return KeyEventResult.handled;
    }
    // Everything else — the letters, Space, Backspace, the caret keys the
    // arrows are not — belongs to the field.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    // No WidgetsApp is mounted, so the default text-editing key bindings have
    // to be supplied by hand. Focus must nest *inside* them: key events
    // propagate upwards from the focused node, so the lower handler is the one
    // that gets first refusal on Enter, Escape and the arrows.
    return DefaultTextEditingShortcuts(
      child: Focus(
        onKeyEvent: _onKey,
        // The shell has no input-region support, so this surface swallows
        // every click on the monitor. Without dismiss-on-backdrop a
        // mouse-only user would have no way out.
        child: FadeOverlayScaffold(
          closing: widget.closingNotifier,
          onClosed: widget.onClosed,
          onBackdropTap: _requestClose,
          child: _buildCard(theme),
        ),
      ),
    );
  }

  Widget _buildCard(ThemeConfig theme) {
    return GestureDetector(
      // Absorb taps so clicking inside the card does not dismiss it.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: SizedBox(
        width: kEmojiCardWidth,
        child: Container(
          decoration: BoxDecoration(
            color: theme.popupBackground,
            borderRadius: BorderRadius.circular(ShellRadii.card + 4),
            border: Border.all(color: theme.accent, width: 1.5),
          ),
          padding: const EdgeInsets.all(kEmojiCardPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OverlaySearchField(
                controller: _searchController,
                focusNode: _searchFocus,
                theme: theme,
                icon: FontAwesomeIcons.faceSmile,
                hint: 'Search by name, keyword, or category…',
                onChanged: _onQueryChanged,
              ),
              const SizedBox(height: 8),
              // Flexible, then a fixed height: the SizedBox pins the grid to
              // one size however many rows there are, and the Flexible caps
              // it at whatever the surface can actually give (which only
              // bites on a very short monitor).
              Flexible(
                child: SizedBox(
                  height: kEmojiGridHeight,
                  // Scrolling marks the viewport needing paint, and that mark
                  // travels to the nearest boundary — which, without this one, is
                  // the window itself, so every scrolled frame re-recorded the
                  // search field, the footer and the full-output scrim. The cells
                  // carry their own boundaries; this is the other half. It sits
                  // *above* the results builder, so the element that stops the
                  // mark is one a keystroke does not replace.
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<List<Emoji>>(
                      valueListenable: _results,
                      builder: (context, results, _) =>
                          _buildGrid(theme, results),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // The footer names the selection, so it is the one part of the
              // card a hover has to redraw — and, through the notifier, the
              // only part that does.
              ValueListenableBuilder<List<Emoji>>(
                valueListenable: _results,
                builder: (context, results, _) => ValueListenableBuilder<int>(
                  valueListenable: _selection,
                  builder: (context, selected, _) => _EmojiFooter(
                    theme: theme,
                    selected: selected >= 0 && selected < results.length
                        ? results[selected]
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(ThemeConfig theme, List<Emoji> results) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No matching emoji',
          style: TextStyle(color: theme.muted, fontSize: ShellFontSizes.body),
        ),
      );
    }
    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      // mainAxisExtent rather than an aspect ratio: the row height is what
      // _scrollSelectedIntoView does arithmetic on, so it has to be the
      // constant and not something derived from the width at layout time.
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: kEmojiColumns,
        mainAxisExtent: kEmojiCellSize,
      ),
      // `GridView.builder` is already lazy. What it was over-building is the
      // *cache extent*, which defaults to 250 logical pixels: at a row height of
      // 46 that is five and a half rows either side of a seven-row viewport, so
      // the first frame laid out about a hundred and eighty paragraphs to show
      // seventy. Two rows is enough to stay ahead of a scroll.
      cacheExtent: kEmojiCellSize * 2,
      itemCount: results.length,
      // Two wrappers per cell this grid has no use for, and a fling builds cells
      // by the hundred. Nothing in a cell has state worth keeping alive off
      // screen, and `kExcludeSemantics` drops every window out of the semantics
      // tree anyway. The repaint boundaries stay: they are what a scroll reuses
      // rather than re-records.
      addAutomaticKeepAlives: false,
      addSemanticIndexes: false,
      itemBuilder: (context, i) => _EmojiCell(
        theme: theme,
        emoji: results[i],
        index: i,
        selection: _selection,
        onTap: _copyAt,
        onHover: _selectAt,
      ),
    );
  }
}

/// One cell: the glyph, and the ring that says it is the one Enter will copy.
///
/// Stateful and subscribed to the picker's selection itself, so moving the ring
/// costs the two cells it moved between rather than the grid — `_SelectedIcon`'s
/// shape in the desktop grid, and here for the same reason: the selection follows
/// the pointer, so it moves on every frame of a scroll under the cursor.
///
/// It does **not** go through `HoverRegion`, the shell's primitive for this
/// shape and the wrong tool here: a cell draws no hover state of its own
/// (entering it *is* selecting it), so the `bool _hovered` that primitive owns
/// would be a second rebuild per cell for a value nothing paints. The
/// `GestureDetector` still carries an explicit `behavior:`.
class _EmojiCell extends StatefulWidget {
  const _EmojiCell({
    required this.theme,
    required this.emoji,
    required this.index,
    required this.selection,
    required this.onTap,
    required this.onHover,
  });

  final ThemeConfig theme;
  final Emoji emoji;

  /// This cell's place in the results, and so the value of [selection] that
  /// means "this one".
  final int index;

  final ValueListenable<int> selection;

  final void Function(int index) onTap;
  final void Function(int index) onHover;

  @override
  State<_EmojiCell> createState() => _EmojiCellState();
}

class _EmojiCellState extends State<_EmojiCell> {
  late bool _selected;

  /// The glyph, built once and handed back unchanged.
  ///
  /// The calendar tab's rule, for its reason: what a selection flip changes is
  /// a decoration, and an identical child widget is one the framework skips
  /// outright (`Element.updateChild` short-circuits on `child.widget ==
  /// newWidget`) rather than shaping the paragraph again. Ringing and
  /// un-ringing a cell is then a `DecoratedBox` and nothing else.
  late Widget _glyph;

  @override
  void initState() {
    super.initState();
    _selected = widget.selection.value == widget.index;
    _glyph = _buildGlyph();
    widget.selection.addListener(_onSelectionChanged);
  }

  // The glyph names its own colour-emoji family rather than taking the
  // theme's — see [kEmojiGridGlyphStyle] for why that is the difference
  // between a fontconfig query per codepoint and none.
  Widget _buildGlyph() =>
      Text(widget.emoji.char, style: kEmojiGridGlyphStyle);

  @override
  void didUpdateWidget(_EmojiCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.selection, oldWidget.selection)) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
    }
    // A recycled cell may be showing a different emoji at a different index,
    // so both are re-read rather than carried over.
    if (widget.emoji.char != oldWidget.emoji.char) _glyph = _buildGlyph();
    _selected = widget.selection.value == widget.index;
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    final selected = widget.selection.value == widget.index;
    if (selected == _selected) return;
    setState(() => _selected = selected);
  }

  void _handleTap() => widget.onTap(widget.index);
  void _handleEnter(PointerEnterEvent _) => widget.onHover(widget.index);

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: _handleEnter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: Container(
          margin: const EdgeInsets.all(2),
          // Null rather than a transparent border on an unselected cell: a
          // `Border` at zero alpha is still a stroke the rasteriser is asked
          // for, on every one of the cells that is not the selected one, and
          // a decoration that is null is a `DecoratedBox` that is never built
          // at all. The glyph does not move when one appears — the border's
          // inset is symmetric and the child is centred.
          decoration: _selected
              ? BoxDecoration(
                  color: theme.surfaceHover,
                  borderRadius: BorderRadius.circular(ShellRadii.control),
                  border: Border.all(color: theme.accent, width: 1),
                )
              : null,
          alignment: Alignment.center,
          child: _glyph,
        ),
      ),
    );
  }
}

/// What is selected, and how to take it.
///
/// The name is the half that makes the grid legible — a wall of glyphs says
/// nothing about which of three similar faces is under the ring — and the key
/// hints are the other half: nothing about a grid of glyphs says which key
/// takes the one under the ring, or that Escape leaves without taking it.
class _EmojiFooter extends StatelessWidget {
  const _EmojiFooter({required this.theme, required this.selected});

  final ThemeConfig theme;
  final Emoji? selected;

  @override
  Widget build(BuildContext context) {
    final emoji = selected;
    return Row(
      children: [
        if (emoji != null) ...[
          Text(emoji.char, style: kEmojiFooterGlyphStyle),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emoji.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.popupForeground,
                    fontSize: ShellFontSizes.body,
                  ),
                ),
                Text(
                  emoji.category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: ShellFontSizes.caption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
        ] else
          const Spacer(),
        Text(
          'Enter to copy  ·  Esc to cancel',
          style: TextStyle(
            color: theme.muted,
            fontSize: ShellFontSizes.caption,
          ),
        ),
      ],
    );
  }
}
