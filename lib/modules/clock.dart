import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config_reader.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/timers/timer_sound.dart';
import 'package:moonswing/timers/timer_store.dart';
import 'package:moonswing/timers/timer_widgets.dart';

/// How the bar spells the hour: `14:05` or `2:05 PM`.
enum ClockHourFormat {
  h24('24'),
  h12('12');

  const ClockHourFormat(this.slug);

  /// The `hour_format` spelling.
  final String slug;

  /// [slug]'s value, or null for anything else — an unknown spelling costs the
  /// key, never the table. An integer `12`, or `"12h"`, is taken as what a
  /// hand-edited file almost certainly meant.
  static ClockHourFormat? parse(Object? raw) {
    final spelling = switch (raw) {
      String s => s.trim().toLowerCase().replaceAll('h', ''),
      int i => '$i',
      _ => null,
    };
    for (final format in values) {
      if (format.slug == spelling) return format;
    }
    return null;
  }
}

class ClockConfig {
  const ClockConfig({
    this.showWeekday = false,
    this.showDate = true,
    this.showYear = false,
    this.showWeekNumber = false,
    this.showTime = true,
    this.showSeconds = false,
    this.hourFormat = ClockHourFormat.h24,
    this.timerSound = kDefaultTimerSound,
    this.timerVolume = kDefaultTimerVolume,
  });

  /// The day's name, `Mon`.
  final bool showWeekday;

  /// The month and the day of the month, `Nov 2`.
  final bool showDate;

  /// `2026`. A part of its own rather than a longer date, so it can be shown
  /// with the date switched off.
  final bool showYear;

  /// The ISO 8601 week of the year, `W45`.
  final bool showWeekNumber;

  /// The hour and minute.
  final bool showTime;

  /// Seconds on the time. Means nothing while [showTime] is off.
  final bool showSeconds;

  final ClockHourFormat hourFormat;

  /// Whether the readout changes every second rather than every minute.
  bool get showsSeconds => showTime && showSeconds;

  /// Whether every part is switched off — the bar then draws a clock glyph in
  /// their place, because this button is how the overview is opened and an
  /// empty one would be a dead strip nobody could find to click.
  bool get showsNothing =>
      !showWeekday && !showDate && !showYear && !showWeekNumber && !showTime;

  /// What a finished countdown rings: a shipped alarm's slug, a path, a
  /// sound-theme name, or `none`. See `lib/timers/timer_sound.dart`.
  ///
  /// A `[modules.clock]` key because the clock is where the shell's timers
  /// live — the bar readout hangs off this module and the composer that starts
  /// a timer is in the calendar page behind it. It is read off the *config*
  /// rather than off the module being in a panel, for `[modules.screenshot]`'s
  /// reason: a countdown started from the calendar page finishes whether or not
  /// the monitor it finishes on is carrying a clock.
  final String timerSound;

  /// 0 to 1. Clamped rather than trusted: this key is hand-edited, and a volume
  /// of 40 handed to mpv is a different kind of surprise.
  final double timerVolume;

  /// What the sound layer reads off this.
  TimerSoundConfig get timerSoundConfig =>
      TimerSoundConfig(sound: timerSound, volume: timerVolume);

  factory ClockConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ClockConfig();
    const defaults = ClockConfig();
    return ClockConfig(
      showWeekday: map.boolOr('show_weekday', defaults.showWeekday),
      showDate: map.boolOr('show_date', defaults.showDate),
      showYear: map.boolOr('show_year', defaults.showYear),
      showWeekNumber: map.boolOr('show_week_number', defaults.showWeekNumber),
      showTime: map.boolOr('show_time', defaults.showTime),
      showSeconds: map.boolOr('show_seconds', defaults.showSeconds),
      hourFormat:
          ClockHourFormat.parse(map['hour_format']) ?? defaults.hourFormat,
      timerSound: map.stringOr('timer_sound', defaults.timerSound),
      timerVolume: map.doubleOr('timer_volume', defaults.timerVolume,
          min: 0.0, max: 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClockConfig &&
          other.showWeekday == showWeekday &&
          other.showDate == showDate &&
          other.showYear == showYear &&
          other.showWeekNumber == showWeekNumber &&
          other.showTime == showTime &&
          other.showSeconds == showSeconds &&
          other.hourFormat == hourFormat &&
          other.timerSound == timerSound &&
          other.timerVolume == timerVolume;

  @override
  int get hashCode => Object.hash(
        showWeekday,
        showDate,
        showYear,
        showWeekNumber,
        showTime,
        showSeconds,
        hourFormat,
        timerSound,
        timerVolume,
      );
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The ISO 8601 week [date] falls in: weeks start on Monday, and week 1 is the
/// one holding the year's first Thursday — so 1 January can be in week 52 or
/// 53 of the year before, and 31 December in week 1 of the next.
///
/// Counted on UTC midnights, so a daylight-saving change inside the span
/// cannot make a day 23 hours long and drop it from the division.
int isoWeekNumber(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final firstOfYear = DateTime.utc(thursday.year);
  return thursday.difference(firstOfYear).inDays ~/ 7 + 1;
}

/// What the bar shows for [now] under [config], one string per part, in the
/// order they are drawn: weekday, date, year, week, time. Empty when every part
/// is off.
///
/// Pure, and what the widget compares between ticks — a tick that would draw
/// the same strings rebuilds nothing.
List<String> clockParts(ClockConfig config, DateTime now) => [
      if (config.showWeekday) _weekdays[now.weekday - 1],
      if (config.showDate) '${_months[now.month - 1]} ${now.day}',
      if (config.showYear) '${now.year}',
      if (config.showWeekNumber) 'W${_two(isoWeekNumber(now))}',
      if (config.showTime) _formatTime(config, now),
    ];

String _two(int n) => n.toString().padLeft(2, '0');

String _formatTime(ClockConfig config, DateTime now) {
  final seconds = config.showSeconds ? ':${_two(now.second)}' : '';
  switch (config.hourFormat) {
    case ClockHourFormat.h24:
      return '${_two(now.hour)}:${_two(now.minute)}$seconds';
    case ClockHourFormat.h12:
      final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final meridiem = now.hour < 12 ? 'AM' : 'PM';
      return '$hour:${_two(now.minute)}$seconds $meridiem';
  }
}

class Clock extends StatefulWidget {
  const Clock({
    super.key,
    required this.config,
    this.timers,
    this.overview,
  });

  final ClockConfig config;

  /// What a click on the date and time pokes. Defaults to the singleton the
  /// root listens to; a widget test passes its own.
  final SettingsController? overview;

  /// Where the running timers and stopwatches come from, defaulting to the
  /// singleton. Injected by widget tests, which drive a store with no ticker
  /// behind it — a pending [Timer] fails the binding's end-of-test invariants.
  final TimersStore? timers;

  @override
  ClockState createState() => ClockState();
}

// ignore: library_private_types_in_public_api
class ClockState extends State<Clock> with PopupHost<Clock> {
  late List<String> _parts;
  Timer? _timer;
  bool _hovered = false;

  TimersStore get _timers => widget.timers ?? TimersStore.instance;

  @override
  void initState() {
    super.initState();
    _parts = clockParts(widget.config, DateTime.now());
    _scheduleNextTick();
    _timers.addListener(_onTimersChanged);
  }

  /// The last timer being stopped takes the readout out of the bar, so the
  /// popup hanging off it has to go too — otherwise it sits there anchored to
  /// a button that no longer exists, with nothing in it.
  void _onTimersChanged() {
    if (isPopupOpen && _timers.isEmpty) closePopup();
  }

  void _toggleTimersPopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    openBarPopup(
      context,
      // Width pinned, height hugging its rows: this card rebuilds while it is
      // open, so a content-*width* one would walk away from its button as the
      // digits changed. Starting a timer is only possible from the calendar
      // overlay, which dismisses this popup on its way up, so rows can leave the
      // card while it is open but never arrive.
      preferredConstraints: const BoxConstraints(
        minWidth: kTimersPopupWidth,
        maxWidth: kTimersPopupWidth,
        maxHeight: 320,
      ),
      child: ThemeProvider(
        child: TimersPopupContent(store: widget.timers),
      ),
    );
  }

  @override
  void didUpdateWidget(Clock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A `[modules.clock]` edit lands here as a new config; the parts are
    // re-read at once rather than at the next tick, or switching the date on
    // would wait up to a second to show it.
    if (oldWidget.config != widget.config) {
      _parts = clockParts(widget.config, DateTime.now());
    }
  }

  // Ticks on the second even with seconds hidden, and rebuilds only when the
  // readout changed. A once-a-minute timer would be fewer wake-ups, but timers
  // run on the monotonic clock, which stops across a suspend: after a resume
  // the bar's one clock would show the time it went to sleep at for up to a
  // minute.
  void _scheduleNextTick() {
    final now = DateTime.now();
    final msUntilNextSecond = 1000 - now.millisecond;
    _timer = Timer(Duration(milliseconds: msUntilNextSecond), () {
      _updateTime();
      _scheduleNextTick();
    });
  }

  void _updateTime() {
    if (!mounted) return;
    final parts = clockParts(widget.config, DateTime.now());
    if (listEquals(parts, _parts)) return;
    setState(() => _parts = parts);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timers.removeListener(_onTimersChanged);
    closePopup();
    super.dispose();
  }

  /// The overview, on its calendar, on this bar's output. The root owns the
  /// window — the clock used to host one of its own, which made it a second
  /// overview beside the one the todo and keyboard buttons open, and tied the
  /// panel's lifetime to this widget's.
  void _toggleOverview(BuildContext context) {
    (widget.overview ?? SettingsController.instance).toggle(
      OverviewTab.calendar,
      output: DisplayScope.of(context)?.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final style = TextStyle(fontSize: 16, color: theme.foreground);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Only the date and time open the overlay. The timers readout beside
        // them is its own gesture region, or stopping a timer from the bar
        // would mean opening the calendar first.
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _toggleOverview(context),
            child: Container(
              decoration: BoxDecoration(
                color: _hovered ? theme.surfaceHover : null,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: BarFill(
                child: _parts.isEmpty
                    ? ShellIcon(
                        ShellGlyph.clock,
                        size: 14,
                        color: theme.foreground,
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _parts.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Text(_parts[i], style: style),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
        // Renders itself away when nothing is running, separator included.
        TimerBarIndicator(
          store: widget.timers,
          active: isPopupOpen,
          onTap: _toggleTimersPopup,
        ),
      ],
    );
  }
}

final Module clockModule = Module.simple(
  configKey: 'clock',
  fromMap: (map) {
    final config = ClockConfig.fromMap(map);
    // A side effect in `fromMap`, the shape `screenshot.dart` has and for its
    // reason: the store is where the alarm reads its settings, and a countdown
    // finishes whether or not any panel on any monitor carries this module.
    // `Module.simple`'s signature guard stops this re-running per keystroke,
    // and pushing from here rather than from `TimersStore` resolves a spelling
    // once per edit rather than once per timer.
    TimerSoundStore.instance.configure(config.timerSoundConfig);
    return config;
  },
  builder: (context, config) => Clock(config: config),
);
