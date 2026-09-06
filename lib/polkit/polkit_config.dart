import 'package:flutter/foundation.dart';

import 'package:graceful_shell/config_reader.dart';

/// `[polkit]` — whether the shell answers polkit's authentication requests.
///
/// It sits beside the feature the way `power/power_config.dart` and
/// `weather/weather_config.dart` do, and `config.dart` re-exports it.
@immutable
class PolkitConfig {
  const PolkitConfig({
    this.enabled = true,
    this.maxAttempts = 3,
  });

  /// Whether to register as this session's authentication agent at all.
  ///
  /// On by default, because with **no** agent registered polkitd cannot ask
  /// anybody anything: every `auth_admin` action comes back `AccessDenied` with
  /// no prompt, which a user reads as the setting being broken.
  ///
  /// Off is for a session that already runs one — `polkit-gnome`, `lxpolkit` —
  /// where the shell would otherwise lose the race and silently never prompt. The
  /// shell already yields when it finds an agent registered ahead of it, so this
  /// is for the opposite ordering: turning it off so a *later* one wins.
  final bool enabled;

  /// How many times PAM may refuse before the dialog stops asking.
  ///
  /// Three by default, which is what every polkit agent has settled on. Clamped
  /// rather than trusted: zero attempts is a dialog that cannot be answered, and
  /// a large number is a password oracle left on the screen.
  final int maxAttempts;

  factory PolkitConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PolkitConfig();
    return PolkitConfig(
      enabled: map.boolOr('enabled', true),
      maxAttempts: map.intOr('max_attempts', 3, min: 1, max: 5),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PolkitConfig &&
          other.enabled == enabled &&
          other.maxAttempts == maxAttempts;

  @override
  int get hashCode => Object.hash(enabled, maxAttempts);
}
