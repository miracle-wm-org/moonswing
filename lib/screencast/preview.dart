import 'dart:async';
import 'dart:ffi'; // for the Pointer.asTypedList extension
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'capture_session.dart';

/// A source of preview frames, abstracted so widget tests can feed the picker
/// synthetic images without touching Wayland.
abstract class PreviewFrames {
  /// Starts producing frames into [onFrame] and returns a stop function.
  void Function() subscribe(void Function(CapturedFrame frame) onFrame);
}

/// The real implementation: a throttled [CaptureSession] on one source.
class CaptureSessionPreviewFrames implements PreviewFrames {
  CaptureSessionPreviewFrames(this._build);

  /// Builds the session. Called on subscribe, so a preview that scrolls out of
  /// existence stops capturing.
  final CaptureSession Function() _build;

  @override
  void Function() subscribe(void Function(CapturedFrame frame) onFrame) {
    final session = _build()..onFrame = onFrame;
    session.start();
    return session.dispose;
  }
}

/// Renders live frames from a [PreviewFrames].
///
/// The decode path is deliberately `ImmutableBuffer` + `ImageDescriptor.raw` with
/// a BGRA pixel format rather than `decodeImageFromPixels` with a per-pixel
/// reorder loop: the capture buffers are already XRGB8888/ARGB8888, which is
/// byte-identical to BGRA on little-endian, so the only work per frame is one
/// bulk copy out of the shm mapping.
class CapturePreview extends StatefulWidget {
  const CapturePreview({
    super.key,
    required this.frames,
    required this.placeholderColor,
    this.fit = BoxFit.cover,
  });

  final PreviewFrames frames;
  final Color placeholderColor;
  final BoxFit fit;

  @override
  State<CapturePreview> createState() => _CapturePreviewState();
}

class _CapturePreviewState extends State<CapturePreview> {
  void Function()? _unsubscribe;
  ui.Image? _image;
  Uint8List? _scratch;
  bool _decoding = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _unsubscribe = widget.frames.subscribe(_onFrame);
  }

  @override
  void didUpdateWidget(CapturePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frames != widget.frames) {
      _unsubscribe?.call();
      _unsubscribe = widget.frames.subscribe(_onFrame);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _unsubscribe?.call();
    _unsubscribe = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  void _onFrame(CapturedFrame frame) {
    // One decode at a time: at preview rates a backlog would only grow, and
    // the newest frame is the only interesting one.
    if (_decoding || _disposed) return;
    _decoding = true;

    final size = frame.sizeBytes;
    var scratch = _scratch;
    if (scratch == null || scratch.length != size) {
      scratch = Uint8List(size);
      _scratch = scratch;
    }
    scratch.setAll(0, frame.data.asTypedList(size));

    // XRGB has undefined alpha bytes, which would render the preview
    // transparent — force them opaque. ARGB carries real alpha, but the
    // compositor's captured frames are opaque anyway.
    final words = Uint32List.view(scratch.buffer);
    for (var i = 0; i < words.length; i++) {
      words[i] |= 0xFF000000;
    }

    _decode(scratch, frame.width, frame.height, frame.stride);
  }

  Future<void> _decode(
      Uint8List bytes, int width, int height, int stride) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        rowBytes: stride,
        pixelFormat: ui.PixelFormat.bgra8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      if (_disposed || !mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = frame.image;
      });
    } catch (_) {
      // A malformed frame just leaves the previous image on screen.
    } finally {
      _decoding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return ColoredBox(color: widget.placeholderColor);
    }
    return FittedBox(
      fit: widget.fit,
      clipBehavior: Clip.hardEdge,
      child: RawImage(
        image: image,
        width: image.width.toDouble(),
        height: image.height.toDouble(),
        filterQuality: FilterQuality.low,
      ),
    );
  }
}
