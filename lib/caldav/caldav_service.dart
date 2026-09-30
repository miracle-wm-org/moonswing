// Start-up for the CalDAV calendars: read the saved accounts, hand `[caldav]`
// to the calendar store, and keep it in step with edits made in Settings.
//
// Not a `ShellService`, for `startGoogleService`'s reason: no panel waits on
// it, and it starts no network traffic itself — the store fetches only for a
// lease, which the Calendar tab takes while it is open and has calendars to
// show.

import 'dart:async';

import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/caldav/caldav_calendar_store.dart';
import 'package:moonswing/caldav/caldav_config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/overlay/calendar/time_zones.dart';

/// Reads `[caldav]` off the live config.
CalDavConfig readCalDavConfig() => CalDavConfig.fromMap(
  ConfigStore.instance.get<Map<String, dynamic>>(['caldav']),
);

void startCalDavCalendarService() {
  unawaited(CalDavAccountStore.instance.load());
  CalDavCalendarStore.instance.zone = zonedWallClockToLocal;
  void apply() => CalDavCalendarStore.instance.configure(readCalDavConfig());

  apply();
  ConfigStore.instance.addListener(apply);
}
