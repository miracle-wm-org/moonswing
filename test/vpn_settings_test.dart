// Settings › Network's VPN section and forms, over a fake NetworkManager.

import 'dart:convert';

import 'package:dbus/dbus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/network_vpn.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/vpn/nm_vpn_client.dart';
import 'package:moonswing/vpn/vpn_model.dart';
import 'package:moonswing/vpn/vpn_spec.dart';
import 'package:moonswing/vpn/vpn_store.dart';
import 'package:moonswing/vpn/x25519.dart';

import 'vpn_fakes.dart';

void main() {
  late FakeVpnBackend nm;
  late VpnStore store;

  setUp(() {
    nm = FakeVpnBackend();
    store = VpnStore.forTesting(
      backend: nm,
      readPlugins: () => const [fakeOpenVpnPlugin],
      newUuid: () => 'test-uuid',
    );
  });

  tearDown(() {
    store.release();
    store.dispose();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    // Here rather than in setUp: the lease subscribes to the fake's events,
    // and a subscription made outside the test's fake-async zone is never
    // delivered inside it.
    store.acquire();
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextEditingShortcuts(
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) =>
                      SizedBox(width: 1000, height: 1600, child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a row per VPN, whose switch brings it up', (tester) async {
    final path = nm.put(
      const PptpSpec(
        name: 'Legacy',
        gateway: 'gw.example.com',
        username: 'u',
      ).toSettings(uuid: 'a'),
    );
    await store.retry();
    final opened = <VpnFormRequest>[];
    await pump(
      tester,
      SingleChildScrollView(
        child: VpnSection(store: store, onOpen: opened.add),
      ),
    );
    expect(find.text('Legacy'), findsOneWidget);
    expect(find.text('PPTP · gw.example.com'), findsOneWidget);

    await tester.tap(find.byType(SettingsToggle));
    await tester.pumpAndSettle();
    expect(nm.calls, contains('activate $path'));
    expect(find.text('PPTP · gw.example.com · Connected'), findsOneWidget);
  });

  testWidgets('a sign-in failure offers a password', (tester) async {
    final path = nm.put(
      const PptpSpec(
        name: 'Legacy',
        gateway: 'gw',
        username: 'u',
      ).toSettings(uuid: 'a'),
    );
    nm.activateTo = 1;
    await store.retry();
    final opened = <VpnFormRequest>[];
    await pump(
      tester,
      SingleChildScrollView(
        child: VpnSection(store: store, onOpen: opened.add),
      ),
    );
    await tester.tap(find.byType(SettingsToggle));
    await tester.pump();
    final activePath = nm.active[path]!.$1;
    nm.active.remove(path);
    // Deactivated (4), because the login failed (10).
    nm.emit(VpnActivationStateChanged(activePath, 4, 10));
    await tester.pumpAndSettle();
    expect(find.text('The server refused the sign-in.'), findsOneWidget);
    await tester.tap(find.text('Password…'));
    expect(opened.single, isA<VpnPasswordRequest>());
  });

  testWidgets('the adder offers the three kinds and import', (tester) async {
    await store.retry();
    final opened = <VpnFormRequest>[];
    await pump(
      tester,
      SingleChildScrollView(
        child: VpnSection(store: store, onOpen: opened.add),
      ),
    );
    expect(find.text('No VPNs yet'), findsOneWidget);
    await tester.tap(find.text('Add VPN'));
    await tester.pumpAndSettle();
    expect(find.text('OpenVPN'), findsOneWidget);
    expect(find.text('Import from file…'), findsOneWidget);
    // Only PPTP's plugin is missing here.
    expect(find.text('plugin not installed'), findsOneWidget);
    await tester.tap(find.text('WireGuard'));
    await tester.pumpAndSettle();
    expect((opened.single as VpnAddRequest).kind, VpnKind.wireguard);
  });

  testWidgets('the WireGuard form generates a key and saves the tunnel', (
    tester,
  ) async {
    await store.retry();
    var closed = 0;
    await pump(
      tester,
      VpnFormPage(
        store: store,
        request: const VpnAddRequest(VpnKind.wireguard),
        onClose: () => closed++,
      ),
    );
    expect(find.text('Appears once the private key is valid'), findsOneWidget);
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(find.text('Appears once the private key is valid'), findsNothing);

    final fields = find.byType(EditableText);
    final peer = base64.encode(List.filled(32, 7));
    await tester.enterText(fields.at(0), 'Home');
    await tester.enterText(fields.at(2), '10.0.0.2/32');
    await tester.enterText(fields.at(5), peer);
    await tester.enterText(fields.at(6), 'vpn.example.com:51820');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(closed, 1);
    final saved = nm.saved.values.single;
    expect(saved['connection']!['type'], const DBusString('wireguard'));
    expect(saved['connection']!['interface-name'], const DBusString('wg-home'));
    final privateKey = nmString(saved['wireguard']!['private-key']);
    // The key saved is the one whose public half the form showed.
    expect(find.text(wireGuardPublicKey(privateKey)!), findsOneWidget);
  });

  testWidgets('a form says what is missing instead of saving', (tester) async {
    await store.retry();
    var closed = 0;
    await pump(
      tester,
      VpnFormPage(
        store: store,
        request: const VpnAddRequest(VpnKind.openvpn),
        onClose: () => closed++,
      ),
    );
    await tester.enterText(find.byType(EditableText).at(0), 'Office');
    await tester.enterText(find.byType(EditableText).at(1), 'vpn.example.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CA certificate'), findsWidgets);
    expect(closed, 0);
    expect(nm.saved, isEmpty);
  });
}
