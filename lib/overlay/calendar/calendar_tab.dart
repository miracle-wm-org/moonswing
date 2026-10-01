// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/accounts_scope.dart';
import 'package:moonswing/accounts/calendar_event_source.dart';
import 'package:moonswing/app_info.dart';
import 'package:moonswing/caldav/caldav_calendar_store.dart';
import 'package:moonswing/clock/minute_clock_store.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/calendar/calendar_events.dart';
import 'package:moonswing/overlay/calendar/clock_column.dart';
import 'package:moonswing/overlay/calendar/event_details.dart';
import 'package:moonswing/overlay/calendar/event_layout.dart';
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
/// holds a [GoogleCalendarStore] lease on the span on screen — and likewise a
/// [CalDavCalendarStore] lease when a CalDAV account is signed in with a
/// calendar chosen under `[caldav]` — and draws the events of both *on* the
/// calendar, through one [MergedCalendarEvents]: bars in each day of the
/// month, and a Week and a Day view where a timed event is a box as long as
/// the meeting. Clicking one opens its details. The leases exist only while the
/// tab is [active], so a closed overlay fetches nothing.
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
    this.caldav,
    this.showCalDavEvents,
    this.openUrl,
    this.minuteClock,
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

  /// Where the events come from, or null for the [AccountsScope]'s. Injected
  /// by tests.
  final GoogleCalendarStore? google;

  /// Whether to show the account's events, or null to read
  /// `[google] show_in_calendar` from [ConfigStore].
  final bool? showGoogleEvents;

  /// Where the CalDAV calendars' events come from, or null for the
  /// [AccountsScope]'s. Injected by tests.
  final CalDavCalendarStore? caldav;

  /// Whether to show the CalDAV calendars' events, or null to read
  /// `[caldav]` from the store's configuration.
  final bool? showCalDavEvents;

  /// Opens an event's page or join link, or null for the default browser.
  final bool Function(String url)? openUrl;

  /// Where the week and day views' line marking now reads the time, or null
  /// for the shell's. Injected by tests.
  final MinuteClockStore? minuteClock;

  @override
  _CalendarTabState createState() => _CalendarTabState();
}

/// How much of the calendar is on screen at once.
enum CalendarView { month, week, day }

class _CalendarTabState extends State<CalendarTab> {
  late DateTime _visibleMonth;
  late DateTime _selectedDay;
  CalendarView _view = CalendarView.month;

  late final GoogleCalendarStore _google =
      widget.google ?? AccountsScope.googleCalendarOf(context);
  late final CalDavCalendarStore _caldav =
      widget.caldav ?? AccountsScope.caldavCalendarOf(context);
  GoogleCalendarLease? _lease;
  CalDavCalendarLease? _caldavLease;

  /// What either source's visibility hangs on besides the config: the Google
  /// accounts and the CalDAV ones. Never the stores themselves, whose every
  /// fetch would rebuild the whole tab; the views below listen to those.
  late final Listenable _sources = Listenable.merge([
    _google.account,
    _caldav.accounts,
  ]);

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _selectedDay = dayKey(today);
    _visibleMonth = DateTime(today.year, today.month, 1);
    _sources.addListener(_syncLease);
    _syncLease();
  }

  @override
  void didUpdateWidget(CalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLease();
  }

  @override
  void dispose() {
    _sources.removeListener(_syncLease);
    _lease?.release();
    _lease = null;
    _caldavLease?.release();
    _caldavLease = null;
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

  /// Whether Google's events are on screen.
  bool get _googleVisible => _showEvents && _google.account.signedIn;

  /// Whether the CalDAV calendars' events are on screen.
  bool get _caldavVisible {
    final injected = widget.showCalDavEvents;
    if (injected != null) return injected && _caldav.accounts.signedIn;
    if (_injected) return false;
    return _caldav.active;
  }

  /// The sources on screen, as one, or null when there are none. Equal to the
  /// last while the same sources are, so the views keep their subscriptions.
  CalendarEventSource? get _events {
    final sources = <CalendarEventSource>[
      if (_googleVisible) _google,
      if (_caldavVisible) _caldav,
    ];
    return sources.isEmpty ? null : MergedCalendarEvents(sources);
  }

  /// Takes, moves or drops the leases on the span on screen. For the month it
  /// is the grid's, leading and trailing days included, since those carry
  /// bars too. For a week or a day it is that week *and* its month's grid, so
  /// stepping through the days of a month fetches nothing new.
  void _syncLease() {
    final google = widget.active && _googleVisible;
    final caldav = widget.active && _caldavVisible;
    if (!google) {
      _lease?.release();
      _lease = null;
    }
    if (!caldav) {
      _caldavLease?.release();
      _caldavLease = null;
    }
    if (!google && !caldav) return;
    final grid = buildMonthGrid(
      _visibleMonth.year,
      _visibleMonth.month,
      weekStart: _weekStart,
    );
    var from = grid.days.first;
    var last = grid.days.last;
    if (_view != CalendarView.month) {
      final week = weekOf(_selectedDay, _weekStart);
      if (week.first.isBefore(from)) from = week.first;
      if (week.last.isAfter(last)) last = week.last;
    }
    final to = DateTime(last.year, last.month, last.day + 1);
    if (google) {
      final lease = _lease;
      if (lease == null) {
        _lease = _google.acquire(from, to);
      } else {
        lease.update(from, to);
      }
    }
    if (caldav) {
      final lease = _caldavLease;
      if (lease == null) {
        _caldavLease = _caldav.acquire(from, to);
      } else {
        lease.update(from, to);
      }
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

  void _goToToday() => _goToDay(DateTime.now());

  /// Selects [day] and brings its month along, staying in the current view.
  void _goToDay(DateTime day, {CalendarView? view}) {
    setState(() {
      _selectedDay = dayKey(day);
      _visibleMonth = DateTime(day.year, day.month, 1);
      if (view != null) _view = view;
    });
    _syncLease();
  }

  /// The chevrons: a month, a week or a day at a time.
  void _step(int delta) {
    switch (_view) {
      case CalendarView.month:
        _goToMonth(addMonths(_visibleMonth, delta));
      case CalendarView.week:
        _goToDay(
          DateTime(
            _selectedDay.year,
            _selectedDay.month,
            _selectedDay.day + 7 * delta,
          ),
        );
      case CalendarView.day:
        _goToDay(
          DateTime(
            _selectedDay.year,
            _selectedDay.month,
            _selectedDay.day + delta,
          ),
        );
    }
  }

  void _setView(CalendarView view) {
    if (view == _view) return;
    // Leaving the month for a week or a day lands on the selected day, and
    // coming back shows the month it is in.
    _goToDay(_selectedDay, view: view);
  }

  void _openEvent(BuildContext context, GoogleEvent event) {
    final events = _events;
    if (events == null) return;
    unawaited(
      showEventDetails(
        context,
        event: event,
        store: events,
        openUrl: widget.openUrl ?? openUriWithDefault,
      ),
    );
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
    final source = _events;
    final events = source != null;
    // A week or a day of nothing is a blank page: without events on screen
    // there is only the month.
    final view = events ? _view : CalendarView.month;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The month keeps the whole of its side now that the timers have moved
        // under the clocks, so the grid's six rows are as tall as the tab is.
        Expanded(
          child: _CalendarPane(
            view: view,
            visibleMonth: _visibleMonth,
            selectedDay: _selectedDay,
            weekStart: _weekStart,
            onStep: _step,
            onDaySelected: (day) => setState(() => _selectedDay = day),
            onToday: _goToToday,
            onView: _setView,
            onOpenDay: (day) => _goToDay(day, view: CalendarView.day),
            onEvent: (event) => _openEvent(context, event),
            events: source,
            minuteClock: widget.minuteClock,
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
        listenable: _sources,
        builder: (context, _) => _buildPane(context),
      );
    }

    // Changing "Week starts on" in the settings tab must re-lay the grid while
    // the overlay stays open, and an added clock must appear on the same frame,
    // so this listens rather than snapshotting.
    return ListenableBuilder(
      listenable: Listenable.merge([ConfigStore.instance, _sources]),
      builder: (context, _) => _buildPane(context),
    );
  }
}

// ---------------------------------------------------------------------------
// The calendar: a header, then the month grid or the time grid
// ---------------------------------------------------------------------------

class _CalendarPane extends StatelessWidget {
  const _CalendarPane({
    required this.view,
    required this.visibleMonth,
    required this.selectedDay,
    required this.weekStart,
    required this.onStep,
    required this.onDaySelected,
    required this.onToday,
    required this.onView,
    required this.onOpenDay,
    required this.onEvent,
    required this.events,
    required this.minuteClock,
  });

  final CalendarView view;
  final DateTime visibleMonth;
  final DateTime selectedDay;
  final int weekStart;
  final ValueChanged<int> onStep;
  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onToday;
  final ValueChanged<CalendarView> onView;
  final ValueChanged<DateTime> onOpenDay;
  final EventTap onEvent;

  /// The accounts' events, or null when they are not shown.
  final CalendarEventSource? events;

  final MinuteClockStore? minuteClock;

  String get _title => switch (view) {
    CalendarView.month =>
      '${monthNames[visibleMonth.month - 1]} ${visibleMonth.year}',
    CalendarView.week => weekRangeLabel(weekOf(selectedDay, weekStart)),
    CalendarView.day =>
      '${weekdayNames[selectedDay.weekday % 7].substring(0, 3)} '
          '${selectedDay.day} ${monthAbbrev[selectedDay.month - 1]} '
          '${selectedDay.year}',
  };

  @override
  Widget build(BuildContext context) {
    final events = this.events;
    final Widget body = switch (view) {
      CalendarView.month => _MonthGrid(
        visibleMonth: visibleMonth,
        selectedDay: selectedDay,
        weekStart: weekStart,
        onDaySelected: onDaySelected,
        onOpenDay: onOpenDay,
        onEvent: onEvent,
        events: events,
      ),
      CalendarView.week => CalendarTimeGrid(
        // Keyed on the view, so each keeps its own scroll position and the
        // week and the day are not one grid re-laid.
        key: const ValueKey('week'),
        store: events!,
        days: weekOf(selectedDay, weekStart),
        onEvent: onEvent,
        onDay: onOpenDay,
        clock: minuteClock,
      ),
      CalendarView.day => CalendarTimeGrid(
        key: const ValueKey('day'),
        store: events!,
        days: [selectedDay],
        onEvent: onEvent,
        clock: minuteClock,
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CalendarHeader(
            title: _title,
            view: events == null ? null : view,
            events: events,
            onPrevious: () => onStep(-1),
            onNext: () => onStep(1),
            onToday: onToday,
            onView: onView,
          ),
          if (events != null) _EventsError(store: events),
          const SizedBox(height: 12),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.selectedDay,
    required this.weekStart,
    required this.onDaySelected,
    required this.onOpenDay,
    required this.onEvent,
    required this.events,
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final int weekStart;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<DateTime> onOpenDay;
  final EventTap onEvent;
  final CalendarEventSource? events;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final grid = buildMonthGrid(
      visibleMonth.year,
      visibleMonth.month,
      weekStart: weekStart,
    );
    final today = dayKey(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    events == null
                        ? weekdayInitials[(weekStart + i) % 7]
                        : weekdayNames[(weekStart + i) % 7]
                              .substring(0, 3)
                              .toUpperCase(),
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                onOpenDay: onOpenDay,
                                onEvent: onEvent,
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
      ],
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.title,
    required this.view,
    required this.events,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onView,
  });

  final String title;

  /// Null when there is no choice of view: no events, so only the month.
  final CalendarView? view;
  final CalendarEventSource? events;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<CalendarView> onView;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final view = this.view;
    final events = this.events;
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.heading,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (events != null)
          // Only while nothing is on screen yet: a refresh behind events
          // already shown is not worth a spinner.
          StoreSelector<bool>(
            listenable: events,
            selector: () => events.loading,
            builder: (context, loading) => loading
                ? const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: LoadingIndicator(size: 14),
                  )
                : const SizedBox.shrink(),
          ),
        const Spacer(),
        if (view != null) ...[
          const SizedBox(width: 12),
          SettingsSegmented(
            options: [for (final v in CalendarView.values) v.name],
            value: view.name,
            onChanged: (name) => onView(CalendarView.values.byName(name)),
          ),
          const SizedBox(width: 12),
        ],
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

/// Why calendars could not be read, with a retry. The last good events stay
/// on screen underneath.
class _EventsError extends StatelessWidget {
  const _EventsError({required this.store});

  final CalendarEventSource store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return StoreSelector<String>(
      listenable: store,
      selector: () => store.error,
      builder: (context, error) {
        if (error.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.triangleExclamation,
                size: 11,
                color: kErrorColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SettingsActionButton(
                label: 'Retry',
                compact: true,
                onTap: store.refresh,
              ),
            ],
          ),
        );
      },
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
    required this.onOpenDay,
    required this.onEvent,
    this.events,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<DateTime> onOpenDay;
  final EventTap onEvent;

  /// Where the event bars read from, or null for a plain day number.
  final CalendarEventSource? events;

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
    // With events, the number moves to the top of the cell and the day's bars
    // fill the rest; each bar is its own tap target over the cell's.
    final label = events == null
        ? Center(child: number)
        : Padding(
            padding: const EdgeInsets.fromLTRB(3, 2, 3, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 20, child: Center(child: number)),
                Expanded(
                  child: MonthDayEvents(
                    store: events,
                    day: day,
                    onEvent: onEvent,
                    onMore: onOpenDay,
                  ),
                ),
              ],
            ),
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
            // A full accent fill would sit under the bars' own colours, so a
            // cell with events is tinted instead.
            background = events == null
                ? theme.accent
                : theme.accent.withValues(alpha: hovered ? 0.4 : 0.28);
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
