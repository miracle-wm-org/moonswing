// The quick settings module: its three stores over fakes (PulseAudio,
// NetworkManager, BlueZ), the bar button's glyphs, and the panel — that each
// section's way through to Settings names the right page, that the power menu
// is one tap away, and that a list page never changes the card's height.

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/modules/brightness.dart';
import 'package:moonswing/modules/network.dart';
import 'package:moonswing/modules/quick_settings.dart';
import 'package:moonswing/overlay/settings/bluetooth.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/power/power_menu_controller.dart';
import 'package:moonswing/quick_panel/audio_devices_store.dart';
import 'package:moonswing/quick_panel/bluetooth_store.dart';
import 'package:moonswing/quick_panel/quick_settings_panel.dart';
import 'package:moonswing/quick_panel/wifi_store.dart';
import 'package:moonswing/scopes.dart';

import 'brightness_monitor_test.dart' show writeDevice;
import 'glyph_finder.dart';
import 'power_profile_fakes.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

AudioDevice _dev(
  int index,
  String name, {
  double volume = 0.5,
  bool muted = false,
}) => AudioDevice(
  index: index,
  name: name,
  description: name.toUpperCase(),
  volume: volume,
  muted: muted,
);

class FakeAudioBackend implements AudioDevicesBackend {
  FakeAudioBackend({
    List<AudioDevice>? sinks,
    List<AudioDevice>? sources,
    this.defaultOutput = 'speakers',
    this.defaultInput = 'mic',
  }) : sinks = sinks ?? [_dev(1, 'speakers'), _dev(2, 'headset')],
       sources =
           sources ??
           [_dev(3, 'mic', volume: 0.8), _dev(4, 'speakers.monitor')];

  List<AudioDevice> sinks;
  List<AudioDevice> sources;
  String defaultOutput;
  String defaultInput;
  Object? initFailure;

  final volumes = <(AudioDirection, String, double)>[];
  final mutes = <(AudioDirection, String, bool)>[];
  final defaultsSet = <(AudioDirection, String)>[];

  final _changed = StreamController<(AudioDirection, AudioDevice)>.broadcast();
  final _removed = StreamController<(AudioDirection, int)>.broadcast();
  final _defaults =
      StreamController<({String output, String input})>.broadcast();
  final _reconnected = StreamController<void>.broadcast();

  void emitChanged(AudioDirection d, AudioDevice device) =>
      _changed.add((d, device));
  void emitRemoved(AudioDirection d, int index) => _removed.add((d, index));

  @override
  Future<void> initialize() async {
    final failure = initFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<({String output, String input})> defaults() async =>
      (output: defaultOutput, input: defaultInput);

  @override
  Future<List<AudioDevice>> devices(AudioDirection direction) async =>
      direction == AudioDirection.output ? sinks : sources;

  @override
  Stream<(AudioDirection, AudioDevice)> get changed => _changed.stream;

  @override
  Stream<(AudioDirection, int)> get removed => _removed.stream;

  @override
  Stream<({String output, String input})> get defaultsChanged =>
      _defaults.stream;

  @override
  Stream<void> get reconnected => _reconnected.stream;

  @override
  Future<void> setVolume(AudioDirection d, String name, double volume) async =>
      volumes.add((d, name, volume));

  @override
  Future<void> setMute(AudioDirection d, String name, bool muted) async =>
      mutes.add((d, name, muted));

  @override
  Future<void> setDefault(AudioDirection d, String name) async {
    defaultsSet.add((d, name));
    if (d == AudioDirection.output) {
      defaultOutput = name;
    } else {
      defaultInput = name;
    }
    _defaults.add((output: defaultOutput, input: defaultInput));
  }
}

AvailableNetwork _net(
  String name, {
  bool connected = false,
  bool secured = true,
  bool saved = false,
  int signal = 70,
}) => AvailableNetwork(
  type: NetworkType.wifi,
  name: name,
  signal: signal,
  secured: secured,
  isConnected: connected,
  devicePath: DBusObjectPath('/dev/wlan0'),
  apPath: DBusObjectPath('/ap/$name'),
  savedConnectionPath: saved ? DBusObjectPath('/conn/$name') : null,
);

class FakeWifiBackend implements WifiBackend {
  WifiRadio radio = const WifiRadio(
    hasDevice: true,
    enabled: true,
    hardwareEnabled: true,
  );
  Object? readFailure;
  bool refuseWrites = false;
  List<AvailableNetwork> inRange = [
    _net('Home', connected: true, saved: true),
    _net('Cafe', secured: false),
    _net('Neighbour'),
  ];
  final connected = <String>[];
  final enabledCalls = <bool>[];
  int scans = 0;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<WifiRadio> readRadio() async {
    final failure = readFailure;
    if (failure != null) throw failure;
    return radio;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    enabledCalls.add(enabled);
    if (refuseWrites) throw Exception('polkit said no');
    radio = WifiRadio(
      hasDevice: radio.hasDevice,
      enabled: enabled,
      hardwareEnabled: radio.hardwareEnabled,
    );
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<AvailableNetwork>> scan() async {
    scans++;
    return inRange;
  }

  @override
  Future<void> connect(AvailableNetwork network) async =>
      connected.add(network.name);
}

BluetoothDevice _bt(
  String name, {
  bool connected = false,
  bool paired = true,
  int? rssi,
}) => BluetoothDevice(
  name: name,
  address: 'AA:$name',
  connected: connected,
  paired: paired,
  rssi: rssi,
  objectPath: DBusObjectPath('/org/bluez/hci0/dev_$name'),
);

class FakeBluetoothBackend implements BluetoothBackend {
  bool powered = true;
  bool hasAdapter = true;
  List<BluetoothDevice> devices = [
    _bt('Buds', connected: true),
    _bt('Keyboard'),
    _bt('Stranger', paired: false),
  ];
  int reads = 0;
  final poweredCalls = <bool>[];
  final connects = <String>[];
  final disconnects = <String>[];
  final _changes = StreamController<void>.broadcast();

  void emit() => _changes.add(null);

  @override
  Future<BluetoothScanResult> read() async {
    reads++;
    return BluetoothScanResult(
      adapterPath: hasAdapter ? DBusObjectPath('/org/bluez/hci0') : null,
      adapterPowered: powered,
      devices: devices,
    );
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> setPowered(DBusObjectPath adapter, bool powered) async {
    poweredCalls.add(powered);
    this.powered = powered;
  }

  @override
  Future<void> connect(BluetoothDevice device) async =>
      connects.add(device.name);

  @override
  Future<void> disconnect(BluetoothDevice device) async =>
      disconnects.add(device.name);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

// ---------------------------------------------------------------------------
// Stores
// ---------------------------------------------------------------------------

void main() {
  group('AudioDevicesStore', () {
    test('a lease reads both directions and leaves monitors out', () async {
      final store = AudioDevicesStore.forTesting(FakeAudioBackend());
      store.acquire();
      addTearDown(store.release);
      expect(store.status, AudioDevicesStatus.loading);
      await _settle();
      await _settle();
      expect(store.status, AudioDevicesStatus.ready);
      expect(store.devices(AudioDirection.output).map((d) => d.name), [
        'speakers',
        'headset',
      ]);
      expect(store.devices(AudioDirection.input).map((d) => d.name), ['mic']);
      expect(store.current(AudioDirection.output)!.name, 'speakers');
      expect(store.current(AudioDirection.input)!.volume, 0.8);
    });

    test('events move a device, add one, remove one — and an echo is '
        'silent', () async {
      final backend = FakeAudioBackend();
      final store = AudioDevicesStore.forTesting(backend);
      store.acquire();
      addTearDown(store.release);
      await _settle();
      await _settle();
      var notified = 0;
      store.addListener(() => notified++);

      backend.emitChanged(AudioDirection.output, _dev(1, 'speakers'));
      await _settle();
      expect(notified, 0, reason: 'nothing moved');

      backend.emitChanged(
        AudioDirection.output,
        _dev(1, 'speakers', volume: 0.9),
      );
      await _settle();
      expect(notified, 1);
      expect(store.current(AudioDirection.output)!.volume, 0.9);

      backend.emitChanged(AudioDirection.input, _dev(9, 'usb-mic'));
      backend.emitChanged(AudioDirection.input, _dev(10, 'x.monitor'));
      await _settle();
      expect(store.devices(AudioDirection.input).map((d) => d.name), [
        'mic',
        'usb-mic',
      ]);

      backend.emitRemoved(AudioDirection.output, 2);
      await _settle();
      expect(store.devices(AudioDirection.output).map((d) => d.name), [
        'speakers',
      ]);
    });

    test('a level write is shown at once and sent to the default', () async {
      final backend = FakeAudioBackend();
      final store = AudioDevicesStore.forTesting(backend);
      store.acquire();
      addTearDown(store.release);
      await _settle();
      await _settle();

      await store.setVolume(AudioDirection.output, 0.25);
      expect(store.current(AudioDirection.output)!.volume, 0.25);
      expect(backend.volumes, [(AudioDirection.output, 'speakers', 0.25)]);

      await store.setMuted(AudioDirection.input, true);
      expect(store.current(AudioDirection.input)!.muted, isTrue);
      expect(backend.mutes, [(AudioDirection.input, 'mic', true)]);
    });

    test('the default follows the server, not the request', () async {
      final backend = FakeAudioBackend();
      final store = AudioDevicesStore.forTesting(backend);
      store.acquire();
      addTearDown(store.release);
      await _settle();
      await _settle();

      await store.setDefault(AudioDirection.output, 'headset');
      await _settle();
      expect(backend.defaultsSet, [(AudioDirection.output, 'headset')]);
      expect(store.current(AudioDirection.output)!.name, 'headset');
    });

    test('a lease dropped and retaken mid-start subscribes once', () async {
      final backend = FakeAudioBackend();
      final store = AudioDevicesStore.forTesting(backend);
      store.acquire();
      store.release();
      store.acquire();
      addTearDown(store.release);
      await _settle();
      await _settle();
      var notified = 0;
      store.addListener(() => notified++);
      backend.emitChanged(
        AudioDirection.output,
        _dev(1, 'speakers', volume: 0.1),
      );
      await _settle();
      expect(notified, 1);
    });

    test('no server is a visible state with a retry', () async {
      final backend = FakeAudioBackend()..initFailure = Exception('no pulse');
      final store = AudioDevicesStore.forTesting(backend);
      store.acquire();
      addTearDown(store.release);
      await _settle();
      expect(store.status, AudioDevicesStatus.unavailable);
      expect(store.error, isNotEmpty);

      backend.initFailure = null;
      await store.retry();
      expect(store.status, AudioDevicesStatus.ready);
      expect(store.error, isEmpty);
    });
  });

  group('WifiStore', () {
    test('a lease reads the radio', () async {
      final store = WifiStore.forTesting(FakeWifiBackend());
      store.acquire();
      addTearDown(store.release);
      expect(store.status, WifiStatus.loading);
      await _settle();
      expect(store.status, WifiStatus.ready);
      expect(store.radio.enabled, isTrue);
    });

    test('a switch reads back; a refusal stays on screen', () async {
      final backend = FakeWifiBackend();
      final store = WifiStore.forTesting(backend);
      store.acquire();
      addTearDown(store.release);
      await _settle();

      await store.setEnabled(false);
      expect(backend.enabledCalls, [false]);
      expect(store.radio.enabled, isFalse);
      expect(store.error, isEmpty);

      backend.refuseWrites = true;
      await store.setEnabled(true);
      expect(store.radio.enabled, isFalse);
      expect(store.error, contains('refused'));
      expect(store.toggling, isFalse);
    });

    test('scans and joins', () async {
      final backend = FakeWifiBackend();
      final store = WifiStore.forTesting(backend);
      store.acquire();
      addTearDown(store.release);
      await _settle();

      await store.scan();
      expect(store.networks!.map((n) => n.name), ['Home', 'Cafe', 'Neighbour']);
      await store.connect(store.networks![1]);
      expect(backend.connected, ['Cafe']);
      expect(store.connecting, isNull);
    });

    test('NetworkManager missing is a visible state', () async {
      final backend = FakeWifiBackend()..readFailure = Exception('no NM');
      final store = WifiStore.forTesting(backend);
      store.acquire();
      addTearDown(store.release);
      await _settle();
      expect(store.status, WifiStatus.unavailable);
      expect(store.error, isNotEmpty);
    });

    test('only saved or open networks join in place', () {
      expect(wifiJoinsInPlace(_net('a', saved: true)), isTrue);
      expect(wifiJoinsInPlace(_net('b', secured: false)), isTrue);
      expect(wifiJoinsInPlace(_net('c')), isFalse);
      expect(
        wifiJoinsInPlace(_net('d', connected: true, saved: true)),
        isFalse,
      );
      expect(wifiRowAction(_net('c')), WifiRowAction.settings);
      expect(wifiRowAction(_net('e', connected: true)), WifiRowAction.none);
    });
  });

  group('BluetoothStore', () {
    test('a lease reads the adapter and keeps only paired devices', () async {
      final store = BluetoothStore.forTesting(FakeBluetoothBackend());
      store.acquire();
      addTearDown(store.release);
      await _settle();
      expect(store.status, BluetoothStatus.ready);
      expect(store.hasAdapter, isTrue);
      expect(store.powered, isTrue);
      expect(store.paired.map((d) => d.name), ['Buds', 'Keyboard']);
      expect(store.connected!.name, 'Buds');
    });

    test('re-reads on a change, and an unchanged one is silent', () async {
      final backend = FakeBluetoothBackend();
      final store = BluetoothStore.forTesting(backend);
      store.acquire();
      addTearDown(store.release);
      await _settle();
      var notified = 0;
      store.addListener(() => notified++);

      backend.emit();
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(backend.reads, 2);
      expect(notified, 0);

      // Only RSSI moved: not drawn.
      backend.devices = [
        _bt('Buds', connected: true, rssi: -40),
        _bt('Keyboard', rssi: -70),
      ];
      backend.emit();
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(notified, 0);

      backend.devices = [_bt('Buds'), _bt('Keyboard')];
      backend.emit();
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(notified, 1);
      expect(store.connected, isNull);
    });

    test('switches the adapter and toggles a connection', () async {
      final backend = FakeBluetoothBackend();
      final store = BluetoothStore.forTesting(backend);
      store.acquire();
      addTearDown(store.release);
      await _settle();

      await store.setPowered(false);
      expect(backend.poweredCalls, [false]);
      expect(store.powered, isFalse);

      await store.toggleConnection(store.paired[0]);
      await store.toggleConnection(store.paired[1]);
      expect(backend.disconnects, ['Buds']);
      expect(backend.connects, ['Keyboard']);
    });

    test('only signals about what is drawn count', () {
      DBusSignal props(String key) => DBusSignal(
        sender: 'org.bluez',
        path: DBusObjectPath('/org/bluez/hci0/dev_x'),
        interface: 'org.freedesktop.DBus.Properties',
        name: 'PropertiesChanged',
        values: [
          const DBusString('org.bluez.Device1'),
          DBusDict.stringVariant({key: const DBusBoolean(true)}),
          DBusArray.string(const []),
        ],
      );
      expect(bluezSignalMatters(props('Connected')), isTrue);
      expect(bluezSignalMatters(props('Powered')), isTrue);
      expect(bluezSignalMatters(props('RSSI')), isFalse);
      expect(
        bluezSignalMatters(
          DBusSignal(
            sender: 'org.bluez',
            path: DBusObjectPath('/'),
            interface: 'org.freedesktop.DBus.ObjectManager',
            name: 'InterfacesAdded',
            values: const [],
          ),
        ),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // The bar button
  // -------------------------------------------------------------------------

  test('the bar glyphs follow the connection, the adapter and the output', () {
    final none = quickSettingsGlyphs(
      connection: NetworkInfo.none,
      bluetoothOn: false,
      output: null,
    );
    expect(none.map((g) => g.glyph), [ShellGlyph.wifi]);
    expect(none.single.dim, isTrue);

    final all = quickSettingsGlyphs(
      connection: const NetworkInfo(
        type: NetworkType.ethernet,
        name: 'Ethernet',
        signal: 100,
        ip: '',
        prefix: 0,
      ),
      bluetoothOn: true,
      output: _dev(1, 's', muted: true),
    );
    expect(all.map((g) => g.glyph), [
      ShellGlyph.ethernet,
      ShellGlyph.bluetooth,
      ShellGlyph.volumeMuted,
    ]);
    expect(all.last.dim, isTrue);
  });

  // -------------------------------------------------------------------------
  // The panel
  // -------------------------------------------------------------------------

  group('QuickSettingsPanel', () {
    late Directory sysfs;
    setUp(() => sysfs = Directory.systemTemp.createTempSync('qs_backlight'));
    tearDown(() => sysfs.deleteSync(recursive: true));

    ({
      QuickSettingsServices services,
      FakeAudioBackend audio,
      FakeWifiBackend wifi,
      FakeBluetoothBackend bluetooth,
      FakePowerProfilesClient power,
      SettingsController settings,
      PowerMenuController powerMenu,
    })
    make({bool backlight = false}) {
      if (backlight) writeDevice(sysfs, 'intel_backlight', 600, 1200);
      final audio = FakeAudioBackend();
      final wifi = FakeWifiBackend();
      final bluetooth = FakeBluetoothBackend();
      final power = FakePowerProfilesClient();
      final settings = SettingsController.forTesting();
      final powerMenu = PowerMenuController.forTesting();
      return (
        services: QuickSettingsServices(
          wifi: WifiStore.forTesting(wifi),
          network: NetworkStatusStore.forTesting(
            query: () async => const NetworkInfo(
              type: NetworkType.wifi,
              name: 'Home',
              signal: 70,
              ip: '10.0.0.2',
              prefix: 24,
            ),
          ),
          bluetooth: BluetoothStore.forTesting(bluetooth),
          power: fakePowerStore(profiles: power),
          audio: AudioDevicesStore.forTesting(audio),
          backlight: BacklightStore.forTesting(
            sysfsRoot: sysfs.path,
            writer: (_, _) async {},
          ),
          settings: settings,
          powerMenu: powerMenu,
        ),
        audio: audio,
        wifi: wifi,
        bluetooth: bluetooth,
        power: power,
        settings: settings,
        powerMenu: powerMenu,
      );
    }

    Future<void> pump(
      WidgetTester tester,
      QuickSettingsServices services, {
      VoidCallback? onClose,
    }) async {
      await tester.pumpWidget(
        ThemeScope(
          theme: const ThemeConfig(),
          child: Align(
            alignment: Alignment.topLeft,
            child: QuickSettingsPanel(
              services: services,
              onClose: onClose ?? () {},
              output: 'DP-1',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    /// Tears the panel down so every lease is given back and no store's timer
    /// outlives the test.
    Future<void> unpump(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('draws every section from the stores', (tester) async {
      final f = make();
      await pump(tester, f.services);

      expect(find.text('Wi-Fi'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(find.text('Buds'), findsOneWidget);
      expect(find.text('Balanced'), findsOneWidget);
      expect(find.text('SPEAKERS'), findsOneWidget);
      expect(find.text('MIC'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      // No backlight on this machine: no brightness section.
      expect(find.text('Brightness'), findsNothing);
      await unpump(tester);
    });

    testWidgets('a backlight adds the brightness section', (tester) async {
      final f = make(backlight: true);
      await pump(tester, f.services);
      expect(find.text('Brightness'), findsOneWidget);
      expect(find.text('50%'), findsNWidgets(2));
      await unpump(tester);
    });

    testWidgets('each gear opens its own page of Settings, on this screen', (
      tester,
    ) async {
      final f = make(backlight: true);
      var closed = 0;
      await pump(tester, f.services, onClose: () => closed++);

      final gears = findGlyph(ShellGlyph.settings);
      // Power mode, output, input, brightness, and the footer's.
      expect(gears, findsNWidgets(5));
      final expected = [
        SettingsRoute.power,
        SettingsRoute.audioOutput,
        SettingsRoute.audioInput,
        const SettingsRoute(category: 'display'),
        const SettingsRoute.tab(OverviewTab.settings),
      ];
      for (var i = 0; i < expected.length; i++) {
        await tester.tap(gears.at(i));
        await tester.pump();
        expect(f.settings.pending, expected[i], reason: 'gear $i');
        expect(f.settings.output, 'DP-1');
        f.settings.consume();
      }
      expect(closed, expected.length);
      await unpump(tester);
    });

    testWidgets('the power menu is one tap away', (tester) async {
      final f = make();
      var closed = 0;
      await pump(tester, f.services, onClose: () => closed++);

      await tester.tap(find.text('Log out / power off…'));
      await tester.pump();
      expect(f.powerMenu.signalCount, 1);
      expect(closed, 1);
      await unpump(tester);
    });

    testWidgets('a power mode is one tap', (tester) async {
      final f = make();
      await pump(tester, f.services);

      await tester.tap(find.text('Performance'));
      await tester.pump();
      await tester.pump();
      expect(f.power.setProfiles, ['performance']);
      await unpump(tester);
    });

    testWidgets('the Wi-Fi and Bluetooth tiles switch their radios', (
      tester,
    ) async {
      final f = make();
      await pump(tester, f.services);

      await tester.tap(find.text('Wi-Fi'));
      await tester.pump();
      await tester.pump();
      expect(f.wifi.enabledCalls, [false]);
      expect(find.text('Off'), findsOneWidget);

      await tester.tap(find.text('Bluetooth'));
      await tester.pump();
      await tester.pump();
      expect(f.bluetooth.poweredCalls, [false]);
      expect(find.text('Off'), findsNWidgets(2));
      await unpump(tester);
    });

    testWidgets('a list page swaps in over the same box, and back', (
      tester,
    ) async {
      final f = make();
      await pump(tester, f.services);
      final panel = find.byType(QuickSettingsPanel);
      final size = tester.getSize(panel);

      // The output device's name opens the list of outputs.
      await tester.tap(find.text('SPEAKERS'));
      await tester.pump();
      expect(find.text('Output device'), findsOneWidget);
      expect(tester.getSize(panel), size);

      await tester.tap(find.text('HEADSET'));
      await tester.pump();
      await tester.pump();
      expect(f.audio.defaultsSet, [(AudioDirection.output, 'headset')]);

      // Back, then the Wi-Fi list, which scans on the way in.
      await tester.tap(findGlyph(ShellGlyph.chevronLeft));
      await tester.pump();
      expect(find.text('Output device'), findsNothing);
      expect(find.text('HEADSET'), findsOneWidget);

      await tester.tap(findGlyph(ShellGlyph.chevronRight).first);
      await tester.pump();
      await tester.pump();
      expect(f.wifi.scans, 1);
      expect(find.text('Cafe'), findsOneWidget);
      expect(tester.getSize(panel), size);

      // An open network joins in place; a new secured one goes to Settings.
      await tester.tap(find.text('Cafe'));
      await tester.pump();
      await tester.pump();
      expect(f.wifi.connected, ['Cafe']);

      await tester.tap(find.text('Neighbour'));
      await tester.pump();
      expect(f.settings.pending, const SettingsRoute(category: 'network'));
      await unpump(tester);
    });

    testWidgets('the Bluetooth list connects a paired device', (tester) async {
      final f = make();
      await pump(tester, f.services);

      await tester.tap(findGlyph(ShellGlyph.chevronRight).at(1));
      await tester.pump();
      expect(find.text('Keyboard'), findsOneWidget);
      expect(find.text('Stranger'), findsNothing);

      await tester.tap(find.text('Keyboard'));
      await tester.pump();
      await tester.pump();
      expect(f.bluetooth.connects, ['Keyboard']);

      await tester.tap(find.text('Bluetooth settings…'));
      await tester.pump();
      expect(f.settings.pending, const SettingsRoute(category: 'bluetooth'));
      await unpump(tester);
    });

    testWidgets('the mute buttons mute each direction', (tester) async {
      final f = make();
      await pump(tester, f.services);

      await tester.tap(findGlyph(ShellGlyph.volumeLow));
      await tester.pump();
      await tester.tap(findGlyph(ShellGlyph.microphone));
      await tester.pump();
      expect(f.audio.mutes, [
        (AudioDirection.output, 'speakers', true),
        (AudioDirection.input, 'mic', true),
      ]);
      expect(find.text('Muted'), findsNWidgets(2));
      await unpump(tester);
    });

    testWidgets('every store lease is given back on close', (tester) async {
      final f = make();
      await pump(tester, f.services);
      expect(f.services.audio.leaseCount, 1);
      expect(f.services.wifi.leaseCount, 1);
      expect(f.services.bluetooth.leaseCount, 1);
      expect(f.services.power.leaseCount, 1);
      await unpump(tester);
      expect(f.services.audio.leaseCount, 0);
      expect(f.services.wifi.leaseCount, 0);
      expect(f.services.bluetooth.leaseCount, 0);
      expect(f.services.power.leaseCount, 0);
    });
  });
}
