import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import '../native/glib_source.dart';
import 'wl_types.dart';

/// Raw `libwayland-client` bindings.
///
/// A *second* Wayland connection, separate from the pure-Dart `package:wayland`
/// client the rest of the shell uses: that client cannot pass file descriptors
/// (its `writeFd`/`readFd` are stubs), and image-copy-capture requires them
/// (`wl_shm.create_pool`). libwayland handles SCM_RIGHTS natively. Precedent for
/// a second connection: `lib/overlay/settings/display.dart`.
class WlFfi {
  WlFfi._(this._lib) {
    displayConnect = _lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>)>('wl_display_connect');
    displayDisconnect = _lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('wl_display_disconnect');
    displayGetFd = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('wl_display_get_fd');
    displayFlush = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('wl_display_flush');
    displayRoundtrip = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('wl_display_roundtrip');
    displayDispatchPending = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('wl_display_dispatch_pending');
    displayPrepareRead = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('wl_display_prepare_read');
    displayReadEvents = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('wl_display_read_events');
    displayCancelRead = _lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('wl_display_cancel_read');
    displayGetError = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('wl_display_get_error');

    proxyMarshalArrayFlags = _lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.Pointer<WlInterface>,
            ffi.Uint32,
            ffi.Uint32,
            ffi.Pointer<ffi.Void>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int,
            ffi.Pointer<WlInterface>, int, int, ffi.Pointer<ffi.Void>)>(
        'wl_proxy_marshal_array_flags');
    proxyAddListener = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Pointer<ffi.Void>>, ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Void>>,
            ffi.Pointer<ffi.Void>)>('wl_proxy_add_listener');
    proxyDestroy = _lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('wl_proxy_destroy');
    proxyGetVersion = _lib.lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('wl_proxy_get_version');
    proxyGetId = _lib.lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('wl_proxy_get_id');
  }

  static WlFfi? _instance;

  /// Throws if `libwayland-client.so.0` is unavailable — callers treat that
  /// as "screencast unsupported" and fail soft.
  static WlFfi get instance =>
      _instance ??= WlFfi._(ffi.DynamicLibrary.open('libwayland-client.so.0'));

  final ffi.DynamicLibrary _lib;

  late final ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>) displayConnect;
  late final void Function(ffi.Pointer<ffi.Void>) displayDisconnect;
  late final int Function(ffi.Pointer<ffi.Void>) displayGetFd;
  late final int Function(ffi.Pointer<ffi.Void>) displayFlush;
  late final int Function(ffi.Pointer<ffi.Void>) displayRoundtrip;
  late final int Function(ffi.Pointer<ffi.Void>) displayDispatchPending;
  late final int Function(ffi.Pointer<ffi.Void>) displayPrepareRead;
  late final int Function(ffi.Pointer<ffi.Void>) displayReadEvents;
  late final void Function(ffi.Pointer<ffi.Void>) displayCancelRead;
  late final int Function(ffi.Pointer<ffi.Void>) displayGetError;

  late final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int,
      ffi.Pointer<WlInterface>, int, int, ffi.Pointer<ffi.Void>)
      proxyMarshalArrayFlags;
  late final int Function(ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Pointer<ffi.Void>>, ffi.Pointer<ffi.Void>) proxyAddListener;
  late final void Function(ffi.Pointer<ffi.Void>) proxyDestroy;
  late final int Function(ffi.Pointer<ffi.Void>) proxyGetVersion;
  late final int Function(ffi.Pointer<ffi.Void>) proxyGetId;

  /// Looks up one of the core interface structs libwayland exports as data
  /// symbols (`wl_registry_interface`, `wl_output_interface`, …). Using the
  /// real structs instead of hand-built copies removes a whole class of
  /// transcription bugs for everything that isn't an ext protocol.
  ffi.Pointer<WlInterface> coreInterface(String symbol) =>
      _lib.lookup<WlInterface>(symbol);
}

/// `WL_MARSHAL_FLAG_DESTROY` — marshal the (destructor) request and destroy
/// the proxy in one step.
const int wlMarshalFlagDestroy = 1;

/// One capture-side Wayland connection with its event pump.
///
/// The pump can be driven two ways: [attachToGlibLoop] (the shell — a
/// `g_unix_fd_add` watch on the display fd wakes the standard
/// prepare_read/read_events/dispatch_pending cycle), or manual [roundtrip] calls
/// (the spike tool and startup code, where blocking is fine).
class WlDisplayConnection {
  WlDisplayConnection._(this.display);

  static WlDisplayConnection? connect() {
    final ffi.Pointer<ffi.Void> d;
    try {
      d = WlFfi.instance.displayConnect(ffi.nullptr);
    } catch (_) {
      return null; // libwayland-client not present
    }
    if (d.address == 0) return null;
    return WlDisplayConnection._(d);
  }

  final ffi.Pointer<ffi.Void> display;
  GlibFdWatch? _watch;
  bool _dead = false;
  bool _disconnected = false;

  /// Invoked once if the compositor connection dies (protocol error/hangup).
  void Function()? onError;

  bool get isAlive => !_dead;

  int get fd => WlFfi.instance.displayGetFd(display);

  void attachToGlibLoop() {
    _watch ??= GlibFdWatch(fd, _onFdReady);
  }

  void _onFdReady(int condition) {
    if (_dead) return;
    if (condition & (GlibFdWatch.gIoErr | GlibFdWatch.gIoHup) != 0) {
      _fail();
      return;
    }
    pumpOnce();
  }

  /// Standard single-threaded libwayland read cycle; only called when the fd
  /// is known readable, so `read_events` does not block.
  void pumpOnce() {
    final w = WlFfi.instance;
    while (w.displayPrepareRead(display) != 0) {
      w.displayDispatchPending(display);
    }
    if (w.displayReadEvents(display) == -1) {
      _fail();
      return;
    }
    if (w.displayDispatchPending(display) == -1) {
      _fail();
      return;
    }
    w.displayFlush(display);
  }

  /// Blocks until the compositor has processed all pending requests,
  /// dispatching events as they arrive. Startup only — never call from an
  /// event callback.
  bool roundtrip() {
    if (_dead) return false;
    if (WlFfi.instance.displayRoundtrip(display) == -1) {
      _fail();
      return false;
    }
    return true;
  }

  void flush() {
    if (!_dead) WlFfi.instance.displayFlush(display);
  }

  void _fail() {
    if (_dead) return;
    _dead = true;
    _watch?.dispose();
    _watch = null;
    onError?.call();
  }

  void disconnect() {
    _watch?.dispose();
    _watch = null;
    _dead = true;
    if (!_disconnected) {
      _disconnected = true;
      WlFfi.instance.displayDisconnect(display);
    }
  }
}
