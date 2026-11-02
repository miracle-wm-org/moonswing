// The libnm importer against the machine's real NetworkManager plugins.
//
// Skipped where libnm or the OpenVPN plugin is missing — which is most CI
// machines. `MOONSWING_VPN_PLUGIN_DIR` points it at a directory of `.name`
// files instead of NetworkManager's own, for running against a plugin
// extracted from a package rather than installed.

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/vpn/libnm_import.dart';
import 'package:moonswing/vpn/vpn_model.dart';
import 'package:moonswing/vpn/vpn_plugins.dart';

const _ca = '''-----BEGIN CERTIFICATE-----
MIIBszCCAVmgAwIBAgIUFakeFakeFakeFakeFakeFakeFakeFaMAoGCCqGSM49BAMC
-----END CERTIFICATE-----''';

String? _skipReason() {
  try {
    ffi.DynamicLibrary.open('libnm.so.0');
  } catch (_) {
    return 'libnm is not installed';
  }
  final plugins = _plugins();
  if (!plugins.any((p) => p.kind == VpnKind.openvpn)) {
    return 'NetworkManager-openvpn is not installed';
  }
  return null;
}

List<VpnPluginInfo> _plugins() {
  final dir = Platform.environment['MOONSWING_VPN_PLUGIN_DIR'];
  return readVpnPlugins(dirs: dir == null ? kVpnPluginDirs : [dir]);
}

void main() {
  final skip = _skipReason();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('vpn-import'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('an .ovpn becomes an OpenVPN profile through the plugin', () {
    // The CA by path, not inline: an inline block is written out under the
    // real ~/.cert by the plugin, which a test has no business doing.
    final ca = File('${tmp.path}/ca.crt')..writeAsStringSync(_ca);
    final file = File('${tmp.path}/office.ovpn')
      ..writeAsStringSync('''
client
dev tun
proto tcp
remote vpn.example.com 1194
auth-user-pass
ca ${ca.path}
''');
    final settings = LibnmImporter().importFile(file.path, _plugins());
    // A plugin fills in only what its format says; the profile's type and
    // uuid are left to the caller, as `nmcli` normalises them.
    expect(settings['connection']!['id'], const DBusString('office'));
    final vpn = settings['vpn']!;
    expect(vpn['service-type'], const DBusString(kOpenVpnService));
    final data = nmStringMap(settings['vpn']!['data']);
    expect(data['connection-type'], 'password');
    expect(data['proto-tcp'], 'yes');
    expect(data['ca'], ca.path);
    expect(data['remote'], contains('vpn.example.com'));
    // An empty a{ss} still arrives as a typed dictionary.
    expect(vpn['secrets'], isA<DBusDict>());
  }, skip: skip);

  test('a file no plugin reads is refused in words', () {
    final file = File('${tmp.path}/notes.txt')
      ..writeAsStringSync('nothing to see here\n');
    expect(
      () => LibnmImporter().importFile(file.path, _plugins()),
      throwsA(isA<VpnImportException>()),
    );
  }, skip: skip);

  test('a missing libnm is a sentence, not a crash', () {
    final importer = LibnmImporter(sonames: const ['libnm-not-here.so.9']);
    expect(
      () => importer.importFile('/nowhere', const [
        VpnPluginInfo(
          file: '/x.name',
          name: 'openvpn',
          service: kOpenVpnService,
          libnmPlugin: 'libnm-vpn-plugin-openvpn.so',
        ),
      ]),
      throwsA(
        isA<VpnImportException>().having(
          (e) => e.message,
          'message',
          contains('libnm'),
        ),
      ),
    );
  });
}
