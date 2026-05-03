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
import 'package:flutter/src/foundation/_features.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
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
    required this.position,
  });

  final String connector;
  final String model;
  final String manufacturer;
  final ffi.Pointer<ffi.NativeType> gdkMonitor;

  /// Top-left position of this monitor in logical pixels.
  final Offset position;

  @override
  String toString() =>
      'MonitorInfo(connector: $connector, model: $model, manufacturer: $manufacturer, position: $position)';
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
      position: monitor.getPosition(),
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

/// Manages dynamically-created LayerShell windows (e.g. the notification panel)
/// for inclusion in the root ViewCollection.
/// XDG popup windows are handled separately via WindowRegistry / WindowManager.
class DynamicLayerShellViews extends ChangeNotifier {
  static final DynamicLayerShellViews instance = DynamicLayerShellViews._();
  DynamicLayerShellViews._();

  final List<Widget> _views = [];
  List<Widget> get views => List.unmodifiable(_views);

  void add(Widget view) {
    _views.add(view);
    notifyListeners();
  }

  void remove(Widget view) {
    _views.remove(view);
    notifyListeners();
  }
}

class ExtendedWindowingOwnerLinux extends WindowingOwnerLinux {
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

class LayershellWindowController extends RegularWindowController {
  /// Create a new LayershellWindowController.
  factory LayershellWindowController({
    required ExtendedWindowingOwnerLinux owner,
    required RegularWindowControllerDelegate delegate,
    GtkLayerShellLayer layer = GtkLayerShellLayer.top,
    List<GtkLayerShellEdge> anchorEdges = const [
      GtkLayerShellEdge.top,
      GtkLayerShellEdge.left,
      GtkLayerShellEdge.right,
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
    final inner = owner.createRegularWindowController(
        delegate: delegate, resizable: false) as RegularWindowControllerLinux;
    return LayershellWindowController._wrap(
      inner,
      layer: layer,
      anchorEdges: anchorEdges,
      keyboardMode: keyboardMode,
      width: width,
      height: height,
      exclusiveZone: exclusiveZone,
      monitor: monitor,
    );
  }

  LayershellWindowController._wrap(
    this._inner, {
    required GtkLayerShellLayer layer,
    required List<GtkLayerShellEdge> anchorEdges,
    required GtkLayerShellKeyboardMode keyboardMode,
    int? width,
    int? height,
    int? exclusiveZone,
    ffi.Pointer<ffi.NativeType>? monitor,
  }) : super.empty() {
    // Forward change notifications from the inner controller so listeners on
    // this wrapper (e.g. LayerShellWindow's ListenableBuilder) stay in sync.
    _inner.addListener(notifyListeners);

    // Apply layer-shell settings now — the GtkWindow exists but present() is
    // deferred to the first frame, satisfying gtk-layer-shell's ordering rule.
    final gtkWin = GtkWindow(_inner.windowHandle.cast());
    FlView.fromHandle(_inner.flutterViewHandle.cast())
        .setBackgroundColor('#00000000');

    gtkWin.layerInitForWindow();
    if (monitor != null && monitor.address != 0) {
      gtkWin.layerSetMonitor(monitor);
    }
    if (exclusiveZone != null) {
      gtkWin.layerAutoExclusiveZoneEnable();
      gtkWin.layerSetExclusiveZone(exclusiveZone);
    }
    for (final edge in anchorEdges) {
      gtkWin.layerSetAnchor(edge, true);
    }
    gtkWin.layerSetLayer(layer);
    gtkWin.layerSetKeyboardMode(keyboardMode);
    gtkWin.setSizeRequest(width ?? -1, height ?? -1);
    gtkWin.setDefaultSize(width ?? -1, height ?? -1);
    gtkWin.setAppPaintable(true);
  }

  final RegularWindowControllerLinux _inner;

  /// The underlying GTK window, exposed for use as a popup transient parent.
  GtkWindow get gtkWindow => GtkWindow(_inner.windowHandle.cast());

  @override
  FlutterView get rootView => _inner.rootView;

  @override
  Size get contentSize => _inner.contentSize;

  @override
  void destroy() {
    _inner.removeListener(notifyListeners);
    _inner.destroy();
  }

  @override
  bool get isActivated => _inner.isActivated;

  @override
  void setSize(Size size) => _inner.setSize(size);

  @override
  void activate() => _inner.activate();

  // Layer-shell windows are compositor-managed — no-op these operations.

  @override
  bool get isFullscreen => false;

  @override
  bool get isMaximized => false;

  @override
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
  String get title => '';
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
        _window = GtkWindow(GtkWindow.gtkWindowNew(0)),
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
    final rawX =
        (anchorPoint.dx - childOffset.dx + positioner.offset.dx).toInt();
    final rawY =
        (anchorPoint.dy - childOffset.dy + positioner.offset.dy).toInt();

    // Clamp position so the popup stays fully on screen.
    final screenSize = getScreenSize();
    final maxX = ((screenSize.width - size.width).toInt())
        .clamp(0, screenSize.width.toInt());
    final maxY = ((screenSize.height - size.height).toInt())
        .clamp(0, screenSize.height.toInt());
    final x = rawX.clamp(0, maxX);
    final y = rawY.clamp(0, maxY);

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
  Offset get offsetFromParent => Offset.zero;

  @override
  void updatePosition({Rect? anchorRect, WindowPositioner? positioner}) {
    // No-op: layer-shell popups are positioned at creation time.
  }

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

// ---------------------------------------------------------------------------
// Shared popup infrastructure
// ---------------------------------------------------------------------------

/// Shared delegate that forwards [onWindowDestroyed] to a callback.
///
/// Replaces per-module private delegate classes.
class PopupDelegate extends PopupWindowControllerDelegate {
  PopupDelegate({required this.onDestroyed});
  final VoidCallback onDestroyed;

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    onDestroyed();
  }
}

/// Mixin for [State] classes that own a single popup window.
///
/// Encapsulates the controller/view lifecycle, focus-loss tracking, and
/// WindowRegistry registration so each module only needs to compute its own
/// anchor geometry and call [openPopup].
mixin PopupHost<T extends StatefulWidget> on State<T> {
  PopupWindowController? _popupController;
  WindowRegistry? _registry;
  WindowEntry? _entry;

  /// Whether a popup is currently open.
  bool get isPopupOpen => _popupController != null;

  /// Opens a popup positioned relative to the given anchor geometry.
  ///
  /// If a popup is already open this is a no-op — call [closePopup] first.
  void openPopup(
    BuildContext context, {
    required Widget child,
    required BoxConstraints preferredConstraints,
    required Rect anchorRect,
    required WindowPositionerAnchor parentAnchor,
    required WindowPositionerAnchor childAnchor,
  }) {
    final parentController = WindowScope.of(context);
    PopupWindowController? thisController;
    _popupController = thisController = PopupWindowController(
      parent: parentController,
      anchorRect: anchorRect,
      positioner: WindowPositioner(
        parentAnchor: parentAnchor,
        childAnchor: childAnchor,
      ),
      preferredConstraints: preferredConstraints,
      delegate: PopupDelegate(onDestroyed: () {
        if (_popupController == thisController) closePopup();
      }),
    );
    _registry = WindowRegistry.of(context);
    _entry = WindowEntry(controller: _popupController!, builder: (_) => child);
    _registry!.register(_entry!);
    setState(() {});
  }

  /// Closes and destroys the current popup, if any.
  void closePopup() {
    if (_entry != null) {
      _registry?.unregister(_entry!);
      _entry = null;
    }
    _registry = null;
    final ctrl = _popupController;
    _popupController = null;
    if (ctrl is PopupGtkWindowController && !ctrl.isDestroyed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ctrl.isDestroyed) ctrl.destroy();
      });
    }
    if (mounted) setState(() {});
  }
}

/// Wraps [child] with a scale + fade bounce-in animation.
///
/// Place this inside any popup content widget (inside Directionality /
/// DefaultTextStyle) so the content springs into view when the popup opens.
class PopupBounceIn extends StatefulWidget {
  const PopupBounceIn({super.key, required this.child});
  final Widget child;

  @override
  State<PopupBounceIn> createState() => _PopupBounceInState();
}

class _PopupBounceInState extends State<PopupBounceIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}
