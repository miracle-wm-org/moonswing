import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/calendar/analog_clock.dart';
import 'package:graceful_shell/overlay/calendar/month.dart';
import 'package:graceful_shell/overlay/calendar/time_zones.dart';
import 'package:graceful_shell/overlay/calendar/timezone_picker.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// Width of the whole column. Fixed rather than fractional: the overlay panel
/// is 800 wide at its smallest, and the month grid beside this has to stay
/// usable at that size.
///
/// Wider than it was, because the column now carries the timers section under
/// the world clocks: a duration field, two buttons and an entry's three
/// controls all have to fit across it, and at 220 they did not.
const double kClockColumnWidth = 280;

/// The dial at full size. Shrinks on a short surface — see the [LayoutBuilder]
/// in [_CalendarClockColumnState.build].
const double kAnalogClockSize = 128;

/// One world clock's row. Fixed, so the list can be a [ListView] with an
/// `itemExtent` — sized for the row's two lines at the readable sizes this
/// column moved to.
const double kWorldClockRowHeight = 50;

/// The local time, as a dial and a digital readout, over the user's list of
/// world clocks.
///
/// Takes its list and its callbacks as parameters and its time from a
/// [ClockSource], so a widget test drives it with a frozen clock and a handful
/// of fixed offsets and never touches `ConfigStore` or the IANA database.
class CalendarClockColumn extends StatefulWidget {
  const CalendarClockColumn({
    super.key,
    required this.active,
    required this.clocks,
    required this.onAdd,
    required this.onRemove,
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
  final ClockSource clock;

  /// What is rendered under the world clocks — the calendar's timers section.
  ///
  /// It splits the space below the dial with the clock list, half each, rather
  /// than being sized to its content: the list and the timers both grow with
  /// what the user has put in them, and an equal share is the only division
  /// that does not privilege whichever of the two was given a fixed height.
  /// Null leaves the whole of that space to the clocks, which is what the
  /// column's own widget tests pump.
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
    // **The whole column, boundaried.** A tick rewrites the dial, the readout
    // and the date, and a `RenderObject` marked needing paint dirties
    // everything up to the nearest repaint boundary — of which this surface
    // had none, so one second's worth of second hand re-recorded the entire
    // overlay picture — the month grid, both lists, the tab strip — and, the
    // GTK embedder implementing no partial repaint, rastered the whole output
    // again after it. That is a bill paid once a second underneath whatever
    // the pointer is doing.
    //
    // The boundary goes here rather than around the three readouts, and the
    // difference is not cosmetic: changing a `Text` marks needs *layout*, not
    // needs paint, and layout stops at the nearest *relayout* boundary — the
    // `Column` below, whose constraints are tight — which then marks *itself*
    // needing paint on the way out. A boundary inside that `Column` would have
    // been stepped straight over. This one is above it.
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The dial gives way rather than either list being squeezed to
          // nothing: it shrinks with the column, and on a pathologically short
          // output it goes altogether, leaving the digital readout — which says
          // the same thing in a fifth of the height. Both thresholds are lower
          // than they were, because the space below is now shared by two
          // sections instead of held by one.
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
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemExtent: kWorldClockRowHeight,
                          itemCount: widget.clocks.length,
                          itemBuilder: (_, i) {
                            final clock = widget.clocks[i];
                            return _WorldClockRow(
                              clock: clock,
                              zone: widget.clock.resolve(clock.zone, _now),
                              here: _now,
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
    required this.onRemove,
  });

  final WorldClock clock;

  /// Null when the database does not know the zone — a hand-edited or
  /// deprecated name. The row still renders, and still offers its remove
  /// button, because it is the only way the user can get rid of it.
  final ZoneTime? zone;

  /// The local wall clock, for the day-difference badge.
  final DateTime here;

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
          color: _hovered ? theme.surfaceHover : theme.controlSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
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
                        color: theme.accent,
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
