// When a story went up, as the card writes it. Pure, so the boundaries —
// midnight, a week ago — are testable with a fixed `now`.

const List<String> _weekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const List<String> _months = [
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

/// [published] relative to [now], both read in local time.
///
/// A clock time for today, `Yesterday`, a weekday inside the last week, a
/// date beyond it. Absolute rather than "5m ago" on purpose: the card does
/// not tick — it rebuilds when the feed moves and not otherwise — and a
/// relative age would be wrong by however long it had sat there.
String formatNewsTime(DateTime published, DateTime now) {
  final local = published.toLocal();
  final today = now.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final day = DateTime(local.year, local.month, local.day);
  final midnight = DateTime(today.year, today.month, today.day);
  // Calendar days apart, counted on dates rather than as a `Duration` divided
  // by twenty-four hours, which a daylight-saving change makes wrong.
  final daysAgo = DateTime.utc(
    midnight.year,
    midnight.month,
    midnight.day,
  ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  // A story stamped a little in the future — a feed whose clock runs ahead —
  // is today's.
  if (daysAgo <= 0) return '${two(local.hour)}:${two(local.minute)}';
  if (daysAgo == 1) return 'Yesterday';
  if (daysAgo < 7) return _weekdays[local.weekday - 1];
  return '${local.day} ${_months[local.month - 1]}';
}
