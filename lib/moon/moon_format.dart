// The strings the lunar surfaces print, as pure functions.
//
// `lib/timers/timer_format.dart` beside `timer_store.dart`, for the same
// reason: a readout is the half of a feature that is trivially wrong and
// trivially testable, and putting it in the widget is what makes it neither.
//
// Deliberately not `overlay/calendar/time_zones.dart`'s `formatClockTime`,
// which is four lines of the same arithmetic: that file is the one place in the
// shell allowed to import `package:timezone`, and `lib/moon/` is a plain unit
// test with no database behind it. Nothing here formats a *zone* — every
// instant the Moon layer prints is already in the machine's local time.

/// Three-letter month names. Spelled out rather than taken from `intl`, the
/// `overlay/calendar/month.dart` and `weather_api.dart` call: twelve labels are
/// not formatting machinery.
const List<String> kMonthLabels = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `21:04`. Twenty-four hour, because every other clock in the shell is —
/// `modules/clock.dart` and the calendar's world clocks both pad to `HH:mm`
/// and neither offers a 12-hour setting to be consistent with.
String formatMoonTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// `28 Aug`, or `28 Aug 2027` when [reference] is in another year — a date a
/// year out with no year on it is the kind of thing a reader trusts and should
/// not.
String formatMoonDate(DateTime date, {DateTime? reference}) {
  final label = '${date.day} ${kMonthLabels[date.month - 1]}';
  if (reference == null || reference.year == date.year) return label;
  return '$label ${date.year}';
}

/// `in 6 days`, `tomorrow`, `in 4 hours`, `in 20 minutes`.
///
/// Calendar days rather than 24-hour blocks: a full moon at 23:00 tomorrow is
/// "tomorrow", not "in 1 day", and one at 01:00 tomorrow is not "in 8 hours" to
/// anybody planning an evening around it. Both halves matter — under a day the
/// hours are what somebody wants, over it the date is.
String formatMoonCountdown(DateTime target, DateTime now) {
  final difference = target.difference(now);
  if (difference.isNegative) return 'now';

  final days = _calendarDaysBetween(now, target);
  if (days >= 2) return 'in $days days';
  if (days == 1) return 'tomorrow';

  final hours = difference.inHours;
  if (hours >= 2) return 'in $hours hours';
  if (hours == 1) return 'in an hour';
  final minutes = difference.inMinutes;
  if (minutes >= 2) return 'in $minutes minutes';
  return 'within the minute';
}

/// Whole calendar days from [from] to [to], both taken as local dates.
///
/// Through UTC midnights, the `overlay/calendar/month.dart` `dayDelta`
/// discipline: differencing two local `DateTime`s measures elapsed *time*, and
/// `inDays` truncates the 23-hour day the clocks change on to zero.
int _calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// `384,400 km`. Grouped, because six unbroken digits is a number nobody reads.
String formatKilometres(double km) {
  final digits = km.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${buffer.toString()} km';
}

/// `1.28 light-seconds` — the distance in the unit that makes it feel like a
/// distance.
String formatLightTime(double km) {
  final seconds = km / 299792.458;
  return '${seconds.toStringAsFixed(2)} light-seconds';
}
