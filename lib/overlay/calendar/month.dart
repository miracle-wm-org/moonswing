/// Calendar month math.
///
/// Hand-rolled rather than pulling in `intl`: the shell only ever needs English
/// month names and a day grid, and `intl` would add a heavy dependency for it.
library;

const List<String> monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> monthAbbrev = [
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

/// Single-letter weekday headers, indexed by [DateTime.weekday] % 7 — so index
/// 0 is Sunday, matching [buildMonthGrid]'s default week start.
const List<String> weekdayInitials = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// Full weekday names, indexed the same way as [weekdayInitials].
const List<String> weekdayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/// Number of days in [month] (1..12) of [year].
///
/// Day 0 of the following month is the last day of this one, so leap years fall
/// out of DateTime's own normalization.
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// The first of the month [delta] months away from [d].
///
/// Always returns day 1, so stepping forward from Jan 31 lands on Feb 1 rather
/// than overflowing into March.
DateTime addMonths(DateTime d, int delta) => DateTime(d.year, d.month + delta, 1);

/// Local midnight on the same day as [d].
DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole calendar days between two wall clocks: +1 when [there] is already
/// tomorrow relative to [here], -1 when it is still yesterday.
///
/// Both sides are re-expressed as UTC midnights before subtracting. Differencing
/// the two dates as-is would measure elapsed *time*, and `inDays` truncates —
/// so a 23-hour or 25-hour DST day reports 0 and the badge silently disappears
/// on the two days of the year it is most likely to be wrong about.
int dayDelta(DateTime there, DateTime here) =>
    DateTime.utc(there.year, there.month, there.day)
        .difference(DateTime.utc(here.year, here.month, here.day))
        .inDays;

/// A fixed 6x7 block of days covering one month plus the leading and trailing
/// days needed to fill whole weeks.
///
/// Always exactly 42 cells, even when the month only spans five weeks, so the
/// grid never changes height as the user pages between months.
class MonthGrid {
  const MonthGrid({
    required this.year,
    required this.month,
    required this.days,
    required this.leading,
  });

  final int year;

  /// 1..12.
  final int month;

  /// Exactly 42 local-midnight days, in order.
  final List<DateTime> days;

  /// How many cells at the start belong to the previous month.
  final int leading;

  /// Whether the cell at [index] falls inside [month] rather than in the
  /// spill-over from the neighbouring months.
  bool isInMonth(int index) =>
      index >= leading && index < leading + daysInMonth(year, month);
}

/// Builds the grid for [year]/[month].
///
/// [weekStart] is a [DateTime] weekday constant — [DateTime.sunday] (the
/// default) or [DateTime.monday].
MonthGrid buildMonthGrid(int year, int month, {int weekStart = DateTime.sunday}) {
  final first = DateTime(year, month, 1);

  // DateTime.weekday runs Monday(1)..Sunday(7). Normalize both the month's
  // first weekday and the configured week start onto the same 0-based axis so
  // the offset is a plain subtraction.
  final firstIndex = first.weekday % 7;
  final startIndex = weekStart % 7;
  final leading = (firstIndex - startIndex + 7) % 7;

  final days = <DateTime>[
    // Days are built with explicit DateTime(y, m, n) arithmetic rather than
    // repeated add(Duration(days: 1)): a duration add shifts by exactly 24h and
    // so duplicates or skips a day across a DST boundary.
    for (var i = 0; i < 42; i++) DateTime(year, month, i - leading + 1),
  ];

  return MonthGrid(year: year, month: month, days: days, leading: leading);
}
