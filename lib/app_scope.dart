/// Transient systemd scopes for the applications the shell launches.
///
/// GIO spawns a desktop entry's command out of *this* process. Whether GLib
/// hands the result straight to init (its double fork) or leaves it a child of
/// the shell varies by version, but either way a fork inherits the launcher's
/// cgroup, so every application started from the launcher, the dock, the app
/// directory or a desktop icon keeps running inside whatever unit the session
/// started the shell in. Under the snap that unit is
/// `snap.moonswing.….scope`, and a snap with processes in its scope "has
/// running apps": snapd refuses to refresh it, so updating the shell meant
/// quitting everything ever launched from it first. The same inheritance is
/// why stopping the shell's own unit takes those applications down with it.
///
/// The fix is what every other desktop shell does: hand the freshly-spawned pid
/// to the session's systemd user manager and have it adopt the process into a
/// transient scope of its own under `app.slice`. The application becomes a
/// sibling of the shell instead of a part of it, which is as close to "launched
/// from the user's session" as a launcher can get without re-implementing
/// desktop-entry expansion.
///
/// Best-effort by construction, and never in the way of a launch: the
/// application has already started by the time any of this runs, so a session
/// with no systemd user manager — or one where the shell's own cgroup sits
/// outside the user manager's delegated subtree, which is where a migration is
/// refused — costs the scope and nothing else. A refusal that says systemd is
/// not there at all is remembered, so a launcher that opens twenty apps does
/// not make twenty doomed round trips.
library;

import 'package:dbus/dbus.dart';

import 'dbus_clients.dart';

/// Log hook, pointed at `debugPrint` by `main()`. Silent by default, like
/// `screencastLog` — this file is Flutter-free.
void Function(String message) appScopeLog = (_) {};

const String _systemdName = 'org.freedesktop.systemd1';
const String _systemdPath = '/org/freedesktop/systemd1';
const String _managerInterface = 'org.freedesktop.systemd1.Manager';

/// The bus error systemd's absence answers with: nobody owns the name and no
/// service file starts one. Any other error is this launch's problem, not the
/// session's, so only this one is remembered.
const String _serviceUnknown = 'org.freedesktop.DBus.Error.ServiceUnknown';

/// What systemd accepts in a unit name, minus `-`, which [_escapeUnitPart]
/// spends as its own separator.
final RegExp _unitUnsafe = RegExp(r'[^A-Za-z0-9:_.]');

/// systemd's own escaping for one segment of a unit name: a literal `-` becomes
/// `\x2d`, so it cannot read as the `-` that separates the segments, and
/// anything else outside the allowed set becomes `_`.
///
/// Escaped a character at a time and stopped at [maxLength] rather than
/// truncated afterwards, so a long id cannot be cut through the middle of an
/// escape and leave a `\x` behind.
String _escapeUnitPart(String value, {int maxLength = 128}) {
  final escaped = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final piece = char == '-' ? r'\x2d' : char.replaceAll(_unitUnsafe, '_');
    if (escaped.length + piece.length > maxLength) break;
    escaped.write(piece);
  }
  return escaped.toString();
}

/// The scope unit name for one launch, in the shape the systemd desktop
/// integration document asks launchers to use: `app-<launcher>-<id>-<n>.scope`.
///
/// [appId] is a desktop-file id, which may be empty (GIO gives one to entries
/// it found by path, but not to every `GAppInfo`) and may carry a `.desktop`
/// suffix. Unit names are bounded at 255 bytes, so the id is truncated well
/// short of it rather than producing a name systemd will reject.
String appScopeUnitName({required String appId, required int pid}) {
  var id = appId.trim();
  if (id.toLowerCase().endsWith('.desktop')) {
    id = id.substring(0, id.length - '.desktop'.length);
  }
  id = _escapeUnitPart(id);
  if (id.isEmpty) id = 'app';
  return 'app-moonswing-$id-$pid.scope';
}

/// Starts one transient scope. Injectable so the naming and the
/// give-up-once-systemd-is-absent rules can be tested without a bus.
typedef TransientScopeStarter = Future<void> Function({
  required String unitName,
  required int pid,
  required String description,
});

/// Adopts launched applications into transient systemd scopes. One per process
/// ([appScopes]); the shell holds no state beyond "is this session's systemd
/// user manager there at all".
class AppScopeAdopter {
  AppScopeAdopter({TransientScopeStarter? start})
      : _start = start ?? _startTransientScope;

  final TransientScopeStarter _start;

  bool _unavailable = false;

  /// True once the session has told us it has no systemd user manager. Nothing
  /// clears it: a manager that was not there when the shell started is not
  /// going to appear under the same session bus.
  bool get unavailable => _unavailable;

  /// Moves [pid] into a scope of its own, answering whether it landed there.
  ///
  /// Never throws and never blocks a launch — the application is already
  /// running by the time this is called.
  Future<bool> adopt({
    required int pid,
    String appId = '',
    String appName = '',
  }) async {
    if (pid <= 0 || _unavailable) return false;
    // A `GAppInfo` loaded from a path outside `XDG_DATA_DIRS` — a desktop
    // icon's launcher — has no desktop-file id, so name its scope after the
    // application instead of leaving every one of them called `app`.
    final unitName = appScopeUnitName(
      appId: appId.isNotEmpty ? appId : appName,
      pid: pid,
    );
    final label = appName.isNotEmpty
        ? appName
        : appId.isNotEmpty
            ? appId
            : 'pid $pid';
    try {
      await _start(
        unitName: unitName,
        pid: pid,
        description: 'Application launched by Moonswing: $label',
      );
      appScopeLog('adopted $label (pid $pid) into $unitName');
      return true;
    } on DBusMethodResponseException catch (e) {
      if (e.errorName == _serviceUnknown) {
        _unavailable = true;
        appScopeLog('no systemd user manager; launched apps stay in the '
            "shell's own cgroup");
      } else {
        // A pid that exited before the round trip landed, a manager that will
        // not migrate out of the shell's cgroup: this launch keeps the cgroup
        // it inherited, and the next one is still worth trying.
        appScopeLog('scope for $label refused: ${e.errorName}');
      }
      return false;
    } catch (e) {
      // No session bus at all, or a socket that will not answer. Same posture
      // as a missing manager: stop asking.
      _unavailable = true;
      appScopeLog('scope for $label failed, giving up on scopes: $e');
      return false;
    }
  }
}

/// The process-wide adopter. Every launch in `app_info.dart` goes through it.
final AppScopeAdopter appScopes = AppScopeAdopter();

/// `StartTransientUnit` against the session's systemd user manager.
///
/// `PIDs=` is what makes this an adoption rather than a launch: the process is
/// already running, and systemd migrates it into the new scope's cgroup.
/// `CollectMode=inactive-or-failed` is what keeps a scope from outliving the
/// application it was made for — without it a scope whose process died badly
/// stays loaded until something garbage-collects it.
Future<void> _startTransientScope({
  required String unitName,
  required int pid,
  required String description,
}) async {
  final manager = DBusRemoteObject(
    sessionBus,
    name: _systemdName,
    path: DBusObjectPath(_systemdPath),
  );
  await manager.callMethod(
    _managerInterface,
    'StartTransientUnit',
    [
      DBusString(unitName),
      // "fail" rather than "replace": a name collision means something else
      // owns that scope, and taking it over is not an improvement.
      DBusString('fail'),
      DBusArray(DBusSignature('(sv)'), [
        DBusStruct([
          DBusString('Description'),
          DBusVariant(DBusString(description)),
        ]),
        DBusStruct([
          DBusString('PIDs'),
          DBusVariant(DBusArray(DBusSignature('u'), [DBusUint32(pid)])),
        ]),
        DBusStruct([
          DBusString('Slice'),
          DBusVariant(DBusString('app.slice')),
        ]),
        DBusStruct([
          DBusString('CollectMode'),
          DBusVariant(DBusString('inactive-or-failed')),
        ]),
      ]),
      // Auxiliary units: none.
      DBusArray(DBusSignature('(sa(sv))'), const <DBusValue>[]),
    ],
    replySignature: DBusSignature('o'),
  );
}
