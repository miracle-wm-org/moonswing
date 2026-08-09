import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/calendar/analog_clock.dart';
import 'package:graceful_shell/overlay/calendar/month.dart';
import 'package:graceful_shell/overlay/calendar/time_zones.dart';
import 'package:graceful_shell/overlay/calendar/timezone_picker.dart';
import 'package:graceful_shell/scopes.dart';

/// Width of the whole column. Fixed rather than fractional: the overlay panel
/// is 800 wide at its smallest, and the month grid beside this has to stay
/// usable at that size.
const double kClockColumnWidth = 220;

/// The dial at full size. Shrinks on a short surface — see the [LayoutBuilder]
/// in [_CalendarClockColumnState.build].
const double kAnalogClockSize = 128;

const double kWorldClockRowHeight = 46;

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
  });

  /// Whether the calendar is the tab the user is looking at.
  ///
  /// The overlay body is an `IndexedStack`, which keeps every tab alive once
  /// built — so without this the clock would keep ticking behind the settings
  /// pane for as long as the overlay is open.
  final bool active;

  final List<WorldClock> clocks;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final ClockSource clock;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        // On a pathologically short output the dial gives way rather than the
        // list being squeezed to nothing.
        final dialSize = constraints.hasBoundedHeight
            ? (constraints.maxHeight * 0.32).clamp(64.0, kAnalogClockSize)
            : kAnalogClockSize;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: AnalogClock(time: _now, size: dialSize)),
              const SizedBox(height: 10),
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
                    fontSize: 12,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'WORLD CLOCKS',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
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
              const SizedBox(height: 4),
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
            ],
          ),
        );
      },
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
          fontSize: 12,
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
                      fontSize: 12,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.9),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    zone == null
                        ? 'Unknown time zone'
                        : formatUtcOffset(zone.offset),
                    style: TextStyle(
                      fontSize: 10,
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
                      fontSize: 15,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (delta.isNotEmpty)
                    Text(
                      delta,
                      style: TextStyle(
                        fontSize: 10,
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
/// which does not fit a 46px row that already carries two lines of text.
class _RemoveButton extends StatefulWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RemoveButton> createState() => _RemoveButtonState();
}

class _RemoveButtonState extends State<_RemoveButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: 18,
          height: 18,
          child: Center(
            child: FaIcon(
              FontAwesomeIcons.xmark,
              size: 11,
              color: _hovered
                  ? theme.accent
                  : theme.popupForeground.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
