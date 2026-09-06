// Getting pixels out of a [CapturedFrame] and into the two things that want
// them: a PNG on disk, and a fixed-size canvas for the recorder's pipe.
//
// The frame's `data` points into the capture session's shm mapping and is only
// valid inside the `onFrame` callback, so everything here copies out
// synchronously and the asynchronous *encode* is handed a Dart list that is ours.
//
// Byte order is read off the frame rather than assumed:
// `capture_session.dart` negotiates one of four `wl_shm` formats and prefers
// XRGB, whose little-endian bytes are B,G,R,X — byte-identical to BGRA. A
// per-pixel swizzle is never needed and must never be added: at 4K a reorder loop
// is tens of milliseconds a frame.

import 'dart:ffi'; // for the Pointer.asTypedList extension
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:graceful_shell/screencast/capture_session.dart';

import 'capture_targets.dart';

/// How one of the negotiated `wl_shm` formats lays its bytes out.
class FrameByteOrder {
  const FrameByteOrder(this.uiFormat, this.ffmpegPixelFormat);

  final ui.PixelFormat uiFormat;

  /// The `-pix_fmt` name for ffmpeg's rawvideo demuxer.
  final String ffmpegPixelFormat;
}

const FrameByteOrder _bgra =
    FrameByteOrder(ui.PixelFormat.bgra8888, 'bgra');
const FrameByteOrder _rgba =
    FrameByteOrder(ui.PixelFormat.rgba8888, 'rgba');

/// The byte order of [shmFormat], defaulting to BGRA — which is what the
/// session negotiates first and what every ordinary run gets.
FrameByteOrder byteOrderFor(int shmFormat) => switch (shmFormat) {
      shmFormatXbgr8888 || shmFormatAbgr8888 => _rgba,
      _ => _bgra,
    };

/// A copy of one frame, out of the shm mapping and safe to keep.
class FrameBytes {
  const FrameBytes({
    required this.bytes,
    required this.width,
    required this.height,
    required this.order,
  });

  /// Tightly packed: the stride is always `width * 4`, whatever the source's
  /// was.
  final Uint8List bytes;
  final int width;
  final int height;
  final FrameByteOrder order;
}

/// Copies [frame] — all of it, or just [crop] in *buffer* pixels — into a fresh,
/// tightly packed list.
///
/// [opaque] forces the alpha byte of every pixel, which the PNG path needs and the
/// recorder does not: the XRGB the session prefers leaves those bytes undefined,
/// so a shot saved without this comes out transparent, while the recorder's
/// `yuv420p` conversion discards alpha anyway.
FrameBytes copyFrame(
  CapturedFrame frame, {
  CaptureRect? crop,
  bool opaque = false,
}) {
  final region = _clampToFrame(crop, frame);
  final width = region.width;
  final height = region.height;
  final out = Uint8List(width * height * 4);
  final source = frame.data.asTypedList(frame.sizeBytes);
  final rowBytes = width * 4;

  if (region.x == 0 && region.width == frame.width && frame.stride == rowBytes) {
    // The common case — a whole, tightly strided frame — is one bulk copy.
    out.setRange(0, out.length, source, region.y * frame.stride);
  } else {
    for (var row = 0; row < height; row++) {
      final start = (region.y + row) * frame.stride + region.x * 4;
      out.setRange(row * rowBytes, (row + 1) * rowBytes, source, start);
    }
  }

  if (opaque) {
    final words = Uint32List.view(out.buffer, out.offsetInBytes, out.length ~/ 4);
    for (var i = 0; i < words.length; i++) {
      words[i] |= 0xFF000000;
    }
  }

  return FrameBytes(
    bytes: out,
    width: width,
    height: height,
    order: byteOrderFor(frame.shmFormat),
  );
}

/// Copies [frame] into [canvas], a fixed [canvasWidth] x [canvasHeight] buffer,
/// clipped and top-left aligned.
///
/// The recorder pins its geometry when it starts, because ffmpeg's rawvideo
/// demuxer is told the frame size once. A window resized while being recorded
/// therefore lands in the canvas it started with: grown, it is cropped; shrunk,
/// the uncovered margin is cleared. A visible compromise, and the right one — the
/// alternative is a recording that ends the moment somebody drags a corner.
void blitIntoCanvas(
  CapturedFrame frame,
  Uint8List canvas,
  int canvasWidth,
  int canvasHeight, {
  CaptureRect? crop,
}) {
  final region = _clampToFrame(crop, frame);
  final width = region.width < canvasWidth ? region.width : canvasWidth;
  final height = region.height < canvasHeight ? region.height : canvasHeight;
  if (width <= 0 || height <= 0) {
    canvas.fillRange(0, canvas.length, 0);
    return;
  }
  // Only when the frame no longer covers the canvas: clearing unconditionally
  // is a second full-size write per frame, at the rate this is called.
  if (width < canvasWidth || height < canvasHeight) {
    canvas.fillRange(0, canvas.length, 0);
  }

  final source = frame.data.asTypedList(frame.sizeBytes);
  final canvasStride = canvasWidth * 4;
  final rowBytes = width * 4;
  for (var row = 0; row < height; row++) {
    final from = (region.y + row) * frame.stride + region.x * 4;
    final to = row * canvasStride;
    canvas.setRange(to, to + rowBytes, source, from);
  }
}

/// Encodes [bytes] as a PNG, or null when the engine refuses them.
///
/// `ImageDescriptor.raw` rather than `decodeImageFromPixels`, the decode path
/// `screencast/preview.dart` documents: the bytes are already in a format
/// `dart:ui` names, so nothing here touches an individual pixel.
Future<Uint8List?> encodePng(FrameBytes bytes) async {
  if (bytes.width <= 0 || bytes.height <= 0) return null;
  ui.Image? image;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes.bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: bytes.width,
      height: bytes.height,
      rowBytes: bytes.width * 4,
      pixelFormat: bytes.order.uiFormat,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    image = frame.image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
  }
}

/// [crop] clipped to [frame], or the whole frame when there is none. Always
/// answers a rectangle inside the buffer, so every caller can index without a
/// bounds check of its own.
CaptureRect _clampToFrame(CaptureRect? crop, CapturedFrame frame) {
  final whole = CaptureRect(0, 0, frame.width, frame.height);
  if (crop == null) return whole;
  final clipped = crop.intersect(whole);
  return clipped.isEmpty ? whole : clipped;
}
