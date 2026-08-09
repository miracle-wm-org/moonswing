// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/calendar/month.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

/// The Calendar tab of the overlay: a month grid the user can page through.
///
/// There is no account integration — the grid is local date arithmetic only, so
/// the tab needs no network, no credentials and no start-up service.
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key, this.weekStart});

  /// A [DateTime] weekday constant, or null to read `[calendar] week_start`
  /// from [ConfigStore]. Injected by tests so they never touch the real config.
  final int? weekStart;

  @override
  _CalendarTabState createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  late DateTime _visibleMonth;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _selectedDay = dayKey(today);
    _visibleMonth = DateTime(today.year, today.month, 1);
  }

  int get _weekStart {
    if (widget.weekStart != null) return widget.weekStart!;
    final value = ConfigStore.instance.get<String>(['calendar', 'week_start']);
    return value?.toLowerCase() == 'monday' ? DateTime.monday : DateTime.sunday;
  }

  void _goToMonth(DateTime month) {
    setState(() => _visibleMonth = DateTime(month.year, month.month, 1));
  }

  void _goToToday() {
    final today = DateTime.now();
    setState(() {
      _selectedDay = dayKey(today);
      _visibleMonth = DateTime(today.year, today.month, 1);
    });
  }

  Widget _buildPane(BuildContext context) => _MonthPane(
        visibleMonth: _visibleMonth,
        selectedDay: _selectedDay,
        weekStart: _weekStart,
        onMonthChanged: _goToMonth,
        onDaySelected: (day) => setState(() => _selectedDay = day),
        onToday: _goToToday,
      );

  @override
  Widget build(BuildContext context) {
    // Only subscribe when the week start comes from the config: an injected one
    // cannot change, and touching the singleton would throw in a widget test
    // that never called initShared().
    if (widget.weekStart != null) return _buildPane(context);

    // Changing "Week starts on" in the settings tab must re-lay the grid while
    // the overlay stays open, so this listens rather than snapshotting.
    return ListenableBuilder(
      listenable: ConfigStore.instance,
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
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final int weekStart;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
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
                        fontSize: 11,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w600,
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
                          Builder(builder: (context) {
                            final index = week * 7 + weekday;
                            final day = grid.days[index];
                            return Expanded(
                              child: _DayCell(
                                day: day,
                                inMonth: grid.isInMonth(index),
                                isToday: day == today,
                                isSelected: day == selectedDay,
                                onTap: () => onDaySelected(day),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
              ],
            ),
          ),
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
            fontSize: 18,
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

class _TodayButton extends StatefulWidget {
  const _TodayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_TodayButton> createState() => _TodayButtonState();
}

class _TodayButtonState extends State<_TodayButton> {
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Today',
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    final Color background;
    if (widget.isSelected) {
      background = theme.accent;
    } else if (_hovered) {
      background = theme.surfaceHover;
    } else {
      background = const Color(0x00000000);
    }

    // Days spilling in from the neighbouring months stay legible but recede.
    var foreground = widget.isSelected
        ? theme.popupForeground
        : theme.popupForeground.withValues(alpha: widget.inMonth ? 0.9 : 0.35);
    if (widget.isToday && !widget.isSelected) foreground = theme.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: widget.isToday && !widget.isSelected
                ? Border.all(color: theme.accent, width: 1.5)
                : null,
          ),
          child: Center(
            child: Text(
              '${widget.day.day}',
              style: TextStyle(
                fontSize: 13,
                fontFamily: theme.fontFamily,
                color: foreground,
                fontWeight: widget.isToday || widget.isSelected
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
