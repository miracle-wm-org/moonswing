import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/module.dart';
import 'package:moonswing/modules/battery.dart';
import 'package:moonswing/modules/claude.dart';
import 'package:moonswing/modules/clock.dart';
import 'package:moonswing/modules/dock.dart';
import 'package:moonswing/modules/github.dart';
import 'package:moonswing/modules/keybinds.dart';
import 'package:moonswing/modules/keyboard_layout.dart';
import 'package:moonswing/modules/launcher.dart';
import 'package:moonswing/modules/media_player.dart';
import 'package:moonswing/modules/network.dart';
import 'package:moonswing/modules/notifications.dart';
import 'package:moonswing/modules/screen_recorder.dart';
import 'package:moonswing/modules/scratchpad.dart';
import 'package:moonswing/modules/screenshot.dart';
import 'package:moonswing/modules/sound_control.dart';
import 'package:moonswing/modules/system.dart';
import 'package:moonswing/modules/system_monitor.dart';
import 'package:moonswing/modules/system_tray.dart';
import 'package:moonswing/modules/todo.dart';
import 'package:moonswing/modules/weather.dart';
import 'package:moonswing/modules/workspaces.dart';

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
      screenshotModule,
      screenRecorderModule,
      keyboardLayoutModule,
      keybindsModule,
      githubModule,
      claudeModule,
      scratchpadModule,
      todoModule,
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
      'screenshot',
      'screen_recorder',
      'keyboard_layout',
      'keybinds',
      'github',
      'claude',
      'scratchpad',
      'todo',
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

  /// The regression test for the thing that keeps `[modules.*]` options live
  /// now that the shell root no longer rebuilds every panel on every config
  /// notify: module config is pushed imperatively and read out of `builder` at
  /// build time, so [Module.configChanges] is the only thing that can tell a
  /// panel its module moved.
  test('configChanges fires when a module table moves, and only then', () {
    Module.register(clockModule);
    var fired = 0;
    void onChanged() => fired++;
    Module.configChanges.addListener(onChanged);
    addTearDown(() => Module.configChanges.removeListener(onChanged));

    Module.loadAll({
      'clock': {'show_date': true},
    });
    final first = fired;
    expect(first, greaterThan(0), reason: 'the first load is always a change');

    // The same table again: ConfigStore notifies on every keystroke anywhere
    // in the settings UI, and re-ranking every module for an unrelated edit is
    // exactly what this guard exists to prevent.
    Module.loadAll({
      'clock': {'show_date': true},
    });
    expect(fired, first, reason: 'an identical table is not a change');

    Module.loadAll({
      'clock': {'show_date': false},
    });
    expect(fired, first + 1, reason: 'a moved value is');

    // Once per sweep, not once per module, however many moved.
    Module.register(batteryModule);
    Module.loadAll({
      'clock': {'show_date': true},
      'battery': {'poll_seconds': 11.0},
    });
    expect(fired, first + 2);
  });
}
