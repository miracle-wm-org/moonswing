// NetworkManager's VPN surface, over D-Bus.
//
// Everything the pane does to a VPN is one of NetworkManager's own calls:
//
//   Settings.ListConnections / Connection.GetSettings   the list
//   Settings.AddConnection                              add, import
//   Connection.Delete                                   remove
//   Connection.GetSecrets + Connection.Update           set a password
//   NetworkManager.ActivateConnection                   switch on
//   NetworkManager.DeactivateConnection                 switch off
//
// and its signals say when something moved, whoever moved it — `nmcli`, an
// applet, the connection dropping. Adding, removing and changing a profile are
// polkit-checked by NetworkManager (`settings.modify.system`), which this shell
// answers itself as the session's polkit agent.
library;

import 'dart:async';

import 'package:dbus/dbus.dart';

import 'package:moonswing/dbus_clients.dart';
import 'package:moonswing/vpn/vpn_model.dart';

const _nmName = 'org.freedesktop.NetworkManager';
const _nmPath = '/org/freedesktop/NetworkManager';
const _nmSettingsPath = '/org/freedesktop/NetworkManager/Settings';
const _settingsIface = 'org.freedesktop.NetworkManager.Settings';
const _connectionIface = 'org.freedesktop.NetworkManager.Settings.Connection';
const _activeIface = 'org.freedesktop.NetworkManager.Connection.Active';
const _propertiesIface = 'org.freedesktop.DBus.Properties';

/// A call NetworkManager did not answer, or refused.
class VpnBackendException implements Exception {
  const VpnBackendException(this.message, {this.unavailable = false});

  final String message;

  /// Whether NetworkManager itself is missing, rather than one call refused.
  final bool unavailable;

  @override
  String toString() => message;
}

/// Something NetworkManager says moved.
sealed class VpnBackendEvent {
  const VpnBackendEvent();
}

/// A profile was added, removed or changed.
class VpnProfilesChanged extends VpnBackendEvent {
  const VpnProfilesChanged();
}

/// The set of active connections changed.
class VpnActivationsChanged extends VpnBackendEvent {
  const VpnActivationsChanged();
}

/// One active connection moved to [state], for [reason]
/// (`NMActiveConnectionStateReason`).
class VpnActivationStateChanged extends VpnBackendEvent {
  const VpnActivationStateChanged(this.activePath, this.state, this.reason);

  final String activePath;
  final int state;
  final int reason;
}

/// NetworkManager started, stopped or restarted.
class VpnServiceChanged extends VpnBackendEvent {
  const VpnServiceChanged({required this.running});

  final bool running;
}

/// What `VpnStore` needs from NetworkManager. Every call may throw a
/// [VpnBackendException].
abstract interface class VpnBackend {
  /// Every saved connection with its settings (secrets excluded).
  Future<Map<String, NmSettings>> connections();

  Future<NmSettings> settingsOf(String path);

  /// The `vpn` setting's secrets, or empty when NetworkManager will not or
  /// cannot say.
  Future<Map<String, String>> vpnSecretsOf(String path);

  Future<List<VpnActivation>> activations();

  /// Starts [connectionPath]; answers the active connection's path.
  Future<String> activate(String connectionPath);

  Future<void> deactivate(String activePath);

  /// Saves a new profile; answers its path.
  Future<String> add(NmSettings settings);

  Future<void> update(String path, NmSettings settings);

  Future<void> delete(String path);

  /// What NetworkManager reports moving, for as long as it is listened to.
  Stream<VpnBackendEvent> events();
}

class DBusVpnBackend implements VpnBackend {
  DBusVpnBackend({DBusClient? client}) : _clientOverride = client;

  final DBusClient? _clientOverride;
  DBusClient get _client => _clientOverride ?? systemBus;

  DBusRemoteObject _object(String path) =>
      DBusRemoteObject(_client, name: _nmName, path: DBusObjectPath(path));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DBusServiceUnknownException {
      throw const VpnBackendException(
        'NetworkManager is not running.',
        unavailable: true,
      );
    } on DBusAccessDeniedException catch (e) {
      throw VpnBackendException(_errorText(e, 'Not allowed.'));
    } on DBusMethodResponseException catch (e) {
      throw VpnBackendException(_errorText(e, e.errorName));
    } on DBusClosedException {
      throw const VpnBackendException(
        'The system bus connection closed.',
        unavailable: true,
      );
    }
  }

  /// NetworkManager's own sentence — "The VPN service
  /// 'org.freedesktop.NetworkManager.openvpn' was not installed." — rather
  /// than the error's name.
  static String _errorText(DBusMethodResponseException e, String fallback) {
    final values = e.response.values;
    if (values.isNotEmpty && values.first is DBusString) {
      final text = values.first.asString().trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  @override
  Future<Map<String, NmSettings>> connections() => _guard(() async {
    final reply = await _object(_nmSettingsPath).callMethod(
      _settingsIface,
      'ListConnections',
      const [],
      replySignature: DBusSignature('ao'),
    );
    final paths = reply.returnValues.first.asObjectPathArray().toList();
    final out = <String, NmSettings>{};
    await Future.wait([
      for (final path in paths)
        _readSettings(path.value).then(
          (settings) => out[path.value] = settings,
          // A profile removed between the list and the read, or one this
          // user may not read, costs that profile.
          onError: (Object _) => const <String, Map<String, DBusValue>>{},
        ),
    ]);
    return {
      for (final path in paths)
        if (out[path.value] case final s? when s.isNotEmpty) path.value: s,
    };
  });

  Future<NmSettings> _readSettings(String path) async {
    final reply = await _object(path).callMethod(
      _connectionIface,
      'GetSettings',
      const [],
      replySignature: DBusSignature('a{sa{sv}}'),
    );
    return nmSettingsFromValue(reply.returnValues.first);
  }

  @override
  Future<NmSettings> settingsOf(String path) =>
      _guard(() => _readSettings(path));

  @override
  Future<Map<String, String>> vpnSecretsOf(String path) async {
    try {
      final reply = await _object(path).callMethod(
        _connectionIface,
        'GetSecrets',
        const [DBusString('vpn')],
        replySignature: DBusSignature('a{sa{sv}}'),
      );
      final settings = nmSettingsFromValue(reply.returnValues.first);
      return nmStringMap(settings['vpn']?['secrets']);
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<List<VpnActivation>> activations() => _guard(() async {
    final value = await _object(
      _nmPath,
    ).getProperty(_nmName, 'ActiveConnections', signature: DBusSignature('ao'));
    final paths = value.asObjectPathArray().toList();
    final out = <VpnActivation?>[
      ...await Future.wait([
        for (final path in paths)
          _object(
            path.value,
          ).getAllProperties(_activeIface).then<VpnActivation?>((props) {
            final connection = props['Connection'];
            final state = props['State'];
            if (connection is! DBusObjectPath || state is! DBusUint32) {
              return null;
            }
            return VpnActivation(
              activePath: path.value,
              connectionPath: connection.value,
              state: VpnState.fromActiveState(state.value),
            );
          }, onError: (Object _) => null),
      ]),
    ];
    return out.whereType<VpnActivation>().toList(growable: false);
  });

  @override
  Future<String> activate(String connectionPath) => _guard(() async {
    final reply = await _object(_nmPath).callMethod(
      _nmName,
      'ActivateConnection',
      [
        DBusObjectPath(connectionPath),
        // "/" for both: NetworkManager picks the device a VPN rides on, and
        // creates the one a WireGuard tunnel is.
        DBusObjectPath('/'),
        DBusObjectPath('/'),
      ],
      replySignature: DBusSignature('o'),
    );
    return reply.returnValues.first.asObjectPath().value;
  });

  @override
  Future<void> deactivate(String activePath) => _guard(() async {
    await _object(_nmPath).callMethod(_nmName, 'DeactivateConnection', [
      DBusObjectPath(activePath),
    ], replySignature: DBusSignature(''));
  });

  @override
  Future<String> add(NmSettings settings) => _guard(() async {
    final reply = await _object(_nmSettingsPath).callMethod(
      _settingsIface,
      'AddConnection',
      [nmSettingsValue(settings)],
      replySignature: DBusSignature('o'),
    );
    return reply.returnValues.first.asObjectPath().value;
  });

  @override
  Future<void> update(String path, NmSettings settings) => _guard(() async {
    await _object(path).callMethod(_connectionIface, 'Update', [
      nmSettingsValue(settings),
    ], replySignature: DBusSignature(''));
  });

  @override
  Future<void> delete(String path) => _guard(() async {
    await _object(path).callMethod(
      _connectionIface,
      'Delete',
      const [],
      replySignature: DBusSignature(''),
    );
  });

  @override
  Stream<VpnBackendEvent> events() {
    late final StreamController<VpnBackendEvent> controller;
    final subs = <StreamSubscription<Object?>>[];
    void add(VpnBackendEvent e) {
      if (!controller.isClosed) controller.add(e);
    }

    // A match rule NetworkManager's absence makes moot still installs, so
    // none of these fails for a machine without it; only a dead bus does,
    // and that is the store's next call's error to report.
    void onError(Object _) {}

    controller = StreamController<VpnBackendEvent>.broadcast(
      onListen: () {
        subs
          ..add(
            DBusSignalStream(
              _client,
              sender: _nmName,
              interface: _settingsIface,
              path: DBusObjectPath(_nmSettingsPath),
            ).listen((_) => add(const VpnProfilesChanged()), onError: onError),
          )
          ..add(
            DBusSignalStream(
              _client,
              sender: _nmName,
              interface: _connectionIface,
              name: 'Updated',
            ).listen((_) => add(const VpnProfilesChanged()), onError: onError),
          )
          ..add(
            DBusSignalStream(
              _client,
              sender: _nmName,
              interface: _activeIface,
              name: 'StateChanged',
              signature: DBusSignature('uu'),
            ).listen((signal) {
              add(
                VpnActivationStateChanged(
                  signal.path.value,
                  signal.values[0].asUint32(),
                  signal.values[1].asUint32(),
                ),
              );
            }, onError: onError),
          )
          ..add(
            DBusSignalStream(
              _client,
              sender: _nmName,
              interface: _propertiesIface,
              name: 'PropertiesChanged',
              path: DBusObjectPath(_nmPath),
            ).listen((signal) {
              final changed = signal.values.length > 1
                  ? signal.values[1]
                  : null;
              if (changed is DBusDict &&
                  changed.children.containsKey(
                    const DBusString('ActiveConnections'),
                  )) {
                add(const VpnActivationsChanged());
              }
            }, onError: onError),
          )
          ..add(
            _client.nameOwnerChanged
                .where((e) => e.name == _nmName)
                .listen(
                  (e) => add(VpnServiceChanged(running: e.newOwner != null)),
                  onError: onError,
                ),
          );
      },
      onCancel: () async {
        final pending = [for (final s in subs) s.cancel()];
        subs.clear();
        await Future.wait(pending);
      },
    );
    return controller.stream;
  }
}
