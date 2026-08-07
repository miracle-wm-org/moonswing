// This library builds on Flutter's experimental windowing APIs, the same ones
// `package:layer_shell` uses. Those APIs are `@internal` and Flutter makes
// breaking changes to them even in patch versions, so this package cannot be
// published and must be consumed as a path/git dependency on a Flutter channel
// with `flutter config --enable-windowing`.

// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: invalid_use_of_protected_member

import 'dart:ffi' as ffi;
import 'dart:ui' show Display, FlutterView;

import 'package:flutter/widgets.dart';
import 'package:flutter/src/foundation/_features.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:layer_shell/layer_shell.dart'
    show ExtendedWindowingOwnerLinux, initLayerShell;
import 'package:layer_shell/src/gtk.dart';

import 'src/gtk_session_lock.dart';

const String _kWindowingDisabledErrorMessage = '''
Windowing APIs are not enabled.

Windowing APIs are currently experimental. Do not use windowing APIs in
production applications or plugins published to pub.dev.

To try experimental windowing APIs:
1. Switch to Flutter's main release channel.
2. Turn on the windowing feature flag.

See: https://github.com/flutter/flutter/issues/30701.
''';

bool _initialized = false;

/// Initializes session-lock support and installs the windowing owner globally.
///
/// Call this once after `WidgetsFlutterBinding.ensureInitialized()`, *instead
/// of* `initLayerShell()` — it calls that first (so layer-shell windows keep
/// working) and then swaps in a [SessionLockWindowingOwnerLinux], which is an
/// [ExtendedWindowingOwnerLinux] and therefore satisfies every existing
/// layer-shell and popup code path.
void initSessionLock() {
  initLayerShell();
  WidgetsBinding.instance.windowingOwner = SessionLockWindowingOwnerLinux();
  _initialized = true;
}

/// A session lock: the client side of `ext-session-lock-v1`.
///
/// Lifecycle, mirroring the protocol:
///
/// 1. [prepare] creates the lock object and wires its signals.
/// 2. [lock] asks the compositor to lock the session. Every normal and
///    layer-shell surface — including the shell's own panels — is hidden, and
///    outputs without a lock surface are blanked with an opaque colour.
/// 3. One [SessionLockWindowController] per monitor turns a GTK window into
///    that output's lock surface (it calls [newSurface] for you).
/// 4. [onLocked] fires once the compositor confirms the session is locked.
/// 5. [unlockAndDestroy] unlocks and tears the lock down.
///
/// If the client disconnects without unlocking, the compositor keeps the
/// session locked — a crash can never expose the session.
class SessionLock {
  SessionLock({this.onLocked, this.onFinished});

  /// Called when the compositor confirms the session is locked.
  final VoidCallback? onLocked;

  /// Called when the lock ends without us unlocking it — the compositor
  /// refused the lock or dropped it. The session may still be locked, so
  /// treat this as "give up and clean up".
  final VoidCallback? onFinished;

  ffi.Pointer<ffi.Void> _lock = ffi.nullptr;
  ffi.NativeCallable<
      ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>? _onLockedNative;
  ffi.NativeCallable<
      ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>? _onFinishedNative;
  bool _locked = false;
  bool _everLocked = false;
  bool _disposed = false;

  /// True when `libgtk-session-lock` could be loaded at all.
  static bool get isAvailable => GtkSessionLockBindings.instance != null;

  /// True when the library loaded *and* the compositor implements
  /// `ext-session-lock-v1`.
  static bool get isSupported {
    final bindings = GtkSessionLockBindings.instance;
    if (bindings == null) return false;
    try {
      return bindings.isSupported();
    } catch (_) {
      return false;
    }
  }

  /// The `ext-session-lock-v1` version the compositor offers, or 0.
  static int get protocolVersion {
    final bindings = GtkSessionLockBindings.instance;
    if (bindings == null) return 0;
    try {
      return bindings.getProtocolVersion();
    } catch (_) {
      return 0;
    }
  }

  /// The underlying `GtkSessionLockLock*`.
  ffi.Pointer<ffi.Void> get handle => _lock;

  /// True once [prepare] has run and the lock has not been destroyed.
  bool get isPrepared => _lock.address != 0 && !_disposed;

  /// True between the compositor's `locked` signal and teardown.
  bool get isLocked => _locked;

  /// Creates the lock object and connects its `locked`/`finished` signals.
  ///
  /// Throws [StateError] when the library or protocol is unavailable — callers
  /// should check [isSupported] first.
  void prepare() {
    if (_disposed) {
      throw StateError('SessionLock has already been destroyed.');
    }
    if (isPrepared) return;

    final bindings = GtkSessionLockBindings.instance;
    if (bindings == null) {
      throw StateError(
          'libgtk-session-lock is not installed; cannot lock the session.');
    }
    if (!bindings.isSupported()) {
      throw StateError(
          'The compositor does not implement ext-session-lock-v1.');
    }

    _lock = bindings.prepareLock();
    if (_lock.address == 0) {
      throw StateError('gtk_session_lock_prepare_lock() returned null.');
    }

    // Signal signature is `void handler(GObject *self, gpointer user_data)`;
    // neither argument is interesting to us.
    _onLockedNative = ffi.NativeCallable<
        ffi.Void Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>)>.isolateLocal(_handleLocked);
    _onFinishedNative = ffi.NativeCallable<
        ffi.Void Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>)>.isolateLocal(_handleFinished);

    gSignalConnect(_lock, 'locked', _onLockedNative!.nativeFunction.cast());
    gSignalConnect(_lock, 'finished', _onFinishedNative!.nativeFunction.cast());
  }

  void _handleLocked(ffi.Pointer<ffi.Void> _, ffi.Pointer<ffi.Void> __) {
    _locked = true;
    _everLocked = true;
    onLocked?.call();
  }

  void _handleFinished(ffi.Pointer<ffi.Void> _, ffi.Pointer<ffi.Void> __) {
    _locked = false;
    onFinished?.call();
  }

  /// Asks the compositor to lock the session.
  void lock() {
    final bindings = _requireBindings();
    bindings.lockLock(_lock);
  }

  /// Turns [window] into the lock surface for [monitor].
  ///
  /// Called by [SessionLockWindowController] before the window is realized.
  void newSurface(GtkWindow window, ffi.Pointer<ffi.NativeType> monitor) {
    final bindings = _requireBindings();
    bindings.lockNewSurface(_lock, window.instance.cast(), monitor.cast());
  }

  /// Unlocks the session and destroys the lock.
  ///
  /// Destroy the [SessionLockWindowController]s *after* calling this: the
  /// protocol says lock surfaces "should be destroyed by the client" once the
  /// unlock request has been made.
  void unlockAndDestroy() {
    if (!isPrepared) return;
    final bindings = GtkSessionLockBindings.instance;
    _locked = false;
    _disposed = true;
    final lock = _lock;
    _lock = ffi.nullptr;
    bindings?.lockUnlockAndDestroy(lock);
    // Mandatory: the compositor may kill the connection with a protocol error
    // if it has not processed the unlock before we carry on tearing down.
    gdkDisplaySync();
    _closeCallbacks();
  }

  /// Tears the lock down with whichever destructor the protocol allows.
  ///
  /// The choice is not the caller's to make: once the `locked` event has been
  /// received, `ext_session_lock_v1.destroy` is a protocol error
  /// (`invalid_destroy`) and `unlock_and_destroy` is the only legal request —
  /// and before it, the reverse. Getting this wrong kills the Wayland
  /// connection, taking the whole shell with it.
  ///
  /// Use this when responding to [onFinished] or unwinding a failed lock.
  void release() {
    if (!isPrepared) return;
    if (_everLocked) {
      unlockAndDestroy();
      return;
    }
    final bindings = GtkSessionLockBindings.instance;
    _locked = false;
    _disposed = true;
    final lock = _lock;
    _lock = ffi.nullptr;
    bindings?.lockDestroy(lock);
    _closeCallbacks();
  }

  /// Drops the lock without telling the compositor anything, leaving the
  /// session locked.
  ///
  /// For shutdown while locked. There is deliberately no Wayland request here:
  /// after `locked`, the only legal destructor is `unlock_and_destroy`, which
  /// would *unlock* the session — the opposite of what a dying shell wants.
  /// Simply disconnecting leaves the session locked, which is the protocol's
  /// documented behaviour.
  void abandon() {
    if (!isPrepared) return;
    _locked = false;
    _disposed = true;
    _lock = ffi.nullptr;
    _closeCallbacks();
  }

  void _closeCallbacks() {
    _onLockedNative?.close();
    _onLockedNative = null;
    _onFinishedNative?.close();
    _onFinishedNative = null;
  }

  GtkSessionLockBindings _requireBindings() {
    if (!isPrepared) {
      throw StateError('SessionLock.prepare() has not been called.');
    }
    final bindings = GtkSessionLockBindings.instance;
    if (bindings == null) {
      throw StateError('libgtk-session-lock is not available.');
    }
    return bindings;
  }
}

/// A [WindowingOwnerLinux] that can also create `ext-session-lock-v1` windows.
///
/// Extends [ExtendedWindowingOwnerLinux] rather than replacing it so that
/// layer-shell windows, popups, dialogs and lock windows all share a single
/// owner and therefore a single [LinuxWindowRegistrar].
class SessionLockWindowingOwnerLinux extends ExtendedWindowingOwnerLinux {
  /// Creates a lock-surface window controller and registers its native window
  /// and view with the owner's registrar.
  ///
  /// Mirrors [ExtendedWindowingOwnerLinux.createLayerShellWindowController].
  SessionLockWindowController createSessionLockWindowController({
    required SessionLock sessionLock,
    required ffi.Pointer<ffi.NativeType> monitor,
  }) {
    final controller = SessionLockWindowController._internal(
      owner: this,
      sessionLock: sessionLock,
      monitor: monitor,
    );
    registrar.register(
      viewId: controller.rootView.viewId,
      windowHandle: controller.windowHandle,
      viewHandle: controller.flutterViewHandle,
    );
    return controller;
  }

  /// Removes a lock window from the registrar. Called by
  /// [SessionLockWindowController.destroy]; routed through the owner because
  /// [registrar] is only accessible from within a [WindowingOwnerLinux].
  void unregisterSessionLockWindow(int viewId) => registrar.unregister(viewId);
}

/// A window whose surface is an `ext_session_lock_surface_v1` for one monitor.
///
/// Modelled on `layer_shell`'s `LayershellWindowController`, with the
/// gtk-session-lock setup inserted *before* the window is realized:
/// `gtk_session_lock_lock_new_surface()` has to claim the GDK window's surface
/// before GTK maps it, which is why window creation is driven here rather than
/// reusing the SDK's regular controller (which realizes in its own
/// constructor).
class SessionLockWindowController extends WindowController
    implements BaseWindowControllerLinux {
  /// Creates a lock window on [monitor] for an already-[SessionLock.prepare]d
  /// and [SessionLock.lock]ed session lock.
  ///
  /// [initSessionLock] must have been called first.
  factory SessionLockWindowController({
    required SessionLock sessionLock,
    required ffi.Pointer<ffi.NativeType> monitor,
  }) {
    if (!isWindowingEnabled) {
      throw UnsupportedError(_kWindowingDisabledErrorMessage);
    }
    final owner = WidgetsBinding.instance.windowingOwner;
    if (!_initialized || owner is! SessionLockWindowingOwnerLinux) {
      throw StateError('initSessionLock() must be called before creating a '
          'SessionLockWindowController.');
    }
    return owner.createSessionLockWindowController(
      sessionLock: sessionLock,
      monitor: monitor,
    );
  }

  SessionLockWindowController._internal({
    required SessionLockWindowingOwnerLinux owner,
    required SessionLock sessionLock,
    required ffi.Pointer<ffi.NativeType> monitor,
  })  : _owner = owner,
        _window = GtkWindow(GtkWindowType.toplevel),
        super.empty() {
    // gtk-session-lock has to claim this window's surface before GTK realizes
    // and maps it, exactly like gtk_layer_init_for_window().
    sessionLock.newSurface(_window, monitor);

    // Measured immediately, because this is the step that silently no-ops:
    // gtk_session_lock_lock_new_surface() passes the lock object straight to
    // lock_surface_new(), which bails on `g_return_val_if_fail (session_lock)`
    // before it connects the realize/map handlers. When that happens nothing
    // claims the surface and GDK maps an ordinary xdg_toplevel — a floating
    // window instead of a lock surface.
    attachedAsLockSurface = isLockWindow;

    // gtk-layer-shell disables decorations itself in layer_surface_new(); the
    // gtk-session-lock fork dropped that call, and a decorated GTK3 window
    // draws its CSD titlebar *inside* the lock surface. Must happen before
    // realize, like every other bit of surface setup here.
    gtkWindowSetDecorated(_window.instance.cast(), false);

    // Size the window to the monitor before it is ever laid out.
    //
    // gtk-session-lock only constrains the size once the compositor's
    // lock-surface configure arrives (it sets min == max geometry hints).
    // Until then GTK uses the window's natural size, so the first Flutter
    // layout would run in a tiny window and blow up with overflow errors.
    // Starting at the monitor's geometry means the very first frame is laid
    // out at the size the configure is going to ask for anyway.
    final geometry = GdkMonitor(monitor).getGeometry();
    if (geometry.width > 0 && geometry.height > 0) {
      _window.setDefaultSize(geometry.width.toInt(), geometry.height.toInt());
    }

    // Force creation as Flutter will try and render to it immediately.
    _window.realize();

    // Connected after realize, unlike the layer-shell controller: one of the
    // signals fl_window_monitor_new() hooks is "moved-to-rect" on the
    // *GdkWindow*, and gtk_widget_get_window() is NULL until the widget is
    // realized — which makes GTK log a NULL-instance criticial and silently
    // drop that handler.
    _windowMonitor = FlWindowMonitor(
      _window,
      onConfigure: notifyListeners,
      onStateChanged: notifyListeners,
      onIsActiveNotify: notifyListeners,
      onTitleNotify: notifyListeners,
      onClose: () {},
      onDestroy: () {
        _destroyed = true;
        notifyListeners();
      },
    );

    final engine = FlEngine.current();
    _view = FlView(engine);
    // Opaque black: a lock surface must never be see-through, even for the
    // frame or two before Flutter paints the wallpaper.
    _view.setBackgroundColor('#FF000000');
    _viewMonitor = FlViewMonitor(
      _view,
      onFirstFrame: () {
        _window.present();
      },
    );
    final int viewId = _view.getId();
    rootView = WidgetsBinding.instance.platformDispatcher.views.firstWhere(
      (FlutterView view) => view.viewId == viewId,
    );
    _view.show();
    _window.add(_view);
  }

  final SessionLockWindowingOwnerLinux _owner;
  final GtkWindow _window;
  late final FlView _view;
  late final FlViewMonitor _viewMonitor;
  late final FlWindowMonitor _windowMonitor;
  bool _destroyed = false;

  /// Whether `gtk_session_lock_lock_new_surface()` actually took the window
  /// over, sampled right after the call and before the window is realized.
  ///
  /// False means the lock surface was never registered and this window will
  /// map as an ordinary toplevel.
  late final bool attachedAsLockSurface;

  @override
  Size get contentSize => _window.getSize();

  @override
  bool get isDestroyed => _destroyed;

  @override
  void destroy() {
    if (_destroyed) return;
    _viewMonitor.close();
    _viewMonitor.unref();
    // The role object must die before the wl_surface: gtk_widget_destroy
    // tears down the wl_surface on unmap while gtk-session-lock only destroys
    // the ext_session_lock_surface_v1 in the window's finalizer, and Mir
    // answers that reversed order by deleting the role server-side — the
    // finalizer's destroy then hits an unknown object and the compositor
    // kills the connection.
    GtkSessionLockBindings.instance?.unmapLockWindow(_window.instance.cast());
    _window.destroy();
    _windowMonitor.close();
    _windowMonitor.unref();
    _destroyed = true;
    _owner.unregisterSessionLockWindow(rootView.viewId);
  }

  /// Whether gtk-session-lock actually took this window over as a lock
  /// surface.
  ///
  /// False means `gtk_session_lock_lock_new_surface()` did not attach — GDK
  /// will map the window as an ordinary `xdg_toplevel`, i.e. a normal floating
  /// window rather than a lock surface. Worth logging: the failure is silent
  /// apart from a `g_critical` on stderr.
  bool get isLockWindow {
    if (_destroyed) return false;
    final bindings = GtkSessionLockBindings.instance;
    if (bindings == null) return false;
    try {
      return bindings.isLockWindow(_window.instance.cast());
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isActivated => _window.isActive();

  @override
  void setSize(Size size) =>
      _window.resize(size.width.toInt(), size.height.toInt());

  @override
  void activate() => _window.present();

  @override
  ffi.Pointer<ffi.Void> get windowHandle {
    if (_destroyed) {
      throw StateError('Window has been destroyed.');
    }
    return _window.instance.cast();
  }

  @override
  ffi.Pointer<ffi.Void> get flutterViewHandle {
    if (_destroyed) {
      throw StateError('Window has been destroyed.');
    }
    return _view.instance.cast();
  }

  // Lock surfaces are entirely compositor-managed — no-op these operations.

  @override
  bool get isFullscreen => true;

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

/// Mounts the Flutter view of a [SessionLockWindowController].
///
/// Mirrors `layer_shell`'s `LayerShellWindow`.
class SessionLockWindow extends StatelessWidget {
  SessionLockWindow({
    super.key,
    required this.controller,
    required this.child,
  }) {
    if (!isWindowingEnabled) {
      throw UnsupportedError(_kWindowingDisabledErrorMessage);
    }
  }

  final SessionLockWindowController controller;

  final Widget child;

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
