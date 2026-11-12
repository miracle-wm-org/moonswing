// Dragging a module along its section of a bar to a new place in it.
//
// **Hand-rolled from raw pointer events, never a recognizer in the arena.** Every
// bar popup opens on tap-*down* (see `HoverRegion`), and a tap only fires its
// down at once while it is alone in the arena: a pan recognizer around every
// module would hold each of them back until the press deadline. A [Listener]
// takes no part in the arena, so a click is exactly what it was. What that
// costs is deciding by hand when a press has become a drag, and two rules
// follow from it:
//
// - **A drag starts only past the tap's own slop** ([barModuleDragSlop]): a tap
//   that has won keeps its pointer until it strays [kTouchSlop], and is
//   cancelled there — so a press that becomes a drag never also clicks.
// - **A module with a drag of its own keeps it** ([BarDragClaim]). The dock's
//   pinned apps reorder by dragging; its pan passes its own (smaller) slop
//   first and claims the press, and this drag then never starts.
//
// Like the dock's, the drag reaches [ConfigStore] only on the drop — every
// `set` notifies synchronously and rebuilds every panel on every monitor — and
// the section is reordered in local state while it runs. Children are keyed by
// the id they were given, so a module keeps its element, and whatever popup or
// timer it owns, as it moves.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:moonswing/bar_module_row.dart';
import 'package:moonswing/popup_coordinator.dart';

/// How far a press must travel before it is a drag of the module under it:
/// past both a tap's slop, so the tap is already cancelled, and a pan's, so a
/// module's own drag has had the chance to claim the press.
double barModuleDragSlop(PointerDeviceKind kind) =>
    math.max(kTouchSlop, computePanSlop(kind, null)) + 2;

/// Lets a module with a drag of its own keep a press from becoming a drag of
/// the whole module. Reset by every press on a module; claimed from the inner
/// drag's start, which comes first because its slop is smaller.
abstract final class BarDragClaim {
  static bool _claimed = false;

  /// Whether a module's own drag has taken the current press.
  static bool get claimed => _claimed;

  /// Takes the current press for a module's own drag.
  static void claim() => _claimed = true;

  static void _reset() => _claimed = false;
}

/// Where the module at [position] of a section starts along the bar, laid out
/// as [RenderBarModuleRow] lays it: a module of zero extent takes no room and
/// no gap.
double barSlotStart(List<double> extents, int position, double gap) {
  var start = 0.0;
  var shown = 0;
  for (var j = 0; j < position; j++) {
    final extent = extents[j];
    if (extent <= 0) continue;
    if (shown > 0) start += gap;
    start += extent;
    shown++;
  }
  if (extents[position] > 0 && shown > 0) start += gap;
  return start;
}

/// Where [dragged] goes among [rest] when its leading edge is at [start]: the
/// place whose slot starts nearest it. Ties go to the earlier place, so a
/// module held still does not swap back and forth.
int barDropPosition({
  required List<double> rest,
  required double dragged,
  required double start,
  required double gap,
}) {
  var best = 0;
  var bestDistance = double.infinity;
  for (var k = 0; k <= rest.length; k++) {
    final extents = [...rest]..insert(k, dragged);
    final distance = (barSlotStart(extents, k, gap) - start).abs();
    if (distance < bestDistance) {
      best = k;
      bestDistance = distance;
    }
  }
  return best;
}

/// A bar section whose modules can be dragged along it into a new order.
///
/// [ids] names each of [children] — stable across a reorder, so a module keeps
/// its element as it moves. [onReorder] is told the new order once, on the
/// drop, as `order[i]` = the index in [children] of what now goes i-th; it is
/// not called for a drag that left everything where it was. Null makes the
/// section a plain [BarModuleRow].
class ReorderableBarSection extends StatefulWidget {
  const ReorderableBarSection({
    super.key,
    required this.axis,
    required this.ids,
    required this.children,
    this.gap = 8,
    this.onReorder,
  }) : assert(ids.length == children.length);

  final Axis axis;
  final double gap;
  final List<String> ids;
  final List<Widget> children;
  final void Function(List<int> order)? onReorder;

  @override
  State<ReorderableBarSection> createState() => _ReorderableBarSectionState();
}

class _ReorderableBarSectionState extends State<ReorderableBarSection> {
  /// The display order while a drag runs, as indices into the children; null
  /// when idle, which is their own order.
  List<int>? _order;

  /// The child pressed, and the pointer pressing it, before and during a drag.
  int? _pressed;
  int? _pointer;
  Offset _downAt = Offset.zero;
  bool _dragging = false;

  /// Each child's extent along the bar, by child index, measured as the drag
  /// started; a reorder does not resize anything.
  List<double> _extents = const [];

  /// The pointer's offset into the dragged module, and where the module's
  /// leading edge now is, both along the bar in the section's own space.
  double _grab = 0;
  double _start = 0;

  bool get _horizontal => widget.axis == Axis.horizontal;

  @override
  void didUpdateWidget(ReorderableBarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list changed under the drag — a drop landing in the config, or the
    // settings page editing the same section: what was being dragged is no
    // longer what is shown.
    if (!listEquals(oldWidget.ids, widget.ids)) _reset();
  }

  void _reset() {
    _order = null;
    _pressed = null;
    _pointer = null;
    _dragging = false;
  }

  double _along(Offset local) => _horizontal ? local.dx : local.dy;

  RenderBarModuleRow? get _row {
    final row = context.findRenderObject();
    return row is RenderBarModuleRow && row.hasSize ? row : null;
  }

  void _onDown(int index, PointerDownEvent event) {
    if (widget.onReorder == null) return;
    if (event.buttons & kPrimaryButton == 0) return;
    if (_pointer != null) return;
    BarDragClaim._reset();
    _pressed = index;
    _pointer = event.pointer;
    _downAt = event.position;
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if (!_dragging) {
      if (BarDragClaim.claimed) {
        // A module's own drag has the press; leave it be.
        _pointer = null;
        _pressed = null;
        return;
      }
      if ((event.position - _downAt).distance <=
          barModuleDragSlop(event.kind)) {
        return;
      }
      if (!_begin()) return;
    }
    final row = _row;
    if (row == null) return;
    final along = _along(row.globalToLocal(event.position));
    final order = _order!;
    final dragged = _pressed!;
    final total = _horizontal ? row.size.width : row.size.height;
    final extent = _extents[dragged];
    // Kept inside the section: a module is reordered within its own side of
    // the bar, never carried off it.
    final start = (along - _grab)
        .clamp(0.0, math.max(0.0, total - extent))
        .toDouble();
    final rest = [
      for (final i in order)
        if (i != dragged) i,
    ];
    final position = barDropPosition(
      rest: [for (final i in rest) _extents[i]],
      dragged: extent,
      start: start,
      gap: widget.gap,
    );
    setState(() {
      _start = start;
      _order = [...rest]..insert(position, dragged);
    });
  }

  /// Turns the press into a drag, or says it cannot be one.
  bool _begin() {
    final row = _row;
    final pressed = _pressed;
    if (row == null || pressed == null) return false;
    final extents = List<double>.filled(widget.children.length, 0);
    var child = row.firstChild;
    var i = 0;
    while (child != null && i < extents.length) {
      extents[i] = _horizontal ? child.size.width : child.size.height;
      child = row.childAfter(child);
      i++;
    }
    final order = List<int>.generate(extents.length, (i) => i);
    final slot = barSlotStart(extents, pressed, widget.gap);
    _extents = extents;
    _grab = _along(row.globalToLocal(_downAt)) - slot;
    _start = slot;
    _order = order;
    _dragging = true;
    // The press opened the module's popup on its way down; a drag is not a
    // click, so that goes.
    PopupCoordinator.instance.dismissOutside(null);
    return true;
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final order = _order;
    final moved =
        _dragging &&
        order != null &&
        !listEquals(order, List<int>.generate(order.length, (i) => i));
    setState(_reset);
    if (moved) widget.onReorder?.call(order);
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    setState(_reset);
  }

  double _shiftOf(int index) {
    final order = _order;
    if (!_dragging || order == null || index != _pressed) return 0;
    final position = order.indexOf(index);
    final extents = [for (final i in order) _extents[i]];
    return _start - barSlotStart(extents, position, widget.gap);
  }

  @override
  Widget build(BuildContext context) {
    final order =
        _order ?? List<int>.generate(widget.children.length, (i) => i);
    return BarModuleRow(
      axis: widget.axis,
      gap: widget.gap,
      children: [
        for (final i in order)
          Listener(
            key: ValueKey(widget.ids[i]),
            onPointerDown: (event) => _onDown(i, event),
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onCancel,
            // Always a Transform, at zero when still, so the dragged module
            // keeps its element; a translation pushes no layer.
            child: Transform.translate(
              offset: _horizontal
                  ? Offset(_shiftOf(i), 0)
                  : Offset(0, _shiftOf(i)),
              child: widget.children[i],
            ),
          ),
      ],
    );
  }
}
