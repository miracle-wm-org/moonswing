// The pure half of the VPN pane: X25519, the form specs and the dictionaries
// they become, the WireGuard reader, the plugin registry, and the reading of a
// NetworkManager profile back into a row.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/vpn/vpn_model.dart';
import 'package:moonswing/vpn/vpn_plugins.dart';
import 'package:moonswing/vpn/vpn_spec.dart';
import 'package:moonswing/vpn/wireguard_conf.dart';
import 'package:moonswing/vpn/x25519.dart';

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Two valid keys, from RFC 7748 §6.1.
final _alicePrivate = base64.encode(
  _hex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'),
);
final _bobPublic = base64.encode(
  _hex('de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f'),
);

Map<String, String> _data(NmSettings s) => nmStringMap(s['vpn']!['data']);
Map<String, String> _secrets(NmSettings s) => nmStringMap(s['vpn']!['secrets']);

void main() {
  group('X25519', () {
    test('RFC 7748 §5.2 test vector', () {
      final out = x25519(
        _hex(
          'a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4',
        ),
        _hex(
          'e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c',
        ),
      );
      expect(
        _toHex(out),
        'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552',
      );
    });

    test('RFC 7748 §6.1 key pairs and shared secret', () {
      final alice = _hex(
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
      );
      final bob = _hex(
        '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb',
      );
      expect(
        _toHex(x25519PublicKey(alice)),
        '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a',
      );
      expect(
        _toHex(x25519PublicKey(bob)),
        'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f',
      );
      final shared = x25519(alice, x25519PublicKey(bob));
      expect(
        _toHex(shared),
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742',
      );
      expect(_toHex(x25519(bob, x25519PublicKey(alice))), _toHex(shared));
    });

    test('WireGuard keys in base64', () {
      expect(isWireGuardKey(_alicePrivate), isTrue);
      expect(isWireGuardKey('not a key'), isFalse);
      // 31 bytes is not a key, however it is padded.
      expect(isWireGuardKey(base64.encode(List.filled(31, 1))), isFalse);
      expect(
        wireGuardPublicKey(_alicePrivate),
        base64.encode(
          _hex(
            '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a',
          ),
        ),
      );
      expect(wireGuardPublicKey('garbage'), isNull);
    });

    test('a generated key is clamped and has a public half', () {
      final key = generateWireGuardPrivateKey();
      final bytes = decodeWireGuardKey(key)!;
      expect(bytes[0] & 7, 0);
      expect(bytes[31] & 0x80, 0);
      expect(bytes[31] & 0x40, 0x40);
      expect(wireGuardPublicKey(key), isNotNull);
    });
  });

  group('OpenVPN', () {
    test('password sign-in stores the password with NetworkManager', () {
      const spec = OpenVpnSpec(
        name: ' Office ',
        gateway: 'vpn.example.com:443',
        caCert: '/home/u/ca.crt',
        username: 'ada',
        password: 'hunter2',
        tcp: true,
      );
      expect(spec.validate(), isNull);
      final s = spec.toSettings(uuid: 'u-1');
      expect(s['connection']!['id'], const DBusString('Office'));
      expect(s['connection']!['type'], const DBusString('vpn'));
      expect(s['connection']!['uuid'], const DBusString('u-1'));
      expect(s['connection']!['autoconnect'], const DBusBoolean(false));
      expect(s['vpn']!['service-type'], const DBusString(kOpenVpnService));
      expect(_data(s), {
        'remote': 'vpn.example.com:443',
        'connection-type': 'password',
        'ca': '/home/u/ca.crt',
        'proto-tcp': 'yes',
        'username': 'ada',
        'password-flags': '0',
      });
      expect(_secrets(s), {'password': 'hunter2'});
    });

    test('certificates need a certificate and a key', () {
      const missing = OpenVpnSpec(
        name: 'x',
        gateway: 'h',
        auth: OpenVpnAuth.certificates,
        caCert: '/ca',
      );
      expect(missing.validate(), contains('certificate'));
      const spec = OpenVpnSpec(
        name: 'x',
        gateway: 'h',
        auth: OpenVpnAuth.certificates,
        caCert: '/ca',
        userCert: '/c',
        userKey: '/k',
      );
      expect(spec.validate(), isNull);
      final s = spec.toSettings(uuid: 'u');
      expect(_data(s)['connection-type'], 'tls');
      expect(_data(s)['cert'], '/c');
      expect(_data(s)['key'], '/k');
      expect(_data(s).containsKey('username'), isFalse);
      // No secrets at all: no empty dictionary sent either.
      expect(s['vpn']!.containsKey('secrets'), isFalse);
    });

    test('refuses a spec missing what the plugin needs', () {
      expect(
        const OpenVpnSpec(name: '', gateway: 'h', caCert: '/ca').validate(),
        isNotNull,
      );
      expect(
        const OpenVpnSpec(name: 'x', gateway: 'a b', caCert: '/ca').validate(),
        contains('spaces'),
      );
      expect(
        const OpenVpnSpec(name: 'x', gateway: 'h').validate(),
        contains('CA'),
      );
      expect(
        const OpenVpnSpec(name: 'x', gateway: 'h', caCert: '/ca').validate(),
        contains('user name'),
      );
    });
  });

  group('PPTP', () {
    test('requires MPPE and refuses the weaker sign-ins with it', () {
      const spec = PptpSpec(
        name: 'Legacy',
        gateway: '203.0.113.5',
        username: 'ada',
        password: 'pw',
      );
      expect(spec.validate(), isNull);
      final s = spec.toSettings(uuid: 'u');
      expect(s['vpn']!['service-type'], const DBusString(kPptpService));
      expect(_data(s), {
        'gateway': '203.0.113.5',
        'user': 'ada',
        'password-flags': '0',
        'require-mppe': 'yes',
        'refuse-eap': 'yes',
        'refuse-pap': 'yes',
        'refuse-chap': 'yes',
      });
      expect(_secrets(s), {'password': 'pw'});
    });

    test('without MPPE nothing is refused', () {
      const spec = PptpSpec(
        name: 'x',
        gateway: 'h',
        username: 'u',
        mppe: false,
        domain: 'CORP',
      );
      final data = _data(spec.toSettings(uuid: 'u'));
      expect(data.containsKey('require-mppe'), isFalse);
      expect(data.containsKey('refuse-pap'), isFalse);
      expect(data['domain'], 'CORP');
    });
  });

  group('withVpnPassword', () {
    final base = const OpenVpnSpec(
      name: 'x',
      gateway: 'h',
      auth: OpenVpnAuth.certificates,
      caCert: '/ca',
      userCert: '/c',
      userKey: '/k',
    ).toSettings(uuid: 'u');

    test('keeps the secrets already saved and adds the password', () {
      final out = withVpnPassword(
        base,
        kind: VpnKind.openvpn,
        password: 'pw',
        username: 'ada',
        existingSecrets: const {'cert-pass': 'k'},
      )!;
      expect(_secrets(out), {'cert-pass': 'k', 'password': 'pw'});
      expect(_data(out)['username'], 'ada');
      expect(_data(out)['password-flags'], '0');
      // A certificate-only profile becomes one that takes a password too.
      expect(_data(out)['connection-type'], 'password-tls');
      // The original is untouched.
      expect(base['vpn']!.containsKey('secrets'), isFalse);
    });

    test('writes PPTP\'s user name under its own key', () {
      final pptp = const PptpSpec(
        name: 'x',
        gateway: 'h',
        username: 'old',
      ).toSettings(uuid: 'u');
      final out = withVpnPassword(
        pptp,
        kind: VpnKind.pptp,
        password: 'pw',
        username: 'new',
      )!;
      expect(_data(out)['user'], 'new');
    });

    test('declines a kind whose secret it does not know', () {
      expect(
        withVpnPassword(base, kind: VpnKind.other, password: 'pw'),
        isNull,
      );
    });
  });

  group('WireGuard', () {
    WireGuardSpec spec({
      List<String> addresses = const ['10.0.0.2/32', 'fd00::2/128'],
      List<String> dns = const ['10.0.0.1', 'fd00::1', 'corp.example'],
      List<String> allowed = const ['0.0.0.0/0', '::/0'],
    }) => WireGuardSpec(
      name: 'Home',
      interfaceName: 'wg-home',
      privateKey: _alicePrivate,
      addresses: addresses,
      dns: dns,
      listenPort: 51820,
      peers: [
        WireGuardPeerSpec(
          publicKey: _bobPublic,
          endpoint: 'vpn.example.com:51820',
          allowedIps: allowed,
          persistentKeepalive: 25,
        ),
      ],
    );

    test('becomes a wireguard profile with its peer', () {
      final s = spec().toSettings(uuid: 'u');
      expect(spec().validate(), isNull);
      expect(s['connection']!['type'], const DBusString('wireguard'));
      expect(s['connection']!['interface-name'], const DBusString('wg-home'));
      final wg = s['wireguard']!;
      expect(wg['private-key'], DBusString(_alicePrivate));
      expect(wg['private-key-flags'], const DBusUint32(0));
      expect(wg['listen-port'], const DBusUint32(51820));
      final peers = wg['peers']! as DBusArray;
      expect(peers.signature, DBusSignature('aa{sv}'));
      final peer = (peers.children.single as DBusDict).children;
      expect(
        peer[const DBusString('public-key')],
        DBusVariant(DBusString(_bobPublic)),
      );
      expect(
        peer[const DBusString('allowed-ips')],
        DBusVariant(DBusArray.string(['0.0.0.0/0', '::/0'])),
      );
      expect(
        peer[const DBusString('persistent-keepalive')],
        const DBusVariant(DBusUint32(25)),
      );
    });

    test('splits addresses and name servers by family', () {
      final s = spec().toSettings(uuid: 'u');
      final v4 = s['ipv4']!;
      expect(v4['method'], const DBusString('manual'));
      final address = (v4['address-data']! as DBusArray).children.single;
      expect(
        (address as DBusDict).children[const DBusString('address')],
        const DBusVariant(DBusString('10.0.0.2')),
      );
      // 10.0.0.1 as an in_addr_t: network order in memory.
      final dns = (v4['dns']! as DBusArray).children.single as DBusUint32;
      final bytes = ByteData(4)..setUint32(0, dns.value, Endian.host);
      expect([for (var i = 0; i < 4; i++) bytes.getUint8(i)], [10, 0, 0, 1]);
      final v6 = s['ipv6']!;
      expect(v6['method'], const DBusString('manual'));
      final dns6 = (v6['dns']! as DBusArray).children.single as DBusArray;
      expect(dns6.children.length, 16);
    });

    test('a tunnel carrying everything takes every lookup', () {
      final s = spec().toSettings(uuid: 'u');
      expect(s['ipv4']!['dns-search'], DBusArray.string(['corp.example', '~']));
      expect(s['ipv4']!['dns-priority'], const DBusInt32(-50));
      final split = spec(allowed: const ['10.0.0.0/24']).toSettings(uuid: 'u');
      expect(split['ipv4']!['dns-search'], DBusArray.string(['corp.example']));
      expect(split['ipv4']!.containsKey('dns-priority'), isFalse);
    });

    test('a family with no address is off', () {
      final s = spec(
        addresses: const ['10.0.0.2/32'],
        dns: const [],
      ).toSettings(uuid: 'u');
      expect(s['ipv6']!['method'], const DBusString('ignore'));
      expect(s['ipv6']!.containsKey('address-data'), isFalse);
    });

    test('refuses keys, addresses and endpoints that cannot work', () {
      WireGuardSpec withPeer(WireGuardPeerSpec peer) => WireGuardSpec(
        name: 'x',
        interfaceName: 'wg0',
        privateKey: _alicePrivate,
        addresses: const ['10.0.0.2/32'],
        peers: [peer],
      );
      expect(
        withPeer(const WireGuardPeerSpec(publicKey: 'nope')).validate(),
        contains('public key'),
      );
      expect(
        withPeer(
          WireGuardPeerSpec(
            publicKey: _bobPublic,
            endpoint: 'host',
            allowedIps: const ['0.0.0.0/0'],
          ),
        ).validate(),
        contains('port'),
      );
      expect(
        withPeer(
          WireGuardPeerSpec(publicKey: _bobPublic, allowedIps: const ['10/99']),
        ).validate(),
        contains('10/99'),
      );
      expect(
        withPeer(
          WireGuardPeerSpec(
            publicKey: _bobPublic,
            endpoint: '[2001:db8::1]:51820',
            allowedIps: const ['::/0'],
          ),
        ).validate(),
        isNull,
      );
      expect(
        WireGuardSpec(
          name: 'x',
          interfaceName: 'this-is-far-too-long',
          privateKey: _alicePrivate,
        ).validate(),
        contains('interface name'),
      );
    });

    test('interface names are short, Linux-legal and unique', () {
      expect(wireGuardInterfaceFor('Home', const []), 'wg-home');
      expect(wireGuardInterfaceFor('Home', const ['wg-home']), 'wg-home2');
      expect(
        wireGuardInterfaceFor('Office in Zürich!', const []),
        'wg-office-in-z',
      );
      expect(wireGuardInterfaceFor('', const []), 'wg');
      for (final name in ['a', 'A very long tunnel name indeed', '中文']) {
        final ifname = wireGuardInterfaceFor(name, const []);
        expect(isValidInterfaceName(ifname), isTrue, reason: ifname);
      }
    });
  });

  group('wg-quick files', () {
    final file =
        '''
# Provider-issued
[Interface]
PrivateKey = $_alicePrivate
Address = 10.66.0.2/32, fd00:66::2/128
DNS = 10.66.0.1
MTU = 1380
PostUp = iptables -A FORWARD -i %i -j ACCEPT
SaveConfig = true

[Peer]
PublicKey = $_bobPublic
AllowedIPs = 0.0.0.0/0
AllowedIPs = ::/0
Endpoint = [2001:db8::1]:51820  # the server
PersistentKeepalive = 25
Frobnicate = yes
''';

    test('reads the interface and every peer', () {
      expect(looksLikeWireGuardConf(file), isTrue);
      final parsed = parseWireGuardConf(file, path: '/home/u/wg0.conf');
      final spec = parsed.spec;
      expect(spec.name, 'wg0');
      expect(spec.interfaceName, 'wg0');
      expect(spec.addresses, ['10.66.0.2/32', 'fd00:66::2/128']);
      expect(spec.dns, ['10.66.0.1']);
      expect(spec.mtu, 1380);
      final peer = spec.peers.single;
      expect(peer.allowedIps, ['0.0.0.0/0', '::/0']);
      expect(peer.endpoint, '[2001:db8::1]:51820');
      expect(peer.persistentKeepalive, 25);
      expect(spec.validate(), isNull);
    });

    test('says what it left out', () {
      final warnings = parseWireGuardConf(file, path: 'x.conf').warnings;
      expect(warnings, contains(contains('Frobnicate')));
      expect(warnings, contains(contains('PostUp')));
      // SaveConfig has no meaning for NetworkManager and is not worth a line.
      expect(warnings.where((w) => w.contains('SaveConfig')), isEmpty);
    });

    test('takes another interface name when the file\'s is in use', () {
      final spec = parseWireGuardConf(
        file,
        path: '/x/wg0.conf',
        takenInterfaces: const ['wg0'],
      ).spec;
      expect(spec.interfaceName, isNot('wg0'));
      expect(isValidInterfaceName(spec.interfaceName), isTrue);
    });

    test('Table = off turns the peer routes off', () {
      final spec = parseWireGuardConf(
        '[Interface]\nPrivateKey = $_alicePrivate\nTable = off\n',
        path: 'a.conf',
      ).spec;
      expect(spec.peerRoutes, isFalse);
      final s = spec.toSettings(uuid: 'u');
      expect(s['wireguard']!['peer-routes'], const DBusBoolean(false));
    });

    test('refuses a file with no key, or a value that means nothing', () {
      expect(
        () => parseWireGuardConf('[Interface]\nAddress = 1.2.3.4\n', path: 'a'),
        throwsFormatException,
      );
      expect(
        () => parseWireGuardConf(
          '[Interface]\nPrivateKey = $_alicePrivate\nListenPort = banana\n',
          path: 'a',
        ),
        throwsFormatException,
      );
      expect(looksLikeWireGuardConf('client\nremote vpn 1194\n'), isFalse);
    });
  });

  group('plugin registry', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('vpn-plugins'));
    tearDown(() => tmp.deleteSync(recursive: true));

    const openvpn = '''
[VPN Connection]
name=openvpn
service=org.freedesktop.NetworkManager.openvpn
program=/usr/libexec/nm-openvpn-service

[libnm]
plugin=libnm-vpn-plugin-openvpn.so
''';

    test('reads a .name file', () {
      final info = parseVpnPluginFile('/a/openvpn.name', openvpn)!;
      expect(info.name, 'openvpn');
      expect(info.service, kOpenVpnService);
      expect(info.libnmPlugin, 'libnm-vpn-plugin-openvpn.so');
      expect(info.kind, VpnKind.openvpn);
      expect(parseVpnPluginFile('/b', '[VPN Connection]\nname=x\n'), isNull);
    });

    test('the earlier directory wins, and a missing one is empty', () {
      final etc = Directory('${tmp.path}/etc')..createSync();
      final lib = Directory('${tmp.path}/lib')..createSync();
      File('${etc.path}/nm-openvpn-service.name').writeAsStringSync(
        openvpn.replaceFirst('name=openvpn', 'name=override'),
      );
      File('${lib.path}/nm-openvpn-service.name').writeAsStringSync(openvpn);
      File('${lib.path}/README').writeAsStringSync('not a plugin');
      final plugins = readVpnPlugins(
        dirs: [etc.path, lib.path, '${tmp.path}/missing'],
      );
      expect(plugins.single.name, 'override');
    });
  });

  group('reading profiles back', () {
    test('a plugin VPN, a WireGuard tunnel, and a Wi-Fi network', () {
      final ovpn = const OpenVpnSpec(
        name: 'Office',
        gateway: 'vpn.example.com',
        caCert: '/ca',
        username: 'u',
      ).toSettings(uuid: 'a');
      final p = VpnProfile.fromSettings('/p/1', ovpn)!;
      expect(p.kind, VpnKind.openvpn);
      expect(p.server, 'vpn.example.com');
      expect(p.takesPassword, isTrue);

      final wg = WireGuardSpec(
        name: 'Home',
        interfaceName: 'wg-home',
        privateKey: _alicePrivate,
        addresses: const ['10.0.0.2/32'],
        peers: [
          WireGuardPeerSpec(
            publicKey: _bobPublic,
            endpoint: 'h:1',
            allowedIps: const ['0.0.0.0/0'],
          ),
        ],
      ).toSettings(uuid: 'b');
      // As GetSettings answers: unwrapped through the a{sa{sv}} round trip.
      final roundTripped = nmSettingsFromValue(nmSettingsValue(wg));
      final w = VpnProfile.fromSettings('/p/2', roundTripped)!;
      expect(w.kind, VpnKind.wireguard);
      expect(w.server, 'h:1');
      expect(w.interfaceName, 'wg-home');

      expect(
        VpnProfile.fromSettings('/p/3', {
          'connection': {'type': const DBusString('802-11-wireless')},
        }),
        isNull,
      );
    });

    test('a plugin the pane has no form for is listed by its short name', () {
      final p = VpnProfile.fromSettings('/p', {
        'connection': {
          'type': const DBusString('vpn'),
          'id': const DBusString('Work'),
        },
        'vpn': {
          'service-type': const DBusString(
            'org.freedesktop.NetworkManager.openconnect',
          ),
          'data': nmStringDict(const {'gateway': 'vpn.corp'}),
        },
      })!;
      expect(p.kind, VpnKind.other);
      expect(p.kindLabel, 'openconnect');
      expect(p.server, 'vpn.corp');
      expect(p.takesPassword, isFalse);
    });

    test('failure reasons', () {
      expect(vpnFailureReason(2), isNull);
      expect(vpnFailureReason(11), isNull);
      expect(vpnFailureReason(9), contains('password'));
      expect(vpnReasonWantsPassword(10), isTrue);
      expect(vpnReasonWantsPassword(6), isFalse);
    });
  });
}
