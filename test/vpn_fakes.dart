// A NetworkManager in memory, for the VPN store and pane tests.

import 'dart:async';

import 'package:moonswing/vpn/libnm_import.dart';
import 'package:moonswing/vpn/nm_vpn_client.dart';
import 'package:moonswing/vpn/vpn_model.dart';
import 'package:moonswing/vpn/vpn_plugins.dart';

class FakeVpnBackend implements VpnBackend {
  final Map<String, NmSettings> saved = {};
  final Map<String, Map<String, String>> secrets = {};

  /// connection path → (active path, NMActiveConnectionState).
  final Map<String, (String, int)> active = {};

  final List<String> calls = [];

  /// Set to make every call fail as NetworkManager being absent would.
  bool down = false;

  /// What `ActivateConnection` refuses with, when set.
  String? refuseActivate;

  /// Whether activation lands at once (2) or stays activating (1).
  int activateTo = 2;

  int _next = 1;
  final StreamController<VpnBackendEvent> _events =
      StreamController.broadcast();

  bool get listening => _events.hasListener;

  void emit(VpnBackendEvent e) => _events.add(e);

  void _check() {
    if (down) {
      throw const VpnBackendException(
        'NetworkManager is not running.',
        unavailable: true,
      );
    }
  }

  String put(NmSettings settings) {
    final path = '/org/freedesktop/NetworkManager/Settings/${_next++}';
    saved[path] = settings;
    return path;
  }

  @override
  Future<Map<String, NmSettings>> connections() async {
    _check();
    calls.add('connections');
    return Map.of(saved);
  }

  @override
  Future<NmSettings> settingsOf(String path) async {
    _check();
    final s = saved[path];
    if (s == null) throw const VpnBackendException('No such connection.');
    // GetSettings never carries secrets.
    final copy = nmCopySettings(s);
    copy['vpn']?.remove('secrets');
    return copy;
  }

  @override
  Future<Map<String, String>> vpnSecretsOf(String path) async =>
      secrets[path] ?? const {};

  @override
  Future<List<VpnActivation>> activations() async {
    _check();
    calls.add('activations');
    return [
      for (final e in active.entries)
        VpnActivation(
          activePath: e.value.$1,
          connectionPath: e.key,
          state: VpnState.fromActiveState(e.value.$2),
        ),
    ];
  }

  @override
  Future<String> activate(String connectionPath) async {
    _check();
    calls.add('activate $connectionPath');
    final refusal = refuseActivate;
    if (refusal != null) throw VpnBackendException(refusal);
    final activePath =
        '/org/freedesktop/NetworkManager/ActiveConnection/'
        '${_next++}';
    active[connectionPath] = (activePath, activateTo);
    return activePath;
  }

  @override
  Future<void> deactivate(String activePath) async {
    _check();
    calls.add('deactivate $activePath');
    active.removeWhere((_, v) => v.$1 == activePath);
  }

  @override
  Future<String> add(NmSettings settings) async {
    _check();
    calls.add('add');
    return put(settings);
  }

  @override
  Future<void> update(String path, NmSettings settings) async {
    _check();
    calls.add('update $path');
    saved[path] = settings;
  }

  @override
  Future<void> delete(String path) async {
    _check();
    calls.add('delete $path');
    saved.remove(path);
    active.remove(path);
  }

  @override
  Stream<VpnBackendEvent> events() => _events.stream;
}

class FakeImporter implements VpnPluginImporter {
  FakeImporter(this.result);

  NmSettings Function(String path) result;
  final List<String> paths = [];

  @override
  NmSettings importFile(String path, List<VpnPluginInfo> plugins) {
    paths.add(path);
    return result(path);
  }
}

const VpnPluginInfo fakeOpenVpnPlugin = VpnPluginInfo(
  file: '/usr/lib/NetworkManager/VPN/nm-openvpn-service.name',
  name: 'openvpn',
  service: kOpenVpnService,
  libnmPlugin: 'libnm-vpn-plugin-openvpn.so',
);
