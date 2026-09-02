// The emoji picker: a centred search card over a scrim, in its own full-screen
// layer-shell window, opened by Ctrl+Shift+E.
//
// Everything it acts on is injected — the table it ranks and the copy itself —
// so widget tests drive the whole thing without forking `wl-copy`.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/emoji/emoji_data.dart';
import 'package:graceful_shell/emoji/emoji_search.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/overlay_fade_scaffold.dart';
import 'package:graceful_shell/overlay_search_field.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// Cells across the grid.
///
/// A *count* rather than a width, which is what makes every keyboard move in
/// this file plain arithmetic (`emojiGridMove`) and therefore a unit test with
/// no canvas behind it. A grid that reflowed to its width would put Down on a
/// different emoji per monitor, and would need a layout pass before the key
/// handler could answer.
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

/// Where a keyboard move lands, given [count] results laid out
/// [kEmojiColumns] wide.
///
/// Pure and public so `test/emoji_picker_test.dart` can pin the rules that
/// are easy to get wrong and invisible in a screenshot. A **horizontal** move
/// clamps, so Right at the end of a row steps to the start of the next
/// exactly as reading does. A **vertical** one that would leave the grid
/// lands in the nearest row it can, *in the same column* — which is what
/// makes one rule serve both Up/Down and PageUp/PageDown: on the first row
/// Up is already in that column and so holds (never wrapping round to the
/// end), while PageUp from the middle travels to the top rather than holding
/// with it. The one place the column is given up is a ragged last row that
/// has no cell in it, where the last cell is the only sensible landing —
/// arriving nowhere reads as the key being broken.
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
/// Follows the [FadeOverlayScaffold] close handshake every full-screen overlay
/// uses: the owner flips [closingNotifier], this plays its exit animation,
/// then calls [onClosed] so the native window can be destroyed.
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

  late List<SearchableEmoji> _table;
  List<Emoji> _results = const [];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _table = widget.emoji ?? searchableEmoji;
    _results = rankEmoji(_table, '');
  }

  @override
  void didUpdateWidget(EmojiPickerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.emoji, oldWidget.emoji)) {
      _table = widget.emoji ?? searchableEmoji;
      setState(() {
        _results = rankEmoji(_table, _searchController.text);
        _selected = 0;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Escape, and the backdrop: leave with nothing copied, playing the exit.
  void _requestClose() => widget.closingNotifier.value = true;

  void _onQueryChanged(String value) {
    setState(() {
      _results = rankEmoji(_table, value);
      _selected = 0;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  /// Enter, and a click: copy the selection and go.
  ///
  /// Closes *without* the exit animation, the launcher's call and for a
  /// sharper version of its reason: the point of this window is to put
  /// something on the clipboard and get out of the way of the field the user
  /// is about to paste into, and every frame it spends fading is a frame that
  /// surface does not have the keyboard back.
  void _copySelected() {
    if (_selected < 0 || _selected >= _results.length) return;
    widget.onCopy(_results[_selected].char);
    widget.onClosed();
  }

  void _move({int columns = 0, int rows = 0}) {
    if (_results.isEmpty) return;
    final next = emojiGridMove(
      _selected,
      _results.length,
      columns: columns,
      rows: rows,
    );
    if (next == _selected) return;
    setState(() => _selected = next);
    _scrollSelectedIntoView();
  }

  void _moveTo(int index) {
    if (_results.isEmpty) return;
    final next = index.clamp(0, _results.length - 1);
    if (next == _selected) return;
    setState(() => _selected = next);
    _scrollSelectedIntoView();
  }

  /// Rows have a fixed extent, so this is arithmetic against the scroll
  /// offset — no `Scrollable.ensureVisible`, which animates and would fight a
  /// held arrow key.
  void _scrollSelectedIntoView() {
    if (!_scrollController.hasClients) return;
    final row = _selected ~/ kEmojiColumns;
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
      // Enter is the copy key, and Space is deliberately *not* one: a key
      // this handler takes never reaches the field at all (the Linux embedder
      // forwards a key to the input method only when the framework did not
      // take it), so binding Space here would cost every query its spaces and
      // leave "grinning face with sweat" typeable only as one word.
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
        _moveTo(_results.length - 1);
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
    final selected = _selected >= 0 && _selected < _results.length
        ? _results[_selected]
        : null;
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
                  child: _buildGrid(theme),
                ),
              ),
              const SizedBox(height: 8),
              _EmojiFooter(theme: theme, selected: selected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(ThemeConfig theme) {
    if (_results.isEmpty) {
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
      itemCount: _results.length,
      itemBuilder: (context, i) => _EmojiCell(
        theme: theme,
        emoji: _results[i],
        selected: i == _selected,
        onTap: () {
          setState(() => _selected = i);
          _copySelected();
        },
        onHover: () {
          if (_selected != i) setState(() => _selected = i);
        },
      ),
    );
  }
}

/// One cell: the glyph, and the ring that says it is the one Enter will copy.
class _EmojiCell extends StatelessWidget {
  const _EmojiCell({
    required this.theme,
    required this.emoji,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final ThemeConfig theme;
  final Emoji emoji;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: onTap,
      onEnter: onHover,
      builder: (context, hovered) => Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? theme.surfaceHover : null,
          borderRadius: BorderRadius.circular(ShellRadii.control),
          border: Border.all(
            color: selected ? theme.accent : const Color(0x00000000),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          emoji.char,
          // The glyph comes from whichever colour emoji font fontconfig
          // resolves, so it carries its own colours and the theme's
          // foreground reaches only a font that has none.
          style: const TextStyle(fontSize: kEmojiGlyphSize),
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
          Text(
            emoji.char,
            style: const TextStyle(fontSize: kEmojiFooterGlyphSize),
          ),
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
