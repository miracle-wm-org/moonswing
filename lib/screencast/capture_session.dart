import 'dart:async';
import 'dart:ffi' as ffi;

import '../native/libc.dart' as libc;
import '../wayland_ffi/wl_protocols.dart';
import 'capture_connection.dart';
import 'screencast_log.dart';

/// `wl_shm.format` codes the session can negotiate. 0/1 are the enum values;
/// the rest are drm fourccs (wl_shm reuses them beyond the first two).
const int shmFormatArgb8888 = 0;
const int shmFormatXrgb8888 = 1;
const int shmFormatXbgr8888 = 0x34324258; // 'XB24'
const int shmFormatAbgr8888 = 0x34324241; // 'AB24'

/// Preference order: opaque BGRx first (no alpha surprises downstream), then
/// the alpha and byte-swapped variants.
const List<int> _formatPreference = [
  shmFormatXrgb8888,
  shmFormatArgb8888,
  shmFormatXbgr8888,
  shmFormatAbgr8888,
];

/// One captured frame. [data] points into the session's mapped shm buffer and
/// is only valid inside the `onFrame` callback — the next capture overwrites
/// it. Consumers copy out (PipeWire: memcpy into a pw_buffer; previews: into
/// a reusable Uint8List).
class CapturedFrame {
  const CapturedFrame({
    required this.data,
    required this.width,
    required this.height,
    required this.stride,
    required this.shmFormat,
    this.presentationTimeNs,
  });

  final ffi.Pointer<ffi.Uint8> data;
  final int width;
  final int height;
  final int stride;
  final int shmFormat;
  final int? presentationTimeNs;

  int get sizeBytes => stride * height;
}

/// A continuous image-copy-capture session on one source (an output or a foreign
/// toplevel).
///
/// Lifecycle: [start] → constraints batch (`shm_format`*, `buffer_size`, `done`)
/// → shm buffer alloc → frame loop (`create_frame` → `attach_buffer` → full
/// `damage_buffer` → `capture` → `ready`/`failed`). On `ready` the frame is
/// delivered and the next starts — immediately in streaming mode, or after
/// [minFrameInterval] in preview mode. On constraint changes the buffer is
/// reallocated and [onSizeChanged] fires so PipeWire can renegotiate.
class CaptureSession {
  CaptureSession.forOutput(
    this._connection,
    WlOutputFfi output, {
    this.paintCursors = true,
    this.minFrameInterval,
  })  : _output = output,
        _toplevel = null;

  CaptureSession.forToplevel(
    this._connection,
    ExtForeignToplevelHandleV1 toplevel, {
    this.paintCursors = true,
    this.minFrameInterval,
  })  : _output = null,
        _toplevel = toplevel;

  final CaptureConnection _connection;
  final WlOutputFfi? _output;
  final ExtForeignToplevelHandleV1? _toplevel;
  final bool paintCursors;

  /// Preview throttle; null = streaming (re-capture immediately on ready).
  final Duration? minFrameInterval;

  /// Delivered on every ready frame. The pointer is valid only inside the
  /// callback.
  void Function(CapturedFrame frame)? onFrame;

  /// Fired after a constraint change forced a buffer reallocation (window
  /// resized). The next frames have the new size.
  void Function(int width, int height)? onSizeChanged;

  /// Fired once when the session is over: source gone, user revoked, the
  /// connection died, or repeated unrecoverable capture failures.
  void Function(String reason)? onStopped;

  ExtImageCaptureSourceV1? _source;
  ExtImageCopyCaptureSessionV1? _session;
  ExtImageCopyCaptureFrameV1? _frame;

  // Latest constraints from the compositor; generation counts `done` batches
  // so a failed(buffer_constraints) can tell whether the fresh batch already
  // arrived or is still in flight.
  final List<int> _shmFormats = [];
  int _pendingWidth = 0;
  int _pendingHeight = 0;
  int _constraintsGeneration = 0;

  // The shm buffer currently attached, and the generation it was built from.
  int _bufferGeneration = -1;
  int _memfd = -1;
  ffi.Pointer<ffi.Uint8>? _map;
  int _mapSize = 0;
  WlShmPoolFfi? _pool;
  WlBufferFfi? _buffer;
  int _width = 0;
  int _height = 0;
  int _format = -1;

  Timer? _timer;
  int _consecutiveUnknownFailures = 0;
  int? _presentationTimeNs;
  bool _stopped = false;
  bool _started = false;

  static const int _maxUnknownFailures = 5;

  bool get isActive => _started && !_stopped;
  int get width => _width;
  int get height => _height;
  int get shmFormat => _format;

  void start() {
    assert(!_started);
    _started = true;
    final manager = _connection.copyCaptureManager!;
    final source = _output != null
        ? _connection.outputSourceManager!.createSource(_output)
        : _connection.toplevelSourceManager!.createSource(_toplevel!);
    _source = source;
    final session = manager.createSession(
        source, paintCursors ? ExtImageCopyCaptureManagerV1.optionPaintCursors : 0);
    _session = session;

    session.onShmFormat = (format) {
      // A new batch replaces the old set; the first event after a `done`
      // starts a fresh list.
      if (_constraintsBatchOpen) {
        _shmFormats.add(format);
      } else {
        _shmFormats
          ..clear()
          ..add(format);
        _constraintsBatchOpen = true;
      }
    };
    session.onBufferSize = (w, h) {
      if (!_constraintsBatchOpen) {
        _shmFormats.clear();
        _constraintsBatchOpen = true;
      }
      _pendingWidth = w;
      _pendingHeight = h;
    };
    session.onDone = _onConstraintsDone;
    session.onStopped = () => _stop('session stopped by compositor');
  }

  bool _constraintsBatchOpen = false;

  void _onConstraintsDone() {
    if (_stopped) return;
    _constraintsBatchOpen = false;
    _constraintsGeneration++;
    // Only start a capture cycle if none is in flight; an in-flight frame
    // either completes or fails with buffer_constraints, both of which come
    // back through here via _captureNext.
    if (_frame == null) {
      _captureNext();
    }
  }

  void _captureNext() {
    if (_stopped || _frame != null) return;
    if (_bufferGeneration != _constraintsGeneration) {
      if (!_reallocBuffer()) return; // _stop already called
    }
    final session = _session;
    final buffer = _buffer;
    if (session == null || buffer == null) return;

    final frame = session.createFrame();
    _frame = frame;
    _presentationTimeNs = null;
    frame.onPresentationTime = (hi, lo, nsec) =>
        _presentationTimeNs = ((hi << 32) | lo) * 1000000000 + nsec;
    frame.onReady = _onFrameReady;
    frame.onFailed = _onFrameFailed;
    frame.attachBuffer(buffer);
    // No damage tracking: full damage every frame, as the protocol requires
    // for clients that don't track it.
    frame.damageBuffer(0, 0, _width, _height);
    frame.capture();
  }

  bool _reallocBuffer() {
    _releaseBuffer();

    if (_pendingWidth <= 0 || _pendingHeight <= 0) {
      _stop('compositor advertised an empty buffer size');
      return false;
    }
    final format = _pickFormat();
    if (format == null) {
      _stop('no supported shm format (offered: '
          '${_shmFormats.map((f) => '0x${f.toRadixString(16)}').join(', ')})');
      return false;
    }

    final sizeChanged = _width != _pendingWidth || _height != _pendingHeight;
    _width = _pendingWidth;
    _height = _pendingHeight;
    _format = format;
    final stride = _width * 4;
    final size = stride * _height;

    final fd = libc.memfdCreate('graceful-shell-capture');
    if (fd < 0) {
      _stop('memfd_create failed');
      return false;
    }
    if (!libc.ftruncateFd(fd, size)) {
      libc.closeFd(fd);
      _stop('ftruncate failed');
      return false;
    }
    final map = libc.mmapShared(fd, size);
    if (map == null) {
      libc.closeFd(fd);
      _stop('mmap failed');
      return false;
    }

    _memfd = fd;
    _map = map;
    _mapSize = size;
    _pool = _connection.shm!.createPool(fd, size);
    _buffer = _pool!.createBuffer(0, _width, _height, stride, format);
    _bufferGeneration = _constraintsGeneration;

    if (sizeChanged) onSizeChanged?.call(_width, _height);
    return true;
  }

  int? _pickFormat() {
    for (final preferred in _formatPreference) {
      if (_shmFormats.contains(preferred)) return preferred;
    }
    return null;
  }

  void _onFrameReady() {
    _consecutiveUnknownFailures = 0;
    _destroyFrame();
    final map = _map;
    if (map != null && !_stopped) {
      onFrame?.call(CapturedFrame(
        data: map,
        width: _width,
        height: _height,
        stride: _width * 4,
        shmFormat: _format,
        presentationTimeNs: _presentationTimeNs,
      ));
    }
    _scheduleNext();
  }

  void _onFrameFailed(int reason) {
    _destroyFrame();
    switch (reason) {
      case ExtImageCopyCaptureFrameV1.failureBufferConstraints:
        // The buffer no longer matches. If the fresh constraints batch has
        // already arrived, realloc and retry now; otherwise the pending
        // batch's `done` restarts the loop.
        if (_bufferGeneration != _constraintsGeneration) {
          _captureNext();
        }
      case ExtImageCopyCaptureFrameV1.failureStopped:
        _stop('session stopped by compositor');
      default: // unknown — retry with a short backoff, bounded
        _consecutiveUnknownFailures++;
        if (_consecutiveUnknownFailures > _maxUnknownFailures) {
          _stop('too many consecutive capture failures');
        } else {
          _timer?.cancel();
          _timer = Timer(const Duration(milliseconds: 200), _captureNext);
        }
    }
  }

  void _scheduleNext() {
    if (_stopped) return;
    final interval = minFrameInterval;
    if (interval == null) {
      // Streaming: re-capture immediately; the compositor throttles by
      // waiting for the content to change.
      _captureNext();
    } else {
      _timer?.cancel();
      _timer = Timer(interval, _captureNext);
    }
  }

  void _destroyFrame() {
    _frame?.destroy();
    _frame = null;
  }

  void _releaseBuffer() {
    _buffer?.destroy();
    _buffer = null;
    _pool?.destroy();
    _pool = null;
    if (_map != null) {
      libc.munmapPtr(_map!, _mapSize);
      _map = null;
      _mapSize = 0;
    }
    if (_memfd >= 0) {
      libc.closeFd(_memfd);
      _memfd = -1;
    }
    _bufferGeneration = -1;
  }

  void _stop(String reason) {
    if (_stopped) return;
    _stopped = true;
    screencastLog('CaptureSession stopped: $reason');
    _teardown();
    onStopped?.call(reason);
  }

  /// Client-initiated stop (stream closed, preview dismissed). No onStopped.
  void dispose() {
    _stopped = true;
    _teardown();
  }

  void _teardown() {
    _timer?.cancel();
    _timer = null;
    _destroyFrame();
    _session?.destroy();
    _session = null;
    _source?.destroy();
    _source = null;
    _releaseBuffer();
  }
}
