// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Do not import this file in production applications or packages published
// to pub.dev. Flutter will make breaking changes to this file, even in patch
// versions.
//
// All APIs in this file must be private or must:
//
// 1. Have the `` attribute.
// 2. Throw an `UnsupportedError` if `isWindowingEnabled`
//    is `false`.
//
// See: https://github.com/flutter/flutter/issues/30701.

// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:ffi' as ffi;
import 'dart:ui' show Display, FlutterView;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/src/foundation/_features.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
import 'package:flutter/src/widgets/binding.dart';
import 'gtk.dart';

const String _kWindowingDisabledErrorMessage = '''
Windowing APIs are not enabled.

Windowing APIs are currently experimental. Do not use windowing APIs in
production applications or plugins published to pub.dev.

To try experimental windowing APIs:
1. Switch to Flutter's main release channel.
2. Turn on the windowing feature flag.

See: https://github.com/flutter/flutter/issues/30701.
''';

/// Returns the primary monitor's size in logical pixels.
Size getScreenSize() => GdkDisplay.getDefault().getMonitor(0).getGeometry();

/// Monitor information returned by [listMonitors].
class MonitorInfo {
  const MonitorInfo({
    required this.connector,
    required this.model,
    required this.manufacturer,
    required this.gdkMonitor,
  });

  final String connector;
  final String model;
  final String manufacturer;
  final ffi.Pointer<ffi.NativeType> gdkMonitor;

  @override
  String toString() =>
      'MonitorInfo(connector: $connector, model: $model, manufacturer: $manufacturer)';
}

/// List all available monitors using GDK.
List<MonitorInfo> listMonitors() {
  final display = GdkDisplay.getDefault();
  final nMonitors = display.getNMonitors();
  final monitors = <MonitorInfo>[];

  for (var i = 0; i < nMonitors; i++) {
    final monitor = display.getMonitor(i);
    monitors.add(MonitorInfo(
      connector: monitor.getConnector(),
      model: monitor.getModel(),
      manufacturer: monitor.getManufacturer(),
      gdkMonitor: monitor.instance,
    ));
  }

  return monitors;
}

List<GtkLayerShellEdge> anchorEdgesForPosition(String anchor) {
  switch (anchor) {
    case 'bottom':
      return [
        GtkLayerShellEdge.bottom,
        GtkLayerShellEdge.left,
        GtkLayerShellEdge.right
      ];
    case 'left':
      return [
        GtkLayerShellEdge.left,
        GtkLayerShellEdge.top,
        GtkLayerShellEdge.bottom
      ];
    case 'right':
      return [
        GtkLayerShellEdge.right,
        GtkLayerShellEdge.top,
        GtkLayerShellEdge.bottom
      ];
    default: // 'top'
      return [
        GtkLayerShellEdge.top,
        GtkLayerShellEdge.left,
        GtkLayerShellEdge.right
      ];
  }
}

GtkLayerShellLayer layerFromString(String s) {
  switch (s) {
    case 'background':
      return GtkLayerShellLayer.background;
    case 'bottom':
      return GtkLayerShellLayer.bottom;
    case 'overlay':
      return GtkLayerShellLayer.overlay;
    default: // 'top'
      return GtkLayerShellLayer.top;
  }
}

/// Manages dynamically-created popup windows for inclusion in the ViewCollection.
class PopupManager extends ChangeNotifier {
  static final PopupManager instance = PopupManager._();
  PopupManager._();

  final List<Widget> _popupViews = [];
  List<Widget> get popupViews => List.unmodifiable(_popupViews);

  void add(Widget view) {
    _popupViews.add(view);
    notifyListeners();
  }

  void remove(Widget view) {
    _popupViews.remove(view);
    notifyListeners();
  }
}

class ExtendedWindowingOwnerLinux extends WindowingOwnerLinux {
  @override
  RegularWindowController createRegularWindowController({
    Size? preferredSize,
    BoxConstraints? preferredConstraints,
    String? title,
    required RegularWindowControllerDelegate delegate,
  }) {
    throw UnsupportedError(
        "Layer shell windows are created via the factory constructor in this app.");
  }

  @override
  PopupWindowController createPopupWindowController({
    required PopupWindowControllerDelegate delegate,
    required BoxConstraints preferredConstraints,
    required Rect anchorRect,
    required WindowPositioner positioner,
    required BaseWindowController parent,
  }) {
    if (!isWindowingEnabled) {
      throw UnsupportedError(_kWindowingDisabledErrorMessage);
    }
    return PopupGtkWindowController(
      parent: parent,
      anchorRect: anchorRect,
      positioner: positioner,
      preferredConstraints: preferredConstraints,
      delegate: delegate,
    );
  }
}

class LayershellWindowControllerDelegate {
  /// Called when the window is requested to close.
  void onWindowCloseRequested(LayershellWindowController controller) {}

  /// Called when the window is destroyed.
  void onWindowDestroyed() {}
}

class LayershellWindowController extends RegularWindowController {
  /// Create a new LayershellWindowController.
  factory LayershellWindowController({
    required ExtendedWindowingOwnerLinux owner,
    required LayershellWindowControllerDelegate delegate,
    GtkLayerShellLayer layer = GtkLayerShellLayer.top,
    List<GtkLayerShellEdge> anchorEdges = const [
      GtkLayerShellEdge.top,
      GtkLayerShellEdge.left,
      GtkLayerShellEdge.right
    ],
    GtkLayerShellKeyboardMode keyboardMode = GtkLayerShellKeyboardMode.onDemand,
    int? width,
    int? height,
    int? exclusiveZone,
    ffi.Pointer<ffi.NativeType>? monitor,
  }) {
    if (!isWindowingEnabled) {
      throw UnsupportedError(_kWindowingDisabledErrorMessage);
    }

    final controller = LayershellWindowController._internal(
      owner: owner,
      delegate: delegate,
    );

    controller._setup(
      layer: layer,
      anchorEdges: anchorEdges,
      keyboardMode: keyboardMode,
      width: width,
      height: height,
      exclusiveZone: exclusiveZone,
      monitor: monitor,
    );

    return controller;
  }

  LayershellWindowController._internal({
    required ExtendedWindowingOwnerLinux owner,
    required LayershellWindowControllerDelegate delegate,
  })  : _owner = owner,
        _delegate = delegate,
        _window = GtkWindow(),
        super.empty();

  void _setup({
    required GtkLayerShellLayer layer,
    required List<GtkLayerShellEdge> anchorEdges,
    required GtkLayerShellKeyboardMode keyboardMode,
    int? width,
    int? height,
    int? exclusiveZone,
    ffi.Pointer<ffi.NativeType>? monitor,
  }) {
    _windowMonitor = FlWindowMonitor(
      _window,
      // onConfigure
      notifyListeners,
      // onStateChanged
      notifyListeners,
      // onIsActiveNotify
      notifyListeners,
      // onTitleNotify
      notifyListeners,
      // onClose
      () {
        _delegate.onWindowCloseRequested(this);
      },
      // onDestroy
      _delegate.onWindowDestroyed,
    );
    final view = FlView();
    view.setBackgroundColor('#00000000');
    final int viewId = view.getId();
    _view = WidgetsBinding.instance.platformDispatcher.views.firstWhere(
      (FlutterView view) => view.viewId == viewId,
    );

    _window.layerInitForWindow();

    // Set monitor if specified
    if (monitor != null && monitor.address != 0) {
      _window.layerSetMonitor(monitor);
    }

    if (exclusiveZone != null) {
      _window.layerAutoExclusiveZoneEnable();
      _window.layerSetExclusiveZone(exclusiveZone);
    }
    for (final edge in anchorEdges) {
      _window.layerSetAnchor(edge, true);
    }
    _window.layerSetLayer(layer);
    _window.setSizeRequest(width ?? -1, height ?? -1);
    _window.setDefaultSize(width ?? -1, height ?? -1);
    _window.setAppPaintable(true);
    _window.add(view);
    _window.present();
    view.show();
  }

  FlutterView get rootView => _view;
  late final FlutterView _view;
  final ExtendedWindowingOwnerLinux _owner;
  final LayershellWindowControllerDelegate _delegate;
  final GtkWindow _window;
  late final FlWindowMonitor _windowMonitor;
  bool _destroyed = false;

  Size get contentSize => _window.getSize();

  /// The underlying GTK window, exposed for use as a popup transient parent.
  GtkWindow get gtkWindow => _window;

  void destroy() {
    if (_destroyed) {
      return;
    }
    _window.destroy();
    _windowMonitor.close();
    _windowMonitor.unref();
    _destroyed = true;
  }

  bool get isActivated => _window.isActive();

  void setSize(Size size) {
    _window.resize(size.width.toInt(), size.height.toInt());
  }

  void activate() {
    _window.present();
  }

  @override
  bool get isFullscreen => false;

  @override
  bool get isMaximized => false;

  @override
  // TODO: implement isMinimized
  bool get isMinimized => false;

  @override
  void setConstraints(BoxConstraints constraints) {}

  @override
  void setFullscreen(bool fullscreen, {Display? display}) {}

  @override
  void setMaximized(bool maximized) {}

  @override
  void setMinimized(bool minimized) {}

  @override
  void setTitle(String title) {}

  @override
  String get title => "";
}

/// A popup window backed by a transient GTK window (xdg_popup on Wayland).
///
/// The popup is positioned relative to [anchorRect] in screen coordinates
/// using [positioner] to determine the anchor points and offset.
class PopupGtkWindowController extends PopupWindowController {
  factory PopupGtkWindowController({
    required BaseWindowController parent,
    required Rect anchorRect,
    required WindowPositioner positioner,
    required BoxConstraints preferredConstraints,
    required PopupWindowControllerDelegate delegate,
  }) {
    final controller = PopupGtkWindowController._internal(
      parent: parent,
      delegate: delegate,
    );
    controller._setup(
      anchorRect: anchorRect,
      positioner: positioner,
      preferredConstraints: preferredConstraints,
    );
    return controller;
  }

  PopupGtkWindowController._internal({
    required this.parent,
    required PopupWindowControllerDelegate delegate,
  })  : _delegate = delegate,
        _window = GtkWindow(),
        super.empty();

  @override
  final BaseWindowController parent;
  final PopupWindowControllerDelegate _delegate;
  final GtkWindow _window;
  late FlutterView _view;
  late FlWindowMonitor _windowMonitor;
  bool _destroyed = false;

  void _setup({
    required Rect anchorRect,
    required WindowPositioner positioner,
    required BoxConstraints preferredConstraints,
  }) {
    _windowMonitor = FlWindowMonitor(
      _window,
      notifyListeners, // onConfigure
      notifyListeners, // onStateChanged
      notifyListeners, // onIsActiveNotify
      notifyListeners, // onTitleNotify
      () {}, // onClose
      _delegate.onWindowDestroyed, // onDestroy
    );

    final view = FlView();
    view.setBackgroundColor('#00000000');
    final int viewId = view.getId();
    _view = WidgetsBinding.instance.platformDispatcher.views.firstWhere(
      (FlutterView v) => v.viewId == viewId,
    );

    // Compute popup screen position from anchorRect + positioner.
    final anchorPoint = _anchorPointOn(anchorRect, positioner.parentAnchor);
    final size = Size(
      preferredConstraints.maxWidth.isFinite
          ? preferredConstraints.maxWidth
          : 200,
      preferredConstraints.maxHeight.isFinite
          ? preferredConstraints.maxHeight
          : 200,
    );
    final childOffset = _childAnchorOffset(size, positioner.childAnchor);
    final x = (anchorPoint.dx - childOffset.dx + positioner.offset.dx).toInt();
    final y = (anchorPoint.dy - childOffset.dy + positioner.offset.dy).toInt();

    // Use layer shell on the overlay layer so the compositor treats this as a
    // proper layer surface rather than a floating xdg_toplevel.  Anchoring to
    // top+left and setting margins positions the popup at (x, y) in screen
    // coordinates, which is how layer-shell apps (e.g. Waybar) show dropdowns.
    _window.layerInitForWindow();
    _window.layerSetLayer(GtkLayerShellLayer.overlay);
    _window.layerSetKeyboardMode(GtkLayerShellKeyboardMode.onDemand);
    _window.layerSetAnchor(GtkLayerShellEdge.left, true);
    _window.layerSetAnchor(GtkLayerShellEdge.top, true);
    _window.layerSetMargin(GtkLayerShellEdge.left, x);
    _window.layerSetMargin(GtkLayerShellEdge.top, y);

    _window.setSizeRequest(size.width.toInt(), size.height.toInt());
    _window.setDefaultSize(size.width.toInt(), size.height.toInt());
    _window.setAppPaintable(true);
    _window.add(view);
    _window.present();
    view.show();
  }

  static Offset _anchorPointOn(Rect r, WindowPositionerAnchor a) => switch (a) {
        WindowPositionerAnchor.center => r.center,
        WindowPositionerAnchor.top => r.topCenter,
        WindowPositionerAnchor.bottom => r.bottomCenter,
        WindowPositionerAnchor.left => r.centerLeft,
        WindowPositionerAnchor.right => r.centerRight,
        WindowPositionerAnchor.topLeft => r.topLeft,
        WindowPositionerAnchor.topRight => r.topRight,
        WindowPositionerAnchor.bottomLeft => r.bottomLeft,
        WindowPositionerAnchor.bottomRight => r.bottomRight,
      };

  static Offset _childAnchorOffset(Size s, WindowPositionerAnchor a) =>
      switch (a) {
        WindowPositionerAnchor.center => Offset(s.width / 2, s.height / 2),
        WindowPositionerAnchor.top => Offset(s.width / 2, 0),
        WindowPositionerAnchor.bottom => Offset(s.width / 2, s.height),
        WindowPositionerAnchor.left => Offset(0, s.height / 2),
        WindowPositionerAnchor.right => Offset(s.width, s.height / 2),
        WindowPositionerAnchor.topLeft => Offset.zero,
        WindowPositionerAnchor.topRight => Offset(s.width, 0),
        WindowPositionerAnchor.bottomLeft => Offset(0, s.height),
        WindowPositionerAnchor.bottomRight => Offset(s.width, s.height),
      };

  @override
  FlutterView get rootView => _view;

  @override
  Size get contentSize => _window.getSize();

  @override
  bool get isActivated => _window.isActive();

  @override
  void activate() => _window.present();

  @override
  void setConstraints(BoxConstraints c) {
    if (c.maxWidth.isFinite && c.maxHeight.isFinite) {
      _window.resize(c.maxWidth.toInt(), c.maxHeight.toInt());
    }
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _window.destroy();
    _windowMonitor.close();
    _windowMonitor.unref();
    _destroyed = true;
  }

  bool get isDestroyed => _destroyed;
}

class LayerShellWindow extends StatelessWidget {
  @internal
  LayerShellWindow({super.key, required this.controller, required this.child}) {
    if (!isWindowingEnabled) {
      throw UnsupportedError(_kWindowingDisabledErrorMessage);
    }
  }

  @internal
  final LayershellWindowController controller;

  @internal
  final Widget child;

  /// {@macro flutter.widgets.windowing.experimental}
  @internal
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => View(
        view: controller.rootView,
        child: WindowScope(controller: controller, child: child),
      ),
    );
  }
}
