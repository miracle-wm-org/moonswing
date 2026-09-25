// Start-up for the Google account: read the saved account, hand `[google]` to
// the calendar store and the todo sync, and keep them in step with edits made in
// Settings.
//
// Deliberately not a `ShellService`, for `startTodoService`'s reason: no panel
// waits on it, and an account that will not sign in is the settings row's to
// say, not a start-up failure. It starts no network traffic itself. The
// calendar store fetches only for a lease, and the todo sync takes a lease only
// while `todo_sync` is on and the account is signed in.

import 'dart:async';

import 'package:moonswing/config_store.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/google/google_config.dart';
import 'package:moonswing/google/google_todo_sync.dart';

/// Reads `[google]` off the live config.
GoogleConfig readGoogleConfig() => GoogleConfig.fromMap(
  ConfigStore.instance.get<Map<String, dynamic>>(['google']),
);

void startGoogleService() {
  unawaited(GoogleAccountStore.instance.load());
  void apply() {
    final config = readGoogleConfig();
    GoogleCalendarStore.instance.configure(config);
    GoogleTodoSync.instance.configure(config);
  }

  apply();
  ConfigStore.instance.addListener(apply);
}
