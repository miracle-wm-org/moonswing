// The settings pane's search field, and the results that float under it.
//
// Every field in the shell's settings is spread over six sidebar panes and eight
// Shell categories, which is a good arrangement for reading and a poor one for
// *finding*: a user who wants the bar taller has no way to discover that the row
// is called "Height" under Panels & Layout. This is the index made typeable — see
// `settings_search.dart` for the ranking and `settings_catalog.dart` for the table.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart' show ThemeConfig;
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/settings/settings_catalog.dart';
import 'package:graceful_shell/overlay/settings/settings_search.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The height the settings body reserves for the search row.
///
/// The bar is laid out over the body rather than above it (see
/// [SettingsSearchBar]), so the two have to agree on this by hand.
const double kSettingsSearchBarHeight = 52;

/// How wide the field and its results card are.
///
/// Wider than the 180px sidebar and narrower than the pane, because a result row
/// is a label over a breadcrumb and a sentence: at the pane's full width the
/// sentence is one line with two thirds of the card empty after it, and at the
/// sidebar's it is four.
const double kSettingsSearchWidth = 460;

/// One [SettingsRow] is 25px tall and the card must not cover the pane it is
/// searching, so the list scrolls past this.
const double kSettingsSearchMaxResultsHeight = 340;

/// A search field over the whole settings pane, and the results it opens.
///
/// **It floats; it does not push.** The widget fills the settings body and draws
/// the field in its top-left corner, so the pane behind stays where it was — a
/// results list that displaced the sidebar and content would move the very row
/// the user is about to be shown. Filling the body costs nothing at rest:
/// `RenderStack` has no `hitTestSelf`, so with no results open every click goes
/// straight through to the page.
///
/// **An open card is dismissed by a barrier, not by focus** —
/// `AnchoredSearchDropdown`'s arrangement, and for its reason: most controls here
/// are `HoverRegion`s with no focus node, so a card that waited to lose focus
/// would sit over the page through every toggle the user flipped.
///
/// **An empty query shows nothing.** [rankSettings] answers an empty list, so
/// clicking into the field does not drop two hundred rows over the page.
///
/// **The keys are handled below the text bindings.** This [Focus] is nested
/// inside `DefaultTextEditingShortcuts`, so Up/Down/Enter/Escape are taken here
/// while Backspace and the arrows still edit the query.
class SettingsSearchBar extends StatefulWidget {
  const SettingsSearchBar({
    super.key,
    required this.onJump,
    required this.focusNode,
  });

  /// Called with the field the user picked. The overlay moves its tab, its
  /// sidebar category and the Shell pane's route to match, and publishes the
  /// field as a highlight target.
  final ValueChanged<SettingsField> onJump;

  /// Owned by the overlay, so Ctrl+F from anywhere in the panel can focus the
  /// field. A borrowed node is never disposed here — [SettingsTextField]'s
  /// rule, one layer up.
  final FocusNode focusNode;

  @override
  State<SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<SettingsSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<SettingsField> _results = const [];
  int _selected = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    final results = rankSettings(SettingsCatalog.searchable, query);
    setState(() {
      _results = results;
      _selected = 0;
    });
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _results = const [];
      _selected = 0;
    });
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    final next = (_selected + delta).clamp(0, _results.length - 1);
    if (next == _selected) return;
    setState(() => _selected = next);
    _revealSelected();
  }

  /// Keeps the highlighted row in the card, the way the launcher's list does.
  ///
  /// Arithmetic against a fixed row extent rather than an `ensureVisible`, because
  /// the rows are two lines of text and the card is a plain `ListView`.
  void _revealSelected() {
    if (!_scroll.hasClients) return;
    final top = _selected * kSettingsSearchResultHeight;
    final bottom = top + kSettingsSearchResultHeight;
    final offset = _scroll.offset;
    final viewport = _scroll.position.viewportDimension;
    if (top < offset) {
      _scroll.jumpTo(top);
    } else if (bottom > offset + viewport) {
      _scroll.jumpTo(
        (bottom - viewport).clamp(0.0, _scroll.position.maxScrollExtent),
      );
    }
  }

  void _jump(SettingsField field) {
    // Cleared first: the card is over the pane the jump is about to scroll,
    // and a results list still covering the row that has just flashed is the
    // one thing this feature must not do.
    _clear();
    widget.onJump(field);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (_results.isEmpty) return KeyEventResult.handled;
        _jump(_results[_selected]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        // Only an Escape with something to end is taken. With the field
        // already empty it goes on up to the overlay's own handler and closes
        // the panel, which is `file_picker.dart`'s rule for the same key.
        if (_controller.text.isEmpty) return KeyEventResult.ignored;
        _clear();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Focus(
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // Under the field in paint order, so a click on the card itself is
          // hit-tested first and never reaches this.
          if (_results.isNotEmpty)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clear,
              ),
            ),
          Align(alignment: Alignment.topLeft, child: _buildField(theme)),
        ],
      ),
    );
  }

  Widget _buildField(ThemeConfig theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: kSettingsSearchBarHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: SettingsTextField(
              controller: _controller,
              focusNode: widget.focusNode,
              width: kSettingsSearchWidth,
              hint: 'Search settings (Ctrl+F)',
              onChanged: _onQueryChanged,
              leading: FaIcon(
                FontAwesomeIcons.magnifyingGlass,
                size: 12,
                color: theme.popupForeground.withValues(alpha: 0.45),
              ),
              // Always a widget, never null: swapping `trailing` between null
              // and a button restructures the field around its [EditableText],
              // which re-inflates it and drops the focus the user is typing
              // into. [SettingsTextField] documents this.
              trailing: _controller.text.isEmpty
                  ? const SizedBox.square(dimension: ShellSizes.iconButtonDense)
                  : SettingsIconButton(
                      icon: FontAwesomeIcons.xmark,
                      size: 10,
                      box: ShellSizes.iconButtonDense,
                      onTap: _clear,
                    ),
            ),
          ),
        ),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            // Absorbs clicks on the card's own chrome — the gaps between rows,
            // the rim — which would otherwise fall through to the barrier
            // behind it and dismiss the list the user is aiming at.
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: SettingsSearchResults(
                results: _results,
                selected: _selected,
                scrollController: _scroll,
                onHover: (index) => setState(() => _selected = index),
                onPick: _jump,
              ),
            ),
          ),
      ],
    );
  }
}

/// One result row's extent, which the keyboard reveal does arithmetic on.
const double kSettingsSearchResultHeight = 58;

/// The floating list of matches.
///
/// Public because it is the half worth pinning in a widget test: its one real
/// home is inside a layer-shell window no test can pump, which is the reason
/// `NotificationPanel` is public too.
class SettingsSearchResults extends StatelessWidget {
  const SettingsSearchResults({
    super.key,
    required this.results,
    required this.selected,
    required this.onPick,
    this.onHover,
    this.scrollController,
  });

  final List<SettingsField> results;
  final int selected;
  final ValueChanged<SettingsField> onPick;
  final ValueChanged<int>? onHover;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      width: kSettingsSearchWidth,
      constraints: const BoxConstraints(
        maxHeight: kSettingsSearchMaxResultsHeight,
      ),
      decoration: BoxDecoration(
        // Opaque whatever the theme says: this card is read over the settings
        // pane's own form rows, and a translucent one shows the page it is
        // covering straight through itself. [OpaquePopupScope]'s rule, and the
        // settings overlay is what supplies the scope.
        color: OpaquePopupScope.fill(context, theme),
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(color: theme.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ShellRadii.card),
        child: ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          // Fixed, so the keyboard reveal above is arithmetic rather than a
          // layout pass.
          itemExtent: kSettingsSearchResultHeight,
          itemCount: results.length,
          itemBuilder: (context, index) => _SettingsSearchResultRow(
            field: results[index],
            selected: index == selected,
            onHover: onHover == null ? null : () => onHover!(index),
            onTap: () => onPick(results[index]),
          ),
        ),
      ),
    );
  }
}

class _SettingsSearchResultRow extends StatelessWidget {
  const _SettingsSearchResultRow({
    required this.field,
    required this.selected,
    required this.onTap,
    this.onHover,
  });

  final SettingsField field;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Hover-invariant, so it is built once and handed to the builder as a
    // captured child — `SettingsRow`'s companion discipline.
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                field.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.body,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              field.section,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                fontFamily: theme.fontFamily,
                color: theme.accent.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        if (field.description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            field.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
    return HoverRegion(
      onTap: onTap,
      onEnter: onHover,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: selected || hovered
            ? theme.accent.withValues(alpha: 0.18)
            : const Color(0x00000000),
        child: label,
      ),
    );
  }
}
