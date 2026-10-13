// The input-capture Wayland connection.
//
// Its own connection rather than `CaptureHost`'s, for the reason that makes the
// feature work at all: the surfaces it creates must be the ones the compositor
// sends this seat's input to, and pointer focus, keyboard focus and pointer
// locks are all per-client. A connection that also carried screen capture would
// be a client the compositor had to reason about twice.
//
// What it binds, and why each is required:
// - `wl_compositor`, `wl_shm`, `zwlr_layer_shell_v1` — surfaces of its own: a
//   one-pixel strip along every edge a barrier is on, and a transparent
//   full-output surface while input is being captured.
// - `wl_seat` — the pointer and keyboard those surfaces receive.
// - `zwp_relative_pointer_manager_v1` — motion as deltas. A barrier is crossed by
//   pushing *against* the edge, which moves the clamped cursor nowhere, and once
//   captured the cursor is locked and moves nowhere at all.
// - `zwp_pointer_constraints_v1` — the lock that keeps the cursor still while
//   its motion is going to the other machine.
// - `zxdg_output_manager_v1` (optional) — the logical size of each output; the
//   mode divided by the integer scale is the fallback.
//
// Flutter-free, like everything else under the consent dialog.

import '../native/libc.dart';
import '../wayland_ffi/wl_ffi.dart';
import '../wayland_ffi/wl_input_protocols.dart';
import '../wayland_ffi/wl_interfaces.dart';
import '../wayland_ffi/wl_protocols.dart';
import 'barriers.dart';

/// `wl_shm.format.argb8888`.
const int _shmFormatArgb8888 = 0;

/// One `wl_output` and, where the compositor has xdg-output, its logical box.
class InputCaptureOutput {
  InputCaptureOutput(this.wl);

  final WlOutputFfi wl;
  ZxdgOutputV1? xdg;

  /// The output as a zone, in logical coordinates.
  CaptureZone get zone {
    final logical = xdg;
    if (logical != null && logical.hasSize) {
      return CaptureZone(
        x: logical.x,
        y: logical.y,
        width: logical.width,
        height: logical.height,
        connector: wl.connector,
      );
    }
    final scale = wl.scale < 1 ? 1 : wl.scale;
    return CaptureZone(
      x: wl.x,
      y: wl.y,
      width: wl.width ~/ scale,
      height: wl.height ~/ scale,
      connector: wl.connector,
    );
  }
}

class InputCaptureConnection {
  InputCaptureConnection._(this.conn);

  /// Connects and runs the start-up round trips. Null when there is no display
  /// to reach or no libwayland to load.
  static InputCaptureConnection? connect({bool attachToGlibLoop = true}) {
    final display = WlDisplayConnection.connect();
    if (display == null) return null;
    final c = InputCaptureConnection._(display);
    c._init();
    if (attachToGlibLoop) display.attachToGlibLoop();
    return c;
  }

  final WlDisplayConnection conn;

  late final WlRegistryFfi _registry;
  WlCompositorFfi? compositor;
  WlShmFfi? shm;
  ZwlrLayerShellV1? layerShell;
  WlSeatFfi? seat;
  ZwpRelativePointerManagerV1? relativePointerManager;
  ZwpPointerConstraintsV1? pointerConstraints;
  ZxdgOutputManagerV1? _xdgOutputManager;

  final List<InputCaptureOutput> outputs = [];

  WlPointerFfi? pointer;
  WlKeyboardFfi? keyboard;

  /// A keymap that arrived before anything took [keyboard] over, as
  /// (format, fd, size); the taker owns the fd.
  (int, int, int)? pendingKeymap;
  ZwpRelativePointerV1? relativePointer;

  /// An output came, went, or changed geometry.
  void Function()? onOutputsChanged;

  /// The seat gained or lost its pointer or keyboard; the engine re-attaches
  /// its handlers to whatever is now there.
  void Function()? onSeatChanged;

  /// The compositor connection died.
  void Function()? onDied;

  /// What is missing, in words, or null when everything the feature needs is
  /// bound. A seat without a pointer yet is not "missing": a mouse can be
  /// plugged in later.
  String? get missing {
    final absent = [
      if (compositor == null) 'wl_compositor',
      if (shm == null) 'wl_shm',
      if (layerShell == null) 'zwlr_layer_shell_v1',
      if (seat == null) 'wl_seat',
      if (relativePointerManager == null) 'zwp_relative_pointer_manager_v1',
      if (pointerConstraints == null) 'zwp_pointer_constraints_v1',
    ];
    return absent.isEmpty ? null : absent.join(', ');
  }

  void _init() {
    conn.onError = () => onDied?.call();
    final ifaces = WlProtocolInterfaces.instance;
    _registry = WlRegistryFfi.of(conn);
    _registry.onGlobal = (name, interface, version) {
      switch (interface) {
        case 'wl_compositor':
          compositor ??= WlCompositorFfi(
              conn,
              _registry.bind(name, ifaces.wlCompositor,
                  boundVersion(version, 4, ifaces.wlCompositor)));
        case 'wl_shm':
          shm ??= WlShmFfi(conn, _registry.bind(name, ifaces.wlShm, 1));
        case 'zwlr_layer_shell_v1':
          layerShell ??= ZwlrLayerShellV1(
              conn,
              _registry.bind(name, ifaces.layerShell,
                  boundVersion(version, 4, ifaces.layerShell)));
        case 'wl_seat':
          // The first seat only: the portal has no notion of several, and
          // neither has any compositor the shell runs on.
          if (seat != null) return;
          final s = WlSeatFfi(
              conn,
              _registry.bind(name, ifaces.wlSeat,
                  boundVersion(version, WlSeatFfi.maxVersion, ifaces.wlSeat)));
          s.onCapabilities = _onCapabilities;
          seat = s;
        case 'zwp_relative_pointer_manager_v1':
          relativePointerManager ??= ZwpRelativePointerManagerV1(
              conn, _registry.bind(name, ifaces.relativePointerManager, 1));
          _ensureRelativePointer();
        case 'zwp_pointer_constraints_v1':
          pointerConstraints ??= ZwpPointerConstraintsV1(
              conn, _registry.bind(name, ifaces.pointerConstraints, 1));
        case 'zxdg_output_manager_v1':
          if (_xdgOutputManager != null) return;
          _xdgOutputManager = ZxdgOutputManagerV1(
              conn,
              _registry.bind(name, ifaces.xdgOutputManager,
                  boundVersion(version, 3, ifaces.xdgOutputManager)));
          for (final output in outputs) {
            _attachXdg(output);
          }
        case 'wl_output':
          final wl = WlOutputFfi(conn,
              _registry.bind(name, ifaces.wlOutput, version < 4 ? version : 4),
              name);
          final output = InputCaptureOutput(wl);
          wl.onDone = () => onOutputsChanged?.call();
          outputs.add(output);
          _attachXdg(output);
      }
    };
    _registry.onGlobalRemove = (name) {
      final index = outputs.indexWhere((o) => o.wl.globalName == name);
      if (index == -1) return;
      final output = outputs.removeAt(index);
      output.xdg?.destroy();
      output.wl.release();
      onOutputsChanged?.call();
    };

    conn.roundtrip(); // globals; binds happen during dispatch
    conn.roundtrip(); // output geometry, seat capabilities
  }

  void _attachXdg(InputCaptureOutput output) {
    final manager = _xdgOutputManager;
    if (manager == null || output.xdg != null) return;
    final xdg = manager.getXdgOutput(output.wl);
    // From v3 the compositor ends a change with `wl_output.done` alone, which
    // already notifies; this covers the older ones that send only this.
    xdg.onDone = () => onOutputsChanged?.call();
    output.xdg = xdg;
  }

  void _onCapabilities(int caps) {
    final hasPointer = caps & WlSeatFfi.capPointer != 0;
    final hasKeyboard = caps & WlSeatFfi.capKeyboard != 0;
    var changed = false;
    if (hasPointer && pointer == null) {
      pointer = seat!.getPointer();
      _ensureRelativePointer();
      changed = true;
    } else if (!hasPointer && pointer != null) {
      relativePointer?.destroy();
      relativePointer = null;
      pointer!.release();
      pointer = null;
      changed = true;
    }
    if (hasKeyboard && keyboard == null) {
      final k = seat!.getKeyboard();
      // Held until somebody takes the keyboard over: the keymap is sent once,
      // as the keyboard is made, and may arrive inside a start-up round trip.
      k.onKeymap = (format, fd, size) {
        if (pendingKeymap case (_, final old, _)) closeFd(old);
        pendingKeymap = (format, fd, size);
      };
      keyboard = k;
      changed = true;
    } else if (!hasKeyboard && keyboard != null) {
      keyboard!.release();
      keyboard = null;
      changed = true;
    }
    if (changed) onSeatChanged?.call();
  }

  void _ensureRelativePointer() {
    final manager = relativePointerManager;
    final p = pointer;
    if (manager == null || p == null || relativePointer != null) return;
    relativePointer = manager.getRelativePointer(p);
  }

  /// A transparent `width`×`height` ARGB buffer — what maps a surface that
  /// should be seen by input and by nobody's eyes. Zero-filled memory is
  /// already transparent, so nothing is written.
  WlBufferFfi? transparentBuffer(int width, int height) {
    final s = shm;
    if (s == null || width <= 0 || height <= 0) return null;
    final stride = width * 4;
    final size = stride * height;
    final fd = memfdCreate('moonswing-input-capture');
    if (fd < 0) return null;
    try {
      if (!ftruncateFd(fd, size)) return null;
      final pool = s.createPool(fd, size);
      final buffer =
          pool.createBuffer(0, width, height, stride, _shmFormatArgb8888);
      // A buffer outlives the pool it was cut from.
      pool.destroy();
      return buffer;
    } finally {
      // libwayland duplicated it onto the wire inside `create_pool`.
      closeFd(fd);
    }
  }

  InputCaptureOutput? outputFor(CaptureZone zone) {
    for (final output in outputs) {
      if (output.zone == zone) return output;
    }
    return null;
  }

  void dispose() {
    onDied = null;
    conn.disconnect();
  }
}
