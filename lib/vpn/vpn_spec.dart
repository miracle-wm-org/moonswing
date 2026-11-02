// What the pane's three forms describe, and the NetworkManager connection each
// one becomes.
//
// One builder per kind, shared by the form and by the WireGuard importer (whose
// parse produces a [WireGuardSpec]), so a typed tunnel and an imported one are
// the same profile. Validation is here too, beside the arithmetic it protects,
// so the form refuses exactly what NetworkManager would.
//
// Three decisions every builder makes the same way:
//
// * **Secrets are stored by NetworkManager** (`*-flags = 0`). The usual
//   alternative is "agent-owned", which hands every password to whichever
//   secret agent the session runs — nm-applet, GNOME Shell — and this shell is
//   not one; a profile made that way would ask nobody and fail with "no
//   secrets" on its first use. A system-owned secret lives in the profile's
//   root-only keyfile under `/etc/NetworkManager/system-connections/`.
// * **Nothing autoconnects.** NetworkManager's default for a profile is to
//   bring it up whenever it can, which for a VPN means at boot; the pane's
//   switch is how one comes up.
// * **The uuid is the caller's**, so a test can pin the dictionary.
library;

import 'dart:io' show InternetAddress, InternetAddressType;
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals;

import 'package:moonswing/vpn/vpn_model.dart';
import 'package:moonswing/vpn/x25519.dart';

/// A profile name NetworkManager will take: anything non-blank.
String? validateVpnName(String name) =>
    name.trim().isEmpty ? 'Give the VPN a name.' : null;

/// A server: a host name or address, optionally with a port.
String? validateServer(String server, {String what = 'server'}) {
  final s = server.trim();
  if (s.isEmpty) return 'Enter the $what.';
  if (s.contains(RegExp(r'\s'))) return 'The $what cannot contain spaces.';
  return null;
}

// ---------------------------------------------------------------------------
// OpenVPN
// ---------------------------------------------------------------------------

/// How an OpenVPN profile proves who it is — nm-openvpn's `connection-type`.
enum OpenVpnAuth {
  /// A client certificate and key, signed by the server's CA.
  certificates('tls', 'Certificates'),

  /// A user name and password, checked against the server's CA.
  password('password', 'Password'),

  /// Both.
  passwordCertificates('password-tls', 'Password and certificates');

  const OpenVpnAuth(this.connectionType, this.label);

  final String connectionType;
  final String label;

  bool get usesPassword => this != certificates;
  bool get usesCertificate => this != password;
}

@immutable
class OpenVpnSpec {
  const OpenVpnSpec({
    required this.name,
    required this.gateway,
    this.auth = OpenVpnAuth.password,
    this.caCert = '',
    this.userCert = '',
    this.userKey = '',
    this.keyPassword = '',
    this.username = '',
    this.password = '',
    this.tcp = false,
  });

  final String name;

  /// nm-openvpn's `remote`: a host, `host:port`, or several of them separated
  /// by commas — the plugin parses the field itself.
  final String gateway;
  final OpenVpnAuth auth;

  /// Paths. nm-openvpn reads the files when it connects, so they have to stay
  /// where they are.
  final String caCert;
  final String userCert;
  final String userKey;
  final String keyPassword;

  final String username;
  final String password;

  /// TCP rather than OpenVPN's default UDP.
  final bool tcp;

  /// The first thing wrong with the spec, or null.
  String? validate() {
    final name = validateVpnName(this.name);
    if (name != null) return name;
    final gateway = validateServer(this.gateway, what: 'gateway');
    if (gateway != null) return gateway;
    if (caCert.trim().isEmpty) {
      return 'Choose the CA certificate the server was given.';
    }
    if (auth.usesCertificate) {
      if (userCert.trim().isEmpty) return 'Choose your certificate.';
      if (userKey.trim().isEmpty) return 'Choose your private key.';
    }
    if (auth.usesPassword && username.trim().isEmpty) {
      return 'Enter your user name.';
    }
    return null;
  }

  NmSettings toSettings({required String uuid}) {
    final data = <String, String>{
      'remote': gateway.trim(),
      'connection-type': auth.connectionType,
      'ca': caCert.trim(),
      if (tcp) 'proto-tcp': 'yes',
    };
    final secrets = <String, String>{};
    if (auth.usesCertificate) {
      data['cert'] = userCert.trim();
      data['key'] = userKey.trim();
      data['cert-pass-flags'] = '0';
      if (keyPassword.isNotEmpty) secrets['cert-pass'] = keyPassword;
    }
    if (auth.usesPassword) {
      data['username'] = username.trim();
      data['password-flags'] = '0';
      if (password.isNotEmpty) secrets['password'] = password;
    }
    return _pluginSettings(
      name: name,
      uuid: uuid,
      service: kOpenVpnService,
      data: data,
      secrets: secrets,
    );
  }
}

// ---------------------------------------------------------------------------
// PPTP
// ---------------------------------------------------------------------------

@immutable
class PptpSpec {
  const PptpSpec({
    required this.name,
    required this.gateway,
    this.username = '',
    this.password = '',
    this.domain = '',
    this.mppe = true,
  });

  final String name;
  final String gateway;
  final String username;
  final String password;

  /// The NT domain, for a Windows server that wants one.
  final String domain;

  /// Require MPPE encryption. Without it the tunnel carries traffic in the
  /// clear; with it only MS-CHAPv2 can authenticate, so the weaker methods are
  /// refused alongside, as nm-pptp's own editor does.
  final bool mppe;

  String? validate() {
    final name = validateVpnName(this.name);
    if (name != null) return name;
    final gateway = validateServer(this.gateway, what: 'gateway');
    if (gateway != null) return gateway;
    if (username.trim().isEmpty) return 'Enter your user name.';
    return null;
  }

  NmSettings toSettings({required String uuid}) {
    final data = <String, String>{
      'gateway': gateway.trim(),
      'user': username.trim(),
      'password-flags': '0',
      if (domain.trim().isNotEmpty) 'domain': domain.trim(),
      if (mppe) ...{
        'require-mppe': 'yes',
        'refuse-eap': 'yes',
        'refuse-pap': 'yes',
        'refuse-chap': 'yes',
      },
    };
    return _pluginSettings(
      name: name,
      uuid: uuid,
      service: kPptpService,
      data: data,
      secrets: {if (password.isNotEmpty) 'password': password},
    );
  }
}

NmSettings _pluginSettings({
  required String name,
  required String uuid,
  required String service,
  required Map<String, String> data,
  required Map<String, String> secrets,
}) => {
  'connection': {
    'id': DBusString(name.trim()),
    'uuid': DBusString(uuid),
    'type': const DBusString('vpn'),
    'autoconnect': const DBusBoolean(false),
  },
  'vpn': {
    'service-type': DBusString(service),
    'data': nmStringDict(data),
    if (secrets.isNotEmpty) 'secrets': nmStringDict(secrets),
  },
  'ipv4': {'method': const DBusString('auto')},
  'ipv6': {'method': const DBusString('auto')},
};

/// [settings] with [password] stored in its `vpn.secrets` alongside
/// [existingSecrets], the password's flags set to "saved", and [username]
/// written where the plugin reads it when given — for a profile whose sign-in
/// failed. Null for a kind the pane does not know the secret's name for.
///
/// `Update` replaces every secret when it is given any, so the ones the profile
/// already has go back in with the new one.
NmSettings? withVpnPassword(
  NmSettings settings, {
  required VpnKind kind,
  required String password,
  String? username,
  Map<String, String> existingSecrets = const {},
}) {
  final userKey = switch (kind) {
    VpnKind.openvpn => 'username',
    VpnKind.pptp => 'user',
    _ => null,
  };
  if (userKey == null) return null;
  final out = nmCopySettings(settings);
  final vpn = out['vpn'] ??= {};
  final data = Map.of(nmStringMap(vpn['data']));
  data['password-flags'] = '0';
  if (username != null && username.trim().isNotEmpty) {
    data[userKey] = username.trim();
  }
  // A certificate-only OpenVPN profile has no password to take: move it to
  // the type that does, keeping the certificates it already names.
  if (kind == VpnKind.openvpn && data['connection-type'] == 'tls') {
    data['connection-type'] = 'password-tls';
  }
  vpn['data'] = nmStringDict(data);
  vpn['secrets'] = nmStringDict({...existingSecrets, 'password': password});
  return out;
}

// ---------------------------------------------------------------------------
// WireGuard
// ---------------------------------------------------------------------------

/// An address with a prefix length: `10.0.0.2/32`, `fd00::2/128`.
@immutable
class IpPrefix {
  const IpPrefix(this.address, this.prefix);

  final InternetAddress address;
  final int prefix;

  bool get isV4 => address.type == InternetAddressType.IPv4;

  /// Whether it is everything in its family — a default route.
  bool get isDefault => prefix == 0;

  /// Parses `addr[/prefix]`; a bare address is a single host. Null for anything
  /// else.
  static IpPrefix? tryParse(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final slash = t.indexOf('/');
    final addr = InternetAddress.tryParse(
      slash < 0 ? t : t.substring(0, slash),
    );
    if (addr == null) return null;
    final max = addr.type == InternetAddressType.IPv4 ? 32 : 128;
    if (slash < 0) return IpPrefix(addr, max);
    final prefix = int.tryParse(t.substring(slash + 1));
    if (prefix == null || prefix < 0 || prefix > max) return null;
    return IpPrefix(addr, prefix);
  }

  @override
  String toString() => '${address.address}/$prefix';

  @override
  bool operator ==(Object other) =>
      other is IpPrefix && other.address == address && other.prefix == prefix;

  @override
  int get hashCode => Object.hash(address, prefix);
}

/// Splits a WireGuard list — `a, b,c` — into its items.
List<String> splitWireGuardList(String text) => [
  for (final part in text.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

/// A `host:port` endpoint, `[v6]:port` for an IPv6 address. The host may be a
/// name; the port is required, as WireGuard has no default.
String? validateEndpoint(String endpoint) {
  final e = endpoint.trim();
  if (e.isEmpty) return null;
  final String port;
  if (e.startsWith('[')) {
    final close = e.indexOf(']');
    if (close < 0 || close + 1 >= e.length || e[close + 1] != ':') {
      return 'Write an IPv6 endpoint as [address]:port.';
    }
    port = e.substring(close + 2);
  } else {
    final colon = e.lastIndexOf(':');
    if (colon <= 0) return 'The endpoint needs a port: host:port.';
    if (e.indexOf(':') != colon) {
      return 'Write an IPv6 endpoint as [address]:port.';
    }
    port = e.substring(colon + 1);
  }
  final n = int.tryParse(port);
  if (n == null || n < 1 || n > 65535) {
    return 'The endpoint\'s port must be between 1 and 65535.';
  }
  return null;
}

@immutable
class WireGuardPeerSpec {
  const WireGuardPeerSpec({
    required this.publicKey,
    this.presharedKey = '',
    this.endpoint = '',
    this.allowedIps = const [],
    this.persistentKeepalive,
  });

  final String publicKey;
  final String presharedKey;
  final String endpoint;

  /// As written: each a prefix [IpPrefix.tryParse] accepts.
  final List<String> allowedIps;
  final int? persistentKeepalive;

  String? validate(int index, int count) {
    final who = count > 1 ? 'Peer ${index + 1}' : 'The peer';
    if (!isWireGuardKey(publicKey)) {
      return '$who\'s public key is not a WireGuard key.';
    }
    if (presharedKey.trim().isNotEmpty && !isWireGuardKey(presharedKey)) {
      return '$who\'s preshared key is not a WireGuard key.';
    }
    final endpoint = validateEndpoint(this.endpoint);
    if (endpoint != null) return '$who: $endpoint';
    if (allowedIps.isEmpty) {
      return '$who needs at least one allowed IP range (0.0.0.0/0 sends '
          'everything through it).';
    }
    for (final ip in allowedIps) {
      if (IpPrefix.tryParse(ip) == null) {
        return '$who: "$ip" is not an address range.';
      }
    }
    final keepalive = persistentKeepalive;
    if (keepalive != null && (keepalive < 0 || keepalive > 65535)) {
      return '$who\'s keepalive must be between 0 and 65535 seconds.';
    }
    return null;
  }

  DBusDict toValue() => nmVariantDict({
    'public-key': DBusString(publicKey.trim()),
    if (presharedKey.trim().isNotEmpty) ...{
      'preshared-key': DBusString(presharedKey.trim()),
      'preshared-key-flags': const DBusUint32(0),
    },
    if (endpoint.trim().isNotEmpty) 'endpoint': DBusString(endpoint.trim()),
    'allowed-ips': DBusArray.string([
      for (final ip in allowedIps) IpPrefix.tryParse(ip)?.toString() ?? ip,
    ]),
    if (persistentKeepalive != null && persistentKeepalive! > 0)
      'persistent-keepalive': DBusUint32(persistentKeepalive!),
  });

  @override
  bool operator ==(Object other) =>
      other is WireGuardPeerSpec &&
      other.publicKey == publicKey &&
      other.presharedKey == presharedKey &&
      other.endpoint == endpoint &&
      listEquals(other.allowedIps, allowedIps) &&
      other.persistentKeepalive == persistentKeepalive;

  @override
  int get hashCode => Object.hash(
    publicKey,
    presharedKey,
    endpoint,
    Object.hashAll(allowedIps),
    persistentKeepalive,
  );
}

/// The most a Linux interface name can be: `IFNAMSIZ` less the terminator.
const int kMaxInterfaceName = 15;

/// Whether [name] is a usable Linux interface name.
bool isValidInterfaceName(String name) =>
    name.isNotEmpty &&
    name.length <= kMaxInterfaceName &&
    name != '.' &&
    name != '..' &&
    RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(name);

/// An interface name for a tunnel called [name] that none of [taken] has:
/// `wg-` and the name's letters and digits, then a number while it collides.
String wireGuardInterfaceFor(String name, Iterable<String> taken) {
  final used = taken.toSet();
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  var base = slug.isEmpty ? 'wg' : 'wg-$slug';
  if (base.length > kMaxInterfaceName) {
    base = base.substring(0, kMaxInterfaceName).replaceAll(RegExp(r'-+$'), '');
  }
  if (!used.contains(base)) return base;
  for (var n = 2; ; n++) {
    final suffix = '$n';
    final stem = base.length + suffix.length > kMaxInterfaceName
        ? base.substring(0, kMaxInterfaceName - suffix.length)
        : base;
    final candidate = '$stem$suffix';
    if (!used.contains(candidate)) return candidate;
  }
}

@immutable
class WireGuardSpec {
  const WireGuardSpec({
    required this.name,
    required this.interfaceName,
    required this.privateKey,
    this.addresses = const [],
    this.dns = const [],
    this.listenPort,
    this.mtu,
    this.fwmark,
    this.routeTable,
    this.peerRoutes = true,
    this.peers = const [],
  });

  final String name;
  final String interfaceName;
  final String privateKey;

  /// The tunnel's own addresses, as written.
  final List<String> addresses;

  /// Name servers and, for anything that is not an address, search domains —
  /// wg-quick's `DNS =` takes both in one list.
  final List<String> dns;
  final int? listenPort;
  final int? mtu;
  final int? fwmark;

  /// wg-quick's `Table =` as a number, for a table other than the main one.
  final int? routeTable;

  /// Whether NetworkManager adds a route for each peer's allowed IPs —
  /// wg-quick's default, and off for `Table = off`.
  final bool peerRoutes;
  final List<WireGuardPeerSpec> peers;

  String? validate() {
    final name = validateVpnName(this.name);
    if (name != null) return name;
    if (!isValidInterfaceName(interfaceName)) {
      return 'The interface name must be 1 to $kMaxInterfaceName letters, '
          'digits, dots, dashes or underscores.';
    }
    if (!isWireGuardKey(privateKey)) {
      return 'The private key is not a WireGuard key — generate one, or paste '
          'the 44-character key you were given.';
    }
    if (addresses.isEmpty) {
      return 'Enter the tunnel\'s address, such as 10.0.0.2/32.';
    }
    for (final a in addresses) {
      if (IpPrefix.tryParse(a) == null) return '"$a" is not an address.';
    }
    final port = listenPort;
    if (port != null && (port < 0 || port > 65535)) {
      return 'The listen port must be between 0 and 65535.';
    }
    final mtu = this.mtu;
    if (mtu != null && (mtu < 0 || mtu > 65535)) {
      return 'The MTU must be between 0 and 65535.';
    }
    if (peers.isEmpty) return 'Add the server as a peer.';
    for (var i = 0; i < peers.length; i++) {
      final peer = peers[i].validate(i, peers.length);
      if (peer != null) return peer;
    }
    return null;
  }

  NmSettings toSettings({required String uuid}) {
    final parsed = [
      for (final a in addresses) IpPrefix.tryParse(a),
    ].whereType<IpPrefix>().toList();
    final servers = <InternetAddress>[];
    final searches = <String>[];
    for (final entry in dns) {
      final addr = InternetAddress.tryParse(entry);
      if (addr != null) {
        servers.add(addr);
      } else {
        searches.add(entry);
      }
    }
    final routes = [
      for (final peer in peers)
        for (final ip in peer.allowedIps) IpPrefix.tryParse(ip),
    ].whereType<IpPrefix>();

    Map<String, DBusValue> family({required bool v4}) {
      final own = [
        for (final p in parsed)
          if (p.isV4 == v4) p,
      ];
      final ns = [
        for (final s in servers)
          if ((s.type == InternetAddressType.IPv4) == v4) s,
      ];
      final ip = <String, DBusValue>{
        'method': DBusString(
          own.isNotEmpty ? 'manual' : (v4 ? 'disabled' : 'ignore'),
        ),
      };
      if (own.isNotEmpty) {
        ip['address-data'] = DBusArray(DBusSignature('a{sv}'), [
          for (final p in own)
            nmVariantDict({
              'address': DBusString(p.address.address),
              'prefix': DBusUint32(p.prefix),
            }),
        ]);
      }
      if (ns.isNotEmpty) {
        ip['dns'] = v4
            ? DBusArray.uint32([for (final s in ns) _inAddrValue(s)])
            : DBusArray(DBusSignature('ay'), [
                for (final s in ns) DBusArray.byte(s.rawAddress),
              ]);
        final everything = routes.any((r) => r.isV4 == v4 && r.isDefault);
        // A tunnel that carries everything carries the lookups too, as
        // wg-quick's resolv.conf rewrite does: `~` routes every domain to
        // these servers and the negative priority keeps the others out.
        final search = [...searches, if (everything) '~'];
        if (search.isNotEmpty) ip['dns-search'] = DBusArray.string(search);
        if (everything) ip['dns-priority'] = const DBusInt32(-50);
      } else if (searches.isNotEmpty && own.isNotEmpty) {
        ip['dns-search'] = DBusArray.string(searches);
      }
      if (routeTable != null) ip['route-table'] = DBusUint32(routeTable!);
      return ip;
    }

    return {
      'connection': {
        'id': DBusString(name.trim()),
        'uuid': DBusString(uuid),
        'type': const DBusString('wireguard'),
        'interface-name': DBusString(interfaceName),
        'autoconnect': const DBusBoolean(false),
      },
      'wireguard': {
        'private-key': DBusString(privateKey.trim()),
        'private-key-flags': const DBusUint32(0),
        if (listenPort != null && listenPort! > 0)
          'listen-port': DBusUint32(listenPort!),
        if (mtu != null && mtu! > 0) 'mtu': DBusUint32(mtu!),
        if (fwmark != null && fwmark! > 0) 'fwmark': DBusUint32(fwmark!),
        if (!peerRoutes) 'peer-routes': const DBusBoolean(false),
        'peers': DBusArray(DBusSignature('a{sv}'), [
          for (final peer in peers) peer.toValue(),
        ]),
      },
      'ipv4': family(v4: true),
      'ipv6': family(v4: false),
    };
  }

  WireGuardSpec copyWith({String? name, String? interfaceName}) =>
      WireGuardSpec(
        name: name ?? this.name,
        interfaceName: interfaceName ?? this.interfaceName,
        privateKey: privateKey,
        addresses: addresses,
        dns: dns,
        listenPort: listenPort,
        mtu: mtu,
        fwmark: fwmark,
        routeTable: routeTable,
        peerRoutes: peerRoutes,
        peers: peers,
      );
}

/// An IPv4 address as `ipv4.dns` carries it: a `u` whose bytes, in this
/// machine's order, are the address in network order — an `in_addr_t`.
int _inAddrValue(InternetAddress address) {
  final raw = address.rawAddress;
  final bytes = ByteData(4);
  for (var i = 0; i < 4; i++) {
    bytes.setUint8(i, raw[i]);
  }
  return bytes.getUint32(0, Endian.host);
}
