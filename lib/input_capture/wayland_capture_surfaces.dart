// [CaptureSurfaces] over the input-capture Wayland connection: the strips along
// barrier edges, the full-output capture surface with its pointer lock, and the
// seat events that feed [CaptureController].
//
// Two compositor behaviours this leans on, both standard:
// - **Layer surfaces with an exclusive zone of -1 ignore everybody else's
//   exclusive zones**, so a strip runs the full length of its edge even under a
//   panel, and the capture surface covers the whole output.
// - **`keyboard_interactivity = exclusive` on the overlay layer takes the
//   keyboard** for as long as the surface is mapped — on Mir that is a grabbing
//   surface, exactly what "every key goes to the other machine" needs, and the
//   same reason the window switcher hands its grab back before it switches.
//
// The strips are one transparent pixel wide and take input, which is the
// feature's one visible cost: while a session is armed, a click on the very
// last pixel of a barrier edge lands on the strip instead of whatever is under
// it. There is no way round that without the compositor's help — the shell
// learns where the pointer is only from surfaces of its own — so strips exist
// only while some session is enabled, and only on edges a barrier is on.
//
// Flutter-free.

import '../native/libc.dart';
import '../wayland_ffi/wl_input_protocols.dart';
import '../wayland_ffi/wl_protocols.dart';
import 'barriers.dart';
import 'capture_controller.dart';
import 'input_capture_connection.dart';
import 'input_capture_log.dart';

const String _stripNamespace = 'moonswing-input-capture-barrier';
const String _captureNamespace = 'moonswing-input-capture';

/// One layer surface of ours, mapped with a transparent buffer of whatever size
/// the compositor configures.
class _LayerSurface {
  _LayerSurface(
    this._connection, {
    required InputCaptureOutput output,
    required int anchor,
    required int width,
    required int height,
    required int keyboard,
    required String namespace,
    required this.onClosed,
  }) {
    surface = _connection.compositor!.createSurface();
    layer = _connection.layerShell!
        .getLayerSurface(surface, output.wl, layerOverlay, namespace);
    layer
      ..setSize(width, height)
      ..setAnchor(anchor)
      ..setExclusiveZone(-1)
      ..setKeyboardInteractivity(keyboard);
    layer.onConfigure = _onConfigure;
    layer.onClosed = () {
      if (_destroyed) return;
      onClosed();
    };
    // The initial commit, with no buffer: asks for the first configure.
    surface.commit();
  }

  final InputCaptureConnection _connection;
  late final WlSurfaceFfi surface;
  late final ZwlrLayerSurfaceV1 layer;
  final void Function() onClosed;

  final List<WlBufferFfi> _buffers = [];
  int width = 0;
  int height = 0;
  bool _destroyed = false;

  void _onConfigure(int serial, int w, int h) {
    if (_destroyed) return;
    layer.ackConfigure(serial);
    if (w != width || h != height) {
      final buffer = _connection.transparentBuffer(w, h);
      if (buffer != null) {
        width = w;
        height = h;
        _buffers.add(buffer);
        surface.attach(buffer);
        surface.damageBuffer(0, 0, w, h);
      }
    }
    surface.commit();
  }

  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    layer.destroy();
    surface.destroy();
    for (final buffer in _buffers) {
      buffer.destroy();
    }
    _buffers.clear();
  }
}

class WaylandCaptureSurfaces implements CaptureSurfaces {
  WaylandCaptureSurfaces(this._connection) {
    _connection.onSeatChanged = _attachSeat;
    _connection.onOutputsChanged = _onOutputsChanged;
    _attachSeat();
  }

  final InputCaptureConnection _connection;

  /// Set right after construction; the controller needs this to exist first.
  /// Every handler below reaches it through a closure rather than a tear-off,
  /// because a tear-off would read it during construction.
  CaptureController get controller => _controller!;
  set controller(CaptureController value) {
    _controller = value;
    _takePendingKeymap();
  }

  CaptureController? _controller;

  final Map<StripKey, _LayerSurface> _strips = {};

  /// While capturing: the surface on the output whose barrier was crossed,
  /// which takes the keyboard and the pointer lock, and one more on every
  /// other output. See [beginCapture].
  _LayerSurface? _capture;
  final List<_LayerSurface> _covers = [];
  CaptureZone? _captureZone;
  ZwpLockedPointerV1? _lock;

  bool _isCaptureSurface(WlSurfaceFfi? surface) =>
      surface != null &&
      (identical(surface, _capture?.surface) ||
          _covers.any((c) => identical(c.surface, surface)));

  /// Which of our surfaces has the pointer, if any.
  WlSurfaceFfi? _pointerFocus;

  /// The zones the outputs currently make.
  List<CaptureZone> currentZones() =>
      zonesFrom(_connection.outputs.map((o) => o.zone));

  void _onOutputsChanged() => controller.updateZones(currentZones());

  // ---------------------------------------------------------------------------
  // CaptureSurfaces
  // ---------------------------------------------------------------------------

  @override
  void showStrips(Set<StripKey> strips) {
    for (final key in _strips.keys.toList()) {
      if (!strips.contains(key)) {
        final strip = _strips.remove(key)!;
        if (identical(_pointerFocus, strip.surface)) {
          _pointerFocus = null;
          controller.pointerLeftStrip();
        }
        strip.destroy();
      }
    }
    for (final key in strips) {
      if (_strips.containsKey(key)) continue;
      final output = _connection.outputFor(key.zone);
      if (output == null) continue;
      final vertical =
          key.edge == BarrierEdge.left || key.edge == BarrierEdge.right;
      final anchor = switch (key.edge) {
        BarrierEdge.left => anchorLeft | anchorTop | anchorBottom,
        BarrierEdge.right => anchorRight | anchorTop | anchorBottom,
        BarrierEdge.top => anchorTop | anchorLeft | anchorRight,
        BarrierEdge.bottom => anchorBottom | anchorLeft | anchorRight,
      };
      _strips[key] = _LayerSurface(
        _connection,
        output: output,
        anchor: anchor,
        width: vertical ? 1 : 0,
        height: vertical ? 0 : 1,
        keyboard: keyboardInteractivityNone,
        namespace: _stripNamespace,
        onClosed: () {
          // The output went away; the zone change that follows rebuilds the
          // set, and this one must not be destroyed twice meanwhile.
          final strip = _strips.remove(key);
          strip?.destroy();
        },
      );
    }
    _connection.conn.flush();
  }

  /// Every output is covered, not only the one whose barrier was crossed.
  ///
  /// The pointer lock is what should keep the cursor on that one output, and
  /// it is not to be relied on: a compositor may grant locks only to the
  /// surface with keyboard focus as it understands it (sway constrains views,
  /// never layer surfaces, and answers this one's lock with silence). An
  /// unlocked cursor still moves, and relative motion is only sent to the
  /// client whose surface it is over — so a cursor that drifted onto a second
  /// monitor would silently stop moving the other machine's. With a surface
  /// under it wherever it goes, it never leaves this client.
  ///
  /// Only the crossed output's surface takes the keyboard: two mapped surfaces
  /// asking for exclusive focus is a state the protocol gives no answer for.
  @override
  void beginCapture(CaptureZone zone) {
    endCapture();
    final output = _connection.outputFor(zone);
    final pointer = _connection.pointer;
    if (output == null || pointer == null) {
      controller.captureLost();
      return;
    }
    final capture = _coverOutput(output, keyboard: true);
    _capture = capture;
    _captureZone = zone;
    for (final other in _connection.outputs) {
      if (identical(other, output)) continue;
      _covers.add(_coverOutput(other, keyboard: false));
    }
    // Persistent, so a moment's loss of focus (a notification surfacing over
    // the capture surface) re-locks rather than leaving the cursor free.
    final lock = _connection.pointerConstraints!
        .lockPointer(capture.surface, pointer, constraintLifetimePersistent);
    lock.onLocked = () => inputCaptureLog('pointer locked');
    _lock = lock;
    _connection.conn.flush();
  }

  _LayerSurface _coverOutput(InputCaptureOutput output,
          {required bool keyboard}) =>
      _LayerSurface(
        _connection,
        output: output,
        anchor: anchorTop | anchorBottom | anchorLeft | anchorRight,
        width: 0,
        height: 0,
        keyboard: keyboard
            ? keyboardInteractivityExclusive
            : keyboardInteractivityNone,
        namespace: _captureNamespace,
        // Only the crossed output going away ends the capture; another one
        // going away is a zone change, which ends it anyway.
        onClosed: keyboard ? () => controller.captureLost() : () {},
      );

  @override
  void endCapture({double? hintX, double? hintY}) {
    final capture = _capture;
    final zone = _captureZone;
    final lock = _lock;
    _capture = null;
    _captureZone = null;
    _lock = null;
    if (capture == null) return;
    if (lock != null) {
      if (hintX != null && hintY != null && zone != null) {
        // Surface-local, and inside the surface: a hint outside it is
        // meaningless to the compositor.
        final x = (hintX - zone.x).clamp(0.0, zone.width - 1.0);
        final y = (hintY - zone.y).clamp(0.0, zone.height - 1.0);
        lock.setCursorPositionHint(x, y);
        capture.surface.commit();
      }
      lock.destroy();
    }
    if (_isCaptureSurface(_pointerFocus)) _pointerFocus = null;
    capture.destroy();
    for (final cover in _covers) {
      cover.destroy();
    }
    _covers.clear();
    _connection.conn.flush();
  }

  // ---------------------------------------------------------------------------
  // Seat events.
  // ---------------------------------------------------------------------------

  StripKey? _stripOf(WlSurfaceFfi? surface) {
    if (surface == null) return null;
    for (final entry in _strips.entries) {
      if (identical(entry.value.surface, surface)) return entry.key;
    }
    return null;
  }

  /// A strip's surface-local position in global coordinates.
  (double, double) _globalOn(StripKey strip, double x, double y) {
    final zone = strip.zone;
    return switch (strip.edge) {
      BarrierEdge.left || BarrierEdge.top => (zone.x + x, zone.y + y),
      BarrierEdge.right => (zone.right - 1 + x, zone.y + y),
      BarrierEdge.bottom => (zone.x + x, zone.bottom - 1 + y),
    };
  }

  void _attachSeat() {
    final pointer = _connection.pointer;
    if (pointer != null) {
      pointer.onEnter = (serial, surface, x, y) {
        _pointerFocus = surface;
        if (_isCaptureSurface(surface)) {
          // The cursor stays where it hit the barrier, invisible: it is on the
          // other machine now.
          pointer.hideCursor(serial);
          _connection.conn.flush();
          return;
        }
        final strip = _stripOf(surface);
        if (strip == null) return;
        final (gx, gy) = _globalOn(strip, x, y);
        controller.pointerOnStrip(strip, gx, gy);
      };
      pointer.onLeave = (serial, surface) {
        if (_stripOf(surface) != null) controller.pointerLeftStrip();
        if (identical(_pointerFocus, surface)) _pointerFocus = null;
      };
      pointer.onMotion = (time, x, y) {
        final strip = _stripOf(_pointerFocus);
        if (strip == null) return;
        final (gx, gy) = _globalOn(strip, x, y);
        controller.pointerOnStrip(strip, gx, gy);
      };
      pointer.onButton = (serial, time, button, state) =>
          controller.button(button, state == wlStatePressed);
      pointer.onAxis = (time, axis, value) {
        controller.axis(axis, value);
        // Before v5 there is no frame to wait for.
        if (pointer.version < 5) controller.frame();
      };
      pointer.onAxisDiscrete = (axis, discrete) =>
          controller.axisDiscrete(axis, discrete);
      pointer.onAxisValue120 =
          (axis, value) => controller.axisValue120(axis, value);
      pointer.onAxisStop = (time, axis) => controller.axisStop(axis);
      pointer.onFrame = () => controller.frame();
    }
    _connection.relativePointer?.onRelativeMotion =
        (dx, dy, ux, uy) => controller.relativeMotion(dx, dy);

    final keyboard = _connection.keyboard;
    if (keyboard != null) {
      void onKeymap(int format, int fd, int size) {
        if (format != wlKeymapFormatXkbV1) {
          // Not a keymap libei can describe; the receiver will guess.
          controller.keymap(-1, 0);
          closeFd(fd);
          return;
        }
        controller.keymap(fd, size);
      }

      keyboard.onKeymap = onKeymap;
      _takePendingKeymap();
      keyboard.onEnter = (serial, surface, keys) {
        if (identical(surface, _capture?.surface)) {
          controller.keyboardEnter(keys);
        }
      };
      keyboard.onLeave = (serial, surface) {
        // Only the capture surface ever takes the keyboard; a leave from one
        // already destroyed (capture ended first) is no news.
        if (surface != null && identical(surface, _capture?.surface)) {
          controller.keyboardLeave();
        }
      };
      keyboard.onKey = (serial, time, key, state) =>
          controller.key(key, state == wlStatePressed);
      keyboard.onModifiers = (depressed, latched, locked, group) =>
          controller.modifiers(depressed, latched, locked, group);
    }
  }

  /// Hands the controller a keymap that arrived before the keyboard's handler
  /// was attached — or before there was a controller to give it to.
  void _takePendingKeymap() {
    final keyboard = _connection.keyboard;
    if (_controller == null || keyboard == null) return;
    if (_connection.pendingKeymap case (final format, final fd, final size)) {
      _connection.pendingKeymap = null;
      keyboard.onKeymap?.call(format, fd, size);
    }
  }

  void dispose() {
    endCapture();
    for (final strip in _strips.values) {
      strip.destroy();
    }
    _strips.clear();
  }
}
