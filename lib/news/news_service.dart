// Start-up for the headlines: hand `[news]` to the store and keep it in step
// with edits made in Settings.
//
// Not a `ShellService`, for `startGoogleService`'s reason: no panel waits on
// it. It starts no network traffic itself — the store reads only for a lease,
// and only a news card on the desktop takes one.

import 'package:moonswing/config_store.dart';
import 'package:moonswing/news/news_config.dart';
import 'package:moonswing/news/news_store.dart';

/// Reads `[news]` off the live config.
NewsConfig readNewsConfig() => NewsConfig.fromMap(
  ConfigStore.instance.get<Map<String, dynamic>>(['news']),
);

void startNewsService() {
  // `configure` compares, so the notify per settings keystroke elsewhere
  // costs one parse of a two-key table and nothing more.
  void apply() => NewsStore.instance.configure(readNewsConfig());

  apply();
  ConfigStore.instance.addListener(apply);
}
