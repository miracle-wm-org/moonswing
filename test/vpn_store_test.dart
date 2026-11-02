// VpnStore over a fake NetworkManager: what it lists, what a switch does, how
// a failure lands on its row, and the import and password paths.

import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/vpn/libnm_import.dart';
import 'package:moonswing/vpn/nm_vpn_client.dart';
import 'package:moonswing/vpn/vpn_model.dart';
import 'package:moonswing/vpn/vpn_spec.dart';
import 'package:moonswing/vpn/vpn_store.dart';

import 'vpn_fakes.dart';

final _key = base64.encode(List.generate(32, (i) => i + 1));

NmSettings _openvpn(String name, {String type = 'password'}) => {
  'connection': {
    'id': DBusString(name),
    'uuid': DBusString('uuid-$name'),
    'type': const DBusString('vpn'),
  },
  'vpn': {
    'service-type': const DBusString(kOpenVpnService),
    'data': nmStringDict({
      'remote': '$name.example.com',
      'connection-type': type,
      'username': 'ada',
    }),
  },
};

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeVpnBackend nm;
  late VpnStore store;
  late int notifications;

  setUp(() {
    nm = FakeVpnBackend();
    var uuid = 0;
    store = VpnStore.forTesting(
      backend: nm,
      readPlugins: () => const [fakeOpenVpnPlugin],
      newUuid: () => 'new-${++uuid}',
    );
    notifications = 0;
    store.addListener(() => notifications++);
  });

  tearDown(() {
    store.release();
    store.dispose();
  });

  test(
    'lists only the VPNs, by name, and does not notify in acquire',
    () async {
      nm.put(_openvpn('zeta'));
      nm.put({
        'connection': {
          'id': const DBusString('Home Wi-Fi'),
          'type': const DBusString('802-11-wireless'),
        },
      });
      nm.put(_openvpn('Alpha'));
      store.acquire();
      expect(notifications, 0);
      expect(store.status, VpnStoreStatus.loading);
      await _settle();
      expect(store.status, VpnStoreStatus.ready);
      expect(store.profiles.map((p) => p.name), ['Alpha', 'zeta']);
      expect(store.pluginFor(VpnKind.openvpn), isNotNull);
      expect(store.pluginFor(VpnKind.pptp), isNull);
      expect(nm.listening, isTrue);
    },
  );

  test(
    'the switch activates and deactivates, from what NetworkManager says',
    () async {
      final path = nm.put(_openvpn('Office'));
      store.acquire();
      await _settle();
      final profile = store.profiles.single;
      expect(store.stateOf(profile), VpnState.disconnected);

      await store.setEnabled(profile, true);
      expect(nm.calls, contains('activate $path'));
      expect(store.stateOf(profile), VpnState.connected);

      await store.setEnabled(profile, false);
      expect(nm.calls.any((c) => c.startsWith('deactivate')), isTrue);
      expect(store.stateOf(profile), VpnState.disconnected);
    },
  );

  test('a refusal lands on the row, and the switch springs back', () async {
    nm.put(_openvpn('Office'));
    nm.refuseActivate =
        "The VPN service 'org.freedesktop.NetworkManager.openvpn' was not "
        'installed.';
    store.acquire();
    await _settle();
    final profile = store.profiles.single;
    await store.setEnabled(profile, true);
    expect(store.stateOf(profile), VpnState.disconnected);
    expect(store.errorOf(profile)!.message, contains('not installed'));
    expect(store.error, isEmpty);
  });

  test('an activation ending with no secrets asks for a password', () async {
    final path = nm.put(_openvpn('Office'));
    nm.activateTo = 1;
    store.acquire();
    await _settle();
    final profile = store.profiles.single;
    await store.setEnabled(profile, true);
    expect(store.stateOf(profile), VpnState.connecting);

    final activePath = nm.active[path]!.$1;
    nm.active.remove(path);
    nm.emit(VpnActivationStateChanged(activePath, 4, 9));
    await _settle();
    await _settle();
    expect(store.stateOf(profile), VpnState.disconnected);
    final error = store.errorOf(profile)!;
    expect(error.wantsPassword, isTrue);
    expect(error.message, contains('password'));
  });

  test('a tunnel the user turns off records no failure', () async {
    final path = nm.put(_openvpn('Office'));
    store.acquire();
    await _settle();
    final profile = store.profiles.single;
    await store.setEnabled(profile, true);
    final activePath = nm.active[path]!.$1;
    nm.active.remove(path);
    nm.emit(VpnActivationStateChanged(activePath, 4, 2));
    await _settle();
    await _settle();
    expect(store.errorOf(profile), isNull);
  });

  test(
    'a burst of unrelated signals reads again but notifies nothing',
    () async {
      nm.put(_openvpn('Office'));
      store.acquire();
      await _settle();
      final before = notifications;
      for (var i = 0; i < 5; i++) {
        nm.emit(const VpnProfilesChanged());
      }
      await _settle();
      await _settle();
      expect(nm.calls.where((c) => c == 'connections').length, greaterThan(1));
      expect(notifications, before);
    },
  );

  test('NetworkManager missing is the pane\'s failure, with a retry', () async {
    nm.down = true;
    store.acquire();
    await _settle();
    expect(store.status, VpnStoreStatus.unavailable);
    expect(store.error, contains('not running'));
    nm.down = false;
    nm.put(_openvpn('Office'));
    await store.retry();
    expect(store.status, VpnStoreStatus.ready);
    expect(store.error, isEmpty);
    expect(store.profiles, hasLength(1));
  });

  test('add and remove go through NetworkManager', () async {
    store.acquire();
    await _settle();
    await store.add(
      (uuid) => const PptpSpec(
        name: 'Legacy',
        gateway: 'h',
        username: 'u',
      ).toSettings(uuid: uuid),
    );
    expect(store.profiles.single.name, 'Legacy');
    expect(
      nm.saved.values.single['connection']!['uuid'],
      const DBusString('new-1'),
    );
    final failure = await store.remove(store.profiles.single);
    expect(failure, isNull);
    expect(store.profiles, isEmpty);
  });

  test('setPassword keeps the secrets the profile already had', () async {
    final path = nm.put(_openvpn('Office', type: 'password-tls'));
    nm.secrets[path] = const {'cert-pass': 'kp'};
    store.acquire();
    await _settle();
    await store.setPassword(
      store.profiles.single,
      password: 'pw',
      username: 'grace',
    );
    expect(nm.calls, contains('update $path'));
    final vpn = nm.saved[path]!['vpn']!;
    expect(nmStringMap(vpn['secrets']), {'cert-pass': 'kp', 'password': 'pw'});
    expect(nmStringMap(vpn['data'])['username'], 'grace');
    expect(nmStringMap(vpn['data'])['password-flags'], '0');
  });

  group('import', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('vpn-store'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a wg-quick file is read here, not by a plugin', () async {
      final importer = FakeImporter((_) => throw StateError('not a plugin'));
      final s = VpnStore.forTesting(
        backend: nm,
        importer: importer,
        newUuid: () => 'wg-uuid',
      );
      addTearDown(s.dispose);
      final file = File('${tmp.path}/home.conf')
        ..writeAsStringSync('''
[Interface]
PrivateKey = $_key
Address = 10.0.0.2/32

[Peer]
PublicKey = $_key
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.com:51820
''');
      final draft = await s.prepareImport(file.path);
      expect(importer.paths, isEmpty);
      expect(draft.profile.kind, VpnKind.wireguard);
      expect(draft.profile.interfaceName, 'home');
      expect(draft.asksPassword, isFalse);
      await s.saveImport(draft, name: 'Home');
      final saved = nm.saved.values.single;
      expect(saved['connection']!['id'], const DBusString('Home'));
      expect(saved['connection']!['type'], const DBusString('wireguard'));
    });

    test(
      'a plugin\'s import is normalised and asks for the password',
      () async {
        final importer = FakeImporter(
          (_) => {
            // As nm-openvpn's import leaves it: no type, no uuid.
            'connection': {'id': const DBusString('office')},
            'vpn': {
              'service-type': const DBusString(kOpenVpnService),
              'data': nmStringDict(const {
                'remote': 'vpn.example.com:1194',
                'connection-type': 'password',
                'password-flags': '1',
              }),
            },
          },
        );
        final s = VpnStore.forTesting(
          backend: nm,
          importer: importer,
          newUuid: () => 'imp-uuid',
        );
        addTearDown(s.dispose);
        final file = File('${tmp.path}/office.ovpn')
          ..writeAsStringSync('client\nremote vpn.example.com 1194\n');
        final draft = await s.prepareImport(file.path);
        expect(importer.paths, [file.path]);
        expect(draft.profile.kind, VpnKind.openvpn);
        expect(draft.asksPassword, isTrue);
        expect(draft.settings['connection']!['type'], const DBusString('vpn'));
        expect(
          draft.settings['connection']!['uuid'],
          const DBusString('imp-uuid'),
        );
        await s.saveImport(
          draft,
          name: 'Office',
          username: 'ada',
          password: 'pw',
        );
        final vpn = nm.saved.values.single['vpn']!;
        expect(nmStringMap(vpn['secrets']), {'password': 'pw'});
        expect(nmStringMap(vpn['data'])['password-flags'], '0');
        expect(nmStringMap(vpn['data'])['username'], 'ada');
      },
    );

    test('an unreadable file is a sentence', () async {
      expect(
        () => store.prepareImport('${tmp.path}/missing.ovpn'),
        throwsA(isA<VpnImportException>()),
      );
    });
  });

  test('releasing the last lease stops listening', () async {
    store.acquire();
    await _settle();
    expect(nm.listening, isTrue);
    store.release();
    await _settle();
    expect(nm.listening, isFalse);
    // tearDown's release is then a no-op.
  });
}
