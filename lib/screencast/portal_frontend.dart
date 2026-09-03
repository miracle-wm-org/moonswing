// Whether xdg-desktop-portal has actually *noticed* this backend.
//
// Owning `org.freedesktop.impl.portal.desktop.graceful_shell` and exporting the
// object is not the whole job, because there is a third party in the middle.
// An application never talks to this backend: it talks to the xdg-desktop-portal
// *frontend*, which reads `AvailableSourceTypes` off the backend's proxy **once**
// — in `screen_cast_create`, as the frontend starts — and republishes it on
// `org.freedesktop.portal.ScreenCast`. GDBus fills that proxy's property cache
// with a `GetAll` at construction, so a frontend that starts while nobody owns
// the backend name caches *nothing* and publishes `AvailableSourceTypes = 0` for
// the rest of its life.
//
// That is a race the shell loses by default. `startScreencastService` runs off a
// post-frame callback (`main.dart`), so the name is claimed a good deal later
// than the session starts; the snap's own launcher restarts the frontend
// *before* it execs the shell binary; and xdg-desktop-portal is bus-activated,
// so any application asking for any portal can start it first.
//
// The symptom is specific and misleading: screen sharing still works. The
// frontend does not validate a `SelectSources` request against
// `AvailableSourceTypes` (it validates against the set of types the protocol
// defines), so a browser asking to share a monitor gets this shell's picker and
// a working stream. What breaks is every client that *asks first* — OBS reads
// the property in `get_available_capture_types()` and registers no PipeWire
// capture source at all when it reads 0, so "Screen Capture (PipeWire)" is
// missing from the source list on a machine where Google Meet shares the screen
// perfectly well.
//
// Nothing tells the frontend to look again: it re-syncs on a `notify::` for a
// property name that does not exist on the proxy, so the value it publishes is
// frozen at its own start-up. Restarting the frontend is the repair, and this
// file is the one place that decides to.
//
// Flutter-free, like the rest of `lib/screencast/` — `tool/screencast_spike.dart`
// compiles this whole layer.

import 'dart:io';

import 'package:dbus/dbus.dart';

import 'screencast_log.dart';

/// The frontend: what applications talk to, and what OBS reads.
const String portalFrontendName = 'org.freedesktop.portal.Desktop';
const String portalFrontendPath = '/org/freedesktop/portal/desktop';
const String screenCastFrontendInterface = 'org.freedesktop.portal.ScreenCast';

/// The frontend's systemd user unit.
const String portalFrontendUnit = 'xdg-desktop-portal.service';

/// How long to give the frontend to export its interfaces again after a
/// restart, before reading back what it now says. Diagnostic only — the repair
/// has already happened either way.
const Duration kFrontendRestartGrace = Duration(milliseconds: 750);

/// Reads `AvailableSourceTypes` from a frontend that is *already running*.
///
/// Three answers, and the difference between the last two is the whole point:
/// - `null` — nothing to reason about. The frontend is not running, could not
///   be asked, or serves no ScreenCast interface at all (xdg-desktop-portal
///   absent, or no ScreenCast backend routed to it, in which case
///   `screen_cast_create` returned NULL and there is no property to read).
///   None of that is repairable from here; the last is a `portals.conf`
///   question.
/// - `0` — a backend *is* routed and answered nothing, which is the frozen
///   cache above.
/// - anything else — a live backend answered, and the frontend is current.
///
/// The owner check is what keeps this from *activating* the frontend. Reading a
/// property off a well-known name starts its service, and a frontend that is
/// not running is precisely the case with nothing wrong: whenever it does come
/// up, this backend will already be on the bus for it to read. Starting
/// xdg-desktop-portal on every shell launch to discover that would be the
/// check paying a cost the bug never had.
Future<int?> readFrontendSourceTypes(DBusClient client) async {
  try {
    if (!(await client.listNames()).contains(portalFrontendName)) return null;
    final object = DBusRemoteObject(client,
        name: portalFrontendName, path: DBusObjectPath(portalFrontendPath));
    final value = await object.getProperty(
        screenCastFrontendInterface, 'AvailableSourceTypes');
    // Type-test, never cast: the portal contract says `u`, and a frontend that
    // answered something else is one this cannot reason about anyway.
    return value is DBusUint32 ? value.value : null;
  } catch (e) {
    screencastLog('portal frontend: cannot read AvailableSourceTypes ($e)');
    return null;
  }
}

/// Restarts the frontend, and only the frontend.
///
/// `try-restart` rather than `restart`, the rule the snap's launcher already
/// follows: it is a no-op when the unit is not running, so a session with no
/// systemd user instance — or one that has never activated the portal — is not
/// forced to start one. The backends are not ours to bounce.
Future<bool> restartPortalFrontend({
  Future<ProcessResult> Function(String, List<String>)? runner,
}) async {
  final run = runner ?? Process.run;
  try {
    final result =
        await run('systemctl', ['--user', 'try-restart', portalFrontendUnit]);
    return result.exitCode == 0;
  } catch (_) {
    // No systemctl at all (a container, a non-systemd session).
    return false;
  }
}

/// Makes the frontend's answer match this backend's, restarting it at most once.
///
/// Called after the backend owns its name and has exported its object, so the
/// restarted frontend is guaranteed to find somebody to ask.
///
/// The trigger is `0` and deliberately not "differs from [backendSourceTypes]".
/// A frontend routed to *another* backend legitimately answers that backend's
/// number, and restarting would bring back the same routing — so a mismatch
/// rule would restart xdg-desktop-portal on every shell start for the rest of
/// that machine's life, which is the noise the snap's revision stamp exists to
/// avoid. Zero is the one value that cannot be a live backend's answer.
///
/// Best-effort throughout: a frontend that cannot be reached, a restart that
/// cannot be run, and a restart that did not help are all logged and none of
/// them is a failure of this shell's backend, which is up and serving either
/// way.
Future<void> reconcilePortalFrontend({
  required DBusClient client,
  required int backendSourceTypes,
  Future<int?> Function(DBusClient) read = readFrontendSourceTypes,
  Future<bool> Function() restart = restartPortalFrontend,
  Future<void> Function(Duration) delay = _wait,
}) async {
  final published = await read(client);
  if (published == null) return;
  if (published != 0) {
    screencastLog('portal frontend advertises source types $published');
    return;
  }

  screencastLog('portal frontend advertises no source types; it started before '
      'this backend owned its name. Restarting it, so it reads the '
      '$backendSourceTypes this backend offers.');
  if (!await restart()) {
    screencastLog('could not restart the portal frontend; screen capture will '
        'be missing from apps that ask before sharing (OBS). Try: '
        'systemctl --user restart $portalFrontendUnit');
    return;
  }

  await delay(kFrontendRestartGrace);
  final now = await read(client);
  if (now != null && now != 0) {
    screencastLog('portal frontend now advertises source types $now');
  } else {
    screencastLog('portal frontend still advertises no source types after a '
        'restart; check that portals.conf routes '
        'org.freedesktop.impl.portal.ScreenCast to graceful-shell');
  }
}

Future<void> _wait(Duration d) => Future<void>.delayed(d);
