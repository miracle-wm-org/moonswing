import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/calendar/analog_clock.dart';
import 'package:moonswing/overlay/calendar/month.dart';
import 'package:moonswing/overlay/calendar/time_zones.dart';
import 'package:moonswing/overlay/calendar/timezone_picker.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/theme/tokens.dart';

/// Width of the whole column. Fixed rather than fractional: the overlay panel is
/// 800 wide at its smallest, and the month grid beside this has to stay usable.
///
/// Wider than it was, because the column now carries the timers section under the
/// world clocks: a duration field, two buttons and an entry's three controls all
/// have to fit across it.
const double kClockColumnWidth = 280;

/// The dial at full size. Shrinks on a short surface — see the [LayoutBuilder]
/// in [_CalendarClockColumnState.build].
const double kAnalogClockSize = 128;

/// One world clock's row. Fixed, so the list can be a [ListView] with an
/// `itemExtent` — sized for the row's two lines at the readable sizes this
/// column moved to.
const double kWorldClockRowHeight = 50;

/// How close to the top or bottom of the clock list a held row has to be for
/// the list to scroll under it, and how fast it goes at the very edge.
const double _kAutoScrollEdge = 32;
const double _kAutoScrollMaxStep = 8;

/// The local time, as a dial and a digital readout, over the user's list of world
/// clocks.
///
/// Takes its list and callbacks as parameters and its time from a [ClockSource],
/// so a widget test drives it with a frozen clock and never touches
/// `ConfigStore` or the IANA database.
class CalendarClockColumn extends StatefulWidget {
  const CalendarClockColumn({
    super.key,
    required this.active,
    required this.clocks,
    required this.onAdd,
    required this.onRemove,
    this.onReorder,
    this.clock = const SystemClockSource(),
    this.footer,
  });

  /// Whether the calendar is the tab the user is looking at.
  ///
  /// The overlay body is an `IndexedStack`, which keeps every tab alive once
  /// built — so without this the clock would keep ticking behind the settings
  /// pane for as long as the overlay is open.
  final bool active;

  final List<WorldClock> clocks;
  final ValueChanged<TimeZoneName> onAdd;
  final ValueChanged<String> onRemove;

  /// Moves the clock at `from` so that it lands at `to` — the contract of
  /// [reorderedList]. Called once, on drop. Null leaves the rows where they
  /// are, with no grips.
  final void Function(int from, int to)? onReorder;

  final ClockSource clock;

  /// What is rendered under the world clocks — the calendar's timers section.
  ///
  /// It splits the space below the dial with the clock list, half each, rather
  /// than being sized to its content: both grow with what the user put in them,
  /// and an equal share is the only division that does not privilege whichever
  /// was given a fixed height. Null leaves the whole space to the clocks.
  final Widget? footer;

  @override
  State<CalendarClockColumn> createState() => _CalendarClockColumnState();
}

class _CalendarClockColumnState extends State<CalendarClockColumn> {
  Timer? _timer;
  late DateTime _now = widget.clock.now;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CalendarClockColumn old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.clock != widget.clock) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!widget.active) return;
    // Re-read on the way back in, or returning to the tab would show whatever
    // second it was when the user left it.
    _now = widget.clock.now;
    _schedule();
  }

  /// Re-scheduled to the next wall-clock second rather than [Timer.periodic] —
  /// the `modules/clock.dart` idiom. A periodic timer drifts off the boundary
  /// and the second hand visibly stutters.
  void _schedule() {
    final ms = 1000 - widget.clock.now.millisecond;
    _timer = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      setState(() => _now = widget.clock.now);
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // **The whole column, boundaried.** A tick rewrites the dial, the readout and
    // the date, and a `RenderObject` marked needing paint dirties everything up
    // to the nearest repaint boundary — of which this surface had none, so one
    // second's worth of second hand re-recorded the entire overlay picture and,
    // the GTK embedder implementing no partial repaint, rastered the whole output
    // again after it.
    //
    // The boundary goes here rather than around the three readouts: changing a
    // `Text` marks needs *layout*, and layout stops at the nearest *relayout*
    // boundary — the tightly-constrained `Column` below — which then marks itself
    // needing paint on the way out, stepping over any boundary nested inside it.
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The dial gives way rather than either list being squeezed to nothing:
          // it shrinks with the column, and on a very short output it goes
          // altogether, leaving the digital readout — which says the same thing
          // in a fifth of the height.
          final height = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : double.infinity;
          final showDial = height >= 340;
          final dialSize = height.isFinite
              ? (height * 0.16).clamp(64.0, kAnalogClockSize)
              : kAnalogClockSize;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDial) ...[
                  Center(child: AnalogClock(time: _now, size: dialSize)),
                  const SizedBox(height: 10),
                ],
                Center(
                  child: Text(
                    formatClockTime(_now),
                    style: TextStyle(
                      fontSize: 26,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    '${weekdayNames[_now.weekday % 7]}, '
                    '${monthAbbrev[_now.month - 1]} ${_now.day}',
                    style: TextStyle(
                      fontSize: ShellFontSizes.body,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'World clocks',
                        style: TextStyle(
                          fontSize: ShellFontSizes.label,
                          fontFamily: theme.fontFamily,
                          color: theme.popupForeground.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TimeZonePickerButton(
                      zones: widget.clock.zoneNames,
                      existing: {for (final clock in widget.clocks) clock.zone},
                      onSelected: widget.onAdd,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  // A ListView, never a Column: a Column overflows the moment the
                  // user adds one clock more than the column is tall, and no
                  // widget test would catch it because the test picks the count.
                  child: widget.clocks.isEmpty
                      ? _EmptyClocks(theme: theme)
                      : _WorldClockList(
                          count: widget.clocks.length,
                          onReorder: widget.onReorder,
                          rowBuilder: (_, i, {required lifted}) {
                            final clock = widget.clocks[i];
                            return _WorldClockRow(
                              clock: clock,
                              zone: widget.clock.resolve(clock.zone, _now),
                              here: _now,
                              reorderable: widget.onReorder != null,
                              lifted: lifted,
                              onRemove: () => widget.onRemove(clock.zone),
                            );
                          },
                        ),
                ),
                if (widget.footer != null) ...[
                  const SizedBox(height: 10),
                  Container(height: 1, color: theme.divider),
                  const SizedBox(height: 10),
                  // The same flex as the list above it: half each of whatever the
                  // dial and the readout left.
                  Expanded(child: widget.footer!),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Where a drag of a world clock has got to: published to every row through
/// one notifier, so a pointer move rebuilds the rows it displaced and the held
/// copy, never the list.
@immutable
class _ClockDrag {
  const _ClockDrag({required this.from, required this.to, required this.top});

  /// The row being held.
  final int from;

  /// Where it would land if dropped now.
  final int to;

  /// The held row's top in the list's scrolled content, clamped to the list.
  final double top;
}

/// The world clocks' [ListView], whose rows reorder by drag.
///
/// The rhythm is [SettingsList]'s — the rows a held one passes slide aside,
/// and the write is one call on drop — but not its box: this is a column of
/// cards, scrolled, and a fixed [kWorldClockRowHeight] makes a row's slot
/// plain arithmetic.
///
/// **The held row is a copy over the list, not the row itself.** A sliver
/// paints its children in order, so a row carried down the list would pass
/// *under* every row after it. So its slot keeps the original, mounted but
/// invisible — it holds the gesture detector the drag belongs to — and a copy
/// that answers no hits is drawn in a [Stack] above the viewport, under the
/// pointer.
class _WorldClockList extends StatefulWidget {
  const _WorldClockList({
    required this.count,
    required this.rowBuilder,
    required this.onReorder,
  });

  final int count;
  final Widget Function(BuildContext context, int index, {required bool lifted})
  rowBuilder;
  final void Function(int from, int to)? onReorder;

  @override
  State<_WorldClockList> createState() => _WorldClockListState();
}

class _WorldClockListState extends State<_WorldClockList>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<_ClockDrag?> _drag = ValueNotifier(null);
  final ScrollController _scroll = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();

  /// Where in its row the pointer took hold.
  double _grab = 0;
  Offset _pointer = Offset.zero;

  /// Started only while a held row sits at the top or bottom of the list.
  late final Ticker _scroller = createTicker((_) => _scrollTick());
  double _scrollStep = 0;

  bool get _reorderable => widget.onReorder != null && widget.count > 1;

  @override
  void didUpdateWidget(_WorldClockList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A clock added or removed under a held row — the config file edited by
    // hand, or the picker from another monitor. The slots no longer describe
    // the list, so the drag is abandoned rather than dropped somewhere the
    // user did not mean.
    if (_drag.value != null && widget.count != oldWidget.count) _cancel();
  }

  @override
  void dispose() {
    _scroller.dispose();
    _scroll.dispose();
    _drag.dispose();
    super.dispose();
  }

  RenderBox? get _viewport {
    final box = _viewportKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  double get _scrolled => _scroll.hasClients ? _scroll.offset : 0;

  void _start(int index, DragStartDetails details) {
    if (!_reorderable) return;
    final viewport = _viewport;
    if (viewport == null) return;
    _pointer = details.globalPosition;
    _grab =
        viewport.globalToLocal(_pointer).dy +
        _scrolled -
        index * kWorldClockRowHeight;
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
    // Cleared in the same frame as the write, so the rows drop their offsets
    // without animating and the next frame shows the new order already in
    // place.
    _drag.value = null;
    if (frame.to != frame.from) widget.onReorder?.call(frame.from, frame.to);
  }

  void _cancel() {
    _stopAutoScroll();
    _drag.value = null;
  }

  /// Works out where the held row is and where it would land, in the list's
  /// scrolled content — which is what keeps it under the pointer while the
  /// list scrolls.
  void _publish(int from) {
    final viewport = _viewport;
    if (viewport == null) return;
    const extent = kWorldClockRowHeight;
    final last = widget.count - 1;
    final top = (viewport.globalToLocal(_pointer).dy + _scrolled - _grab)
        .clamp(0.0, last * extent);
    // Rows are one height, so the held row has passed a neighbour once its
    // leading edge crosses that neighbour's middle — which is to say once its
    // top is nearer the neighbour's slot than its own.
    final to = (top / extent).round().clamp(0, last);
    _drag.value = _ClockDrag(from: from, to: to, top: top);
  }

  void _updateAutoScroll() {
    final viewport = _viewport;
    if (viewport == null || !_scroll.hasClients) {
      _stopAutoScroll();
      return;
    }
    final y = viewport.globalToLocal(_pointer).dy;
    final height = viewport.size.height;
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
    if (frame == null || !_scroll.hasClients || _scrollStep == 0) {
      _stopAutoScroll();
      return;
    }
    final position = _scroll.position;
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
    final reorderable = _reorderable;
    final list = ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemExtent: kWorldClockRowHeight,
      itemCount: widget.count,
      itemBuilder: (context, i) => _WorldClockSlot(
        index: i,
        drag: _drag,
        reorderable: reorderable,
        onDragStart: (details) => _start(i, details),
        onDragUpdate: _update,
        onDragEnd: _end,
        onDragCancel: _cancel,
        child: widget.rowBuilder(context, i, lifted: false),
      ),
    );
    return ClipRect(
      child: Stack(
        key: _viewportKey,
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<_ClockDrag?>(
            valueListenable: _drag,
            // While a row is held the list answers no hits, so the rows it
            // passes do not light up under the pointer and the one cursor is
            // the grab. The drag itself is unaffected: a pointer's moves go
            // to what it pressed, not to what is under it now.
            builder: (context, frame, child) => MouseRegion(
              cursor: frame == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.grabbing,
              child: IgnorePointer(ignoring: frame != null, child: child),
            ),
            child: list,
          ),
          ValueListenableBuilder<_ClockDrag?>(
            valueListenable: _drag,
            builder: (context, frame, _) {
              if (frame == null) return const SizedBox.shrink();
              return Positioned(
                top: frame.top - _scrolled,
                left: 0,
                right: 0,
                height: kWorldClockRowHeight,
                child: IgnorePointer(
                  // Its own boundary, so following the pointer composites a
                  // layer rather than re-recording the list under it.
                  child: RepaintBoundary(
                    child: widget.rowBuilder(context, frame.from, lifted: true),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One slot of the clock list: the row, moved aside by a drag that passes it,
/// or kept invisible while it is the one held.
class _WorldClockSlot extends StatefulWidget {
  const _WorldClockSlot({
    required this.index,
    required this.drag,
    required this.reorderable,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.child,
  });

  final int index;
  final ValueListenable<_ClockDrag?> drag;
  final bool reorderable;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final Widget child;

  @override
  State<_WorldClockSlot> createState() => _WorldClockSlotState();
}

class _WorldClockSlotState extends State<_WorldClockSlot> {
  /// What this slot shows of the drag. Compared before a rebuild, so a pointer
  /// move rebuilds only the slots it actually displaced.
  ({double offset, bool held, bool glide}) _view = (
    offset: 0,
    held: false,
    glide: false,
  );

  @override
  void initState() {
    super.initState();
    _view = _compute();
    widget.drag.addListener(_onDrag);
  }

  @override
  void didUpdateWidget(_WorldClockSlot oldWidget) {
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

  ({double offset, bool held, bool glide}) _compute() {
    final i = widget.index;
    final frame = widget.drag.value;
    if (frame == null) return (offset: 0, held: false, glide: false);
    if (i == frame.from) return (offset: 0, held: true, glide: false);
    const shift = kWorldClockRowHeight;
    if (i > frame.from && i <= frame.to) {
      return (offset: -shift, held: false, glide: true);
    }
    if (i < frame.from && i >= frame.to) {
      return (offset: shift, held: false, glide: true);
    }
    return (offset: 0, held: false, glide: true);
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    // An Opacity at rest too, at full strength — which paints its child
    // directly — so that hiding the held row changes no structure, and the
    // gesture detector holding the drag is never remounted.
    Widget row = Opacity(opacity: view.held ? 0 : 1, child: widget.child);
    if (widget.reorderable) {
      row = MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: widget.onDragStart,
          onVerticalDragUpdate: widget.onDragUpdate,
          onVerticalDragEnd: (_) => widget.onDragEnd(),
          onVerticalDragCancel: widget.onDragCancel,
          child: row,
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: view.offset),
      // A displaced row glides aside; on a drop every row lands at once.
      duration: view.glide ? ShellDurations.fast : Duration.zero,
      curve: Curves.easeOut,
      // Its own boundary, so moving a row composites a layer rather than
      // re-recording the list.
      child: RepaintBoundary(child: row),
      // Always the transform, even at rest, for the same reason as the
      // Opacity above.
      builder: (context, offset, child) =>
          Transform.translate(offset: Offset(0, offset), child: child),
    );
  }
}

class _EmptyClocks extends StatelessWidget {
  const _EmptyClocks({required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Text(
        'Add a time zone with +',
        style: TextStyle(
          fontSize: ShellFontSizes.body,
          fontFamily: theme.fontFamily,
          color: theme.muted,
        ),
      ),
    );
  }
}

class _WorldClockRow extends StatefulWidget {
  const _WorldClockRow({
    required this.clock,
    required this.zone,
    required this.here,
    required this.reorderable,
    required this.lifted,
    required this.onRemove,
  });

  final WorldClock clock;

  /// Null when the database does not know the zone — a hand-edited or
  /// deprecated name. The row still renders, and still offers its remove
  /// button, because it is the only way the user can get rid of it.
  final ZoneTime? zone;

  /// The local wall clock, for the day-difference badge.
  final DateTime here;

  /// Whether the row shows a grip — the list can be dragged into order.
  final bool reorderable;

  /// Whether this is the copy carried under the pointer by a drag.
  final bool lifted;

  final VoidCallback onRemove;

  @override
  State<_WorldClockRow> createState() => _WorldClockRowState();
}

class _WorldClockRowState extends State<_WorldClockRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final zone = widget.zone;
    final label = widget.clock.label ?? zoneCityLabel(widget.clock.zone);
    final delta = zone == null ? '' : formatDayDelta(dayDelta(zone.time, widget.here));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          // A held row is drawn lifted off the list, as a [SettingsList] row
          // is: the panel's own colour, an accent rim and a shadow.
          color: widget.lifted
              ? theme.popupBackground.withValues(alpha: 1)
              : _hovered
              ? theme.surfaceHover
              : theme.controlSurface,
          borderRadius: BorderRadius.circular(6),
          // Always a border, transparent at rest: a `Container` insets its
          // child by the border's width, so one that came with the lift would
          // shift the held copy's text off the row it was lifted from.
          border: Border.all(
            color: widget.lifted ? theme.accent : const Color(0x00000000),
          ),
          boxShadow: widget.lifted
              ? [
                  BoxShadow(
                    color: theme.popupShadowColor,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            if (widget.reorderable) ...[
              FaIcon(
                FontAwesomeIcons.gripVertical,
                size: 11,
                color: widget.lifted
                    ? theme.accentText
                    : theme.popupForeground.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: ShellFontSizes.body,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    zone == null
                        ? 'Unknown time zone'
                        : formatUtcOffset(zone.offset),
                    style: TextStyle(
                      fontSize: ShellFontSizes.caption,
                      fontFamily: theme.fontFamily,
                      color: zone == null
                          ? theme.muted
                          : theme.popupForeground.withValues(alpha: 0.45),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (zone != null) ...[
              const SizedBox(width: 6),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatClockTime(zone.time, seconds: false),
                    style: TextStyle(
                      fontSize: ShellFontSizes.title,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (delta.isNotEmpty)
                    Text(
                      delta,
                      style: TextStyle(
                        fontSize: ShellFontSizes.caption,
                        fontFamily: theme.fontFamily,
                        color: theme.accentText,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(width: 4),
            // Always present rather than revealed on hover: the row is the only
            // place a clock can be removed from, and a control that is invisible
            // until hovered is unreachable to anyone who does not know it exists.
            _RemoveButton(onTap: widget.onRemove),
          ],
        ),
      ),
    );
  }
}

/// The row's remove button.
///
/// Its own widget rather than [SettingsIconButton] because that one is 26x26,
/// which does not fit a row that already carries two lines of text.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SettingsIconButton(
      icon: FontAwesomeIcons.xmark,
      size: ShellFontSizes.caption,
      box: ShellSizes.iconButtonDense,
      color: theme.popupForeground.withValues(alpha: 0.5),
      onTap: onTap,
    );
  }
}
