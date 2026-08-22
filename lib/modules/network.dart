// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'package:dbus/dbus.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

class NetworkConfig {
  final int pollSeconds;

  const NetworkConfig({this.pollSeconds = 10});

  factory NetworkConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NetworkConfig();
    return NetworkConfig(
      pollSeconds: map.intOr('poll_seconds', 10),
    );
  }
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

enum NetworkType { none, ethernet, wifi }

class NetworkInfo {
  final NetworkType type;
  final String name; // 'Ethernet' or WiFi SSID
  final int signal; // 0–100 (wifi strength; ethernet is always 100)
  final String ip; // e.g. '192.168.1.42'
  final int prefix; // subnet prefix, e.g. 24

  const NetworkInfo({
    required this.type,
    required this.name,
    required this.signal,
    required this.ip,
    required this.prefix,
  });

  static const none = NetworkInfo(
    type: NetworkType.none,
    name: 'Disconnected',
    signal: 0,
    ip: '',
    prefix: 0,
  );
}

class AvailableNetwork {
  final NetworkType type;
  final String name;
  final int signal; // 0–100
  final bool secured;
  final bool isConnected;
  final DBusObjectPath devicePath;
  final DBusObjectPath? apPath;
  final DBusObjectPath? savedConnectionPath;

  const AvailableNetwork({
    required this.type,
    required this.name,
    required this.signal,
    required this.secured,
    required this.isConnected,
    required this.devicePath,
    this.apPath,
    this.savedConnectionPath,
  });
}

// ---------------------------------------------------------------------------
// NetworkManager D-Bus helpers
// ---------------------------------------------------------------------------

const _nmService = 'org.freedesktop.NetworkManager';
const _nmDevIface = 'org.freedesktop.NetworkManager.Device';
const _nmWifiIface = 'org.freedesktop.NetworkManager.Device.Wireless';
const _nmApIface = 'org.freedesktop.NetworkManager.AccessPoint';
const _nmIp4Iface = 'org.freedesktop.NetworkManager.IP4Config';
const _nmSettingsIface = 'org.freedesktop.NetworkManager.Settings';
const _nmConnSettingsIface =
    'org.freedesktop.NetworkManager.Settings.Connection';

Future<NetworkInfo> _queryNetworkInfo() async {
  final client = DBusClient.system();
  try {
    final nmObj = DBusRemoteObject(
      client,
      name: _nmService,
      path: DBusObjectPath('/org/freedesktop/NetworkManager'),
    );

    final devicesResult = await nmObj.callMethod(
      _nmService,
      'GetDevices',
      [],
      replySignature: DBusSignature('ao'),
    );
    final devicePaths = (devicesResult.returnValues[0] as DBusArray)
        .children
        .cast<DBusObjectPath>();

    for (final devPath in devicePaths) {
      final devObj = DBusRemoteObject(client, name: _nmService, path: devPath);

      final stateVal =
          await devObj.getProperty(_nmDevIface, 'State') as DBusUint32;
      if (stateVal.value != 100) continue; // not activated

      final typeVal =
          await devObj.getProperty(_nmDevIface, 'DeviceType') as DBusUint32;
      final deviceType = typeVal.value;
      if (deviceType != 1 && deviceType != 2) continue; // not eth or wifi

      // Gather IP address
      String ip = '';
      int prefix = 0;
      try {
        final ip4Val = await devObj.getProperty(_nmDevIface, 'Ip4Config')
            as DBusObjectPath;
        if (ip4Val.value != '/') {
          final ip4Obj =
              DBusRemoteObject(client, name: _nmService, path: ip4Val);
          final addrDataVal =
              await ip4Obj.getProperty(_nmIp4Iface, 'AddressData') as DBusArray;
          if (addrDataVal.children.isNotEmpty) {
            final first = (addrDataVal.children.first as DBusDict).children;
            ip = ((first[const DBusString('address')] as DBusVariant).value
                    as DBusString)
                .value;
            prefix = ((first[const DBusString('prefix')] as DBusVariant).value
                    as DBusUint32)
                .value;
          }
        }
      } catch (_) {}

      if (deviceType == 1) {
        // Ethernet
        return NetworkInfo(
          type: NetworkType.ethernet,
          name: 'Ethernet',
          signal: 100,
          ip: ip,
          prefix: prefix,
        );
      } else {
        // WiFi (deviceType == 2)
        String ssid = 'WiFi';
        int strength = 0;
        try {
          final apVal = await devObj.getProperty(
              _nmWifiIface, 'ActiveAccessPoint') as DBusObjectPath;
          if (apVal.value != '/') {
            final apObj =
                DBusRemoteObject(client, name: _nmService, path: apVal);
            final ssidVal =
                await apObj.getProperty(_nmApIface, 'Ssid') as DBusArray;
            ssid = String.fromCharCodes(
                ssidVal.children.cast<DBusByte>().map((b) => b.value));
            final strengthVal =
                await apObj.getProperty(_nmApIface, 'Strength') as DBusByte;
            strength = strengthVal.value;
          }
        } catch (_) {}

        return NetworkInfo(
          type: NetworkType.wifi,
          name: ssid,
          signal: strength,
          ip: ip,
          prefix: prefix,
        );
      }
    }
  } catch (_) {
    // NetworkManager unavailable or query error
  } finally {
    await client.close();
  }
  return NetworkInfo.none;
}

DBusDict _innerDict(Map<String, DBusValue> map) {
  return DBusDict(
    DBusSignature('s'),
    DBusSignature('v'),
    {for (final e in map.entries) DBusString(e.key): DBusVariant(e.value)},
  );
}

DBusDict _buildConnectionDict(AvailableNetwork network, String? password) {
  final sections = <DBusValue, DBusValue>{
    DBusString('connection'): _innerDict({
      'id': DBusString(network.name),
      'type': DBusString('802-11-wireless'),
    }),
    DBusString('802-11-wireless'): _innerDict({
      'ssid': DBusArray.byte(network.name.codeUnits),
      'mode': DBusString('infrastructure'),
    }),
    DBusString('ipv4'): _innerDict({'method': DBusString('auto')}),
    DBusString('ipv6'): _innerDict({'method': DBusString('ignore')}),
  };

  if (network.secured && password != null && password.isNotEmpty) {
    sections[DBusString('802-11-wireless-security')] = _innerDict({
      'key-mgmt': DBusString('wpa-psk'),
      'psk': DBusString(password),
    });
  }

  return DBusDict(DBusSignature('s'), DBusSignature('a{sv}'), sections);
}

Future<List<AvailableNetwork>> scanNetworks() async {
  final client = DBusClient.system();
  final results = <AvailableNetwork>[];
  try {
    final nmObj = DBusRemoteObject(
      client,
      name: _nmService,
      path: DBusObjectPath('/org/freedesktop/NetworkManager'),
    );

    final devicesResult = await nmObj.callMethod(
      _nmService,
      'GetDevices',
      [],
      replySignature: DBusSignature('ao'),
    );
    final devicePaths = (devicesResult.returnValues[0] as DBusArray)
        .children
        .cast<DBusObjectPath>();

    // Build map of saved WiFi profiles: SSID → connection path
    final savedBySsid = <String, DBusObjectPath>{};
    try {
      final settingsObj = DBusRemoteObject(
        client,
        name: _nmService,
        path: DBusObjectPath('/org/freedesktop/NetworkManager/Settings'),
      );
      final connsResult = await settingsObj.callMethod(
        _nmSettingsIface,
        'ListConnections',
        [],
        replySignature: DBusSignature('ao'),
      );
      final connPaths = (connsResult.returnValues[0] as DBusArray)
          .children
          .cast<DBusObjectPath>();
      for (final cp in connPaths) {
        try {
          final connObj = DBusRemoteObject(client, name: _nmService, path: cp);
          final settingsResult = await connObj.callMethod(
            _nmConnSettingsIface,
            'GetSettings',
            [],
            replySignature: DBusSignature('a{sa{sv}}'),
          );
          final outer = (settingsResult.returnValues[0] as DBusDict).children;
          final wifiSection = outer[DBusString('802-11-wireless')] as DBusDict?;
          if (wifiSection != null) {
            final ssidEntry =
                wifiSection.children[DBusString('ssid')] as DBusVariant?;
            final ssidArr = ssidEntry?.value as DBusArray?;
            if (ssidArr != null) {
              final ssid = String.fromCharCodes(
                ssidArr.children
                    .cast<DBusByte>()
                    .map((b) => b.value)
                    .where((c) => c != 0),
              );
              if (ssid.isNotEmpty) savedBySsid[ssid] = cp;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    for (final devPath in devicePaths) {
      final devObj = DBusRemoteObject(client, name: _nmService, path: devPath);

      final typeVal =
          await devObj.getProperty(_nmDevIface, 'DeviceType') as DBusUint32;
      final deviceType = typeVal.value;

      if (deviceType == 1) {
        // Ethernet — include only if activated
        final stateVal =
            await devObj.getProperty(_nmDevIface, 'State') as DBusUint32;
        if (stateVal.value == 100) {
          results.add(AvailableNetwork(
            type: NetworkType.ethernet,
            name: 'Ethernet',
            signal: 100,
            secured: false,
            isConnected: true,
            devicePath: devPath,
          ));
        }
      } else if (deviceType == 2) {
        // WiFi
        var activeApPath = DBusObjectPath('/');
        try {
          activeApPath = await devObj.getProperty(
              _nmWifiIface, 'ActiveAccessPoint') as DBusObjectPath;
        } catch (_) {}

        try {
          await devObj.callMethod(
            _nmWifiIface,
            'RequestScan',
            [DBusDict(DBusSignature('s'), DBusSignature('v'), {})],
            replySignature: DBusSignature(''),
          );
          await Future.delayed(const Duration(milliseconds: 1500));
        } catch (_) {}

        try {
          final apsResult = await devObj.callMethod(
            _nmWifiIface,
            'GetAllAccessPoints',
            [],
            replySignature: DBusSignature('ao'),
          );
          final apPaths = (apsResult.returnValues[0] as DBusArray)
              .children
              .cast<DBusObjectPath>();

          for (final apPath in apPaths) {
            try {
              final apObj =
                  DBusRemoteObject(client, name: _nmService, path: apPath);

              final ssidBytes =
                  await apObj.getProperty(_nmApIface, 'Ssid') as DBusArray;
              final ssid = String.fromCharCodes(
                ssidBytes.children
                    .cast<DBusByte>()
                    .map((b) => b.value)
                    .where((c) => c != 0),
              );
              if (ssid.isEmpty) continue;

              final strengthVal =
                  await apObj.getProperty(_nmApIface, 'Strength') as DBusByte;
              final flagsVal =
                  await apObj.getProperty(_nmApIface, 'Flags') as DBusUint32;
              final wpaFlagsVal =
                  await apObj.getProperty(_nmApIface, 'WpaFlags') as DBusUint32;
              final rsnFlagsVal =
                  await apObj.getProperty(_nmApIface, 'RsnFlags') as DBusUint32;

              final secured = (flagsVal.value & 0x1) != 0 ||
                  wpaFlagsVal.value != 0 ||
                  rsnFlagsVal.value != 0;

              results.add(AvailableNetwork(
                type: NetworkType.wifi,
                name: ssid,
                signal: strengthVal.value,
                secured: secured,
                isConnected: apPath.value == activeApPath.value &&
                    activeApPath.value != '/',
                devicePath: devPath,
                apPath: apPath,
                savedConnectionPath: savedBySsid[ssid],
              ));
            } catch (_) {}
          }
        } catch (_) {}
      }
    }
  } catch (_) {
    // NM unavailable
  } finally {
    await client.close();
  }

  // Sort: connected first, then by signal descending
  results.sort((a, b) {
    if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
    return b.signal.compareTo(a.signal);
  });

  // Deduplicate by name (keep first occurrence = highest signal)
  final seen = <String>{};
  return results.where((n) => seen.add(n.name)).toList();
}

Future<void> connectToNetwork({
  required AvailableNetwork network,
  String? password,
}) async {
  final client = DBusClient.system();
  try {
    final nmObj = DBusRemoteObject(
      client,
      name: _nmService,
      path: DBusObjectPath('/org/freedesktop/NetworkManager'),
    );

    if (network.savedConnectionPath != null) {
      await nmObj.callMethod(
        _nmService,
        'ActivateConnection',
        [
          network.savedConnectionPath!,
          network.devicePath,
          network.apPath ?? DBusObjectPath('/'),
        ],
        replySignature: DBusSignature('o'),
      );
    } else {
      await nmObj.callMethod(
        _nmService,
        'AddAndActivateConnection',
        [
          _buildConnectionDict(network, password),
          network.devicePath,
          network.apPath ?? DBusObjectPath('/'),
        ],
        replySignature: DBusSignature('oo'),
      );
    }
  } finally {
    await client.close();
  }
}

// ---------------------------------------------------------------------------
// Bar widget
// ---------------------------------------------------------------------------

class Network extends StatefulWidget {
  const Network({super.key, required this.config});

  final NetworkConfig config;

  @override
  NetworkState createState() => NetworkState();
}

class NetworkState extends State<Network> with PopupHost<Network> {
  NetworkInfo _info = NetworkInfo.none;
  Timer? _timer;


  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(
        Duration(seconds: widget.config.pollSeconds), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    closePopup();
    super.dispose();
  }

  Future<void> _poll() async {
    final info = await _queryNetworkInfo();
    if (mounted) setState(() => _info = info);
  }

  // -------------------------------------------------------------------------
  // Popup
  // -------------------------------------------------------------------------

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }

    openBarPopup(
      context,
      // Loose, so the popup hugs its content: on ethernet the signal-strength
      // rows are not built at all, and a tight box would reserve their height
      // anyway. The maxima are a runaway guard, not a size.
      preferredConstraints: const BoxConstraints(maxWidth: 320, maxHeight: 400),
      child: ThemeProvider(
        child: _NetworkPopupContent(info: _info),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Bar widget
  // -------------------------------------------------------------------------

  FaIconData _networkIcon() {
    switch (_info.type) {
      case NetworkType.ethernet:
        return FontAwesomeIcons.ethernet;
      case NetworkType.wifi:
      case NetworkType.none:
        return FontAwesomeIcons.wifi;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final isNone = _info.type == NetworkType.none;
    // ignore: deprecated_member_use
    final dimColor = theme.foreground.withOpacity(0.4);

    return BarButton(
      active: isPopupOpen,
      onTapDown: (_) => _togglePopup(context),
      child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                _networkIcon(),
                size: 12,
                color: isNone ? dimColor : theme.foreground,
              ),
              const SizedBox(width: 4),
              Text(
                _info.name,
                style: TextStyle(
                  fontSize: 16,
                  color: isNone ? dimColor : theme.foreground,
                ),
              ),
            ],
          ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bar popup
// ---------------------------------------------------------------------------

class _NetworkPopupContent extends StatelessWidget {
  const _NetworkPopupContent({required this.info});

  final NetworkInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final fg = theme.popupForeground;

    // ignore: deprecated_member_use
    final labelStyle = TextStyle(fontSize: 11, color: fg.withOpacity(0.6));
    final valueStyle = TextStyle(fontSize: 14, color: fg);

    final ipText = info.ip.isEmpty ? '—' : '${info.ip}/${info.prefix}';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: PopupBounceIn(
        child: PopupCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('IP Address', style: labelStyle),
              const SizedBox(height: 2),
              Text(ipText, style: valueStyle),
              if (info.type == NetworkType.wifi) ...[
                const SizedBox(height: 10),
                Text('Signal Strength', style: labelStyle),
                const SizedBox(height: 2),
                Text('${info.signal}%', style: valueStyle),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Module
// ---------------------------------------------------------------------------

class NetworkModule extends Module {
  NetworkConfig _config = const NetworkConfig();

  @override
  String get configKey => 'network';

  @override
  void loadConfig(Map<String, dynamic>? map) {
    _config = NetworkConfig.fromMap(map);
  }

  @override
  WidgetBuilder get builder => (context) => Network(config: _config);
}
