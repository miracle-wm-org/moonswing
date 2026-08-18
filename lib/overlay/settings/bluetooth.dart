// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'package:dbus/dbus.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/scopes.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class BluetoothDevice {
  final String name;
  final String address;
  final bool connected;
  final bool paired;
  final int? rssi;
  final String? icon;
  final DBusObjectPath objectPath;

  const BluetoothDevice({
    required this.name,
    required this.address,
    required this.connected,
    required this.paired,
    required this.objectPath,
    this.rssi,
    this.icon,
  });
}

class BluetoothScanResult {
  final DBusObjectPath? adapterPath;
  final bool adapterPowered;
  final List<BluetoothDevice> devices;

  const BluetoothScanResult({
    required this.adapterPath,
    required this.adapterPowered,
    required this.devices,
  });
}

// ---------------------------------------------------------------------------
// BlueZ D-Bus helpers
// ---------------------------------------------------------------------------

const _bluezService = 'org.bluez';
const _adapterIface = 'org.bluez.Adapter1';
const _deviceIface = 'org.bluez.Device1';
const _objectManagerIface = 'org.freedesktop.DBus.ObjectManager';

// Parse a GetManagedObjects result into a BluetoothScanResult.
BluetoothScanResult _parseObjects(Map<DBusValue, DBusValue> objects) {
  DBusObjectPath? adapterPath;
  bool adapterPowered = false;
  final devices = <BluetoothDevice>[];

  for (final entry in objects.entries) {
    final objectPath = entry.key as DBusObjectPath;
    final interfaces = (entry.value as DBusDict).children;

    if (adapterPath == null &&
        interfaces.containsKey(const DBusString(_adapterIface))) {
      try {
        final props =
            (interfaces[const DBusString(_adapterIface)]! as DBusDict).children;
        final poweredVal = props[const DBusString('Powered')];
        if (poweredVal != null) {
          adapterPowered =
              ((poweredVal as DBusVariant).value as DBusBoolean).value;
        }
        adapterPath = objectPath;
      } catch (_) {}
    }

    if (!interfaces.containsKey(const DBusString(_deviceIface))) continue;

    try {
      final props =
          (interfaces[const DBusString(_deviceIface)]! as DBusDict).children;

      String? addressStr;
      final addrVal = props[const DBusString('Address')];
      if (addrVal != null) {
        addressStr = ((addrVal as DBusVariant).value as DBusString).value;
      }
      if (addressStr == null) continue;

      String name = addressStr;
      final nameVal = props[const DBusString('Name')];
      if (nameVal != null) {
        name = ((nameVal as DBusVariant).value as DBusString).value;
      }

      bool connected = false;
      final connVal = props[const DBusString('Connected')];
      if (connVal != null) {
        connected = ((connVal as DBusVariant).value as DBusBoolean).value;
      }

      bool paired = false;
      final pairedVal = props[const DBusString('Paired')];
      if (pairedVal != null) {
        paired = ((pairedVal as DBusVariant).value as DBusBoolean).value;
      }

      int? rssi;
      final rssiVal = props[const DBusString('RSSI')];
      if (rssiVal != null) {
        rssi = ((rssiVal as DBusVariant).value as DBusInt16).value;
      }

      String? icon;
      final iconVal = props[const DBusString('Icon')];
      if (iconVal != null) {
        icon = ((iconVal as DBusVariant).value as DBusString).value;
      }

      devices.add(BluetoothDevice(
        name: name,
        address: addressStr,
        connected: connected,
        paired: paired,
        rssi: rssi,
        icon: icon,
        objectPath: objectPath,
      ));
    } catch (_) {}
  }

  devices.sort((a, b) {
    if (a.connected != b.connected) return a.connected ? -1 : 1;
    if (a.paired != b.paired) return a.paired ? -1 : 1;
    final aRssi = a.rssi ?? -999;
    final bRssi = b.rssi ?? -999;
    return bRssi.compareTo(aRssi);
  });

  return BluetoothScanResult(
    adapterPath: adapterPath,
    adapterPowered: adapterPowered,
    devices: devices,
  );
}

// Fetch adapter + device state. When discover=true, runs StartDiscovery,
// waits, then re-fetches — all on a single persistent client so BlueZ
// keeps discovery active (BlueZ stops discovery when the requesting client
// disconnects).
Future<BluetoothScanResult> scanBluetooth({bool discover = false}) async {
  final client = DBusClient.system();
  try {
    final root = DBusRemoteObject(
      client,
      name: _bluezService,
      path: DBusObjectPath('/'),
    );

    Future<BluetoothScanResult> fetch() async {
      final r = await root.callMethod(
        _objectManagerIface,
        'GetManagedObjects',
        [],
        replySignature: DBusSignature('a{oa{sa{sv}}}'),
      );
      return _parseObjects((r.returnValues[0] as DBusDict).children);
    }

    final initial = await fetch();

    if (discover && initial.adapterPowered && initial.adapterPath != null) {
      final adapter = DBusRemoteObject(
        client,
        name: _bluezService,
        path: initial.adapterPath!,
      );
      await adapter.callMethod(
        _adapterIface,
        'StartDiscovery',
        [],
        replySignature: DBusSignature(''),
      );
      await Future.delayed(const Duration(seconds: 5));
      final fresh = await fetch();
      try {
        await adapter.callMethod(
          _adapterIface,
          'StopDiscovery',
          [],
          replySignature: DBusSignature(''),
        );
      } catch (_) {}
      return fresh;
    }

    return initial;
  } finally {
    await client.close();
  }
}

Future<void> setBluetoothPowered(
    DBusObjectPath adapterPath, bool powered) async {
  final client = DBusClient.system();
  try {
    final adapter = DBusRemoteObject(
      client,
      name: _bluezService,
      path: adapterPath,
    );
    await adapter.setProperty(_adapterIface, 'Powered', DBusBoolean(powered));
  } finally {
    await client.close();
  }
}

Future<void> connectBluetoothDevice(BluetoothDevice device) async {
  final client = DBusClient.system();
  try {
    final obj = DBusRemoteObject(
      client,
      name: _bluezService,
      path: device.objectPath,
    );
    await obj.callMethod(
      _deviceIface,
      'Connect',
      [],
      replySignature: DBusSignature(''),
    );
  } finally {
    await client.close();
  }
}

Future<void> disconnectBluetoothDevice(BluetoothDevice device) async {
  final client = DBusClient.system();
  try {
    final obj = DBusRemoteObject(
      client,
      name: _bluezService,
      path: device.objectPath,
    );
    await obj.callMethod(
      _deviceIface,
      'Disconnect',
      [],
      replySignature: DBusSignature(''),
    );
  } finally {
    await client.close();
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _BtConnectedBadge extends StatelessWidget {
  const _BtConnectedBadge();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.accent, width: 1),
      ),
      child: Text(
        'Connected',
        style: TextStyle(fontSize: 11, color: theme.accent),
      ),
    );
  }
}

class _BtUnpairedBadge extends StatelessWidget {
  const _BtUnpairedBadge();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x00000000),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.popupForeground.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Text(
        'Unpaired',
        style: TextStyle(
          fontSize: 11,
          color: theme.popupForeground.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _BtActionButton extends StatefulWidget {
  const _BtActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  _BtActionButtonState createState() => _BtActionButtonState();
}

class _BtActionButtonState extends State<_BtActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color bg;
    if (widget.primary) {
      bg = _hovered ? theme.accent.withValues(alpha: 0.85) : theme.accent;
    } else {
      bg = _hovered ? theme.surfaceHover : theme.divider;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                color: widget.primary
                    ? const Color(0xFFFFFFFF)
                    : theme.popupForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BtRescanButton extends StatefulWidget {
  const _BtRescanButton({required this.onTap, this.label = 'Scan'});

  final VoidCallback onTap;
  final String label;

  @override
  _BtRescanButtonState createState() => _BtRescanButtonState();
}

class _BtRescanButtonState extends State<_BtRescanButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? theme.surfaceHover : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                FontAwesomeIcons.arrowsRotate,
                size: 11,
                color: theme.popupForeground.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.popupForeground.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BtPowerToggle extends StatefulWidget {
  const _BtPowerToggle({required this.powered, required this.onTap});

  final bool powered;
  final VoidCallback onTap;

  @override
  _BtPowerToggleState createState() => _BtPowerToggleState();
}

class _BtPowerToggleState extends State<_BtPowerToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color bg;
    final Color fg;
    if (widget.powered) {
      bg = _hovered
          ? theme.accent.withValues(alpha: 0.2)
          : theme.accent.withValues(alpha: 0.12);
      fg = theme.accent;
    } else {
      bg = _hovered ? theme.surfaceHover : const Color(0x00000000);
      fg = theme.popupForeground.withValues(alpha: 0.5);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.powered
                ? Border.all(
                    color: theme.accent.withValues(alpha: 0.4), width: 1)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(FontAwesomeIcons.powerOff, size: 11, color: fg),
              const SizedBox(width: 6),
              Text(
                widget.powered ? 'On' : 'Off',
                style: TextStyle(fontSize: 12, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Device list item
// ---------------------------------------------------------------------------

FaIconData _deviceIcon(String? icon) {
  switch (icon) {
    case 'audio-headset':
    case 'audio-headphones':
      return FontAwesomeIcons.headphones;
    case 'input-keyboard':
      return FontAwesomeIcons.keyboard;
    case 'input-mouse':
      return FontAwesomeIcons.computerMouse;
    default:
      return FontAwesomeIcons.bluetooth;
  }
}

class _BluetoothDeviceItem extends StatefulWidget {
  const _BluetoothDeviceItem({
    required this.device,
    required this.actioning,
    required this.onConnect,
    required this.onDisconnect,
    this.actionError,
  });

  final BluetoothDevice device;
  final bool actioning;
  final String? actionError;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  _BluetoothDeviceItemState createState() => _BluetoothDeviceItemState();
}

class _BluetoothDeviceItemState extends State<_BluetoothDeviceItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final d = widget.device;

    Widget trailing;
    if (widget.actioning) {
      trailing = const LoadingIndicator(size: 14);
    } else if (d.connected) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _BtConnectedBadge(),
          const SizedBox(width: 8),
          _BtActionButton(label: 'Disconnect', onTap: widget.onDisconnect),
        ],
      );
    } else if (d.paired) {
      trailing = _BtActionButton(
        label: 'Connect',
        onTap: widget.onConnect,
        primary: true,
      );
    } else {
      trailing = const _BtUnpairedBadge();
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        color: _hovered ? theme.surfaceHover : null,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                FaIcon(
                  _deviceIcon(d.icon),
                  size: 14,
                  color: theme.popupForeground.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        d.name,
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.popupForeground,
                        ),
                      ),
                      Text(
                        d.address,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.popupForeground.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
            if (widget.actionError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 26),
                child: Text(
                  widget.actionError!,
                  style: TextStyle(fontSize: 11, color: theme.accent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings page
// ---------------------------------------------------------------------------

class BluetoothSettingsPage extends StatefulWidget {
  const BluetoothSettingsPage({super.key});

  @override
  _BluetoothSettingsPageState createState() => _BluetoothSettingsPageState();
}

class _BluetoothSettingsPageState extends State<BluetoothSettingsPage> {
  DBusObjectPath? _adapterPath;
  bool? _powered;
  bool _togglingPower = false;

  List<BluetoothDevice>? _devices;
  String? _scanError;

  BluetoothDevice? _actioning;
  bool _isActioning = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _devices = null;
      _scanError = null;
      _actioning = null;
      _isActioning = false;
      _actionError = null;
    });
    try {
      final result = await scanBluetooth(discover: true);
      if (!mounted) return;
      setState(() {
        _adapterPath = result.adapterPath;
        _powered = result.adapterPowered;
        _devices = result.devices;
      });
    } catch (e) {
      if (mounted) setState(() => _scanError = e.toString());
    }
  }

  Future<void> _togglePower() async {
    final path = _adapterPath;
    final current = _powered;
    if (path == null || current == null || _togglingPower) return;

    setState(() => _togglingPower = true);
    try {
      await setBluetoothPowered(path, !current);
      if (mounted) {
        setState(() {
          _powered = !current;
          _togglingPower = false;
          if (!current) {
            // Turned on — trigger a fresh scan.
            _devices = null;
            _scanError = null;
          }
        });
        if (!current) _scan();
      }
    } catch (e) {
      if (mounted) setState(() => _togglingPower = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() {
      _actioning = device;
      _isActioning = true;
      _actionError = null;
    });
    try {
      await connectBluetoothDevice(device);
      if (mounted) {
        setState(() {
          _actioning = null;
          _isActioning = false;
        });
        _scan();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActioning = false;
          _actionError = e.toString();
        });
      }
    }
  }

  Future<void> _disconnect(BluetoothDevice device) async {
    setState(() {
      _actioning = device;
      _isActioning = true;
      _actionError = null;
    });
    try {
      await disconnectBluetoothDevice(device);
      if (mounted) {
        setState(() {
          _actioning = null;
          _isActioning = false;
        });
        _scan();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActioning = false;
          _actionError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);

  Widget _buildPage(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Bluetooth',
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.popupForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_togglingPower)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: LoadingIndicator(size: 12),
                )
              else if (_powered != null)
                _BtPowerToggle(powered: _powered!, onTap: _togglePower),
              if (_powered == true && _devices != null) ...[
                const SizedBox(width: 4),
                _BtRescanButton(onTap: _scan),
              ],
            ],
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(child: _buildBody(theme)),
      ],
    );
  }

  Widget _buildBody(ThemeConfig theme) {
    if (_scanError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _scanError!,
              style: TextStyle(fontSize: 13, color: theme.accent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            _BtRescanButton(onTap: _scan, label: 'Retry'),
          ],
        ),
      );
    }

    if (_powered == false) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              FontAwesomeIcons.bluetooth,
              size: 32,
              color: theme.popupForeground.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 14),
            Text(
              'Bluetooth is off',
              style: TextStyle(
                fontSize: 14,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            _BtActionButton(
              label: 'Turn On',
              onTap: _togglePower,
              primary: true,
            ),
          ],
        ),
      );
    }

    if (_devices == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoadingIndicator(size: 22),
            const SizedBox(height: 12),
            Text(
              'Scanning for devices…',
              style: TextStyle(
                fontSize: 13,
                color: theme.popupForeground.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    if (_devices!.isEmpty) {
      return Center(
        child: Text(
          'No Bluetooth devices found',
          style: TextStyle(
            fontSize: 14,
            color: theme.popupForeground.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _devices!.length,
      itemBuilder: (_, i) {
        final d = _devices![i];
        final isActioning = _actioning?.address == d.address && _isActioning;
        return _BluetoothDeviceItem(
          device: d,
          actioning: isActioning,
          actionError: _actioning?.address == d.address ? _actionError : null,
          onConnect: () => _connect(d),
          onDisconnect: () => _disconnect(d),
        );
      },
    );
  }
}
