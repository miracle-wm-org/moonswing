import 'package:flutter/foundation.dart';

import 'package:moonswing/config_reader.dart';

/// `[control]` — whether other programs may drive the shell over
/// `org.moonswing.Shell` on the session bus, which is what `moonswing-mcp`
/// (and so any AI agent pointed at it) talks to.
///
/// Sits beside the feature, `polkit/polkit_config.dart`'s shape, and
/// `config.dart` re-exports it.
@immutable
class ControlConfig {
  const ControlConfig({this.enabled = true, this.screenshots = true});

  /// Whether to own the name at all. Read at start-up, like every other bus
  /// name the shell takes.
  ///
  /// On by default because it reaches nothing a session-bus client could not
  /// already reach: anything on the bus can talk to the compositor's IPC socket
  /// and post notifications, and a sandboxed application is not given the
  /// session bus unfiltered. Off is for the person who wants the shell to answer
  /// nobody but themselves.
  final bool enabled;

  /// Whether `Screenshot` answers. Read live, at each request, so it can be
  /// switched off without a restart. A picture of the screen is the one thing
  /// the interface hands out that the person may not have meant to share — an
  /// open password manager, a private message — so it has a switch of its own.
  final bool screenshots;

  factory ControlConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ControlConfig();
    return ControlConfig(
      enabled: map.boolOr('enabled', true),
      screenshots: map.boolOr('screenshots', true),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlConfig &&
          other.enabled == enabled &&
          other.screenshots == screenshots;

  @override
  int get hashCode => Object.hash(enabled, screenshots);
}
