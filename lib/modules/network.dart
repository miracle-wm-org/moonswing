// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'package:dbus/dbus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';
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
// Data model
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

// ---------------------------------------------------------------------------
// NetworkManager D-Bus helpers
// ---------------------------------------------------------------------------

const _nmService = 'org.freedesktop.NetworkManager';
const _nmDevIface = 'org.freedesktop.NetworkManager.Device';
const _nmWifiIface = 'org.freedesktop.NetworkManager.Device.Wireless';
const _nmApIface = 'org.freedesktop.NetworkManager.AccessPoint';
const _nmIp4Iface = 'org.freedesktop.NetworkManager.IP4Config';

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

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class Network extends StatefulWidget {
  const Network({super.key, required this.config});

  final NetworkConfig config;

  @override
  NetworkState createState() => NetworkState();
}

class NetworkState extends State<Network> {
  NetworkInfo _info = NetworkInfo.none;
  Timer? _timer;

  PopupWindowController? _popupController;
  PopupWindow? _popupView;
  bool _hovered = false;
  bool _popupHasBeenActive = false;

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
    _closePopup();
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
    if (_popupController != null) {
      _closePopup();
      return;
    }

    final parentController = WindowScope.of(context);
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
    final info = _info;

    PopupWindowController? thisController;
    _popupController = thisController = PopupWindowController(
      parent: parentController,
      anchorRect: anchorRect,
      positioner: WindowPositioner(
        parentAnchor: parentAnchor,
        childAnchor: childAnchor,
      ),
      preferredConstraints:
          const BoxConstraints.tightFor(width: 220, height: 110),
      delegate: _NetworkPopupDelegate(onDestroyed: () {
        if (_popupController == thisController) _closePopup();
      }),
    );

    _popupView = PopupWindow(
      controller: _popupController!,
      child: ThemeScope(
        theme: theme,
        child: _NetworkPopupContent(info: info),
      ),
    );
    _popupHasBeenActive = false;
    _popupController!.addListener(_onPopupStateChanged);
    PopupManager.instance.add(_popupView!);
    setState(() {});
  }

  void _onPopupStateChanged() {
    final ctrl = _popupController;
    if (ctrl == null) return;
    if (ctrl.isActivated) {
      _popupHasBeenActive = true;
    } else if (_popupHasBeenActive) {
      _popupHasBeenActive = false;
      _closePopup();
    }
  }

  void _closePopup() {
    _popupController?.removeListener(_onPopupStateChanged);
    if (_popupView != null) {
      PopupManager.instance.remove(_popupView!);
      _popupView = null;
    }
    final ctrl = _popupController;
    _popupController = null;
    if (ctrl is PopupGtkWindowController && !ctrl.isDestroyed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ctrl.isDestroyed) ctrl.destroy();
      });
    }
    if (mounted) setState(() {});
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
    final isActive = _hovered || _popupController != null;
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
// Popup
// ---------------------------------------------------------------------------

class _NetworkPopupDelegate extends PopupWindowControllerDelegate {
  _NetworkPopupDelegate({required this.onDestroyed});
  final VoidCallback onDestroyed;

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    onDestroyed();
  }
}

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
