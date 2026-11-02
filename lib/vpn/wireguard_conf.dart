// wg-quick's configuration file, read into a [WireGuardSpec].
//
// NetworkManager has no import of its own over D-Bus — `nmcli connection
// import type wireguard` does it inside nmcli, in a library nothing else links —
// so this is the same reading, in Dart, of the format every WireGuard provider
// hands out: an `[Interface]` and one `[Peer]` per server.
//
// Degrades per line, as every reader of outside data in the shell does: a key
// NetworkManager has no equivalent for (`PostUp`, `SaveConfig`) is reported and
// skipped, never a reason to refuse the file. Only a file with no private key,
// or a value that cannot mean anything (`ListenPort = banana`), is refused,
// since the profile built without it would not be the tunnel the file
// describes.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'package:moonswing/vpn/vpn_spec.dart';

/// A parsed file: the tunnel, and what of the file it could not carry.
@immutable
class WireGuardImport {
  const WireGuardImport(this.spec, this.warnings);

  final WireGuardSpec spec;

  /// One line per thing left out, worded for the user.
  final List<String> warnings;
}

/// Whether [text] reads as a wg-quick file rather than, say, an OpenVPN one —
/// an `[Interface]` heading and a private key in it.
bool looksLikeWireGuardConf(String text) {
  var interface = false;
  var key = false;
  for (final raw in text.split('\n')) {
    final line = _stripComment(raw).trim().toLowerCase();
    if (line == '[interface]') interface = true;
    if (line.startsWith('privatekey') && line.contains('=')) key = true;
  }
  return interface && key;
}

String _stripComment(String line) {
  final hash = line.indexOf('#');
  return hash < 0 ? line : line.substring(0, hash);
}

/// The file's name without its directory or `.conf` — wg-quick's interface
/// name, and the profile's name.
String wireGuardBaseName(String path) {
  var name = path;
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  if (name.toLowerCase().endsWith('.conf')) {
    name = name.substring(0, name.length - 5);
  }
  return name;
}

/// Parses a wg-quick file found at [path] (whose name names the tunnel).
/// [takenInterfaces] are the interface names other WireGuard profiles already
/// use. Throws a [FormatException] for a file that does not describe a tunnel.
WireGuardImport parseWireGuardConf(
  String text, {
  required String path,
  Iterable<String> takenInterfaces = const [],
}) {
  final warnings = <String>[];
  String? section;
  String? privateKey;
  final addresses = <String>[];
  final dns = <String>[];
  int? listenPort;
  int? mtu;
  int? fwmark;
  int? table;
  var peerRoutes = true;
  final peers = <_PeerBuilder>[];
  final scripts = <String>{};

  int number(String key, String value, {bool allowOff = false}) {
    if (allowOff && value.toLowerCase() == 'off') return 0;
    final v = value.toLowerCase();
    final n = v.startsWith('0x')
        ? int.tryParse(v.substring(2), radix: 16)
        : int.tryParse(v);
    if (n == null || n < 0) {
      throw FormatException('$key = $value is not a number.');
    }
    return n;
  }

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = _stripComment(lines[i]).trim();
    if (line.isEmpty) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      section = line.substring(1, line.length - 1).trim().toLowerCase();
      if (section == 'peer') {
        peers.add(_PeerBuilder());
      } else if (section != 'interface') {
        warnings.add('Skipped the unknown section [$section].');
      }
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0) {
      warnings.add('Skipped line ${i + 1}, which is not "Key = Value".');
      continue;
    }
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    final k = key.toLowerCase();
    if (section == 'interface') {
      switch (k) {
        case 'privatekey':
          privateKey = value;
        case 'address':
          addresses.addAll(splitWireGuardList(value));
        case 'dns':
          dns.addAll(splitWireGuardList(value));
        case 'listenport':
          listenPort = number(key, value);
        case 'mtu':
          mtu = number(key, value);
        case 'fwmark':
          fwmark = number(key, value, allowOff: true);
        case 'table':
          final t = value.toLowerCase();
          if (t == 'off') {
            peerRoutes = false;
          } else if (t != 'auto' && t != 'main') {
            table = number(key, value);
          }
        case 'preup' || 'postup' || 'predown' || 'postdown':
          scripts.add(key);
        case 'saveconfig':
          // wg-quick writing the running state back into the file has no
          // meaning for a profile NetworkManager owns.
          break;
        default:
          warnings.add(
            'Skipped $key, which NetworkManager has no setting for.',
          );
      }
    } else if (section == 'peer') {
      final peer = peers.last;
      switch (k) {
        case 'publickey':
          peer.publicKey = value;
        case 'presharedkey':
          peer.presharedKey = value;
        case 'endpoint':
          peer.endpoint = value;
        case 'allowedips':
          peer.allowedIps.addAll(splitWireGuardList(value));
        case 'persistentkeepalive':
          peer.keepalive = number(key, value, allowOff: true);
        default:
          warnings.add(
            'Skipped $key, which NetworkManager has no setting for.',
          );
      }
    } else {
      warnings.add('Skipped $key, which is outside any section.');
    }
  }

  if (privateKey == null || privateKey.isEmpty) {
    throw const FormatException(
      'This is not a WireGuard configuration: it has no PrivateKey.',
    );
  }
  if (scripts.isNotEmpty) {
    final list = (scripts.toList()..sort()).join(', ');
    warnings.add(
      'Skipped $list: NetworkManager does not run commands when a tunnel '
      'goes up or down.',
    );
  }

  final base = wireGuardBaseName(path);
  final name = base.isEmpty ? 'WireGuard' : base;
  final taken = takenInterfaces.toSet();
  final interfaceName = isValidInterfaceName(base) && !taken.contains(base)
      ? base
      : wireGuardInterfaceFor(name, taken);

  return WireGuardImport(
    WireGuardSpec(
      name: name,
      interfaceName: interfaceName,
      privateKey: privateKey,
      addresses: addresses,
      dns: dns,
      listenPort: listenPort,
      mtu: mtu,
      fwmark: fwmark,
      routeTable: table,
      peerRoutes: peerRoutes,
      peers: [for (final p in peers) p.build()],
    ),
    warnings,
  );
}

class _PeerBuilder {
  String publicKey = '';
  String presharedKey = '';
  String endpoint = '';
  final List<String> allowedIps = [];
  int? keepalive;

  WireGuardPeerSpec build() => WireGuardPeerSpec(
    publicKey: publicKey,
    presharedKey: presharedKey,
    endpoint: endpoint,
    allowedIps: List.unmodifiable(allowedIps),
    persistentKeepalive: keepalive,
  );
}
