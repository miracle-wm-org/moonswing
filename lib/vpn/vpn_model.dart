// The VPNs NetworkManager keeps, as Settings › Network draws them.
//
// NetworkManager is the store. Every VPN the pane lists is one of its saved
// connections — `type=vpn` (a plugin's: OpenVPN, PPTP, and whatever else is
// installed and was imported) or `type=wireguard` (the kernel's, which needs no
// plugin) — so a profile added with `nmcli`, nm-applet or another desktop's
// settings shows up here, and one added here shows up there. The shell keeps no
// list of its own.
//
// Flutter-free and I/O-free: a connection's settings arrive as the
// `a{sa{sv}}` dictionary NetworkManager speaks over D-Bus, and everything here
// is a reading of it, so a test builds one by hand.
library;

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show immutable;

/// A connection's settings: setting name → property → value, exactly as
/// `org.freedesktop.NetworkManager.Settings.Connection.GetSettings` answers.
typedef NmSettings = Map<String, Map<String, DBusValue>>;

/// NetworkManager's service name for a VPN plugin.
const String kOpenVpnService = 'org.freedesktop.NetworkManager.openvpn';
const String kPptpService = 'org.freedesktop.NetworkManager.pptp';

/// The kinds of VPN the pane can make. Anything else NetworkManager has — an
/// imported OpenConnect, L2TP or strongSwan profile — is [other], listed and
/// toggled like the rest but not built from a form here.
enum VpnKind {
  openvpn('OpenVPN'),
  pptp('PPTP'),
  wireguard('WireGuard'),
  other('VPN');

  const VpnKind(this.label);

  final String label;
}

/// Where a profile is in NetworkManager's activation of it.
enum VpnState {
  disconnected,
  connecting,
  connected,
  disconnecting;

  /// What the switch shows: on for anything on its way up or already up.
  bool get on => this == connecting || this == connected;

  /// `NMActiveConnectionState`: 0 unknown, 1 activating, 2 activated,
  /// 3 deactivating, 4 deactivated.
  static VpnState fromActiveState(int state) => switch (state) {
    1 => VpnState.connecting,
    2 => VpnState.connected,
    3 => VpnState.disconnecting,
    _ => VpnState.disconnected,
  };
}

/// `NMActiveConnectionStateReason`, worded for someone looking at a switch
/// that just turned itself off. Null for the reasons that are not a failure —
/// the user turned it off, or the profile went away.
String? vpnFailureReason(int reason) => switch (reason) {
  // 0 unknown is still a failure: something ended the connection and did not
  // say what.
  0 => 'The connection ended for an unknown reason.',
  1 || 2 || 11 => null,
  3 => 'The network underneath it went away.',
  4 => 'The VPN service stopped.',
  5 => 'The server sent addresses that could not be used.',
  6 => 'The server did not answer in time.',
  7 => 'The VPN service did not start in time.',
  8 => 'The VPN service could not be started.',
  9 => 'A password or key is needed and none is saved.',
  10 => 'The server refused the sign-in.',
  12 => 'A connection it depends on failed.',
  13 => 'The tunnel device could not be created.',
  14 => 'The tunnel device was removed.',
  _ => 'The connection failed (reason $reason).',
};

/// Whether [reason] is one a new password could fix — no secrets, or a refused
/// login — which is when the pane offers to set one.
bool vpnReasonWantsPassword(int reason) => reason == 9 || reason == 10;

/// One saved VPN.
@immutable
class VpnProfile {
  const VpnProfile({
    required this.path,
    required this.uuid,
    required this.name,
    required this.kind,
    this.serviceType = '',
    this.server = '',
    this.interfaceName = '',
  });

  /// The connection's D-Bus object path, under
  /// `/org/freedesktop/NetworkManager/Settings/`.
  final String path;
  final String uuid;
  final String name;
  final VpnKind kind;

  /// The plugin's service name for a `type=vpn` profile; empty for WireGuard.
  final String serviceType;

  /// Where it connects to, as the profile says: OpenVPN's `remote`, PPTP's
  /// `gateway`, the first WireGuard peer's endpoint. Empty when it says nothing.
  final String server;

  /// WireGuard's `connection.interface-name`, which must be unique on the
  /// machine; empty for a plugin VPN.
  final String interfaceName;

  /// What the row says the profile is: its kind, or for a plugin the pane has
  /// no form for, the plugin's own short name (`openconnect`, `l2tp`).
  String get kindLabel {
    if (kind != VpnKind.other) return kind.label;
    final dot = serviceType.lastIndexOf('.');
    final short = dot < 0 ? serviceType : serviceType.substring(dot + 1);
    return short.isEmpty ? kind.label : short;
  }

  /// Whether the pane can set a password on it: the two plugins whose secret
  /// it knows the name of.
  bool get takesPassword => kind == VpnKind.openvpn || kind == VpnKind.pptp;

  /// Reads one connection, or null for one that is not a VPN.
  static VpnProfile? fromSettings(String path, NmSettings settings) {
    final connection = settings['connection'];
    if (connection == null) return null;
    final type = nmString(connection['type']);
    final uuid = nmString(connection['uuid']);
    final id = nmString(connection['id']);
    switch (type) {
      case 'wireguard':
        final peers = settings['wireguard']?['peers'];
        var endpoint = '';
        if (peers is DBusArray) {
          for (final peer in peers.children) {
            if (peer is! DBusDict) continue;
            final e = nmString(peer.children[const DBusString('endpoint')]);
            if (e.isNotEmpty) {
              endpoint = e;
              break;
            }
          }
        }
        return VpnProfile(
          path: path,
          uuid: uuid,
          name: id.isEmpty ? 'WireGuard' : id,
          kind: VpnKind.wireguard,
          server: endpoint,
          interfaceName: nmString(connection['interface-name']),
        );
      case 'vpn':
        final vpn = settings['vpn'] ?? const {};
        final service = nmString(vpn['service-type']);
        final data = nmStringMap(vpn['data']);
        final kind = vpnKindOfService(service);
        final server = switch (kind) {
          VpnKind.openvpn => data['remote'] ?? '',
          _ => data['gateway'] ?? data['remote'] ?? '',
        };
        return VpnProfile(
          path: path,
          uuid: uuid,
          name: id.isEmpty ? kind.label : id,
          kind: kind,
          serviceType: service,
          server: server,
        );
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VpnProfile &&
      other.path == path &&
      other.uuid == uuid &&
      other.name == name &&
      other.kind == kind &&
      other.serviceType == serviceType &&
      other.server == server &&
      other.interfaceName == interfaceName;

  @override
  int get hashCode =>
      Object.hash(path, uuid, name, kind, serviceType, server, interfaceName);
}

/// The kind a plugin service name belongs to. A plugin may be registered under
/// an alias (`openvpn` alone, from an old profile), so the suffix decides.
VpnKind vpnKindOfService(String service) {
  final s = service.toLowerCase();
  if (s == kOpenVpnService || s.endsWith('.openvpn') || s == 'openvpn') {
    return VpnKind.openvpn;
  }
  if (s == kPptpService || s.endsWith('.pptp') || s == 'pptp') {
    return VpnKind.pptp;
  }
  return VpnKind.other;
}

/// One active connection NetworkManager reports, reduced to what decides a
/// switch.
@immutable
class VpnActivation {
  const VpnActivation({
    required this.activePath,
    required this.connectionPath,
    required this.state,
  });

  final String activePath;
  final String connectionPath;
  final VpnState state;

  @override
  bool operator ==(Object other) =>
      other is VpnActivation &&
      other.activePath == activePath &&
      other.connectionPath == connectionPath &&
      other.state == state;

  @override
  int get hashCode => Object.hash(activePath, connectionPath, state);
}

// ---------------------------------------------------------------------------
// Reading and writing the D-Bus dictionary
// ---------------------------------------------------------------------------

/// [value] as a string, through any variant wrapping; empty when it is not one.
String nmString(DBusValue? value) {
  var v = value;
  while (v is DBusVariant) {
    v = v.value;
  }
  return v is DBusString ? v.value : '';
}

/// A `a{ss}` (a plugin's `vpn.data` or `vpn.secrets`) as a map, dropping any
/// entry that is not a string pair; empty when it is not a dictionary at all.
Map<String, String> nmStringMap(DBusValue? value) {
  var v = value;
  while (v is DBusVariant) {
    v = v.value;
  }
  if (v is! DBusDict) return const {};
  return {
    for (final e in v.children.entries)
      if (e.key is DBusString) (e.key as DBusString).value: nmString(e.value),
  };
}

/// `a{ss}`.
DBusDict nmStringDict(Map<String, String> map) => DBusDict(
  DBusSignature('s'),
  DBusSignature('s'),
  {for (final e in map.entries) DBusString(e.key): DBusString(e.value)},
);

/// `a{sv}`.
DBusDict nmVariantDict(Map<String, DBusValue> map) =>
    DBusDict.stringVariant(map);

/// [settings] as the `a{sa{sv}}` `AddConnection` and `Update` take.
DBusDict nmSettingsValue(NmSettings settings) =>
    DBusDict(DBusSignature('s'), DBusSignature('a{sv}'), {
      for (final section in settings.entries)
        DBusString(section.key): nmVariantDict(section.value),
    });

/// The `a{sa{sv}}` `GetSettings` answers, as [NmSettings]. A section or
/// property that is not shaped as the signature says is dropped, not thrown on.
NmSettings nmSettingsFromValue(DBusValue value) {
  if (value is! DBusDict) return {};
  final out = <String, Map<String, DBusValue>>{};
  for (final section in value.children.entries) {
    final name = section.key;
    final body = section.value;
    if (name is! DBusString || body is! DBusDict) continue;
    final props = <String, DBusValue>{};
    for (final prop in body.children.entries) {
      final key = prop.key;
      if (key is! DBusString) continue;
      final v = prop.value;
      props[key.value] = v is DBusVariant ? v.value : v;
    }
    out[name.value] = props;
  }
  return out;
}

/// A deep copy of [settings] whose sections can be written to.
NmSettings nmCopySettings(NmSettings settings) => {
  for (final e in settings.entries) e.key: Map.of(e.value),
};
