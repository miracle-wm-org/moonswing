// Waking from a suspend, as logind announces it.
//
// Dart's timers run on the monotonic clock, which stops while the machine is
// suspended, so a one-shot timer armed for 10:00 before a suspend at 09:00 and
// a wakeup at 11:00 fires at noon. Anything that acts at a wall-clock moment —
// the todo board's calendar cards, its midnight — listens here and catches up.
//
// Best-effort: a machine without logind (or a system bus the shell cannot
// reach) costs the catch-up after a suspend, and every such timer still fires,
// late.

import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'package:moonswing/dbus_clients.dart';

StreamSubscription<DBusSignal>? _sleepWatch;

/// Calls [onResume] each time the machine comes back from a suspend or
/// hibernate. A second call replaces the first's callback.
void watchResume(VoidCallback onResume, {DBusClient? bus}) {
  unawaited(_sleepWatch?.cancel());
  _sleepWatch =
      DBusSignalStream(
        bus ?? systemBus,
        sender: 'org.freedesktop.login1',
        interface: 'org.freedesktop.login1.Manager',
        name: 'PrepareForSleep',
        path: DBusObjectPath('/org/freedesktop/login1'),
        signature: DBusSignature('b'),
      ).listen(
        (signal) {
          // `true` on the way down, `false` on the way back up.
          if (signal.values.first.asBoolean()) return;
          onResume();
        },
        onError: (Object e) => debugPrint('sleep: not watching for resume: $e'),
      );
}
