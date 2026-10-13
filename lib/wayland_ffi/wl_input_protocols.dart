import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import '../native/libc.dart';
import 'wl_interfaces.dart';
import 'wl_protocols.dart';
import 'wl_proxy.dart';
import 'wl_types.dart';

/// Typed wrappers for the proxies the input-capture path uses: surfaces of its
/// own (a layer-shell strip on each barrier edge, a full-output surface while
/// capturing), the seat's pointer and keyboard, and the two pointer protocols
/// that make capture possible at all — `zwp_pointer_constraints_v1` to hold the
/// cursor still and `zwp_relative_pointer_v1` to read the motion it would have
/// made. Same shape as `wl_protocols.dart`: requests are methods with their
/// opcode noted, events dispatch to optional closures.
///
/// A listener table must cover every event the bound version can send, so the
/// seat is bound no higher than [WlSeatFfi.maxVersion] and the pointer and
/// keyboard tables are written out to that version in full.

// ---------------------------------------------------------------------------
// Core: compositor, surface, region.
// ---------------------------------------------------------------------------

class WlCompositorFfi extends WlProxy {
  WlCompositorFfi(super.conn, super.ptr);

  /// `wl_compositor.create_surface` (opcode 0, "n").
  WlSurfaceFfi createSurface() {
    final args = WlArgs(1)..setNewId(0);
    return WlSurfaceFfi(conn,
        marshalConstructor(0, WlProtocolInterfaces.instance.wlSurface, args));
  }

  /// `wl_compositor.create_region` (opcode 1, "n").
  WlRegionFfi createRegion() {
    final args = WlArgs(1)..setNewId(0);
    return WlRegionFfi(conn,
        marshalConstructor(1, WlProtocolInterfaces.instance.wlRegion, args));
  }
}

class WlSurfaceFfi extends WlProxy {
  // No listener: `enter`/`leave` (and v6's preferred scale) say nothing these
  // surfaces need, and libwayland drops events for a proxy without one.
  WlSurfaceFfi(super.conn, super.ptr);

  /// `wl_surface.destroy` (opcode 0).
  void destroy() => sendDestructor(0);

  /// `wl_surface.attach` (opcode 1, "?oii").
  void attach(WlBufferFfi? buffer) {
    final args = WlArgs(3)
      ..setObject(0, buffer?.ptr ?? ffi.nullptr)
      ..setInt(1, 0)
      ..setInt(2, 0);
    marshal(1, args);
  }

  /// `wl_surface.set_input_region` (opcode 5, "?o") — null is "everywhere".
  void setInputRegion(WlRegionFfi? region) {
    final args = WlArgs(1)..setObject(0, region?.ptr ?? ffi.nullptr);
    marshal(5, args);
  }

  /// `wl_surface.commit` (opcode 6).
  void commit() => marshalNoArgs(6);

  /// `wl_surface.damage_buffer` (opcode 9, "iiii", since v4).
  void damageBuffer(int x, int y, int width, int height) {
    final args = WlArgs(4)
      ..setInt(0, x)
      ..setInt(1, y)
      ..setInt(2, width)
      ..setInt(3, height);
    marshal(9, args);
  }
}

class WlRegionFfi extends WlProxy {
  WlRegionFfi(super.conn, super.ptr);

  /// `wl_region.destroy` (opcode 0).
  void destroy() => sendDestructor(0);

  /// `wl_region.add` (opcode 1, "iiii").
  void add(int x, int y, int width, int height) {
    final args = WlArgs(4)
      ..setInt(0, x)
      ..setInt(1, y)
      ..setInt(2, width)
      ..setInt(3, height);
    marshal(1, args);
  }
}

// ---------------------------------------------------------------------------
// Core: seat, pointer, keyboard.
// ---------------------------------------------------------------------------

class WlSeatFfi extends WlProxy {
  WlSeatFfi(super.conn, super.ptr) {
    addListener(_vtable);
  }

  /// The highest seat version the listener tables below are written for.
  /// v8 is `axis_value120`, the high-resolution wheel; v9 only adds
  /// `axis_relative_direction`, which nothing here needs.
  static const int maxVersion = 8;

  static const int capPointer = 1;
  static const int capKeyboard = 2;

  int capabilities = 0;
  void Function(int capabilities)? onCapabilities;

  static final _vtable = buildVtable([
    // capabilities
    evU((p, caps) {
      final seat = proxyByAddress<WlSeatFfi>(p);
      if (seat == null) return;
      seat.capabilities = caps;
      seat.onCapabilities?.call(caps);
    }),
    // name (v2)
    evS((p, name) {}),
  ]);

  /// `wl_seat.get_pointer` (opcode 0, "n").
  WlPointerFfi getPointer() {
    final args = WlArgs(1)..setNewId(0);
    return WlPointerFfi(conn,
        marshalConstructor(0, WlProtocolInterfaces.instance.wlPointer, args));
  }

  /// `wl_seat.get_keyboard` (opcode 1, "n").
  WlKeyboardFfi getKeyboard() {
    final args = WlArgs(1)..setNewId(0);
    return WlKeyboardFfi(conn,
        marshalConstructor(1, WlProtocolInterfaces.instance.wlKeyboard, args));
  }

  /// `wl_seat.release` (opcode 3, since v5).
  void release() {
    if (version >= 5) {
      sendDestructor(3);
    } else {
      destroyLocal();
    }
  }
}

/// `wl_pointer.axis` values.
const int wlPointerAxisVertical = 0;
const int wlPointerAxisHorizontal = 1;

/// `wl_pointer.button_state` / `wl_keyboard.key_state`.
const int wlStateReleased = 0;
const int wlStatePressed = 1;

class WlPointerFfi extends WlProxy {
  WlPointerFfi(super.conn, super.ptr) {
    addListener(_vtable);
  }

  /// Surface-local coordinates as doubles; [surface] is null when the pointer
  /// entered a surface this connection has already destroyed.
  void Function(int serial, WlSurfaceFfi? surface, double x, double y)? onEnter;
  void Function(int serial, WlSurfaceFfi? surface)? onLeave;
  void Function(int timeMs, double x, double y)? onMotion;
  void Function(int serial, int timeMs, int button, int state)? onButton;
  void Function(int timeMs, int axis, double value)? onAxis;
  void Function()? onFrame;
  void Function(int source)? onAxisSource;
  void Function(int timeMs, int axis)? onAxisStop;

  /// Whole wheel clicks (v5–7) — superseded by [onAxisValue120] from v8.
  void Function(int axis, int discrete)? onAxisDiscrete;

  /// Wheel motion in 120ths of a click (v8).
  void Function(int axis, int value120)? onAxisValue120;

  static WlPointerFfi? _of(int p) => proxyByAddress<WlPointerFfi>(p);

  static final _vtable = buildVtable([
    // enter
    evUPII((p, serial, surface, x, y) => _of(p)?.onEnter?.call(
        serial,
        proxyByAddress<WlSurfaceFfi>(surface.address),
        wlFixedToDouble(x),
        wlFixedToDouble(y))),
    // leave
    evUP((p, serial, surface) => _of(p)
        ?.onLeave
        ?.call(serial, proxyByAddress<WlSurfaceFfi>(surface.address))),
    // motion
    evUII((p, time, x, y) => _of(p)
        ?.onMotion
        ?.call(time, wlFixedToDouble(x), wlFixedToDouble(y))),
    // button
    evUUUU((p, serial, time, button, state) =>
        _of(p)?.onButton?.call(serial, time, button, state)),
    // axis
    evUUI((p, time, axis, value) =>
        _of(p)?.onAxis?.call(time, axis, wlFixedToDouble(value))),
    // frame (v5)
    ev0((p) => _of(p)?.onFrame?.call()),
    // axis_source (v5)
    evU((p, source) => _of(p)?.onAxisSource?.call(source)),
    // axis_stop (v5)
    evUU((p, time, axis) => _of(p)?.onAxisStop?.call(time, axis)),
    // axis_discrete (v5)
    evUI((p, axis, discrete) => _of(p)?.onAxisDiscrete?.call(axis, discrete)),
    // axis_value120 (v8)
    evUI((p, axis, value) => _of(p)?.onAxisValue120?.call(axis, value)),
    // axis_relative_direction (v9) — never bound that high; the slot exists so
    // the table cannot be indexed past its end.
    evUU((p, axis, direction) {}),
  ]);

  /// `wl_pointer.set_cursor` (opcode 0, "u?oii") with no surface: hides the
  /// cursor over this client's surfaces.
  void hideCursor(int serial) {
    final args = WlArgs(4)
      ..setUint(0, serial)
      ..setObject(1, ffi.nullptr)
      ..setInt(2, 0)
      ..setInt(3, 0);
    marshal(0, args);
  }

  /// `wl_pointer.release` (opcode 1, since v3).
  void release() {
    if (version >= 3) {
      sendDestructor(1);
    } else {
      destroyLocal();
    }
  }
}

/// `wl_keyboard.keymap_format.xkb_v1`.
const int wlKeymapFormatXkbV1 = 1;

class WlKeyboardFfi extends WlProxy {
  WlKeyboardFfi(super.conn, super.ptr) {
    addListener(_vtable);
  }

  /// The receiver owns [fd] and must close it.
  void Function(int format, int fd, int size)? onKeymap;

  /// [keys] are the evdev codes already held as focus arrived.
  void Function(int serial, WlSurfaceFfi? surface, List<int> keys)? onEnter;
  void Function(int serial, WlSurfaceFfi? surface)? onLeave;

  /// [key] is an evdev code (no +8 offset); [state] is [wlStatePressed] or
  /// [wlStateReleased].
  void Function(int serial, int timeMs, int key, int state)? onKey;
  void Function(int depressed, int latched, int locked, int group)? onModifiers;

  static WlKeyboardFfi? _of(int p) => proxyByAddress<WlKeyboardFfi>(p);

  static final _vtable = buildVtable([
    // keymap
    evUIU((p, format, fd, size) {
      final keyboard = _of(p);
      if (keyboard?.onKeymap == null) {
        // Nobody to hand it to, and an fd nobody closes is a leak per
        // keymap change.
        closeFd(fd);
        return;
      }
      keyboard!.onKeymap!(format, fd, size);
    }),
    // enter
    evUPP((p, serial, surface, keys) {
      final keyboard = _of(p);
      if (keyboard == null) return;
      keyboard.onEnter?.call(
          serial,
          proxyByAddress<WlSurfaceFfi>(surface.address),
          _readKeys(keys.cast<WlArray>()));
    }),
    // leave
    evUP((p, serial, surface) => _of(p)
        ?.onLeave
        ?.call(serial, proxyByAddress<WlSurfaceFfi>(surface.address))),
    // key
    evUUUU((p, serial, time, key, state) =>
        _of(p)?.onKey?.call(serial, time, key, state)),
    // modifiers
    evUUUUU((p, serial, depressed, latched, locked, group) =>
        _of(p)?.onModifiers?.call(depressed, latched, locked, group)),
    // repeat_info (v4) — the receiving machine repeats on its own terms.
    evII((p, rate, delay) {}),
  ]);

  static List<int> _readKeys(ffi.Pointer<WlArray> array) {
    if (array.address == 0) return const [];
    final count = array.ref.size ~/ 4;
    final data = array.ref.data.cast<ffi.Uint32>();
    return [for (var i = 0; i < count; i++) data[i]];
  }

  /// `wl_keyboard.release` (opcode 0, since v3).
  void release() {
    if (version >= 3) {
      sendDestructor(0);
    } else {
      destroyLocal();
    }
  }
}

// ---------------------------------------------------------------------------
// wlr-layer-shell-unstable-v1
// ---------------------------------------------------------------------------

/// `zwlr_layer_shell_v1.layer`.
const int layerOverlay = 3;

/// `zwlr_layer_surface_v1.anchor` bits.
const int anchorTop = 1;
const int anchorBottom = 2;
const int anchorLeft = 4;
const int anchorRight = 8;

/// `zwlr_layer_surface_v1.keyboard_interactivity`.
const int keyboardInteractivityNone = 0;
const int keyboardInteractivityExclusive = 1;

class ZwlrLayerShellV1 extends WlProxy {
  ZwlrLayerShellV1(super.conn, super.ptr);

  /// `get_layer_surface` (opcode 0, "no?ous"). A null [output] lets the
  /// compositor choose.
  ZwlrLayerSurfaceV1 getLayerSurface(
    WlSurfaceFfi surface,
    WlOutputFfi? output,
    int layer,
    String namespace,
  ) {
    final name = namespace.toNativeUtf8();
    try {
      final args = WlArgs(5)
        ..setNewId(0)
        ..setObject(1, surface.ptr)
        ..setObject(2, output?.ptr ?? ffi.nullptr)
        ..setUint(3, layer)
        ..setStringPtr(4, name);
      return ZwlrLayerSurfaceV1(conn,
          marshalConstructor(0, WlProtocolInterfaces.instance.layerSurface, args));
    } finally {
      // libwayland copied it onto the wire inside the marshal.
      malloc.free(name);
    }
  }
}

class ZwlrLayerSurfaceV1 extends WlProxy {
  ZwlrLayerSurfaceV1(super.conn, super.ptr) {
    addListener(_vtable);
  }

  void Function(int serial, int width, int height)? onConfigure;
  void Function()? onClosed;

  static final _vtable = buildVtable([
    // configure
    evUUU((p, serial, w, h) =>
        proxyByAddress<ZwlrLayerSurfaceV1>(p)?.onConfigure?.call(serial, w, h)),
    // closed
    ev0((p) => proxyByAddress<ZwlrLayerSurfaceV1>(p)?.onClosed?.call()),
  ]);

  /// `set_size` (opcode 0, "uu").
  void setSize(int width, int height) {
    final args = WlArgs(2)
      ..setUint(0, width)
      ..setUint(1, height);
    marshal(0, args);
  }

  /// `set_anchor` (opcode 1, "u").
  void setAnchor(int anchor) => marshal(1, WlArgs(1)..setUint(0, anchor));

  /// `set_exclusive_zone` (opcode 2, "i").
  void setExclusiveZone(int zone) => marshal(2, WlArgs(1)..setInt(0, zone));

  /// `set_keyboard_interactivity` (opcode 4, "u").
  void setKeyboardInteractivity(int mode) =>
      marshal(4, WlArgs(1)..setUint(0, mode));

  /// `ack_configure` (opcode 6, "u").
  void ackConfigure(int serial) => marshal(6, WlArgs(1)..setUint(0, serial));

  /// `destroy` (opcode 7).
  void destroy() => sendDestructor(7);
}

// ---------------------------------------------------------------------------
// relative-pointer-unstable-v1
// ---------------------------------------------------------------------------

class ZwpRelativePointerManagerV1 extends WlProxy {
  ZwpRelativePointerManagerV1(super.conn, super.ptr);

  /// `get_relative_pointer` (opcode 1, "no").
  ZwpRelativePointerV1 getRelativePointer(WlPointerFfi pointer) {
    final args = WlArgs(2)
      ..setNewId(0)
      ..setObject(1, pointer.ptr);
    return ZwpRelativePointerV1(
        conn,
        marshalConstructor(
            1, WlProtocolInterfaces.instance.relativePointer, args));
  }
}

class ZwpRelativePointerV1 extends WlProxy {
  ZwpRelativePointerV1(super.conn, super.ptr) {
    addListener(_vtable);
  }

  /// Accelerated deltas first, then the unaccelerated pair, in surface-local
  /// units.
  void Function(double dx, double dy, double dxUnaccel, double dyUnaccel)?
      onRelativeMotion;

  static final _vtable = buildVtable([
    // relative_motion
    evUUIIII((p, hi, lo, dx, dy, ux, uy) =>
        proxyByAddress<ZwpRelativePointerV1>(p)?.onRelativeMotion?.call(
            wlFixedToDouble(dx),
            wlFixedToDouble(dy),
            wlFixedToDouble(ux),
            wlFixedToDouble(uy))),
  ]);

  /// `destroy` (opcode 0).
  void destroy() => sendDestructor(0);
}

// ---------------------------------------------------------------------------
// pointer-constraints-unstable-v1
// ---------------------------------------------------------------------------

/// `zwp_pointer_constraints_v1.lifetime.persistent`: the lock re-arms whenever
/// the surface regains pointer focus, rather than dying with the first loss.
const int constraintLifetimePersistent = 2;

class ZwpPointerConstraintsV1 extends WlProxy {
  ZwpPointerConstraintsV1(super.conn, super.ptr);

  /// `lock_pointer` (opcode 1, "noo?ou") — over the whole surface.
  ZwpLockedPointerV1 lockPointer(
      WlSurfaceFfi surface, WlPointerFfi pointer, int lifetime) {
    final args = WlArgs(5)
      ..setNewId(0)
      ..setObject(1, surface.ptr)
      ..setObject(2, pointer.ptr)
      ..setObject(3, ffi.nullptr)
      ..setUint(4, lifetime);
    return ZwpLockedPointerV1(conn,
        marshalConstructor(1, WlProtocolInterfaces.instance.lockedPointer, args));
  }
}

class ZwpLockedPointerV1 extends WlProxy {
  ZwpLockedPointerV1(super.conn, super.ptr) {
    addListener(_vtable);
  }

  void Function()? onLocked;
  void Function()? onUnlocked;

  static final _vtable = buildVtable([
    // locked
    ev0((p) => proxyByAddress<ZwpLockedPointerV1>(p)?.onLocked?.call()),
    // unlocked
    ev0((p) => proxyByAddress<ZwpLockedPointerV1>(p)?.onUnlocked?.call()),
  ]);

  /// `destroy` (opcode 0).
  void destroy() => sendDestructor(0);

  /// `set_cursor_position_hint` (opcode 1, "ff") — surface-local; applied on
  /// the next commit of the locked surface, and only as a hint.
  void setCursorPositionHint(double x, double y) {
    final args = WlArgs(2)
      ..setInt(0, wlDoubleToFixed(x))
      ..setInt(1, wlDoubleToFixed(y));
    marshal(1, args);
  }
}

// ---------------------------------------------------------------------------
// xdg-output-unstable-v1
// ---------------------------------------------------------------------------

class ZxdgOutputManagerV1 extends WlProxy {
  ZxdgOutputManagerV1(super.conn, super.ptr);

  /// `get_xdg_output` (opcode 1, "no").
  ZxdgOutputV1 getXdgOutput(WlOutputFfi output) {
    final args = WlArgs(2)
      ..setNewId(0)
      ..setObject(1, output.ptr);
    return ZxdgOutputV1(conn,
        marshalConstructor(1, WlProtocolInterfaces.instance.xdgOutput, args));
  }
}

class ZxdgOutputV1 extends WlProxy {
  ZxdgOutputV1(super.conn, super.ptr) {
    addListener(_vtable);
  }

  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;

  /// Whether a logical size has arrived — until it has, the `wl_output`'s mode
  /// is the only size there is.
  bool hasSize = false;

  void Function()? onDone;

  static ZxdgOutputV1? _of(int p) => proxyByAddress<ZxdgOutputV1>(p);

  static final _vtable = buildVtable([
    // logical_position
    evII((p, x, y) {
      final o = _of(p);
      if (o == null) return;
      o.x = x;
      o.y = y;
    }),
    // logical_size
    evII((p, w, h) {
      final o = _of(p);
      if (o == null) return;
      o.width = w;
      o.height = h;
      o.hasSize = true;
    }),
    // done — deprecated from v3 in favour of wl_output.done, which is sent
    // regardless; either one is a moment the geometry is consistent.
    ev0((p) => _of(p)?.onDone?.call()),
    // name (v2)
    evS((p, name) {}),
    // description (v2)
    evS((p, description) {}),
  ]);

  /// `destroy` (opcode 0).
  void destroy() => sendDestructor(0);
}

/// The registry-bind version for [iface]: what the compositor advertises,
/// capped by what this table was written for *and* by what the libwayland in
/// this process knows — binding past the latter would have the compositor send
/// events libwayland cannot parse.
int boundVersion(int advertised, int cap, ffi.Pointer<WlInterface> iface) {
  var v = advertised < cap ? advertised : cap;
  final known = iface.ref.version;
  if (known > 0 && known < v) v = known;
  return v < 1 ? 1 : v;
}
