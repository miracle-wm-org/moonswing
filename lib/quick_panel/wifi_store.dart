// The Wi-Fi radio and the networks in range, for the quick settings panel.
//
// The connection itself — which network, what signal — is the network
// module's `NetworkStatusStore`; this is what that store does not answer:
// whether the radio is on, whether there is a radio at all, and the list a
// user picks from. Leased like every store: the first lease reads the radio
// and subscribes to NetworkManager's property changes, the last one
// unsubscribes. Nothing polls — the radio is signal-driven, and the list is
// scanned only when the panel's Wi-Fi page asks for it.

import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'package:moonswing/dbus_clients.dart';
import 'package:moonswing/modules/network.dart';

/// What NetworkManager says about the radio.
@immutable
class WifiRadio {
  const WifiRadio({
    required this.hasDevice,
    required this.enabled,
    required this.hardwareEnabled,
  });

  /// Whether the machine has a Wi-Fi device at all. A desktop on a cable
  /// usually does not, and the tile says so rather than offering a switch.
  final bool hasDevice;

  /// The software switch, `WirelessEnabled`.
  final bool enabled;

  /// The rfkill switch, `WirelessHardwareEnabled` — a key or a slider on the
  /// machine that no software can override.
  final bool hardwareEnabled;

  static const WifiRadio none = WifiRadio(
    hasDevice: false,
    enabled: false,
    hardwareEnabled: false,
  );

  @override
  bool operator ==(Object other) =>
      other is WifiRadio &&
      other.hasDevice == hasDevice &&
      other.enabled == enabled &&
      other.hardwareEnabled == hardwareEnabled;

  @override
  int get hashCode => Object.hash(hasDevice, enabled, hardwareEnabled);
}

/// The NetworkManager calls the store makes, behind a seam for tests.
abstract class WifiBackend {
  Future<WifiRadio> readRadio();
  Future<void> setEnabled(bool enabled);

  /// Fires whenever NetworkManager's own properties move — the radio, the
  /// active connections, the connectivity check.
  Stream<void> get changes;

  /// Asks for a scan and returns what is in range, best first.
  Future<List<AvailableNetwork>> scan();
  Future<void> connect(AvailableNetwork network);
}

const _nmService = 'org.freedesktop.NetworkManager';
const _nmDevIface = 'org.freedesktop.NetworkManager.Device';

class NetworkManagerWifiBackend implements WifiBackend {
  DBusRemoteObject get _nm => DBusRemoteObject(
    systemBus,
    name: _nmService,
    path: DBusObjectPath('/org/freedesktop/NetworkManager'),
  );

  static bool _bool(DBusValue value) =>
      value is DBusBoolean ? value.value : false;

  @override
  Future<WifiRadio> readRadio() async {
    final nm = _nm;
    final props = await nm.getAllProperties(_nmService);
    final devices = await nm.callMethod(
      _nmService,
      'GetDevices',
      [],
      replySignature: DBusSignature('ao'),
    );
    var hasDevice = false;
    for (final path
        in (devices.returnValues[0] as DBusArray).children
            .cast<DBusObjectPath>()) {
      try {
        final type = await DBusRemoteObject(
          systemBus,
          name: _nmService,
          path: path,
        ).getProperty(_nmDevIface, 'DeviceType');
        if (type is DBusUint32 && type.value == 2) {
          hasDevice = true;
          break;
        }
      } catch (_) {
        // One device that will not answer costs that device.
      }
    }
    return WifiRadio(
      hasDevice: hasDevice,
      enabled: _bool(props['WirelessEnabled'] ?? const DBusBoolean(false)),
      hardwareEnabled: _bool(
        props['WirelessHardwareEnabled'] ?? const DBusBoolean(true),
      ),
    );
  }

  @override
  Future<void> setEnabled(bool enabled) =>
      _nm.setProperty(_nmService, 'WirelessEnabled', DBusBoolean(enabled));

  @override
  Stream<void> get changes => _nm.propertiesChanged
      .where((s) => s.propertiesInterface == _nmService)
      .map((_) {});

  @override
  Future<List<AvailableNetwork>> scan() async => [
    for (final n in await scanNetworks())
      if (n.type == NetworkType.wifi) n,
  ];

  @override
  Future<void> connect(AvailableNetwork network) =>
      connectToNetwork(network: network);
}

enum WifiStatus { idle, loading, ready, unavailable }

class WifiStore extends ChangeNotifier {
  WifiStore._(this._backend);

  static final WifiStore instance = WifiStore._(NetworkManagerWifiBackend());

  @visibleForTesting
  factory WifiStore.forTesting(WifiBackend backend) => WifiStore._(backend);

  final WifiBackend _backend;

  // --- the radio -----------------------------------------------------------

  WifiStatus _status = WifiStatus.idle;
  WifiStatus get status => _status;

  WifiRadio _radio = WifiRadio.none;
  WifiRadio get radio => _radio;

  String _error = '';

  /// Why NetworkManager could not be read, or why the last write was
  /// refused; empty once something succeeds.
  String get error => _error;

  bool _toggling = false;

  /// Whether a switch of the radio is in flight.
  bool get toggling => _toggling;

  // --- the list ------------------------------------------------------------

  List<AvailableNetwork>? _networks;

  /// What the last scan found, or null before one has finished.
  List<AvailableNetwork>? get networks => _networks;

  bool _scanning = false;
  bool get scanning => _scanning;

  String _scanError = '';
  String get scanError => _scanError;

  String? _connecting;

  /// The network a connection is being made to, by name.
  String? get connecting => _connecting;

  String _connectError = '';
  String get connectError => _connectError;

  // --- leases --------------------------------------------------------------

  int _leases = 0;
  StreamSubscription<void>? _changesSub;
  Timer? _changeDebounce;

  @visibleForTesting
  int get leaseCount => _leases;

  void acquire() {
    _leases++;
    if (_leases > 1) return;
    if (_status == WifiStatus.idle) _status = WifiStatus.loading;
    try {
      _changesSub = _backend.changes.listen((_) {
        // NetworkManager emits a burst per change — the radio, then each
        // device's state, then the connectivity check. One re-read for it.
        _changeDebounce?.cancel();
        _changeDebounce = Timer(
          const Duration(milliseconds: 150),
          () => unawaited(_readRadio()),
        );
      }, onError: (Object _) {});
    } catch (_) {
      // No bus: the read below reports it.
    }
    unawaited(_readRadio());
  }

  void release() {
    if (_leases == 0) return;
    _leases--;
    if (_leases > 0) return;
    _changeDebounce?.cancel();
    _changeDebounce = null;
    unawaited(_changesSub?.cancel());
    _changesSub = null;
  }

  Future<void> retry() => _readRadio();

  Future<void> _readRadio() async {
    try {
      final radio = await _backend.readRadio();
      if (_leases == 0) return;
      final moved =
          radio != _radio || _status != WifiStatus.ready || _error.isNotEmpty;
      _radio = radio;
      _status = WifiStatus.ready;
      _error = '';
      if (moved) notifyListeners();
    } catch (e) {
      if (_leases == 0) return;
      _status = WifiStatus.unavailable;
      _error = 'NetworkManager is not answering.';
      debugPrint('Could not read the Wi-Fi radio: $e');
      notifyListeners();
    }
  }

  /// Turns the radio on or off. The tile follows NetworkManager's answer, not
  /// the request: a refusal (polkit, rfkill) leaves it where it was, with the
  /// reason under it.
  Future<void> setEnabled(bool enabled) async {
    if (_toggling || !_radio.hasDevice || _radio.enabled == enabled) return;
    _toggling = true;
    notifyListeners();
    try {
      await _backend.setEnabled(enabled);
      _error = '';
    } catch (e) {
      debugPrint('Could not switch Wi-Fi: $e');
      _error =
          'NetworkManager refused to turn Wi-Fi ${enabled ? 'on' : 'off'}.';
    } finally {
      _toggling = false;
    }
    final error = _error;
    await _readRadio();
    // The read-back clears the error on success; a refusal must outlive it.
    if (error.isNotEmpty && _error.isEmpty) _error = error;
    if (!enabled) _networks = null;
    notifyListeners();
    if (enabled) unawaited(NetworkStatusStore.instance.refresh());
  }

  /// Scans for networks. A scan already running is not started twice.
  Future<void> scan() async {
    if (_scanning) return;
    _scanning = true;
    _scanError = '';
    notifyListeners();
    try {
      final found = await _backend.scan();
      _networks = List.unmodifiable(found);
    } catch (e) {
      debugPrint('Wi-Fi scan failed: $e');
      _scanError = 'Could not scan for networks.';
    } finally {
      _scanning = false;
    }
    notifyListeners();
  }

  /// Connects to [network]. Only for one NetworkManager can join without
  /// asking anything — a saved profile or an open network; the panel sends
  /// a new secured network to Settings › Network, which has the password
  /// field.
  Future<void> connect(AvailableNetwork network) async {
    if (_connecting != null) return;
    _connecting = network.name;
    _connectError = '';
    notifyListeners();
    try {
      await _backend.connect(network);
    } catch (e) {
      debugPrint('Could not connect to ${network.name}: $e');
      _connectError = 'Could not connect to ${network.name}.';
    } finally {
      _connecting = null;
    }
    notifyListeners();
    unawaited(NetworkStatusStore.instance.refresh());
    if (_connectError.isEmpty) unawaited(scan());
  }

  @override
  void dispose() {
    _changeDebounce?.cancel();
    _changesSub?.cancel();
    super.dispose();
  }
}

/// Whether the panel can join [network] in place: it is not the one already
/// joined, and NetworkManager will need nothing typed for it.
bool wifiJoinsInPlace(AvailableNetwork network) =>
    !network.isConnected &&
    (network.savedConnectionPath != null || !network.secured);
