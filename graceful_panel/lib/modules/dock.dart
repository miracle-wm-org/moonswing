import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:xdg_icons/xdg_icons.dart';
import 'package:graceful_panel/config.dart';

// GIO FFI bindings

@ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Int)>(
    symbol: 'g_malloc0')
external ffi.Pointer<ffi.NativeType> _gMalloc0(int count);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(symbol: 'g_free')
external void _gFree(ffi.Pointer<ffi.NativeType> value);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_object_unref')
external void _gObjectUnref(ffi.Pointer<ffi.NativeType> object);

@ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.Uint8>)>(
    symbol: 'g_desktop_app_info_new')
external ffi.Pointer<ffi.NativeType> _gDesktopAppInfoNew(
    ffi.Pointer<ffi.Uint8> desktopId);

@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_app_info_get_name')
external ffi.Pointer<ffi.Uint8> _gAppInfoGetName(
    ffi.Pointer<ffi.NativeType> appInfo);

@ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_app_info_get_icon')
external ffi.Pointer<ffi.NativeType> _gAppInfoGetIcon(
    ffi.Pointer<ffi.NativeType> appInfo);

@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_icon_to_string')
external ffi.Pointer<ffi.Uint8> _gIconToString(
    ffi.Pointer<ffi.NativeType> icon);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<ffi.NativeType>, ffi.Pointer<ffi.NativeType>,
        ffi.Pointer<ffi.NativeType>, ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_app_info_launch')
external int _gAppInfoLaunch(
    ffi.Pointer<ffi.NativeType> appInfo,
    ffi.Pointer<ffi.NativeType> files,
    ffi.Pointer<ffi.NativeType> context,
    ffi.Pointer<ffi.NativeType> error);

// String conversion helpers

ffi.Pointer<ffi.Uint8> _stringToNative(String value) {
  final Uint8List units = utf8.encode(value);
  final ffi.Pointer<ffi.Uint8> buffer =
      _gMalloc0(units.length + 1).cast<ffi.Uint8>();
  final Uint8List nativeString = buffer.asTypedList(units.length + 1);
  nativeString.setAll(0, units);
  nativeString[units.length] = 0;
  return buffer;
}

String _nativeToString(ffi.Pointer<ffi.Uint8> value) {
  var length = 0;
  while (value[length] != 0) {
    length++;
  }
  return utf8.decode(value.asTypedList(length));
}

// Data model

class _DockApp {
  final String name;
  final String iconName;
  final ffi.Pointer<ffi.NativeType> appInfo;

  const _DockApp({
    required this.name,
    required this.iconName,
    required this.appInfo,
  });
}

// Dock widget

class Dock extends StatefulWidget {
  const Dock({super.key, required this.config});

  final DockConfig config;

  @override
  DockState createState() => DockState();
}

class DockState extends State<Dock> {
  List<_DockApp> _apps = [];

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  void _loadApps() {
    final apps = <_DockApp>[];
    for (final appId in widget.config.apps) {
      final desktopId = _stringToNative('$appId.desktop');
      try {
        final appInfo = _gDesktopAppInfoNew(desktopId);
        if (appInfo == ffi.nullptr) continue;

        final namePtr = _gAppInfoGetName(appInfo);
        final name =
            namePtr != ffi.nullptr ? _nativeToString(namePtr) : appId;

        var iconName = appId;
        final iconPtr = _gAppInfoGetIcon(appInfo);
        if (iconPtr != ffi.nullptr) {
          final iconStr = _gIconToString(iconPtr);
          if (iconStr != ffi.nullptr) {
            iconName = _nativeToString(iconStr);
            _gFree(iconStr.cast());
          }
        }

        apps.add(_DockApp(name: name, iconName: iconName, appInfo: appInfo));
      } finally {
        _gFree(desktopId.cast());
      }
    }

    setState(() {
      _apps = apps;
    });
  }

  @override
  void dispose() {
    for (final app in _apps) {
      _gObjectUnref(app.appInfo);
    }
    super.dispose();
  }

  void _launchApp(_DockApp app) {
    try {
      _gAppInfoLaunch(app.appInfo, ffi.nullptr, ffi.nullptr, ffi.nullptr);
    } catch (_) {
      // Launch failed silently
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_apps.isEmpty) return const SizedBox.shrink();

    final size = widget.config.iconSize;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: _apps.map((app) {
        return _DockButton(
          onPressed: () => _launchApp(app),
          child: XdgIcon(
            name: app.iconName,
            size: size,
            iconNotFoundBuilder: () {
              return SizedBox(
                width: size.toDouble(),
                height: size.toDouble(),
                child: Center(
                  child: Text(
                    app.name.isNotEmpty ? app.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: size * 0.6,
                      color: const Color(0xFFE0E0E0),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }).toList(),
    );
  }
}

class _DockButton extends StatefulWidget {
  const _DockButton({
    required this.onPressed,
    required this.child,
  });

  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    Color color = const Color(0x00000000);
    if (_pressed) {
      color = const Color(0xFF2A2A2A);
    } else if (_hovered) {
      color = const Color(0xFF4A4A4A);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
