// Start-up for the Code tab: hand `[code]` to the store and keep it in step
// with edits made in Settings.
//
// Not a `ShellService`, for `startNewsService`'s reason: no panel waits on it.
// It starts no network traffic itself — the store reads only for a lease, and
// only the Code tab takes one, while it is showing.

import 'package:moonswing/code/code_config.dart';
import 'package:moonswing/code/code_store.dart';
import 'package:moonswing/config_store.dart';

/// Reads `[code]` off the live config.
CodeConfig readCodeConfig() => CodeConfig.fromMap(
  ConfigStore.instance.get<Map<String, dynamic>>(['code']),
);

void startCodeService() {
  // `configure` compares, so the notify per settings keystroke elsewhere costs
  // one parse of a five-key table and nothing more.
  void apply() => CodeStore.instance.configure(readCodeConfig());

  apply();
  ConfigStore.instance.addListener(apply);
}
