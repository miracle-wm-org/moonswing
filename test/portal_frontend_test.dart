import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/screencast/portal_frontend.dart';
import 'package:moonswing/screencast/screencast_log.dart';

/// The repair in `lib/screencast/portal_frontend.dart`: xdg-desktop-portal reads
/// this backend's `AvailableSourceTypes` once, as its own frontend starts, and
/// publishes 0 for the rest of its life if the shell had not yet claimed the bus
/// name. Sharing still works, so the only visible symptom is a client that *asks*
/// first (OBS) registering no capture source at all.
///
/// What is pinned here is the policy, not the D-Bus call: when a restart is spent,
/// when it is not, and that nothing here can throw at its caller.

void main() {
  late List<String> log;

  setUp(() {
    log = [];
    screencastLog = log.add;
  });

  tearDown(() => screencastLog = (_) {});

  // The client is never touched — the read is injected — but the signature
  // wants one. Constructing one opens no socket: package:dbus connects lazily.
  DBusClient client() => DBusClient(DBusAddress('unix:path=/nonexistent'));

  Future<int?> Function(DBusClient) reads(List<int?> answers) {
    var i = 0;
    return (_) async => answers[i < answers.length ? i++ : answers.length - 1];
  }

  test('a frontend advertising nothing is restarted once', () async {
    var restarts = 0;
    await reconcilePortalFrontend(
      client: client(),
      backendSourceTypes: 3,
      read: reads([0, 3]),
      restart: () async {
        restarts++;
        return true;
      },
      delay: (_) async {},
    );
    expect(restarts, 1);
    expect(log.join('\n'), contains('now advertises source types 3'));
  });

  test('a frontend that already answers is left alone', () async {
    var restarts = 0;
    await reconcilePortalFrontend(
      client: client(),
      backendSourceTypes: 3,
      read: reads([1]),
      restart: () async {
        restarts++;
        return true;
      },
      delay: (_) async {},
    );
    // Deliberately not restarted on a *mismatch*: 1 is what a frontend routed
    // to another backend legitimately answers, and a restart brings back the
    // same routing — so a mismatch rule would bounce xdg-desktop-portal on
    // every shell start for the life of that machine.
    expect(restarts, 0);
  });

  test('an unreachable frontend is not restarted', () async {
    var restarts = 0;
    await reconcilePortalFrontend(
      client: client(),
      backendSourceTypes: 1,
      read: reads([null]),
      restart: () async {
        restarts++;
        return true;
      },
      delay: (_) async {},
    );
    // Null means no ScreenCast interface at all — xdg-desktop-portal absent, or
    // no backend routed to it. Restarting cannot repair a portals.conf.
    expect(restarts, 0);
  });

  test('a restart that cannot be run says what to run by hand', () async {
    await reconcilePortalFrontend(
      client: client(),
      backendSourceTypes: 1,
      read: reads([0]),
      restart: () async => false,
      delay: (_) async {},
    );
    expect(log.join('\n'), contains('systemctl --user restart'));
  });

  test('a restart that did not help points at portals.conf', () async {
    await reconcilePortalFrontend(
      client: client(),
      backendSourceTypes: 1,
      read: reads([0, 0]),
      restart: () async => true,
      delay: (_) async {},
    );
    expect(log.join('\n'), contains('portals.conf'));
  });

  test('restartPortalFrontend asks systemd for a try-restart of the '
      'frontend alone', () async {
    List<String>? args;
    final ok = await restartPortalFrontend(runner: (exe, a) async {
      expect(exe, 'systemctl');
      args = a;
      return ProcessResult(0, 0, '', '');
    });
    expect(ok, isTrue);
    // --user, and try-restart so a session with no systemd user instance is
    // not forced to start one. Only the frontend: the backends are not ours.
    expect(args, ['--user', 'try-restart', 'xdg-desktop-portal.service']);
  });

  test('no systemctl is a false, never a throw', () async {
    final ok = await restartPortalFrontend(
        runner: (_, __) => throw const ProcessException('systemctl', []));
    expect(ok, isFalse);
  });
}

