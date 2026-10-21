// The one collection editor in the settings UI.
//
// Every list a settings page edits — a panel's modules, the dock's apps, the
// startup applications, the input sources — is a [SettingsList]: one enclosed
// box of numbered rows, each with its own remove icon, dragged by hand into a
// new order, and closed by the row that adds to it. Exported from
// `controls.dart`, so a page imports it the way it imports every other control.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/search_list.dart';
import 'package:moonswing/theme/tokens.dart';

/// A copy of [list] with the element at [from] moved so that it ends up at
/// index [to] — the contract of [SettingsList.onReorder].
List<T> reorderedList<T>(List<T> list, int from, int to) {
  final next = [...list];
  if (from < 0 || from >= next.length) return next;
  final item = next.removeAt(from);
  next.insert(to.clamp(0, next.length), item);
  return next;
}

/// Moves the element of [list] at [from] to [to] in place, by assignment
/// alone — for a list that is a view onto native memory, where `[]=` is the
/// one write every such view supports.
void reorderInPlace<T>(List<T> list, int from, int to) {
  final next = reorderedList(list, from, to);
  for (var i = 0; i < next.length; i++) {
    list[i] = next[i];
  }
}

/// The height every row of a [SettingsList] is at least, the add row included,
/// so a list of one-line items is an even ladder whatever is in each rung.
const double kSettingsListRowHeight = 34;

/// The gap between rows inside the box.
const double _kRowGap = 2;

/// The box's own inset around its rows.
const double _kBoxPadding = 4;

/// How much of the theme's `control_surface` the box is filled with.
const double _kBoxAlpha = 0.4;

/// How close to the edge of the page's viewport a dragged row has to be for
/// the page to scroll under it, and how fast it goes at the very edge.
const double _kAutoScrollEdge = 40;
const double _kAutoScrollMaxStep = 14;

/// The bottom padding every settings page's scroll view carries.
const double _kPageBottomPadding = 16;

/// The width a list falls back to when its parent leaves it unbounded — a
/// [SettingsList] belongs where a row can give it the pane's width, but one
/// dropped into an unflexed `Row` should still lay out.
const double _kFallbackWidth = 320;

/// An enclosed, numbered list whose rows reorder by drag, each removed by its
/// own icon, with [adder] as its last row.
///
/// **One box, not a column of boxes.** The rows sit together in a bordered
/// card, each one hover-tinted in the theme's `surface_hover`, so a collection
/// reads as one thing — which is what it is in the configuration file — and the
/// eye can run down the numbers.
///
/// **The adder is the last row.** Whatever adds to the list — a dropdown of
/// choices ([SettingsListAddDropdown]), a field ([SettingsListAddField]) or a
/// chooser opened by a tap ([SettingsListAddRow]) — closes the box, so the
/// next item appears exactly where the user just clicked.
///
/// **The box fills the height it is given.** It lays out at least as tall as
/// its incoming minimum, so a list that is the last thing on a page reaches the
/// foot of the pane rather than ending in a stub — see
/// [SliverSettingsSection.fillLast], which supplies that minimum. Its rows stay
/// at the top; the room under them is the box's.
///
/// **Reordering is by drag.** [onReorder] is called once, on drop, with the
/// index the row came from and the index it lands at (after its removal — see
/// [reorderedList]). Rows grab anywhere unless [handleOnly] — the setting for a
/// row whose content is itself fields and pickers, where a drag inside a text
/// field has to select text — leaves the grip and number as the only handle.
/// The page scrolls under a row held at its edge. While a row is held, the rows
/// it passes slide aside and every number shows the position its row is about
/// to take.
///
/// Rows are keyed by index unless [itemKey] says otherwise. A store whose rows
/// own text fields seeded once — `MiracleConfigStore`'s — passes its revision
/// in the key, which is what keeps a reorder from leaving one row's text in
/// another's field.
class SettingsList extends StatefulWidget {
  const SettingsList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.adder,
    this.iconBuilder,
    this.trailingBuilder,
    this.onRemove,
    this.onReorder,
    this.itemKey,
    this.emptyText,
    this.numbered,
    this.handleOnly = false,
    this.removeTooltip = 'Remove',
  });

  final int itemCount;

  /// A row's content, laid out `Expanded` between its icon and its trailing
  /// actions.
  final IndexedWidgetBuilder itemBuilder;

  /// The last row: what adds to the list. Null only for a collection nothing
  /// can be added to.
  final Widget? adder;

  /// The row's icon — an application's own, a module's — or null for a row
  /// with none. A list with no icons at all passes no builder.
  final Widget? Function(BuildContext context, int index)? iconBuilder;

  /// A control between the content and the remove icon — a badge, a compact
  /// action button.
  final Widget? Function(BuildContext context, int index)? trailingBuilder;

  /// Removes the row at the index. Null for a list whose rows cannot be
  /// removed, which then shows no remove icon.
  final ValueChanged<int>? onRemove;

  /// Moves the row at `from` to `to`. Null for a collection whose order means
  /// nothing — the desktop's pinned items, which are placed by grid position —
  /// which then shows neither grips nor numbers.
  final void Function(int from, int to)? onReorder;

  final Key Function(int index)? itemKey;

  /// Shown as the list's only row while it is empty, above the adder.
  final String? emptyText;

  /// Whether each row carries its position. Defaults to whether the list is
  /// ordered at all.
  final bool? numbered;

  /// Whether only the grip and number start a drag, rather than the whole row.
  final bool handleOnly;

  final String removeTooltip;

  @override
  State<SettingsList> createState() => _SettingsListState();
}

/// Where a drag has got to: published to every row through one notifier, so a
/// pointer move rebuilds the rows whose offset or number it changed and nothing
/// else — never the list, and never a row's content.
@immutable
class _DragFrame {
  const _DragFrame({
    required this.from,
    required this.to,
    required this.dy,
    required this.shift,
  });

  /// The row being held.
  final int from;

  /// Where it would land if dropped now.
  final int to;

  /// How far the held row is from its own slot.
  final double dy;

  /// How far a row it has passed moves aside: the held row's height and a gap.
  final double shift;
}

class _SettingsListState extends State<SettingsList>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<_DragFrame?> _drag = ValueNotifier(null);
  final GlobalKey _bodyKey = GlobalKey();

  /// Each row's top and height in the body's space, measured when a drag
  /// starts. Rows do not change size while one is held.
  List<double> _tops = const [];
  List<double> _heights = const [];

  /// Where in its row the pointer took hold.
  double _grab = 0;
  Offset _pointer = Offset.zero;

  /// Started only while a held row sits at the edge of the page's viewport.
  late final Ticker _scroller = createTicker((_) => _scrollTick());
  double _scrollStep = 0;

  bool get _reorderable => widget.onReorder != null && widget.itemCount > 1;

  @override
  void didUpdateWidget(SettingsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list changed under a held row — a store write from elsewhere. The
    // measured slots no longer describe it, so the drag is abandoned rather
    // than dropped somewhere the user did not mean.
    if (_drag.value != null && widget.itemCount != oldWidget.itemCount) {
      _cancel();
    }
  }

  @override
  void dispose() {
    _scroller.dispose();
    _drag.dispose();
    super.dispose();
  }

  _RenderListBody? get _body {
    final body = _bodyKey.currentContext?.findRenderObject();
    return body is _RenderListBody && body.hasSize ? body : null;
  }

  void _start(int index, DragStartDetails details) {
    if (!_reorderable) return;
    final body = _body;
    if (body == null) return;
    final (tops, heights) = body.measure(widget.itemCount);
    if (index >= tops.length) return;
    _tops = tops;
    _heights = heights;
    _pointer = details.globalPosition;
    _grab = body.globalToLocal(_pointer).dy - tops[index];
    _publish(index);
  }

  void _update(DragUpdateDetails details) {
    final frame = _drag.value;
    if (frame == null) return;
    _pointer = details.globalPosition;
    _publish(frame.from);
    _updateAutoScroll();
  }

  void _end() {
    final frame = _drag.value;
    _stopAutoScroll();
    if (frame == null) return;
    // Cleared first, and in the same frame as the write: the rows drop their
    // offsets without animating, so the next frame shows the new order with
    // every row already in its slot, rather than sliding back from where the
    // drag left them.
    _drag.value = null;
    if (frame.to != frame.from) widget.onReorder?.call(frame.from, frame.to);
  }

  void _cancel() {
    _stopAutoScroll();
    _drag.value = null;
  }

  /// Works out where the held row is and where it would land, from the
  /// pointer's position in the body's own space — which is what keeps it under
  /// the pointer while the page scrolls.
  void _publish(int from) {
    final body = _body;
    if (body == null || from >= _tops.length) return;
    final n = _tops.length;
    final height = _heights[from];
    final top = (body.globalToLocal(_pointer).dy - _grab).clamp(
      _tops.first,
      math.max(_tops.first, _tops.last + _heights.last - height),
    );
    // A row is passed once the held row's leading edge crosses its middle:
    // the bottom edge going down, the top going up. Edges rather than the
    // held row's own middle, so a row held against the end of the list has
    // passed the last one there.
    double centerOf(int i) => _tops[i] + _heights[i] / 2;
    var to = from;
    for (var j = from + 1; j < n && top + height > centerOf(j); j++) {
      to = j;
    }
    for (var j = from - 1; j >= 0 && top < centerOf(j); j--) {
      to = j;
    }
    _drag.value = _DragFrame(
      from: from,
      to: to,
      dy: top - _tops[from],
      shift: height + _kRowGap,
    );
  }

  void _updateAutoScroll() {
    final scrollable = Scrollable.maybeOf(context);
    final box = scrollable?.context.findRenderObject();
    if (scrollable == null ||
        box is! RenderBox ||
        !box.hasSize ||
        axisDirectionToAxis(scrollable.axisDirection) != Axis.vertical) {
      _stopAutoScroll();
      return;
    }
    final y = box.globalToLocal(_pointer).dy;
    final height = box.size.height;
    double step = 0;
    if (y < _kAutoScrollEdge) {
      step = -_kAutoScrollMaxStep * (1 - math.max(0.0, y) / _kAutoScrollEdge);
    } else if (y > height - _kAutoScrollEdge) {
      step =
          _kAutoScrollMaxStep *
          (1 - math.max(0.0, height - y) / _kAutoScrollEdge);
    }
    _scrollStep = step;
    if (step == 0) {
      _stopAutoScroll();
    } else if (!_scroller.isActive) {
      _scroller.start();
    }
  }

  void _scrollTick() {
    final frame = _drag.value;
    final position = Scrollable.maybeOf(context)?.position;
    if (frame == null || position == null || _scrollStep == 0) {
      _stopAutoScroll();
      return;
    }
    final next = (position.pixels + _scrollStep).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) {
      _stopAutoScroll();
      return;
    }
    position.jumpTo(next);
    // The pointer has not moved, but the list has moved under it.
    _publish(frame.from);
  }

  void _stopAutoScroll() {
    _scrollStep = 0;
    if (_scroller.isActive) _scroller.stop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final reorderable = widget.onReorder != null;
    final numbered = widget.numbered ?? reorderable;
    final onRemove = widget.onRemove;
    final emptyText = widget.emptyText;
    final adder = widget.adder;
    final children = <Widget>[
      for (var i = 0; i < widget.itemCount; i++)
        _ListItem(
          key: widget.itemKey?.call(i) ?? ValueKey<int>(i),
          index: i,
          drag: _drag,
          numbered: numbered,
          reorderable: reorderable,
          handleOnly: widget.handleOnly,
          icon: widget.iconBuilder?.call(context, i),
          trailing: widget.trailingBuilder?.call(context, i),
          removeTooltip: widget.removeTooltip,
          onRemove: onRemove == null ? null : () => onRemove(i),
          onDragStart: (details) => _start(i, details),
          onDragUpdate: _update,
          onDragEnd: _end,
          onDragCancel: _cancel,
          child: widget.itemBuilder(context, i),
        ),
      if (widget.itemCount == 0 && emptyText != null)
        _EmptyRow(text: emptyText),
      ?adder,
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        // A wash of the control surface rather than the surface itself: two of
        // the shipped themes (dracula, carbon) spell `surface_hover` and
        // `control_surface` the same, so rows on a full-strength box would
        // have no hover to show.
        color: theme.controlSurface.atMostAlpha(_kBoxAlpha),
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(color: theme.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_kBoxPadding),
        child: ValueListenableBuilder<_DragFrame?>(
          valueListenable: _drag,
          // Only the paint order follows the drag — the held row is drawn
          // over the rows it passes — so the children are handed in rather
          // than rebuilt.
          builder: (context, frame, _) => _ListBody(
            key: _bodyKey,
            front: frame?.from,
            gap: _kRowGap,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// One row: grip, number, icon, content, trailing control and remove icon,
/// moved aside or carried by the drag.
class _ListItem extends StatefulWidget {
  const _ListItem({
    super.key,
    required this.index,
    required this.drag,
    required this.numbered,
    required this.reorderable,
    required this.handleOnly,
    required this.icon,
    required this.trailing,
    required this.removeTooltip,
    required this.onRemove,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.child,
  });

  final int index;
  final ValueListenable<_DragFrame?> drag;
  final bool numbered;
  final bool reorderable;
  final bool handleOnly;
  final Widget? icon;
  final Widget? trailing;
  final String removeTooltip;
  final VoidCallback? onRemove;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final Widget child;

  @override
  State<_ListItem> createState() => _ListItemState();
}

class _ListItemState extends State<_ListItem> {
  /// What this row shows of the drag: how far it is moved, whether it is the
  /// one held, which position it is about to take, and whether its move should
  /// glide. Compared before a rebuild, so a pointer move rebuilds only the
  /// rows it actually displaced.
  ({double offset, bool lifted, int position, bool glide}) _view = (
    offset: 0,
    lifted: false,
    position: 0,
    glide: false,
  );

  @override
  void initState() {
    super.initState();
    _view = _compute();
    widget.drag.addListener(_onDrag);
  }

  @override
  void didUpdateWidget(_ListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drag != widget.drag) {
      oldWidget.drag.removeListener(_onDrag);
      widget.drag.addListener(_onDrag);
    }
    _view = _compute();
  }

  @override
  void dispose() {
    widget.drag.removeListener(_onDrag);
    super.dispose();
  }

  void _onDrag() {
    final next = _compute();
    if (next != _view) setState(() => _view = next);
  }

  ({double offset, bool lifted, int position, bool glide}) _compute() {
    final i = widget.index;
    final frame = widget.drag.value;
    if (frame == null) {
      return (offset: 0, lifted: false, position: i, glide: false);
    }
    if (i == frame.from) {
      return (offset: frame.dy, lifted: true, position: frame.to, glide: false);
    }
    if (i > frame.from && i <= frame.to) {
      return (
        offset: -frame.shift,
        lifted: false,
        position: i - 1,
        glide: true,
      );
    }
    if (i < frame.from && i >= frame.to) {
      return (offset: frame.shift, lifted: false, position: i + 1, glide: true);
    }
    return (offset: 0, lifted: false, position: i, glide: true);
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: view.offset),
      // A displaced row glides aside; the held one follows the pointer
      // exactly, and on a drop every row lands at once.
      duration: view.glide ? ShellDurations.fast : Duration.zero,
      curve: Curves.easeOut,
      // Its own boundary, so moving a row composites a layer rather than
      // re-recording the list — see [SettingsRow] for the rule.
      child: RepaintBoundary(
        child: _ItemChrome(
          position: view.position,
          lifted: view.lifted,
          numbered: widget.numbered,
          reorderable: widget.reorderable,
          handleOnly: widget.handleOnly,
          icon: widget.icon,
          trailing: widget.trailing,
          removeTooltip: widget.removeTooltip,
          onRemove: widget.onRemove,
          onDragStart: widget.onDragStart,
          onDragUpdate: widget.onDragUpdate,
          onDragEnd: widget.onDragEnd,
          onDragCancel: widget.onDragCancel,
          child: widget.child,
        ),
      ),
      // Always the transform, even at rest: swapping it in and out would
      // change the row's place in the tree, remounting the gesture detector
      // holding the drag — and every field in the row.
      builder: (context, offset, child) =>
          Transform.translate(offset: Offset(0, offset), child: child),
    );
  }
}

class _ItemChrome extends StatelessWidget {
  const _ItemChrome({
    required this.position,
    required this.lifted,
    required this.numbered,
    required this.reorderable,
    required this.handleOnly,
    required this.icon,
    required this.trailing,
    required this.removeTooltip,
    required this.onRemove,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.child,
  });

  final int position;
  final bool lifted;
  final bool numbered;
  final bool reorderable;
  final bool handleOnly;
  final Widget? icon;
  final Widget? trailing;
  final String removeTooltip;
  final VoidCallback? onRemove;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final Widget child;

  Widget _draggable(Widget child) => MouseRegion(
    cursor: lifted ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: onDragStart,
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: (_) => onDragEnd(),
      onVerticalDragCancel: onDragCancel,
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final roomy = SettingsPaneStyle.of(context).roomy;
    final icon = this.icon;
    final trailing = this.trailing;
    final onRemove = this.onRemove;
    final muted = theme.popupForeground.withValues(alpha: 0.45);

    // The grip and the number: the handle when [handleOnly], and the part of
    // the row that says it can be moved at all.
    final Widget? handle = !reorderable && !numbered
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reorderable)
                SizedBox(
                  width: 14,
                  child: Center(
                    child: ShellIcon(
                      ShellGlyph.dragHandle,
                      size: 11,
                      color: lifted ? theme.accentText : muted,
                    ),
                  ),
                ),
              if (numbered)
                SizedBox(
                  width: 22,
                  child: Text(
                    '${position + 1}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: ShellFontSizes.caption,
                      fontFamily: theme.fontFamily,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: lifted ? theme.accentText : muted,
                    ),
                  ),
                ),
            ],
          );

    final lead = <Widget>[
      if (handle != null) ...[
        if (reorderable && handleOnly) _draggable(handle) else handle,
        const SizedBox(width: 10),
      ],
      if (icon != null) ...[
        SizedBox(width: 20, child: Center(child: icon)),
        const SizedBox(width: 10),
      ],
    ];

    final row = Row(
      children: [
        ...lead,
        Expanded(child: child),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
        if (onRemove != null) ...[
          const SizedBox(width: 4),
          SettingsIconButton(
            icon: ShellGlyph.close,
            size: 12,
            tooltip: removeTooltip,
            onTap: onRemove,
          ),
        ],
      ],
    );

    final body = HoverRegion(
      // Deferred, so the grab cursor of a row that drags shows through rather
      // than the hand a tappable control would get.
      cursor: MouseCursor.defer,
      builder: (context, hovered) => Container(
        constraints: const BoxConstraints(minHeight: kSettingsListRowHeight),
        padding: roomy
            ? const EdgeInsets.fromLTRB(8, 10, 4, 10)
            : const EdgeInsets.fromLTRB(6, 4, 4, 4),
        decoration: BoxDecoration(
          // A held row is drawn as lifted off the list — the pane's own
          // colour, an accent rim and a shadow — so it reads as in the hand
          // rather than as one more hovered row.
          color: lifted
              ? theme.popupBackground.withValues(alpha: 1)
              : hovered
              ? theme.surfaceHover
              : null,
          borderRadius: BorderRadius.circular(ShellRadii.control),
          // Always a border, transparent at rest: a `Container` insets its
          // child by the border's width, so one that came and went with the
          // lift would grow the held row by two pixels and nudge every row
          // under it.
          border: Border.all(
            color: lifted ? theme.accent : const Color(0x00000000),
          ),
          boxShadow: lifted
              ? [
                  BoxShadow(
                    color: theme.popupShadowColor,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: row,
      ),
    );
    return reorderable && !handleOnly ? _draggable(body) : body;
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: kSettingsListRowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      alignment: Alignment.centerLeft,
      child: SettingsHint(text),
    );
  }
}

// ---------------------------------------------------------------------------
// The add row
// ---------------------------------------------------------------------------

/// The last row of a [SettingsList]: a plus and what it adds.
///
/// For a collection whose next item comes from somewhere a tap opens — the
/// application chooser, the file picker — or that is added blank and filled in
/// where it lands. [SettingsListAddDropdown] and [SettingsListAddField] are
/// this row too, with the list or the field behind it.
///
/// Two of these side by side in a `Row` of `Expanded`s is how a list that adds
/// from two places — the desktop's applications and files — closes.
class SettingsListAddRow extends StatelessWidget {
  const SettingsListAddRow({
    super.key,
    required this.label,
    required this.onTap,
    this.open = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Whether what the row opens is up, which holds its tint.
  final bool open;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final content = Row(
      children: [
        SizedBox(
          width: 20,
          child: Center(
            child: ShellIcon(
              ShellGlyph.add,
              size: ShellFontSizes.caption,
              color: theme.accentText,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              fontFamily: theme.fontFamily,
              color: theme.accentText,
            ),
          ),
        ),
      ],
    );
    // Not inside a [SettingsRow], and it hovers — see that class for the rule.
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          constraints: const BoxConstraints(minHeight: kSettingsListRowHeight),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: hovered || open ? theme.surfaceHover : null,
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// A [SettingsListAddRow] that drops a searchable list of [options] — the
/// modules a panel slot can take, the keyboard layouts xkb knows.
///
/// The card is the row's own width, through the same [AnchoredSearchDropdown]
/// every selector in the settings UI uses, and flips above the row when the
/// room below it will not hold the list.
class SettingsListAddDropdown<T> extends StatelessWidget {
  const SettingsListAddDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.onSelected,
    required this.labelOf,
    this.filter,
    this.iconOf,
    this.detailOf,
    this.isAdded,
    this.emptyText = 'No matches',
  });

  final String label;
  final List<T> options;
  final ValueChanged<T> onSelected;
  final String Function(T option) labelOf;

  /// Ranks [options] for a query. Defaults to a substring match on the label
  /// and the detail.
  final List<T> Function(String query)? filter;

  final Widget? Function(T option)? iconOf;

  /// A second, dimmer string on the right — a module's config key, a layout's
  /// xkb id.
  final String? Function(T option)? detailOf;

  /// An option already in the list: shown dimmed and marked, and refused on
  /// select. Kept in the list rather than hidden, so it does not change shape
  /// under the user between one visit and the next.
  final bool Function(T option)? isAdded;

  final String emptyText;

  List<T> _filter(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return options;
    return options
        .where(
          (o) =>
              labelOf(o).toLowerCase().contains(q) ||
              (detailOf?.call(o)?.toLowerCase().contains(q) ?? false),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnchoredSearchDropdown<T>(
      matchTriggerWidth: true,
      rowHeight: 32,
      maxHeight: 300,
      emptyText: emptyText,
      // A list short enough to see whole needs no field to narrow it.
      showSearch: options.length > 8,
      filter: filter ?? _filter,
      onSelected: (option) {
        if (isAdded?.call(option) ?? false) return;
        onSelected(option);
      },
      itemBuilder: (context, option, highlighted) {
        final theme = ThemeScope.of(context);
        final added = isAdded?.call(option) ?? false;
        final icon = iconOf?.call(option);
        final detail = added ? 'added' : detailOf?.call(option);
        return Row(
          children: [
            if (icon != null) ...[
              SizedBox(width: 20, child: Center(child: icon)),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                labelOf(option),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(
                    alpha: added ? 0.4 : 1,
                  ),
                ),
              ),
            ),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                detail,
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        );
      },
      triggerBuilder: (context, open, toggle) =>
          SettingsListAddRow(label: label, onTap: toggle, open: open),
    );
  }
}

/// A [SettingsListAddRow] that becomes a text field, for a value nothing can
/// list — a path, a feed's address, a tray item's id.
///
/// Enter adds and leaves the field open and focused: these lists are typed in
/// runs, and closing after each entry would mean a click between every two.
/// Escape, or the cross, puts the row back.
class SettingsListAddField extends StatefulWidget {
  const SettingsListAddField({
    super.key,
    required this.label,
    required this.onSubmitted,
    this.hint,
  });

  final String label;
  final String? hint;

  /// Called with the trimmed text; never with an empty string.
  final ValueChanged<String> onSubmitted;

  @override
  State<SettingsListAddField> createState() => _SettingsListAddFieldState();
}

class _SettingsListAddFieldState extends State<SettingsListAddField> {
  final _controller = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _onKey);
  bool _composing = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _open() {
    setState(() => _composing = true);
    _focus.requestFocus();
  }

  void _close() {
    _controller.clear();
    setState(() => _composing = false);
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) widget.onSubmitted(value);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!_composing) {
      return SettingsListAddRow(label: widget.label, onTap: _open);
    }
    final theme = ThemeScope.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: kSettingsListRowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Center(
              child: ShellIcon(
                ShellGlyph.add,
                size: ShellFontSizes.caption,
                color: theme.accentText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SettingsTextField(
              controller: _controller,
              focusNode: _focus,
              hint: widget.hint ?? 'add…',
              onChanged: (_) {},
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 4),
          SettingsIconButton(
            icon: ShellGlyph.check,
            tooltip: 'Add',
            onTap: _submit,
          ),
          SettingsIconButton(
            icon: ShellGlyph.close,
            tooltip: 'Cancel',
            onTap: _close,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filling the pane
// ---------------------------------------------------------------------------

/// A box column whose last child takes whatever minimum height is left over —
/// what lets a labelled list reach the foot of the pane under its label.
///
/// A `Column` cannot: it can only stretch a child into a *bounded* height, and
/// a page's scroll view gives its slivers an unbounded one. This lays its
/// children out loosely and hands the last one the rest of the incoming
/// minimum, so a [SettingsList] at the end of it — which sizes itself to at
/// least its minimum — fills the page, and one with more rows than the page
/// has room for simply grows.
class SettingsFillColumn extends MultiChildRenderObjectWidget {
  const SettingsFillColumn({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderListBody(gap: 0, stretchLast: true);
}

/// The fill a page gives the last thing on it: a minimum height of whatever
/// the page's viewport has left below the content before it.
///
/// Computed from the sliver's own constraints, so it costs nothing to keep up
/// to date: a scroll changes the constraints but not the room left, and an
/// unchanged minimum relays nothing out. A page whose content is already
/// taller than its viewport gets no minimum at all.
class SliverSettingsFill extends StatelessWidget {
  const SliverSettingsFill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // What follows the fill on a page: the bottom inset of the section card
    // it sits on, on a roomy pane the gap a section leaves under itself, and
    // the scroll view's own bottom padding. Kept out of the minimum, or a page
    // that fits would scroll by exactly that much.
    final roomy = SettingsPaneStyle.of(context).roomy;
    final reserve =
        settingsCardPadding(roomy: roomy).bottom +
        (roomy ? 20.0 : 0.0) +
        _kPageBottomPadding;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final room =
            constraints.viewportMainAxisExtent -
            constraints.precedingScrollExtent -
            reserve;
        return SliverToBoxAdapter(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0.0, room)),
            child: child,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

/// The list's body: its rows stacked with a gap, the held one painted last.
class _ListBody extends MultiChildRenderObjectWidget {
  const _ListBody({
    super.key,
    required this.front,
    required this.gap,
    required super.children,
  });

  final int? front;
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderListBody(gap: gap, stretchLast: false)..front = front;

  @override
  void updateRenderObject(BuildContext context, _RenderListBody renderObject) {
    renderObject
      ..gap = gap
      ..front = front;
  }
}

class _ListBodyParentData extends ContainerBoxParentData<RenderBox> {}

/// A vertical stack at the incoming width.
///
/// Two things a `Column` does not do: it is at least as tall as its incoming
/// minimum — and with [stretchLast] hands that extra to its last child rather
/// than leaving it as space — and it paints the child at [front] after the
/// others, so a row being dragged passes *over* the rows it displaces.
class _RenderListBody extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ListBodyParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ListBodyParentData> {
  _RenderListBody({required double gap, required this.stretchLast})
    : _gap = gap;

  final bool stretchLast;

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  int? get front => _front;
  int? _front;
  set front(int? value) {
    if (value == _front) return;
    _front = value;
    markNeedsPaint();
  }

  /// Each of the first [count] children's top and height, for a drag.
  (List<double>, List<double>) measure(int count) {
    final tops = <double>[];
    final heights = <double>[];
    var child = firstChild;
    while (child != null && tops.length < count) {
      final data = child.parentData! as _ListBodyParentData;
      tops.add(data.offset.dy);
      heights.add(child.size.height);
      child = data.nextSibling;
    }
    return (tops, heights);
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ListBodyParentData) {
      child.parentData = _ListBodyParentData();
    }
  }

  double _width(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? constraints.maxWidth
      : constraints.constrainWidth(_kFallbackWidth);

  Size _layout(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) layoutChild,
  ) {
    final width = _width(constraints);
    final loose = BoxConstraints.tightFor(width: width);
    var height = 0.0;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _ListBodyParentData;
      final next = data.nextSibling;
      var childConstraints = loose;
      if (stretchLast && next == null) {
        childConstraints = BoxConstraints(
          minWidth: width,
          maxWidth: width,
          minHeight: math.max(0.0, constraints.minHeight - height),
        );
      }
      final size = layoutChild(child, childConstraints);
      height += size.height;
      if (next != null) height += _gap;
      child = next;
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    var y = 0.0;
    size = _layout(constraints, (child, childConstraints) {
      child.layout(childConstraints, parentUsesSize: true);
      final data = child.parentData! as _ListBodyParentData;
      data.offset = Offset(0, y);
      y += child.size.height + _gap;
      return child.size;
    });
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, (child, c) => child.getDryLayout(c));

  double _sumHeights(double Function(RenderBox child) height) {
    var total = 0.0;
    var count = 0;
    var child = firstChild;
    while (child != null) {
      total += height(child);
      count++;
      child = (child.parentData! as _ListBodyParentData).nextSibling;
    }
    return total + math.max(0, count - 1) * _gap;
  }

  double _maxWidth(double Function(RenderBox child) width) {
    var widest = 0.0;
    var child = firstChild;
    while (child != null) {
      widest = math.max(widest, width(child));
      child = (child.parentData! as _ListBodyParentData).nextSibling;
    }
    return widest;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _sumHeights((c) => c.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _sumHeights((c) => c.getMaxIntrinsicHeight(width));

  @override
  double computeMinIntrinsicWidth(double height) =>
      _maxWidth((c) => c.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _maxWidth((c) => c.getMaxIntrinsicWidth(double.infinity));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderBox? held;
    var index = 0;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _ListBodyParentData;
      if (index == _front) {
        held = child;
      } else {
        context.paintChild(child, data.offset + offset);
      }
      index++;
      child = data.nextSibling;
    }
    if (held != null) {
      final data = held.parentData! as _ListBodyParentData;
      context.paintChild(held, data.offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
