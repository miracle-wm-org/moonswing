import 'dart:ffi' as ffi;

import 'wl_ffi.dart';
import 'wl_interfaces.dart';
import 'wl_proxy.dart';
import 'wl_types.dart';

/// Typed wrappers for the proxies the capture path uses. Requests are methods
/// (with the opcode noted), events dispatch to optional closures — the same
/// shape as `lib/input_trigger/input_trigger_protocol.dart`, over FFI.

// ---------------------------------------------------------------------------
// Core: registry, output, shm.
// ---------------------------------------------------------------------------

class WlRegistryFfi extends WlProxy {
  WlRegistryFfi._(super.conn, super.ptr) {
    addListener(_vtable);
  }

  /// `wl_display.get_registry` (opcode 1).
  factory WlRegistryFfi.of(WlDisplayConnection conn) {
    final w = WlFfi.instance;
    final args = WlArgs(1)..setNewId(0);
    final ptr = w.proxyMarshalArrayFlags(
      conn.display,
      1,
      WlProtocolInterfaces.instance.wlRegistry,
      w.proxyGetVersion(conn.display),
      0,
      args.pointer,
    );
    args.free();
    conn.flush();
    return WlRegistryFfi._(conn, ptr);
  }

  void Function(int name, String interface, int version)? onGlobal;
  void Function(int name)? onGlobalRemove;

  static final _vtable = buildVtable([
    evUSU((p, name, interface, version) =>
        proxyByAddress<WlRegistryFfi>(p)?.onGlobal?.call(name, interface, version)),
    evU((p, name) =>
        proxyByAddress<WlRegistryFfi>(p)?.onGlobalRemove?.call(name)),
  ]);

  /// `wl_registry.bind` (opcode 0) — returns the raw new proxy for the caller
  /// to wrap. The wire form of the untyped new_id is (interface, version,
  /// id), hence the three leading args.
  ffi.Pointer<ffi.Void> bind(
      int name, ffi.Pointer<WlInterface> iface, int version) {
    final args = WlArgs(4)
      ..setUint(0, name)
      ..setStringPtr(1, iface.ref.name)
      ..setUint(2, version)
      ..setNewId(3);
    return marshalConstructor(0, iface, args, version: version);
  }
}

class WlOutputFfi extends WlProxy {
  WlOutputFfi(super.conn, super.ptr, this.globalName) {
    addListener(_vtable);
  }

  /// The registry global name, for hotplug removal.
  final int globalName;

  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
  int refreshMHz = 0;
  String make = '';
  String model = '';

  /// The connector name (`DP-1`, …) from `wl_output.name` (v4) — the identity
  /// used to correlate with the shell's main-connection outputs and GDK
  /// monitors.
  String? connector;

  void Function()? onDone;

  static const _currentModeFlag = 0x1;

  static final _vtable = buildVtable([
    // geometry
    evGeometry((p, x, y, make, model) {
      final o = proxyByAddress<WlOutputFfi>(p);
      if (o == null) return;
      o.x = x;
      o.y = y;
      o.make = make;
      o.model = model;
    }),
    // mode
    evUIII((p, flags, w, h, refresh) {
      final o = proxyByAddress<WlOutputFfi>(p);
      if (o == null || flags & _currentModeFlag == 0) return;
      o.width = w;
      o.height = h;
      o.refreshMHz = refresh;
    }),
    // done
    ev0((p) => proxyByAddress<WlOutputFfi>(p)?.onDone?.call()),
    // scale
    evI((p, scale) {}),
    // name
    evS((p, name) => proxyByAddress<WlOutputFfi>(p)?.connector = name),
    // description
    evS((p, description) {}),
  ]);

  /// `wl_output.release` (opcode 0, since v3).
  void release() {
    if (version >= 3) {
      sendDestructor(0);
    } else {
      destroyLocal();
    }
  }
}

class WlShmFfi extends WlProxy {
  WlShmFfi(super.conn, super.ptr);

  // wl_shm.format events are dropped (no listener): the copy-capture session
  // advertises its own format constraints, which is what matters here.

  /// `wl_shm.create_pool` (opcode 0, "nhi").
  WlShmPoolFfi createPool(int fd, int size) {
    final args = WlArgs(3)
      ..setNewId(0)
      ..setFd(1, fd)
      ..setInt(2, size);
    final ptr = marshalConstructor(
        0, WlProtocolInterfaces.instance.wlShmPool, args);
    return WlShmPoolFfi(conn, ptr);
  }
}

class WlShmPoolFfi extends WlProxy {
  WlShmPoolFfi(super.conn, super.ptr);

  /// `wl_shm_pool.create_buffer` (opcode 0, "niiiiu").
  WlBufferFfi createBuffer(
      int offset, int width, int height, int stride, int format) {
    final args = WlArgs(6)
      ..setNewId(0)
      ..setInt(1, offset)
      ..setInt(2, width)
      ..setInt(3, height)
      ..setInt(4, stride)
      ..setUint(5, format);
    final ptr =
        marshalConstructor(0, WlProtocolInterfaces.instance.wlBuffer, args);
    return WlBufferFfi(conn, ptr);
  }

  /// `wl_shm_pool.destroy` (opcode 1).
  void destroy() => sendDestructor(1);
}

class WlBufferFfi extends WlProxy {
  WlBufferFfi(super.conn, super.ptr);

  // wl_buffer.release is unused by the copy-capture protocol (the frame's
  // ready/failed events govern buffer reuse), so no listener is attached.

  /// `wl_buffer.destroy` (opcode 0).
  void destroy() => sendDestructor(0);
}

// ---------------------------------------------------------------------------
// ext-image-capture-source-v1
// ---------------------------------------------------------------------------

class ExtImageCaptureSourceV1 extends WlProxy {
  ExtImageCaptureSourceV1(super.conn, super.ptr);

  /// `destroy` (opcode 0).
  void destroy() => sendDestructor(0);
}

class ExtOutputImageCaptureSourceManagerV1 extends WlProxy {
  ExtOutputImageCaptureSourceManagerV1(super.conn, super.ptr);

  /// `create_source` (opcode 0, "no").
  ExtImageCaptureSourceV1 createSource(WlOutputFfi output) {
    final args = WlArgs(2)
      ..setNewId(0)
      ..setObject(1, output.ptr);
    final ptr = marshalConstructor(
        0, WlProtocolInterfaces.instance.captureSource, args);
    return ExtImageCaptureSourceV1(conn, ptr);
  }

  /// `destroy` (opcode 1).
  void destroy() => sendDestructor(1);
}

class ExtForeignToplevelImageCaptureSourceManagerV1 extends WlProxy {
  ExtForeignToplevelImageCaptureSourceManagerV1(super.conn, super.ptr);

  /// `create_source` (opcode 0, "no").
  ExtImageCaptureSourceV1 createSource(ExtForeignToplevelHandleV1 toplevel) {
    final args = WlArgs(2)
      ..setNewId(0)
      ..setObject(1, toplevel.ptr);
    final ptr = marshalConstructor(
        0, WlProtocolInterfaces.instance.captureSource, args);
    return ExtImageCaptureSourceV1(conn, ptr);
  }

  /// `destroy` (opcode 1).
  void destroy() => sendDestructor(1);
}

// ---------------------------------------------------------------------------
// ext-image-copy-capture-v1
// ---------------------------------------------------------------------------

class ExtImageCopyCaptureManagerV1 extends WlProxy {
  ExtImageCopyCaptureManagerV1(super.conn, super.ptr);

  static const int optionPaintCursors = 1;

  /// `create_session` (opcode 0, "nou").
  ExtImageCopyCaptureSessionV1 createSession(
      ExtImageCaptureSourceV1 source, int options) {
    final args = WlArgs(3)
      ..setNewId(0)
      ..setObject(1, source.ptr)
      ..setUint(2, options);
    final ptr = marshalConstructor(
        0, WlProtocolInterfaces.instance.copyCaptureSession, args);
    return ExtImageCopyCaptureSessionV1(conn, ptr);
  }

  /// `destroy` (opcode 2).
  void destroy() => sendDestructor(2);
}

class ExtImageCopyCaptureSessionV1 extends WlProxy {
  ExtImageCopyCaptureSessionV1(super.conn, super.ptr) {
    addListener(_vtable);
  }

  void Function(int width, int height)? onBufferSize;
  void Function(int format)? onShmFormat;
  void Function()? onDone;
  void Function()? onStopped;

  static final _vtable = buildVtable([
    // buffer_size
    evUU((p, w, h) =>
        proxyByAddress<ExtImageCopyCaptureSessionV1>(p)?.onBufferSize?.call(w, h)),
    // shm_format
    evU((p, format) =>
        proxyByAddress<ExtImageCopyCaptureSessionV1>(p)?.onShmFormat?.call(format)),
    // dmabuf_device — ignored (v1 is shm-only)
    evP((p, device) {}),
    // dmabuf_format — ignored (v1 is shm-only)
    evUP((p, format, modifiers) {}),
    // done
    ev0((p) => proxyByAddress<ExtImageCopyCaptureSessionV1>(p)?.onDone?.call()),
    // stopped
    ev0((p) =>
        proxyByAddress<ExtImageCopyCaptureSessionV1>(p)?.onStopped?.call()),
  ]);

  /// `create_frame` (opcode 0, "n").
  ExtImageCopyCaptureFrameV1 createFrame() {
    final args = WlArgs(1)..setNewId(0);
    final ptr = marshalConstructor(
        0, WlProtocolInterfaces.instance.copyCaptureFrame, args);
    return ExtImageCopyCaptureFrameV1(conn, ptr);
  }

  /// `destroy` (opcode 1).
  void destroy() => sendDestructor(1);
}

class ExtImageCopyCaptureFrameV1 extends WlProxy {
  ExtImageCopyCaptureFrameV1(super.conn, super.ptr) {
    addListener(_vtable);
  }

  static const int failureUnknown = 0;
  static const int failureBufferConstraints = 1;
  static const int failureStopped = 2;

  void Function(int tvSecHi, int tvSecLo, int tvNsec)? onPresentationTime;
  void Function()? onReady;
  void Function(int reason)? onFailed;

  static final _vtable = buildVtable([
    // transform — the shell's own outputs are never rotated by the capture
    // path in v1; ignored.
    evU((p, transform) {}),
    // damage — full-frame copies in v1; ignored.
    evIIII((p, x, y, w, h) {}),
    // presentation_time
    evUUU((p, hi, lo, nsec) => proxyByAddress<ExtImageCopyCaptureFrameV1>(p)
        ?.onPresentationTime
        ?.call(hi, lo, nsec)),
    // ready
    ev0((p) => proxyByAddress<ExtImageCopyCaptureFrameV1>(p)?.onReady?.call()),
    // failed
    evU((p, reason) =>
        proxyByAddress<ExtImageCopyCaptureFrameV1>(p)?.onFailed?.call(reason)),
  ]);

  /// `destroy` (opcode 0).
  void destroy() => sendDestructor(0);

  /// `attach_buffer` (opcode 1, "o").
  void attachBuffer(WlBufferFfi buffer) {
    final args = WlArgs(1)..setObject(0, buffer.ptr);
    marshal(1, args);
  }

  /// `damage_buffer` (opcode 2, "iiii").
  void damageBuffer(int x, int y, int width, int height) {
    final args = WlArgs(4)
      ..setInt(0, x)
      ..setInt(1, y)
      ..setInt(2, width)
      ..setInt(3, height);
    marshal(2, args);
  }

  /// `capture` (opcode 3).
  void capture() => marshalNoArgs(3);
}

// ---------------------------------------------------------------------------
// ext-foreign-toplevel-list-v1
// ---------------------------------------------------------------------------

class ExtForeignToplevelListV1 extends WlProxy {
  ExtForeignToplevelListV1(super.conn, super.ptr) {
    addListener(_vtable);
  }

  /// A new toplevel handle appeared; its title/app_id/identifier events
  /// follow, committed by `done`.
  void Function(ExtForeignToplevelHandleV1 handle)? onToplevel;
  void Function()? onFinished;

  static final _vtable = buildVtable([
    // toplevel — libwayland created the child proxy from the message's
    // interface metadata; wrap it before its own events dispatch.
    evP((p, child) {
      final list = proxyByAddress<ExtForeignToplevelListV1>(p);
      if (list == null) return;
      final handle = ExtForeignToplevelHandleV1(list.conn, child.cast());
      list.onToplevel?.call(handle);
    }),
    // finished
    ev0((p) => proxyByAddress<ExtForeignToplevelListV1>(p)?.onFinished?.call()),
  ]);

  /// `stop` (opcode 0).
  void stop() => marshalNoArgs(0);

  /// `destroy` (opcode 1).
  void destroy() => sendDestructor(1);
}

class ExtForeignToplevelHandleV1 extends WlProxy {
  ExtForeignToplevelHandleV1(super.conn, super.ptr) {
    addListener(_vtable);
  }

  String title = '';
  String appId = '';
  String identifier = '';

  void Function()? onClosed;
  void Function()? onDone;

  static final _vtable = buildVtable([
    // closed
    ev0((p) => proxyByAddress<ExtForeignToplevelHandleV1>(p)?.onClosed?.call()),
    // done
    ev0((p) => proxyByAddress<ExtForeignToplevelHandleV1>(p)?.onDone?.call()),
    // title
    evS((p, title) =>
        proxyByAddress<ExtForeignToplevelHandleV1>(p)?.title = title),
    // app_id
    evS((p, appId) =>
        proxyByAddress<ExtForeignToplevelHandleV1>(p)?.appId = appId),
    // identifier
    evS((p, identifier) =>
        proxyByAddress<ExtForeignToplevelHandleV1>(p)?.identifier = identifier),
  ]);

  /// `destroy` (opcode 0).
  void destroy() => sendDestructor(0);
}
