import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'wl_ffi.dart';
import 'wl_types.dart';

/// Live proxy wrappers keyed by `wl_proxy*` address. Event trampolines route
/// through this map instead of libwayland's user_data, so a stray event for
/// an already-destroyed proxy resolves to null rather than a dangling
/// pointer.
final Map<int, WlProxy> _liveProxies = {};

T? proxyByAddress<T extends WlProxy>(int address) {
  final p = _liveProxies[address];
  return p is T ? p : null;
}

/// Base class for typed wrappers around a `wl_proxy*`, mirroring the shape of
/// the `WaylandObject` subclasses in `lib/input_trigger/input_trigger_protocol.dart`
/// but over dart:ffi instead of the pure-Dart client.
abstract class WlProxy {
  WlProxy(this.conn, this.ptr) {
    _liveProxies[ptr.address] = this;
  }

  final WlDisplayConnection conn;
  final ffi.Pointer<ffi.Void> ptr;
  bool _destroyed = false;

  bool get isDestroyed => _destroyed;
  int get version => WlFfi.instance.proxyGetVersion(ptr);

  /// Sends a constructor request and returns the raw new proxy. [args] is
  /// freed. The caller wraps the result in its typed class.
  ffi.Pointer<ffi.Void> marshalConstructor(
    int opcode,
    ffi.Pointer<WlInterface> iface,
    WlArgs args, {
    int? version,
  }) {
    final v = version ?? WlFfi.instance.proxyGetVersion(ptr);
    final child = WlFfi.instance
        .proxyMarshalArrayFlags(ptr, opcode, iface, v, 0, args.pointer);
    args.free();
    conn.flush();
    return child;
  }

  /// Sends a plain request. [args] is freed.
  void marshal(int opcode, WlArgs args) {
    WlFfi.instance.proxyMarshalArrayFlags(
        ptr, opcode, ffi.nullptr, 0, 0, args.pointer);
    args.free();
    conn.flush();
  }

  void marshalNoArgs(int opcode) => marshal(opcode, WlArgs(0));

  /// Sends a destructor request and destroys the proxy in one step
  /// (`WL_MARSHAL_FLAG_DESTROY`), then drops the wrapper registration.
  void sendDestructor(int opcode) {
    if (_destroyed) return;
    _destroyed = true;
    _liveProxies.remove(ptr.address);
    final args = WlArgs(0);
    WlFfi.instance.proxyMarshalArrayFlags(
        ptr, opcode, ffi.nullptr, 0, wlMarshalFlagDestroy, args.pointer);
    args.free();
    conn.flush();
  }

  /// Destroys the client-side proxy without a destructor request — for
  /// interfaces with no destructor (wl_registry) or after a terminal event
  /// (`closed`) when the destructor has other semantics.
  void destroyLocal() {
    if (_destroyed) return;
    _destroyed = true;
    _liveProxies.remove(ptr.address);
    WlFfi.instance.proxyDestroy(ptr);
  }

  void addListener(ffi.Pointer<ffi.Pointer<ffi.Void>> vtable) {
    WlFfi.instance.proxyAddListener(ptr, vtable, ffi.nullptr);
  }
}

/// Allocates a listener struct (an array of function pointers in XML event
/// order). Built once per interface and never freed.
ffi.Pointer<ffi.Pointer<ffi.Void>> buildVtable(
    List<ffi.Pointer<ffi.Void>> slots) {
  final vt = calloc<ffi.Pointer<ffi.Void>>(slots.length);
  for (var i = 0; i < slots.length; i++) {
    vt[i] = slots[i];
  }
  return vt;
}

/// The event trampolines below wrap a Dart closure in a `NativeCallable`
/// matching one concrete libwayland dispatch signature
/// (`void fn(void *data, wl_proxy *proxy, <event args>)`). All of them are
/// `isolateLocal`: dispatch only ever happens from this thread, either inside
/// `wl_display_roundtrip` (startup) or from the GLib fd watch. The callables
/// are parked in [_keepAliveCallables] for the process lifetime, matching the
/// static listener structs generated C code uses.
final List<Object> _keepAliveCallables = [];

typedef _C0 = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>);
typedef _CU = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Uint32);
typedef _CUU = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Uint32);
typedef _CUUU = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
    ffi.Uint32, ffi.Uint32, ffi.Uint32);
typedef _CI = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _CIIII = ffi.Void Function(ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _CP = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>);
typedef _CUP = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
    ffi.Uint32, ffi.Pointer<ffi.Void>);
typedef _CS = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>);
typedef _CUSU = ffi.Void Function(ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Pointer<Utf8>, ffi.Uint32);
typedef _CUIII = ffi.Void Function(ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _CGeometry = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Int32,
    ffi.Int32,
    ffi.Int32,
    ffi.Int32,
    ffi.Int32,
    ffi.Pointer<Utf8>,
    ffi.Pointer<Utf8>,
    ffi.Int32);

ffi.Pointer<ffi.Void> _park(ffi.NativeCallable callable) {
  _keepAliveCallables.add(callable);
  return callable.nativeFunction.cast();
}

ffi.Pointer<ffi.Void> ev0(void Function(int proxy) fn) =>
    _park(ffi.NativeCallable<_C0>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p) => fn(p.address)));

ffi.Pointer<ffi.Void> evU(void Function(int proxy, int a) fn) =>
    _park(ffi.NativeCallable<_CU>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p, int a) =>
            fn(p.address, a)));

ffi.Pointer<ffi.Void> evUU(void Function(int proxy, int a, int b) fn) =>
    _park(ffi.NativeCallable<_CUU>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p, int a, int b) =>
            fn(p.address, a, b)));

ffi.Pointer<ffi.Void> evUUU(
        void Function(int proxy, int a, int b, int c) fn) =>
    _park(ffi.NativeCallable<_CUUU>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p, int a, int b,
                int c) =>
            fn(p.address, a, b, c)));

ffi.Pointer<ffi.Void> evI(void Function(int proxy, int a) fn) =>
    _park(ffi.NativeCallable<_CI>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p, int a) =>
            fn(p.address, a)));

ffi.Pointer<ffi.Void> evIIII(
        void Function(int proxy, int a, int b, int c, int e) fn) =>
    _park(ffi.NativeCallable<_CIIII>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p, int a, int b,
                int c, int e) =>
            fn(p.address, a, b, c, e)));

/// Pointer-argument event: an `array` payload or a `new_id` proxy libwayland
/// created for us.
ffi.Pointer<ffi.Void> evP(
        void Function(int proxy, ffi.Pointer<ffi.Void> arg) fn) =>
    _park(ffi.NativeCallable<_CP>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p,
                ffi.Pointer<ffi.Void> a) =>
            fn(p.address, a)));

ffi.Pointer<ffi.Void> evUP(
        void Function(int proxy, int a, ffi.Pointer<ffi.Void> b) fn) =>
    _park(ffi.NativeCallable<_CUP>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p, int a,
                ffi.Pointer<ffi.Void> b) =>
            fn(p.address, a, b)));

ffi.Pointer<ffi.Void> evS(void Function(int proxy, String s) fn) =>
    _park(ffi.NativeCallable<_CS>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p,
                ffi.Pointer<Utf8> s) =>
            fn(p.address, s.address == 0 ? '' : s.toDartString())));

ffi.Pointer<ffi.Void> evUSU(
        void Function(int proxy, int a, String s, int b) fn) =>
    _park(ffi.NativeCallable<_CUSU>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p, int a,
                ffi.Pointer<Utf8> s, int b) =>
            fn(p.address, a, s.address == 0 ? '' : s.toDartString(), b)));

ffi.Pointer<ffi.Void> evUIII(
        void Function(int proxy, int a, int b, int c, int e) fn) =>
    _park(ffi.NativeCallable<_CUIII>.isolateLocal(
        (ffi.Pointer<ffi.Void> d, ffi.Pointer<ffi.Void> p, int a, int b,
                int c, int e) =>
            fn(p.address, a, b, c, e)));

ffi.Pointer<ffi.Void> evGeometry(
        void Function(int proxy, int x, int y, String make, String model) fn) =>
    _park(ffi.NativeCallable<_CGeometry>.isolateLocal(
        (ffi.Pointer<ffi.Void> d,
                ffi.Pointer<ffi.Void> p,
                int x,
                int y,
                int physW,
                int physH,
                int subpixel,
                ffi.Pointer<Utf8> make,
                ffi.Pointer<Utf8> model,
                int transform) =>
            fn(
                p.address,
                x,
                y,
                make.address == 0 ? '' : make.toDartString(),
                model.address == 0 ? '' : model.toDartString())));
