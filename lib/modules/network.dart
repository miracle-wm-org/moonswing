// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:math' as math;
import 'package:dbus/dbus.dart';
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/layer_shell.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

class NetworkConfig {
  final int pollSeconds;

  const NetworkConfig({this.pollSeconds = 10});

  factory NetworkConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NetworkConfig();
    return NetworkConfig(
      pollSeconds: map['poll_seconds'] as int? ?? 10,
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
const _nmConnSettingsIface = 'org.freedesktop.NetworkManager.Settings.Connection';

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
      _nmService, 'GetDevices', [],
      replySignature: DBusSignature('ao'),
    );
    final devicePaths = (devicesResult.returnValues[0] as DBusArray)
        .children.cast<DBusObjectPath>();

    // Build map of saved WiFi profiles: SSID → connection path
    final savedBySsid = <String, DBusObjectPath>{};
    try {
      final settingsObj = DBusRemoteObject(
        client,
        name: _nmService,
        path: DBusObjectPath('/org/freedesktop/NetworkManager/Settings'),
      );
      final connsResult = await settingsObj.callMethod(
        _nmSettingsIface, 'ListConnections', [],
        replySignature: DBusSignature('ao'),
      );
      final connPaths = (connsResult.returnValues[0] as DBusArray)
          .children.cast<DBusObjectPath>();
      for (final cp in connPaths) {
        try {
          final connObj = DBusRemoteObject(client, name: _nmService, path: cp);
          final settingsResult = await connObj.callMethod(
            _nmConnSettingsIface, 'GetSettings', [],
            replySignature: DBusSignature('a{sa{sv}}'),
          );
          final outer = (settingsResult.returnValues[0] as DBusDict).children;
          final wifiSection = outer[DBusString('802-11-wireless')] as DBusDict?;
          if (wifiSection != null) {
            final ssidEntry = wifiSection.children[DBusString('ssid')] as DBusVariant?;
            final ssidArr = ssidEntry?.value as DBusArray?;
            if (ssidArr != null) {
              final ssid = String.fromCharCodes(
                ssidArr.children.cast<DBusByte>()
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

      final typeVal = await devObj.getProperty(_nmDevIface, 'DeviceType') as DBusUint32;
      final deviceType = typeVal.value;

      if (deviceType == 1) {
        // Ethernet — include only if activated
        final stateVal = await devObj.getProperty(_nmDevIface, 'State') as DBusUint32;
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
            _nmWifiIface, 'RequestScan',
            [DBusDict(DBusSignature('s'), DBusSignature('v'), {})],
            replySignature: DBusSignature(''),
          );
          await Future.delayed(const Duration(milliseconds: 1500));
        } catch (_) {}

        try {
          final apsResult = await devObj.callMethod(
            _nmWifiIface, 'GetAllAccessPoints', [],
            replySignature: DBusSignature('ao'),
          );
          final apPaths = (apsResult.returnValues[0] as DBusArray)
              .children.cast<DBusObjectPath>();

          for (final apPath in apPaths) {
            try {
              final apObj = DBusRemoteObject(client, name: _nmService, path: apPath);

              final ssidBytes = await apObj.getProperty(_nmApIface, 'Ssid') as DBusArray;
              final ssid = String.fromCharCodes(
                ssidBytes.children.cast<DBusByte>()
                    .map((b) => b.value)
                    .where((c) => c != 0),
              );
              if (ssid.isEmpty) continue;

              final strengthVal = await apObj.getProperty(_nmApIface, 'Strength') as DBusByte;
              final flagsVal = await apObj.getProperty(_nmApIface, 'Flags') as DBusUint32;
              final wpaFlagsVal = await apObj.getProperty(_nmApIface, 'WpaFlags') as DBusUint32;
              final rsnFlagsVal = await apObj.getProperty(_nmApIface, 'RsnFlags') as DBusUint32;

              final secured = (flagsVal.value & 0x1) != 0 ||
                  wpaFlagsVal.value != 0 ||
                  rsnFlagsVal.value != 0;

              results.add(AvailableNetwork(
                type: NetworkType.wifi,
                name: ssid,
                signal: strengthVal.value,
                secured: secured,
                isConnected: apPath.value == activeApPath.value && activeApPath.value != '/',
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

  bool _hovered = false;

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

    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final flutterView = View.of(context);
    final dpr = flutterView.devicePixelRatio;
    final barLogicalWidth = flutterView.physicalSize.width / dpr;
    final barLogicalHeight = flutterView.physicalSize.height / dpr;

    final anchor = BarScope.of(context).anchor;
    final Rect anchorRect;
    final WindowPositionerAnchor parentAnchor;
    final WindowPositionerAnchor childAnchor;

    switch (anchor) {
      case 'bottom':
        final screenH = getScreenSize().height;
        anchorRect = Rect.fromLTWH(offset.dx, screenH - barLogicalHeight,
            size.width, barLogicalHeight);
        parentAnchor = WindowPositionerAnchor.top;
        childAnchor = WindowPositionerAnchor.bottom;
      case 'left':
        anchorRect = Rect.fromLTWH(0, offset.dy, barLogicalWidth, size.height);
        parentAnchor = WindowPositionerAnchor.right;
        childAnchor = WindowPositionerAnchor.left;
      case 'right':
        // x=0 is the left (inner) edge of the right bar's window surface;
        // placing the popup's right there causes it to appear left of the bar.
        anchorRect = Rect.fromLTWH(0, offset.dy, 0, size.height);
        parentAnchor = WindowPositionerAnchor.left;
        childAnchor = WindowPositionerAnchor.right;
      default: // 'top'
        anchorRect = Rect.fromLTWH(offset.dx, 0, size.width, 0);
        parentAnchor = WindowPositionerAnchor.bottom;
        childAnchor = WindowPositionerAnchor.top;
    }

    final theme = ThemeScope.of(context);

    openPopup(
      context,
      anchorRect: anchorRect,
      parentAnchor: parentAnchor,
      childAnchor: childAnchor,
      preferredConstraints:
          const BoxConstraints.tightFor(width: 220, height: 110),
      child: ThemeScope(
        theme: theme,
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
    final isActive = _hovered || isPopupOpen;
    final isNone = _info.type == NetworkType.none;
    // ignore: deprecated_member_use
    final dimColor = theme.foreground.withOpacity(0.4);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => _togglePopup(context),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? const Color(0x28FFFFFF) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
        ),
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
    final bg = theme.popupBackground;

    // ignore: deprecated_member_use
    final labelStyle = TextStyle(fontSize: 11, color: fg.withOpacity(0.6));
    final valueStyle = TextStyle(fontSize: 14, color: fg);

    final ipText = info.ip.isEmpty ? '—' : '${info.ip}/${info.prefix}';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: PopupBounceIn(
        child: Container(
          color: bg,
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
// Settings page — shared helper widgets
// ---------------------------------------------------------------------------

class _LoadingIndicator extends StatefulWidget {
  const _LoadingIndicator({this.size = 16.0});

  final double size;

  @override
  _LoadingIndicatorState createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<_LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: FaIcon(
          FontAwesomeIcons.circleNotch,
          size: widget.size,
          color: theme.popupForeground.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _ConnectedBadge extends StatelessWidget {
  const _ConnectedBadge();

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
        style: TextStyle(
          fontSize: 11,
          fontFamily: theme.fontFamily,
          color: theme.accent,
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.loading = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool loading;
  final bool enabled;

  @override
  _ActionButtonState createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final canTap = widget.enabled && !widget.loading;
    final Color bg;
    if (widget.primary) {
      bg = _hovered && canTap
          ? theme.accent.withValues(alpha: 0.85)
          : theme.accent;
    } else {
      bg = _hovered && canTap ? theme.surfaceHover : theme.divider;
    }

    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: canTap ? widget.onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: widget.loading
                ? const _LoadingIndicator(size: 14)
                : Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: theme.fontFamily,
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

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  _PasswordFieldState createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _focused ? theme.accent : theme.divider,
          width: 1,
        ),
      ),
      child: EditableText(
        controller: widget.controller,
        focusNode: widget.focusNode,
        style: TextStyle(
          fontSize: 14,
          color: theme.popupForeground,
          fontFamily: theme.fontFamily,
        ),
        cursorColor: theme.accent,
        backgroundCursorColor: theme.divider,
        obscureText: true,
        autofocus: true,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

class _RescanButton extends StatefulWidget {
  const _RescanButton({required this.onTap, this.label = 'Scan'});

  final VoidCallback onTap;
  final String label;

  @override
  _RescanButtonState createState() => _RescanButtonState();
}

class _RescanButtonState extends State<_RescanButton> {
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
                  fontFamily: theme.fontFamily,
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

class _NetworkListItem extends StatefulWidget {
  const _NetworkListItem({
    required this.network,
    required this.onTap,
  });

  final AvailableNetwork network;
  final VoidCallback onTap;

  @override
  _NetworkListItemState createState() => _NetworkListItemState();
}

class _NetworkListItemState extends State<_NetworkListItem> {
  bool _hovered = false;

  FaIconData _icon() {
    return widget.network.type == NetworkType.ethernet
        ? FontAwesomeIcons.ethernet
        : FontAwesomeIcons.wifi;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final n = widget.network;
    final canTap = !n.isConnected;

    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: canTap ? widget.onTap : null,
        child: Container(
          color: _hovered && canTap ? theme.surfaceHover : null,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            children: [
              FaIcon(
                _icon(),
                size: 14,
                color: theme.popupForeground.withValues(
                  alpha: n.type == NetworkType.wifi && n.signal < 30 ? 0.4 : 1.0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      n.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground,
                      ),
                    ),
                    if (n.type == NetworkType.wifi)
                      Text(
                        '${n.signal}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: theme.fontFamily,
                          color: theme.popupForeground.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ),
              if (n.isConnected)
                const _ConnectedBadge()
              else if (n.secured)
                FaIcon(
                  FontAwesomeIcons.lock,
                  size: 11,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings page — NetworkSettingsPage
// ---------------------------------------------------------------------------

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  _NetworkSettingsPageState createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  List<AvailableNetwork>? _networks;
  String? _scanError;

  AvailableNetwork? _connecting;
  bool _isConnecting = false;
  String? _connectError;

  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _networks = null;
      _scanError = null;
    });
    try {
      final networks = await scanNetworks();
      if (mounted) setState(() => _networks = networks);
    } catch (e) {
      if (mounted) setState(() => _scanError = e.toString());
    }
  }

  Future<void> _connect(AvailableNetwork network, String? password) async {
    setState(() {
      _isConnecting = true;
      _connectError = null;
    });
    try {
      await connectToNetwork(network: network, password: password);
      if (mounted) {
        setState(() {
          _connecting = null;
          _isConnecting = false;
        });
        _passwordController.clear();
        _scan();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectError = e.toString();
        });
      }
    }
  }

  void _doConnect() {
    if (_isConnecting || _connecting == null) return;
    final pw = _connecting!.secured ? _passwordController.text.trim() : null;
    _connect(_connecting!, pw);
  }

  void _cancelConnect() {
    setState(() {
      _connecting = null;
      _connectError = null;
    });
    _passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_connecting != null) return _buildConnectForm(context);
    return _buildNetworkList(context);
  }

  Widget _buildNetworkList(BuildContext context) {
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
                  'Networks',
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _RescanButton(onTap: _scan),
            ],
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(child: _buildListBody(theme)),
      ],
    );
  }

  Widget _buildListBody(ThemeConfig theme) {
    if (_scanError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _scanError!,
              style: TextStyle(
                fontSize: 13,
                fontFamily: theme.fontFamily,
                color: theme.accent,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            _RescanButton(onTap: _scan, label: 'Retry'),
          ],
        ),
      );
    }
    if (_networks == null) {
      return const Center(child: _LoadingIndicator(size: 22));
    }
    if (_networks!.isEmpty) {
      return Center(
        child: Text(
          'No networks found',
          style: TextStyle(
            fontSize: 14,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground.withValues(alpha: 0.5),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _networks!.length,
      itemBuilder: (_, i) {
        final n = _networks![i];
        return _NetworkListItem(
          network: n,
          onTap: () => setState(() {
            _connecting = n;
            _connectError = null;
            _passwordController.clear();
          }),
        );
      },
    );
  }

  Widget _buildConnectForm(BuildContext context) {
    final theme = ThemeScope.of(context);
    final n = _connecting!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
          child: Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _cancelConnect,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: FaIcon(
                      FontAwesomeIcons.arrowLeft,
                      size: 14,
                      color: theme.popupForeground,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: Center(
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (n.secured) ...[
                    Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _PasswordField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      onSubmitted: (_) => _doConnect(),
                    ),
                    const SizedBox(height: 16),
                  ] else
                    const SizedBox(height: 16),
                  if (_connectError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _connectError!,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: theme.fontFamily,
                          color: theme.accent,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: 'Connect',
                          onTap: _doConnect,
                          primary: true,
                          loading: _isConnecting,
                          enabled: !_isConnecting,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          label: 'Cancel',
                          onTap: _cancelConnect,
                          enabled: !_isConnecting,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
