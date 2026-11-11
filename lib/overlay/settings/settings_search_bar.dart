// The settings pane's search field, and the results that float under it.
//
// Every field in the shell's settings is spread over six sidebar panes and eight
// Shell categories, which is a good arrangement for reading and a poor one for
// *finding*: a user who wants the bar taller has no way to discover that the row
// is called "Height" under Panels & Layout. This is the index made typeable — see
// `settings_search.dart` for the ranking and `settings_catalog.dart` for the table.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:moonswing/config.dart' show ThemeConfig;
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_search.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The widest the field grows in the overview's header.
///
/// The header gives it whatever is left beside the tab strip, which on a wide
/// panel is more than a query needs; past this the field would only be a longer
/// empty box.
const double kSettingsSearchFieldMaxWidth = 300;

/// How wide the results card is.
///
/// Wider than the field and narrower than the pane, because a result row is a
/// label over a breadcrumb and a sentence: at the pane's full width the sentence
/// is one line with two thirds of the card empty after it, and at the field's it
/// is four.
const double kSettingsSearchWidth = 460;

/// One [SettingsRow] is 25px tall and the card must not cover the pane it is
/// searching, so the list scrolls past this.
const double kSettingsSearchMaxResultsHeight = 340;

/// The gap between the field and the card hanging under it.
const double _kResultsGap = 6;

/// The settings search field, and the results it opens.
///
/// It lives in the overview's header, on the left of the tab strip, and only
/// while the Settings tab is showing; the field takes the width its slot gives
/// it, up to [kSettingsSearchFieldMaxWidth].
///
/// **The results float; they do not push.** The card is an [OverlayPortal]
/// child, hung under the field by a [CompositedTransformFollower], so the pane
/// behind stays where it was — a results list that displaced the sidebar and
/// content would move the very row the user is about to be shown. It needs an
/// [Overlay] above it, which the settings window has.
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
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  List<SettingsField> _results = const [];
  int _selected = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setResults(List<SettingsField> results) {
    setState(() {
      _results = results;
      _selected = 0;
    });
    if (results.isEmpty) {
      _portal.hide();
    } else {
      _portal.show();
    }
  }

  void _onQueryChanged(String query) {
    final notMiracle = MiracleScope.readOf(context)?.unsupported ?? false;
    _setResults(
      rankSettings(
        notMiracle
            ? SettingsCatalog.searchableWithoutMiracle
            : SettingsCatalog.searchable,
        query,
      ),
    );
  }

  void _clear() {
    _controller.clear();
    _setResults(const []);
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
      // The field below is the Tab stop; this only hears what it declines.
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildResults,
        child: CompositedTransformTarget(
          link: _link,
          child: LayoutBuilder(
            builder: (context, constraints) => _buildField(
              theme,
              math.min(constraints.maxWidth, kSettingsSearchFieldMaxWidth),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(ThemeConfig theme, double width) {
    return SettingsTextField(
      controller: _controller,
      focusNode: widget.focusNode,
      width: width,
      hint: 'Search settings (Ctrl+F)',
      onChanged: _onQueryChanged,
      leading: ShellIcon(
        ShellGlyph.search,
        size: 12,
        color: theme.popupForeground.withValues(alpha: 0.45),
      ),
      // Always a widget, never null: swapping `trailing` between null and a
      // button restructures the field around its [EditableText], which
      // re-inflates it and drops the focus the user is typing into.
      // [SettingsTextField] documents this.
      trailing: _controller.text.isEmpty
          ? const SizedBox.square(dimension: ShellSizes.iconButtonDense)
          : SettingsIconButton(
              icon: ShellGlyph.close,
              size: 10,
              box: ShellSizes.iconButtonDense,
              onTap: _clear,
            ),
    );
  }

  /// Whether [global] is over the field, which the barrier must not swallow.
  bool _overField(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    return (Offset.zero & box.size).contains(box.globalToLocal(global));
  }

  /// The card under the field, over a barrier across the whole window.
  Widget _buildResults(BuildContext context) {
    return Stack(
      children: [
        // Under the card in paint order, so a click on the card itself is
        // hit-tested first and never reaches this. The barrier is over the
        // whole window, field included, so it lets a click on the field
        // through: placing the caret in the query is not a dismissal.
        Positioned.fill(
          child: _BarrierHole(
            passes: _overField,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _clear,
            ),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, _kResultsGap),
          // The window's overlay has no repaint boundary of its own, so
          // without this every hover over a row would re-record the panel
          // beneath it.
          child: RepaintBoundary(
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
        ),
      ],
    );
  }
}

/// A barrier with a hole in it: [child] is not hit where [passes] says the
/// pointer is over something the barrier lies on top of but must leave alone.
class _BarrierHole extends SingleChildRenderObjectWidget {
  const _BarrierHole({required this.passes, required super.child});

  final bool Function(Offset global) passes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBarrierHole(passes);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBarrierHole renderObject,
  ) {
    renderObject.passes = passes;
  }
}

class _RenderBarrierHole extends RenderProxyBox {
  _RenderBarrierHole(this.passes);

  bool Function(Offset global) passes;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (passes(localToGlobal(position))) return false;
    return super.hitTest(result, position: position);
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
                color: theme.accentText.withValues(alpha: 0.85),
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
