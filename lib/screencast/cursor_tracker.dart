import 'dart:ffi';
import 'dart:typed_data';

import '../wayland_ffi/wl_protocols.dart';
import 'capture_connection.dart';
import 'capture_session.dart';
import 'screencast_log.dart';

/// The cursor as it falls on one capture source, for the ScreenCast portal's
/// metadata cursor mode: the stream carries the frames with no cursor in them,
/// and this beside each one — where the pointer is and what it looks like — so
/// the application draws (or deliberately does not draw) the cursor itself.
///
/// [image] is ARGB8888 (`wl_shm` byte order: B, G, R, A), [imageWidth] ×
/// [imageHeight], tightly packed; null until the compositor has sent one.
class CursorState {
  const CursorState({
    required this.visible,
    required this.x,
    required this.y,
    required this.hotspotX,
    required this.hotspotY,
    required this.image,
    required this.imageWidth,
    required this.imageHeight,
  });

  static const hidden = CursorState(
      visible: false,
      x: 0,
      y: 0,
      hotspotX: 0,
      hotspotY: 0,
      image: null,
      imageWidth: 0,
      imageHeight: 0);

  /// False while the pointer is off the source (another output, outside the
  /// window) or unusable; the consumer then draws no cursor.
  final bool visible;

  /// Position of the hotspot, in the source's buffer coordinates.
  final int x;
  final int y;
  final int hotspotX;
  final int hotspotY;
  final Uint8List? image;
  final int imageWidth;
  final int imageHeight;
}

/// One `ext_image_copy_capture_cursor_session_v1` and the copy-capture session
/// its image comes through, folded into one [CursorState].
///
/// Position and visibility arrive as events; the image is a capture the
/// compositor holds until the shape changes, so a pointer moving over a still
/// screen is a stream of `position` events and nothing else — which is why the
/// stream has to be told about it ([onChanged]) rather than finding out from
/// the next frame, which may never come.
class CursorTracker {
  CursorTracker.forOutput(this._connection, WlOutputFfi output)
      : _output = output,
        _toplevel = null;

  CursorTracker.forToplevel(
      this._connection, ExtForeignToplevelHandleV1 toplevel)
      : _output = null,
        _toplevel = toplevel;

  final CaptureConnection _connection;
  final WlOutputFfi? _output;
  final ExtForeignToplevelHandleV1? _toplevel;

  /// Fired whenever [state] changed: a move, entering or leaving the source, a
  /// new shape.
  void Function()? onChanged;

  ExtImageCaptureSourceV1? _source;
  ExtImageCopyCaptureCursorSessionV1? _session;
  CaptureSession? _image;

  bool _inside = false;
  int _x = 0;
  int _y = 0;
  int _hotspotX = 0;
  int _hotspotY = 0;
  Uint8List? _pixels;
  int _imageWidth = 0;
  int _imageHeight = 0;
  CursorState _state = CursorState.hidden;
  bool _disposed = false;

  CursorState get state => _state;

  /// Starts tracking. False when the connection has no pointer to name the
  /// seat by — the caller then streams without a cursor at all.
  bool start() {
    final pointer = _connection.pointer;
    if (pointer == null || _session != null) return false;
    final source = createCaptureSource(_connection,
        output: _output, toplevel: _toplevel);
    _source = source;
    final session = _connection.copyCaptureManager!
        .createPointerCursorSession(source, pointer);
    _session = session;
    session.onEnter = () {
      _inside = true;
      _publish();
    };
    session.onLeave = () {
      _inside = false;
      _publish();
    };
    session.onPosition = (x, y) {
      _x = x;
      _y = y;
      _publish();
    };
    // Sent ahead of each image's `ready`, so it lands with the shape it
    // belongs to.
    session.onHotspot = (x, y) {
      _hotspotX = x;
      _hotspotY = y;
    };

    final image = CaptureSession.forCursor(_connection, session);
    _image = image;
    image.onFrame = (frame) {
      final size = frame.width * frame.height * 4;
      final pixels = Uint8List(size);
      if (frame.stride == frame.width * 4) {
        pixels.setAll(0, frame.data.asTypedList(size));
      } else {
        for (var row = 0; row < frame.height; row++) {
          pixels.setAll(
              row * frame.width * 4,
              (frame.data + row * frame.stride)
                  .asTypedList(frame.width * 4));
        }
      }
      _pixels = pixels;
      _imageWidth = frame.width;
      _imageHeight = frame.height;
      _publish();
    };
    // A cursor image that cannot be had leaves the position, which is most of
    // what a consumer wants; it is not a reason to end the cast.
    image.onStopped = (reason) =>
        screencastLog('cursor image capture ended: $reason');
    image.start();
    return true;
  }

  void _publish() {
    if (_disposed) return;
    _state = CursorState(
      visible: _inside,
      x: _x,
      y: _y,
      hotspotX: _hotspotX,
      hotspotY: _hotspotY,
      image: _pixels,
      imageWidth: _imageWidth,
      imageHeight: _imageHeight,
    );
    onChanged?.call();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onChanged = null;
    // The image session first: it was handed out by the cursor session.
    _image?.dispose();
    _image = null;
    _session?.destroy();
    _session = null;
    _source?.destroy();
    _source = null;
  }
}
