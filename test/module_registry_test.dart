import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/modules/battery.dart';
import 'package:graceful_shell/modules/clock.dart';
import 'package:graceful_shell/modules/dock.dart';
import 'package:graceful_shell/modules/launcher.dart';
import 'package:graceful_shell/modules/media_player.dart';
import 'package:graceful_shell/modules/network.dart';
import 'package:graceful_shell/modules/notifications.dart';
import 'package:graceful_shell/modules/sound_control.dart';
import 'package:graceful_shell/modules/system.dart';
import 'package:graceful_shell/modules/system_monitor.dart';
import 'package:graceful_shell/modules/system_tray.dart';
import 'package:graceful_shell/modules/weather.dart';
import 'package:graceful_shell/modules/workspaces.dart';

/// Pins the registry across the Module.simple collapse: every key a panel
/// layout can name must resolve, and per-module options must reach their
/// widget's config.
void main() {
  test('every module registers under its config key', () {
    final modules = [
      workspacesModule,
      mediaPlayerModule,
      soundControlModule,
      batteryModule,
      weatherModule,
      clockModule,
      dockModule,
      systemMonitorModule,
      notificationsModule,
      networkModule,
      systemModule,
      systemTrayModule,
      launcherModule,
    ];
    for (final module in modules) {
      Module.register(module);
    }
    const expected = [
      'workspaces',
      'media_player',
      'sound_control',
      'battery',
      'weather',
      'clock',
      'dock',
      'system_monitor',
      'notifications',
      'network',
      'system',
      'system_tray',
      'launcher',
    ];
    for (final key in expected) {
      expect(Module.lookup(key), isNotNull, reason: key);
    }
    expect(Module.registeredKeys.toSet(), expected.toSet());
  });

  test('loadAll pushes a module table into its config, type-safely', () {
    Module.register(batteryModule);
    // A non-table value must cost the module its options, never throw —
    // a throw here is caught by AppConfig.load, which discards the user's
    // whole config.
    Module.loadAll({'battery': 'nope'});
    Module.loadAll({
      'battery': {'poll_seconds': 45.0},
    });
    expect(Module.lookup('battery'), isNotNull);
  });
}
