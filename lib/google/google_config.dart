// The `[google]` section: what the shell does with the Google account signed
// in under Settings › Accounts.
//
// The account itself (the client and the grant) is not here. It lives in the
// XDG state directory (`google_account_file.dart`), because `config.toml` is
// the file people paste into bug reports.

import 'package:moonswing/config_reader.dart';

/// The `[google]` section.
class GoogleConfig {
  const GoogleConfig({
    this.calendars = const ['primary'],
    this.showInCalendar = true,
    this.todoSync = false,
    this.refreshMinutes = 5,
  });

  /// The calendar ids read, as the calendar list spells them. `primary` is
  /// Google's own alias for the account's main calendar.
  final List<String> calendars;

  /// Whether the Calendar tab shows the account's events.
  final bool showInCalendar;

  /// Whether today's timed events become cards on the todo board.
  final bool todoSync;

  /// How often events are re-read while something is showing them.
  final int refreshMinutes;

  static const int minRefreshMinutes = 1;
  static const int maxRefreshMinutes = 60;

  factory GoogleConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const GoogleConfig();
    final calendars = map
        .stringListOr('calendars', const ['primary'])
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    return GoogleConfig(
      calendars: calendars,
      showInCalendar: map.boolOr('show_in_calendar', true),
      todoSync: map.boolOr('todo_sync', false),
      refreshMinutes: map.intOr(
        'refresh_minutes',
        5,
        min: minRefreshMinutes,
        max: maxRefreshMinutes,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoogleConfig &&
          _listEquals(other.calendars, calendars) &&
          other.showInCalendar == showInCalendar &&
          other.todoSync == todoSync &&
          other.refreshMinutes == refreshMinutes;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(calendars),
    showInCalendar,
    todoSync,
    refreshMinutes,
  );
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
