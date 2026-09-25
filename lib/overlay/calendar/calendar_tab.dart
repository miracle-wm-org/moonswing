// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/overlay/calendar/calendar_agenda.dart';
import 'package:moonswing/overlay/calendar/clock_column.dart';
import 'package:moonswing/overlay/calendar/month.dart';
import 'package:moonswing/overlay/calendar/time_zones.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/timers/timer_store.dart';
import 'package:moonswing/timers/timer_widgets.dart';

/// The Calendar tab of the overlay: a month grid the user can page through,
/// beside a column holding the local time, the world clocks and the timers.
///
/// The timers section is `lib/timers/`'s rather than this tab's: it is given the
/// [active] flag and the store seam and nothing else, because what it starts
/// outlives the overlay and is rendered in the bar.
///
/// The grid itself is local date arithmetic. When a Google account is signed in
/// under Settings › Accounts and `[google] show_in_calendar` is on, the tab also
/// holds a [GoogleCalendarStore] lease on the month on screen: days with events
/// get a dot and the selected day's events are listed under the month. The lease
/// exists only while the tab is [active], so a closed overlay fetches nothing.
///
/// The world clocks are read from and written straight back to [ConfigStore]:
/// one consumer in one window, and adding and removing *are* the persisted
/// events.
class CalendarTab extends StatefulWidget {
  const CalendarTab({
    super.key,
    required this.active,
    this.weekStart,
    this.worldClocks,
    this.onWorldClocksChanged,
    this.clock = const SystemClockSource(),
    this.timers,
    this.google,
    this.showGoogleEvents,
    this.openUrl,
  });

  /// Whether this is the tab the user is looking at.
  ///
  /// Required, not defaulted: the overlay body is an `IndexedStack` that keeps
  /// every tab alive once built, so a call site that forgot to say would leave
  /// the clock ticking behind whatever tab the user moved to.
  final bool active;

  /// A [DateTime] weekday constant, or null to read `[calendar] week_start`
  /// from [ConfigStore]. Injected by tests so they never touch the real config.
  final int? weekStart;

  /// The world clocks to show, or null to read `[calendar] world_clocks` from
  /// [ConfigStore]. The other half of the same injection seam.
  final List<WorldClock>? worldClocks;

  /// Where an add or a remove goes, or null to write it to [ConfigStore].
  final ValueChanged<List<WorldClock>>? onWorldClocksChanged;

  /// Where the clock column gets the time and its zone conversions.
  final ClockSource clock;

  /// Where the timers strip reads its entries, or null for the singleton every
  /// other surface in the shell shares. Injected by widget tests, which drive a
  /// store with no ticker behind it.
  final TimersStore? timers;

  /// Where the events come from, or null for the singleton. Injected by tests.
  final GoogleCalendarStore? google;

  /// Whether to show the account's events, or null to read
  /// `[google] show_in_calendar` from [ConfigStore].
  final bool? showGoogleEvents;

  /// Opens an event's page or join link, or null for the default browser.
  final bool Function(String url)? openUrl;

  @override
  _CalendarTabState createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  late DateTime _visibleMonth;
  late DateTime _selectedDay;

  late final GoogleCalendarStore _google =
      widget.google ?? GoogleCalendarStore.instance;
  GoogleCalendarLease? _lease;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _selectedDay = dayKey(today);
    _visibleMonth = DateTime(today.year, today.month, 1);
    _google.account.addListener(_syncLease);
    _syncLease();
  }

  @override
  void didUpdateWidget(CalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLease();
  }

  @override
  void dispose() {
    _google.account.removeListener(_syncLease);
    _lease?.release();
    _lease = null;
    super.dispose();
  }

  /// Whether the tab's config is injected rather than read from [ConfigStore].
  bool get _injected => widget.weekStart != null && widget.worldClocks != null;

  bool get _showEvents {
    final injected = widget.showGoogleEvents;
    if (injected != null) return injected;
    // A test that injected the rest and said nothing about events gets none,
    // and never reaches the singleton config.
    if (_injected) return false;
    return ConfigStore.instance.get<bool>(['google', 'show_in_calendar']) ??
        true;
  }

  /// Whether the events half of the tab is on screen.
  bool get _eventsVisible => _showEvents && _google.account.signedIn;

  /// Takes, moves or drops the lease on the month on screen. The window is the
  /// grid's, leading and trailing days included, since those carry dots too.
  void _syncLease() {
    final wanted = widget.active && _eventsVisible;
    if (!wanted) {
      _lease?.release();
      _lease = null;
      return;
    }
    final grid = buildMonthGrid(
      _visibleMonth.year,
      _visibleMonth.month,
      weekStart: _weekStart,
    );
    final from = grid.days.first;
    final last = grid.days.last;
    final to = DateTime(last.year, last.month, last.day + 1);
    final lease = _lease;
    if (lease == null) {
      _lease = _google.acquire(from, to);
    } else {
      lease.update(from, to);
    }
  }

  int get _weekStart {
    if (widget.weekStart != null) return widget.weekStart!;
    final value = ConfigStore.instance.get<String>(['calendar', 'week_start']);
    return value?.toLowerCase() == 'monday' ? DateTime.monday : DateTime.sunday;
  }

  void _goToMonth(DateTime month) {
    setState(() => _visibleMonth = DateTime(month.year, month.month, 1));
    _syncLease();
  }

  void _goToToday() {
    final today = DateTime.now();
    setState(() {
      _selectedDay = dayKey(today);
      _visibleMonth = DateTime(today.year, today.month, 1);
    });
    _syncLease();
  }

  List<WorldClock> get _worldClocks =>
      widget.worldClocks ??
      WorldClock.parseList(
        ConfigStore.instance.get<List>(['calendar', 'world_clocks']),
      );

  /// Writes a whole new list.
  ///
  /// [ConfigStore] has no append API, and mutating the list `get` returned would
  /// neither notify nor schedule a save. The notification is synchronous, so the
  /// [ListenableBuilder] below puts the new row on screen this frame and the
  /// atomic write follows on the store's own debounce.
  void _writeWorldClocks(List<WorldClock> next) {
    final sink = widget.onWorldClocksChanged;
    if (sink != null) {
      sink(next);
      return;
    }
    ConfigStore.instance.set(
      ['calendar', 'world_clocks'],
      [for (final clock in next) clock.toMap()],
    );
  }

  void _addWorldClock(TimeZoneName zone) {
    final current = _worldClocks;
    // Adding one that is already listed is a no-op, not a duplicate row — and
    // "already listed" is by zone, so New Delhi over an existing Mumbai is the
    // same clock rather than a second one showing the same time.
    if (current.any((clock) => clock.zone == zone.name)) return;
    // The label rides along for a city the IANA database does not name: the
    // row would otherwise be titled Kolkata for a user who picked New Delhi.
    _writeWorldClocks([
      ...current,
      WorldClock(zone: zone.name, label: zone.label),
    ]);
  }

  void _removeWorldClock(String zone) {
    final current = _worldClocks;
    if (!current.any((clock) => clock.zone == zone)) return;
    _writeWorldClocks(current.where((clock) => clock.zone != zone).toList());
  }

  Widget _buildPane(BuildContext context) {
    final theme = ThemeScope.of(context);
    // The config this pane rebuilds on may have switched the events on or off,
    // or moved the week start and with it the grid's first day. The lease only
    // schedules its work, so taking it from here notifies nobody mid-build.
    _syncLease();
    final events = _eventsVisible;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The month keeps the whole of its side now that the timers have moved
        // under the clocks, so the grid's six rows are as tall as the tab is.
        Expanded(
          child: _MonthPane(
            visibleMonth: _visibleMonth,
            selectedDay: _selectedDay,
            weekStart: _weekStart,
            onMonthChanged: _goToMonth,
            onDaySelected: (day) => setState(() => _selectedDay = day),
            onToday: _goToToday,
            events: events ? _google : null,
            openUrl: widget.openUrl ?? openUriWithDefault,
          ),
        ),
        Container(width: 1, color: theme.divider),
        SizedBox(
          width: kClockColumnWidth,
          child: CalendarClockColumn(
            active: widget.active,
            clock: widget.clock,
            clocks: _worldClocks,
            onAdd: _addWorldClock,
            onRemove: _removeWorldClock,
            // Half of what is below the clocks, rather than a strip along the
            // bottom of the month: the composer is a labelled field and two
            // buttons, which reads as a column of controls beside the grid and
            // not as a band under it.
            footer: TimersPane(active: widget.active, store: widget.timers),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only subscribe when something here comes from the config: injected values
    // cannot change, and touching the singleton would throw in a widget test
    // that never called initShared(). Both seams have to be injected for that
    // to hold — a test that passes only one still reaches the store.
    if (_injected) {
      return ListenableBuilder(
        listenable: _google.account,
        builder: (context, _) => _buildPane(context),
      );
    }

    // Changing "Week starts on" in the settings tab must re-lay the grid while
    // the overlay stays open, and an added clock must appear on the same frame,
    // so this listens rather than snapshotting.
    return ListenableBuilder(
      listenable: Listenable.merge([ConfigStore.instance, _google.account]),
      builder: (context, _) => _buildPane(context),
    );
  }
}

// ---------------------------------------------------------------------------
// Month grid
// ---------------------------------------------------------------------------

class _MonthPane extends StatelessWidget {
  const _MonthPane({
    required this.visibleMonth,
    required this.selectedDay,
    required this.weekStart,
    required this.onMonthChanged,
    required this.onDaySelected,
    required this.onToday,
    required this.events,
    required this.openUrl,
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final int weekStart;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onToday;

  /// The account's events, or null when they are not shown.
  final GoogleCalendarStore? events;

  final bool Function(String url) openUrl;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final events = this.events;
    final grid = buildMonthGrid(
      visibleMonth.year,
      visibleMonth.month,
      weekStart: weekStart,
    );
    final today = dayKey(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MonthHeader(
            month: visibleMonth,
            onPrevious: () => onMonthChanged(addMonths(visibleMonth, -1)),
            onNext: () => onMonthChanged(addMonths(visibleMonth, 1)),
            onToday: onToday,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      weekdayInitials[(weekStart + i) % 7],
                      style: TextStyle(
                        fontSize: ShellFontSizes.secondary,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Column(
              children: [
                for (var week = 0; week < 6; week++)
                  Expanded(
                    child: Row(
                      children: [
                        for (var weekday = 0; weekday < 7; weekday++)
                          Builder(
                            builder: (context) {
                              final index = week * 7 + weekday;
                              final day = grid.days[index];
                              return Expanded(
                                child: _DayCell(
                                  day: day,
                                  inMonth: grid.isInMonth(index),
                                  isToday: day == today,
                                  isSelected: day == selectedDay,
                                  onTap: () => onDaySelected(day),
                                  events: events,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (events != null) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: theme.divider),
            const SizedBox(height: 8),
            CalendarAgenda(store: events, day: selectedDay, onOpen: openUrl),
          ],
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Row(
      children: [
        Text(
          '${monthNames[month.month - 1]} ${month.year}',
          style: TextStyle(
            fontSize: ShellFontSizes.heading,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        _TodayButton(onTap: onToday),
        const SizedBox(width: 4),
        SettingsIconButton(
          icon: FontAwesomeIcons.chevronLeft,
          size: 12,
          onTap: onPrevious,
        ),
        SettingsIconButton(
          icon: FontAwesomeIcons.chevronRight,
          size: 12,
          onTap: onNext,
        ),
      ],
    );
  }
}

class _TodayButton extends StatelessWidget {
  const _TodayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: hovered ? theme.surfaceHover : theme.controlSurface,
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: Text(
          'Today',
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

/// One day of the grid.
///
/// **The hover highlight is contained twice over, and both halves are what make
/// it keep up with the pointer.** Forty-two of these sit in one panel, every one
/// hovers, and a `RenderObject` marked needing paint dirties everything up to the
/// nearest repaint boundary — of which this surface had none. So crossing the
/// grid re-recorded the whole overlay picture per pointer move and, the GTK
/// embedder implementing no partial repaint, rastered the whole output again to
/// tint one 40px box.
///
/// The [RepaintBoundary] stops the mark propagating. And the label is built
/// *outside* the hover builder and handed in as a child, so the rebuild the
/// boundary contains is a decoration and not a paragraph.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
    this.events,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  /// Where the event dot reads from, or null for no dot.
  final GoogleCalendarStore? events;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    // Days spilling in from the neighbouring months stay legible but recede.
    var foreground = isSelected
        ? theme.popupForeground
        : theme.popupForeground.withValues(alpha: inMonth ? 0.9 : 0.35);
    if (isToday && !isSelected) foreground = theme.accentText;

    // Everything below here that the pointer cannot change, resolved once per
    // rebuild of the cell rather than once per pointer move.
    final number = Text(
      '${day.day}',
      style: TextStyle(
        fontSize: ShellFontSizes.label,
        fontFamily: theme.fontFamily,
        color: foreground,
        fontWeight: isToday || isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    final events = this.events;
    final label = events == null
        ? Center(child: number)
        : Stack(
            children: [
              Center(child: number),
              Positioned(
                left: 0,
                right: 0,
                bottom: 4,
                child: Center(
                  child: CalendarEventDot(
                    store: events,
                    day: day,
                    color: isSelected ? foreground : theme.accent,
                  ),
                ),
              ),
            ],
          );
    final border = isToday && !isSelected
        ? Border.all(color: theme.accent, width: 1.5)
        : null;
    final radius = BorderRadius.circular(ShellRadii.card);

    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        // The tap box is the whole cell; the 2px margin is inset painting, and
        // used to be a pointer-cursored dead ring around all forty-two of them.
        builder: (context, hovered) {
          final Color background;
          if (isSelected) {
            background = theme.accent;
          } else if (hovered) {
            background = theme.surfaceHover;
          } else {
            background = const Color(0x00000000);
          }
          return Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: background,
              borderRadius: radius,
              border: border,
            ),
            child: label,
          );
        },
      ),
    );
  }
}
