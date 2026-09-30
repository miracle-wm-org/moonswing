// The Calendar tab's account half: the events drawn *on* the calendar.
//
// Three views read `CalendarEventSource` and nothing else — the month grid's
// bars (one per event, as many as the cell has room for and a "+N more"), and
// the week and day views' time grid, where a timed event is a box as tall as
// it is long and events that overlap share the column. Clicking any of them
// opens its details (`event_details.dart`).
//
// The tab owns the lease (the span on screen), so nothing here causes a
// request. A month cell subscribes *per cell* on a signature of its own day,
// so a refresh that moved one day's events rebuilds that day and none of the
// other forty-one cells; the time grid rebuilds as one, since a week is seven
// columns that are all on screen at once and a refresh is minutes apart.

import 'package:flutter/widgets.dart';

import 'package:moonswing/clock/minute_clock_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/accounts/calendar_event_source.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/calendar/event_layout.dart';
import 'package:moonswing/overlay/calendar/month.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';

/// The height of one event bar in a month cell, gap included.
const double kMonthBarExtent = 17;

/// The height of an hour in the week and day views.
const double kHourExtent = 44;

/// The width of the hour labels down the left of the time grid.
const double kTimeGutterWidth = 48;

/// What to do when an event is clicked: open its details.
typedef EventTap = void Function(GoogleEvent event);

/// The colour [event] is drawn in: its own, else its calendar's, else the
/// theme's accent.
Color eventColor(CalendarEventSource store, GoogleEvent event, ThemeConfig t) {
  final hex = store.colorOf(event);
  return (hex == null ? null : parseHexColor(hex)) ?? t.accent;
}

/// Readable text on a filled [background]: white on anything but a light
/// colour, the way Google draws a banner.
Color textOn(Color background) =>
    background.computeLuminance() > 0.5 ? const Color(0xFF1F1F1F) : kOnAccent;

/// A signature of what [day]'s cell draws, so a cell rebuilds only when its
/// own events moved.
String _daySignature(CalendarEventSource store, DateTime day) {
  final buffer = StringBuffer();
  for (final e in store.eventsOn(day)) {
    buffer
      ..write(e.key)
      ..write(e.hashCode)
      ..write(store.colorOf(e))
      ..write('|');
  }
  return buffer.toString();
}

/// One event as a bar: a filled banner for an all-day (or day-spanning) event,
/// a coloured dot, start time and title for a timed one.
class EventBar extends StatelessWidget {
  const EventBar({
    super.key,
    required this.event,
    required this.day,
    required this.color,
    required this.onTap,
    this.height = kMonthBarExtent - 2,
  });

  final GoogleEvent event;
  final DateTime day;
  final Color color;
  final EventTap onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final banner = !isTimedForGrid(event);
    final startsToday = !event.start.isBefore(dayKey(day));
    final style = TextStyle(
      fontSize: ShellFontSizes.caption,
      fontFamily: theme.fontFamily,
      height: 1.1,
      color: banner ? textOn(color) : theme.popupForeground,
    );
    // Built outside the hover builder: a hover repaints a decoration, and
    // does not re-shape a paragraph.
    final label = Row(
      children: [
        if (!banner) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            banner || !startsToday
                ? event.summary
                : '${clockLabel(event.start)} ${event.summary}',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
    return RepaintBoundary(
      child: HoverRegion(
        onTap: () => onTap(event),
        builder: (context, hovered) {
          final Color background;
          if (banner) {
            background = hovered ? color.withValues(alpha: 0.8) : color;
          } else {
            background = hovered
                ? theme.surfaceHover
                : color.withValues(alpha: 0.14);
          }
          return Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(3),
            ),
            child: label,
          );
        },
      ),
    );
  }
}

/// The bars under a month cell's day number: as many as fit, then "+N more",
/// which opens the day.
class MonthDayEvents extends StatelessWidget {
  const MonthDayEvents({
    super.key,
    required this.store,
    required this.day,
    required this.onEvent,
    required this.onMore,
  });

  final CalendarEventSource store;
  final DateTime day;
  final EventTap onEvent;
  final ValueChanged<DateTime> onMore;

  @override
  Widget build(BuildContext context) => StoreSelector<String>(
    listenable: store,
    selector: () => _daySignature(store, day),
    builder: (context, _) {
      final events = store.eventsOn(day);
      if (events.isEmpty) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) {
          final theme = ThemeScope.of(context);
          final room = (constraints.maxHeight / kMonthBarExtent).floor();
          if (room <= 0) return const SizedBox.shrink();
          final fits = events.length <= room;
          final shown = fits ? events.length : room - 1;
          final hidden = events.length - shown;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in events.take(shown))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: EventBar(
                    event: e,
                    day: day,
                    color: eventColor(store, e, theme),
                    onTap: onEvent,
                  ),
                ),
              if (hidden > 0) _MoreBar(count: hidden, onTap: () => onMore(day)),
            ],
          );
        },
      );
    },
  );
}

class _MoreBar extends StatelessWidget {
  const _MoreBar({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final text = Text(
      '+$count more',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: TextStyle(
        fontSize: ShellFontSizes.caption,
        fontFamily: theme.fontFamily,
        height: 1.1,
        color: theme.popupForeground.withValues(alpha: 0.75),
        fontWeight: FontWeight.w600,
      ),
    );
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          height: kMonthBarExtent - 2,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : const Color(0x00000000),
            borderRadius: BorderRadius.circular(3),
          ),
          child: text,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The week and day views
// ---------------------------------------------------------------------------

/// A time grid over [days]: a header naming each day, a strip of all-day
/// banners, and the hours with each timed event as a box.
///
/// Scrolled to the working day on first build (to an hour before now when
/// [days] holds today), since midnight to seven is empty for nearly everyone.
class CalendarTimeGrid extends StatefulWidget {
  const CalendarTimeGrid({
    super.key,
    required this.store,
    required this.days,
    required this.onEvent,
    this.onDay,
    this.clock,
  });

  final CalendarEventSource store;
  final List<DateTime> days;
  final EventTap onEvent;

  /// Opens a day on its own, from the week's header. Null in the day view.
  final ValueChanged<DateTime>? onDay;

  /// Where the line marking now reads the time, or null for the shell's.
  final MinuteClockStore? clock;

  @override
  State<CalendarTimeGrid> createState() => _CalendarTimeGridState();
}

class _CalendarTimeGridState extends State<CalendarTimeGrid> {
  late final MinuteClockStore _clock =
      widget.clock ?? MinuteClockStore.instance;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _clock.acquire();
    final now = _clock.now;
    final hour = widget.days.any((d) => isSameDay(d, now))
        ? (now.hour - 1).clamp(0, 16)
        : 7;
    _scroll = ScrollController(initialScrollOffset: hour * kHourExtent);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _clock.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final byDay = [for (final d in widget.days) store.eventsOn(d)];
        final banners = [
          for (final events in byDay) events.where((e) => !isTimedForGrid(e)),
        ];
        final hasBanners = banners.any((b) => b.isNotEmpty);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DayHeaders(
              days: widget.days,
              today: _clock.now,
              onDay: widget.onDay,
            ),
            if (hasBanners)
              _BannerStrip(
                store: store,
                days: widget.days,
                banners: [for (final b in banners) b.toList()],
                onEvent: widget.onEvent,
                onDay: widget.onDay,
              ),
            Container(height: 1, color: theme.divider),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(
                  height: kHourExtent * 24,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _HourGutter(),
                      for (var i = 0; i < widget.days.length; i++)
                        Expanded(
                          child: _DayColumn(
                            store: store,
                            day: widget.days[i],
                            placed: layoutDay(
                              byDay[i].where(isTimedForGrid).toList(),
                              widget.days[i],
                            ),
                            clock: _clock,
                            onEvent: widget.onEvent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DayHeaders extends StatelessWidget {
  const _DayHeaders({required this.days, required this.today, this.onDay});

  final List<DateTime> days;
  final DateTime today;
  final ValueChanged<DateTime>? onDay;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const SizedBox(width: kTimeGutterWidth),
          for (final d in days)
            Expanded(
              child: _DayHeader(
                day: d,
                isToday: isSameDay(d, today),
                theme: theme,
                onTap: onDay == null ? null : () => onDay!(d),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.isToday,
    required this.theme,
    this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final ThemeConfig theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = Text(
      weekdayNames[day.weekday % 7].substring(0, 3).toUpperCase(),
      style: TextStyle(
        fontSize: ShellFontSizes.caption,
        fontFamily: theme.fontFamily,
        letterSpacing: 0.5,
        fontWeight: FontWeight.w600,
        color: isToday
            ? theme.accentText
            : theme.popupForeground.withValues(alpha: 0.6),
      ),
    );
    final number = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: isToday
          ? BoxDecoration(color: theme.accent, shape: BoxShape.circle)
          : null,
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: ShellFontSizes.title,
          fontFamily: theme.fontFamily,
          fontWeight: FontWeight.w600,
          color: isToday ? kOnAccent : theme.popupForeground,
        ),
      ),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [name, const SizedBox(height: 2), number],
    );
    if (onTap == null) return Center(child: content);
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : const Color(0x00000000),
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// The all-day row: each day's banners stacked, three at most before a
/// "+N more" that opens the day.
class _BannerStrip extends StatelessWidget {
  const _BannerStrip({
    required this.store,
    required this.days,
    required this.banners,
    required this.onEvent,
    this.onDay,
  });

  static const int _maxRows = 3;

  final CalendarEventSource store;
  final List<DateTime> days;
  final List<List<GoogleEvent>> banners;
  final EventTap onEvent;
  final ValueChanged<DateTime>? onDay;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // The day view has nowhere further to open, so it shows every banner.
    final limit = onDay == null ? 1 << 20 : _maxRows;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: kTimeGutterWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Text(
                'all day',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in banners[i].take(
                      banners[i].length > limit ? limit - 1 : limit,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: EventBar(
                          event: e,
                          day: days[i],
                          color: eventColor(store, e, theme),
                          onTap: onEvent,
                        ),
                      ),
                    if (banners[i].length > limit)
                      _MoreBar(
                        count: banners[i].length - (limit - 1),
                        onTap: () => onDay?.call(days[i]),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HourGutter extends StatelessWidget {
  const _HourGutter();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final style = TextStyle(
      fontSize: ShellFontSizes.caption,
      fontFamily: theme.fontFamily,
      color: theme.popupForeground.withValues(alpha: 0.5),
    );
    return SizedBox(
      width: kTimeGutterWidth,
      child: Stack(
        children: [
          // Midnight is the top edge and needs no label.
          for (var h = 1; h < 24; h++)
            Positioned(
              top: h * kHourExtent - 7,
              right: 8,
              child: Text('${h.toString().padLeft(2, '0')}:00', style: style),
            ),
        ],
      ),
    );
  }
}

/// One day of the time grid: the hour lines, the events, and now.
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.store,
    required this.day,
    required this.placed,
    required this.clock,
    required this.onEvent,
  });

  final CalendarEventSource store;
  final DateTime day;
  final List<PlacedEvent> placed;
  final MinuteClockStore clock;
  final EventTap onEvent;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: [
              // The lines are paint only: a `painter:` answers every hit, and
              // nothing under the events wants the pointer anyway.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _HourLines(theme.divider.withValues(alpha: 0.6)),
                  ),
                ),
              ),
              for (final p in placed)
                Positioned(
                  top: p.top / 60 * kHourExtent,
                  height: (p.bottom - p.top) / 60 * kHourExtent - 1,
                  left: width * p.column / p.columns + 1,
                  width: width / p.columns - 3,
                  child: EventBlock(
                    placed: p,
                    color: eventColor(store, p.event, theme),
                    onTap: onEvent,
                  ),
                ),
              _NowLine(clock: clock, day: day),
            ],
          );
        },
      ),
    );
  }
}

class _HourLines extends CustomPainter {
  const _HourLines(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var h = 1; h < 24; h++) {
      final y = h * kHourExtent - 0.5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_HourLines old) => old.color != color;
}

/// A timed event in the grid: a tinted box with a bar down its edge, the
/// title, and the time when there is room for it.
class EventBlock extends StatelessWidget {
  const EventBlock({
    super.key,
    required this.placed,
    required this.color,
    required this.onTap,
  });

  final PlacedEvent placed;
  final Color color;
  final EventTap onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final event = placed.event;
    final tall = (placed.bottom - placed.top) >= 40;
    final title = Text(
      event.summary,
      maxLines: tall ? 3 : 1,
      softWrap: tall,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: ShellFontSizes.caption,
        fontFamily: theme.fontFamily,
        fontWeight: FontWeight.w600,
        height: 1.15,
        color: theme.popupForeground,
      ),
    );
    final content = ClipRect(
      child: tall
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(child: title),
                Text(
                  '${clockLabel(event.start)}–${clockLabel(event.end)}',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: ShellFontSizes.caption,
                    fontFamily: theme.fontFamily,
                    height: 1.15,
                    color: theme.popupForeground.withValues(alpha: 0.7),
                  ),
                ),
              ],
            )
          : title,
    );
    return RepaintBoundary(
      child: HoverRegion(
        onTap: () => onTap(event),
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: hovered ? 0.45 : 0.3),
              theme.popupBackground,
            ),
            borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// The line across today's column at the current minute. Its own listener on
/// the minute clock, so a minute passing moves one line and repaints nothing
/// else.
class _NowLine extends StatelessWidget {
  const _NowLine({required this.clock, required this.day});

  final MinuteClockStore clock;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: clock,
      builder: (context, _) {
        final now = clock.now;
        if (!isSameDay(now, day)) return const SizedBox.shrink();
        final top = (now.hour * 60 + now.minute) / 60 * kHourExtent;
        return Positioned(
          top: top - 4,
          left: 0,
          right: 0,
          height: 8,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: kErrorColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(child: Container(height: 2, color: kErrorColor)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
