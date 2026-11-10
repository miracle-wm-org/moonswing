// The Bluetooth adapter and its paired devices, for the quick settings panel.
//
// The Bluetooth settings page reads BlueZ once per visit and runs discovery;
// the panel only needs the adapter's switch and the devices already paired,
// kept live while it is open. So: leased, one `GetManagedObjects` per lease
// and then a re-read only when BlueZ reports something the panel draws
// moving — a power switch, a connection, a pairing, a device appearing or
// going — never the RSSI updates discovery floods the bus with.
//
// Pairing a new device is the settings page's, which owns discovery.

import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'package:moonswing/dbus_clients.dart';
import 'package:moonswing/overlay/settings/bluetooth.dart';

/// The BlueZ calls the store makes, behind a seam for tests.
abstract class BluetoothBackend {
  Future<BluetoothScanResult> read();

  /// Fires when something [read] would answer differently has changed.
  Stream<void> get changes;

  Future<void> setPowered(DBusObjectPath adapter, bool powered);
  Future<void> connect(BluetoothDevice device);
  Future<void> disconnect(BluetoothDevice device);
}

/// The properties whose change the panel draws. Anything else — RSSI above
/// all, which discovery updates for every device in range every second — is
/// not worth a re-read.
const Set<String> _kWatchedProperties = {
  'Powered',
  'Connected',
  'Paired',
  'Name',
  'Alias',
};

/// Whether a BlueZ signal is one [BluetoothStore] has to re-read for.
@visibleForTesting
bool bluezSignalMatters(DBusSignal signal) {
  switch (signal.name) {
    case 'InterfacesAdded':
    case 'InterfacesRemoved':
      return true;
    case 'PropertiesChanged':
      final values = signal.values;
      if (values.length < 2) return false;
      final changed = values[1];
      if (changed is! DBusDict) return false;
      return changed.children.keys.any(
        (k) => k is DBusString && _kWatchedProperties.contains(k.value),
      );
    default:
      return false;
  }
}

class BluezBluetoothBackend implements BluetoothBackend {
  @override
  Future<BluetoothScanResult> read() => scanBluetooth();

  @override
  Stream<void> get changes => DBusSignalStream(
    systemBus,
    sender: 'org.bluez',
  ).where(bluezSignalMatters).map((_) {});

  @override
  Future<void> setPowered(DBusObjectPath adapter, bool powered) =>
      setBluetoothPowered(adapter, powered);

  @override
  Future<void> connect(BluetoothDevice device) =>
      connectBluetoothDevice(device);

  @override
  Future<void> disconnect(BluetoothDevice device) =>
      disconnectBluetoothDevice(device);
}

enum BluetoothStatus { idle, loading, ready, unavailable }

class BluetoothStore extends ChangeNotifier {
  BluetoothStore._(this._backend);

  static final BluetoothStore instance = BluetoothStore._(
    BluezBluetoothBackend(),
  );

  @visibleForTesting
  factory BluetoothStore.forTesting(BluetoothBackend backend) =>
      BluetoothStore._(backend);

  final BluetoothBackend _backend;

  BluetoothStatus _status = BluetoothStatus.idle;
  BluetoothStatus get status => _status;

  DBusObjectPath? _adapter;

  /// Whether the machine has an adapter at all.
  bool get hasAdapter => _adapter != null;

  bool _powered = false;
  bool get powered => _powered;

  List<BluetoothDevice> _paired = const [];

  /// The paired devices, connected first.
  List<BluetoothDevice> get paired => _paired;

  /// What the bar and the tile name: the first connected device, if any.
  BluetoothDevice? get connected {
    for (final d in _paired) {
      if (d.connected) return d;
    }
    return null;
  }

  String _error = '';
  String get error => _error;

  bool _toggling = false;
  bool get toggling => _toggling;

  String? _busyAddress;

  /// The device a connect or disconnect is in flight for, by address.
  String? get busyAddress => _busyAddress;

  // --- leases --------------------------------------------------------------

  int _leases = 0;
  StreamSubscription<void>? _changesSub;
  Timer? _debounce;

  @visibleForTesting
  int get leaseCount => _leases;

  void acquire() {
    _leases++;
    if (_leases > 1) return;
    if (_status == BluetoothStatus.idle) _status = BluetoothStatus.loading;
    try {
      _changesSub = _backend.changes.listen((_) {
        _debounce?.cancel();
        _debounce = Timer(
          const Duration(milliseconds: 200),
          () => unawaited(_read()),
        );
      }, onError: (Object _) {});
    } catch (_) {
      // No bus: the read reports it.
    }
    unawaited(_read());
  }

  void release() {
    if (_leases == 0) return;
    _leases--;
    if (_leases > 0) return;
    _debounce?.cancel();
    _debounce = null;
    unawaited(_changesSub?.cancel());
    _changesSub = null;
  }

  Future<void> retry() => _read();

  /// What [_read] last published, so a re-read that moved nothing the panel
  /// draws does not notify.
  String _signature = '';

  Future<void> _read() async {
    try {
      final result = await _backend.read();
      if (_leases == 0) return;
      final paired = [
        for (final d in result.devices)
          if (d.paired) d,
      ];
      final signature = [
        result.adapterPath?.value,
        result.adapterPowered,
        for (final d in paired) '${d.address}|${d.name}|${d.connected}',
      ].join(';');
      final moved =
          signature != _signature ||
          _status != BluetoothStatus.ready ||
          _error.isNotEmpty;
      _error = '';
      _signature = signature;
      _adapter = result.adapterPath;
      _powered = result.adapterPowered;
      _paired = List.unmodifiable(paired);
      _status = BluetoothStatus.ready;
      if (moved) notifyListeners();
    } catch (e) {
      if (_leases == 0) return;
      debugPrint('Could not read Bluetooth: $e');
      _status = BluetoothStatus.unavailable;
      _error = 'BlueZ is not answering.';
      notifyListeners();
    }
  }

  /// Switches the adapter. Shown as the adapter reports it afterwards.
  Future<void> setPowered(bool powered) async {
    final adapter = _adapter;
    if (adapter == null || _toggling || _powered == powered) return;
    _toggling = true;
    notifyListeners();
    try {
      await _backend.setPowered(adapter, powered);
      _error = '';
    } catch (e) {
      debugPrint('Could not switch Bluetooth: $e');
      _error = 'Could not turn Bluetooth ${powered ? 'on' : 'off'}.';
    } finally {
      _toggling = false;
    }
    final error = _error;
    await _read();
    if (error.isNotEmpty) _error = error;
    notifyListeners();
  }

  /// Connects [device] if it is not connected, disconnects it if it is.
  Future<void> toggleConnection(BluetoothDevice device) async {
    if (_busyAddress != null) return;
    _busyAddress = device.address;
    _error = '';
    notifyListeners();
    try {
      if (device.connected) {
        await _backend.disconnect(device);
      } else {
        await _backend.connect(device);
      }
    } catch (e) {
      debugPrint('Bluetooth ${device.connected ? 'dis' : ''}connect: $e');
      _error = device.connected
          ? 'Could not disconnect ${device.name}.'
          : 'Could not connect to ${device.name}.';
    } finally {
      _busyAddress = null;
    }
    final error = _error;
    await _read();
    if (error.isNotEmpty) _error = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _changesSub?.cancel();
    super.dispose();
  }
}
