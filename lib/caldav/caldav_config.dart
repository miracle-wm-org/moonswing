// The `[caldav]` section: what the shell does with the CalDAV accounts signed
// in under Settings › Accounts.
//
// The accounts themselves (the servers and the passwords) are not here. They
// live in the XDG state directory (`caldav_account_store.dart`), because
// `config.toml` is the file people paste into bug reports.

import 'package:moonswing/config_reader.dart';

/// The `[caldav]` section.
class CalDavConfig {
  const CalDavConfig({
    this.calendars = const [],
    this.showInCalendar = true,
    this.refreshMinutes = 5,
  });

  /// The calendars whose events the Calendar tab shows, by collection URL as
  /// the server lists it. A URL is unique across servers, so one list serves
  /// every account. None by default: a server's calendars are switched on one
  /// by one under Settings › Shell › Calendar.
  final List<String> calendars;

  /// Whether the Calendar tab shows the calendars' events.
  final bool showInCalendar;

  /// How often events are re-read while something is showing them.
  final int refreshMinutes;

  static const int minRefreshMinutes = 1;
  static const int maxRefreshMinutes = 60;

  factory CalDavConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CalDavConfig();
    return CalDavConfig(
      calendars: map
          .stringListOr('calendars', const [])
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toSet()
          .toList(),
      showInCalendar: map.boolOr('show_in_calendar', true),
      refreshMinutes: map.intOr(
        'refresh_minutes',
        5,
        min: minRefreshMinutes,
        max: maxRefreshMinutes,
      ),
    );
  }

  /// Whether the calendar at [url] is shown.
  bool shows(Uri url) => calendars.contains(url.toString());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalDavConfig &&
          _listEquals(other.calendars, calendars) &&
          other.showInCalendar == showInCalendar &&
          other.refreshMinutes == refreshMinutes;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(calendars), showInCalendar, refreshMinutes);
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
