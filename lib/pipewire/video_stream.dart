import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../native/glib_source.dart';
import '../native/libc.dart' as libc;
import '../screencast/capture_session.dart';
import '../screencast/screencast_log.dart';
import 'pw_ffi.dart';
import 'spa_constants.dart';
import 'spa_pod.dart';

typedef _StateChangedC = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Pointer<Utf8>);
typedef _ParamChangedC = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Pointer<ffi.Void>);

/// One PipeWire video-source stream, fed by a [CaptureSession].
///
/// Lifecycle: [start] connects the stream with an `EnumFormat` param; the
/// negotiated `param_changed(Format)` is answered with a `Buffers` param;
/// once the stream reaches PAUSED with a valid node id, [nodeId] completes —
/// that id is what the portal's `Start` response carries. Frames are pushed
/// with [pushFrame]: dequeue a pw buffer (drop the frame when the consumer
/// has none free), pointer-to-pointer memcpy, queue.
class PipewireVideoStream {
  PipewireVideoStream({
    required this.width,
    required this.height,
    required this.spaVideoFormat,
    this.maxFrameRate = 60,
    this.name = 'graceful-shell-screencast',
    this.driveWithGlib = true,
  });

  int width;
  int height;
  final int spaVideoFormat;
  final int maxFrameRate;
  final String name;

  /// The shell drives the loop from the GLib main loop; the spike tool calls
  /// [iterate] manually instead.
  final bool driveWithGlib;

  static bool _initialized = false;

  /// Streams whose loop nobody else is driving (`driveWithGlib: false`, or a
  /// process with no GLib main loop). [iterateManuallyDriven] pumps them —
  /// they are registered from [start], before the node id is known, because
  /// that handshake is itself a thing the loop has to deliver.
  static final List<PipewireVideoStream> _manuallyDriven = [];

  /// Drains every manually-driven stream. No-op in the shell.
  static void iterateManuallyDriven() {
    for (final stream in List.of(_manuallyDriven)) {
      stream.iterate();
    }
  }

  /// One-time `pw_init`. False if libpipewire is unavailable.
  static bool ensureInit() {
    if (_initialized) return true;
    try {
      PwFfi.instance.init(ffi.nullptr, ffi.nullptr);
      _initialized = true;
      return true;
    } catch (e) {
      screencastLog('PipeWire unavailable: $e');
      return false;
    }
  }

  ffi.Pointer<ffi.Void> _loop = ffi.nullptr;
  ffi.Pointer<ffi.Void> _context = ffi.nullptr;
  ffi.Pointer<ffi.Void> _core = ffi.nullptr;
  ffi.Pointer<ffi.Void> _stream = ffi.nullptr;
  ffi.Pointer<ffi.Void> _hook = ffi.nullptr;
  ffi.Pointer<ffi.Void> _events = ffi.nullptr;
  GlibFdWatch? _fdWatch;
  ffi.NativeCallable<_StateChangedC>? _stateCallable;
  ffi.NativeCallable<_ParamChangedC>? _paramCallable;
  final List<ffi.Pointer<ffi.Void>> _nativePods = [];

  final Completer<int> _nodeIdCompleter = Completer<int>();
  int _state = pwStreamStateUnconnected;
  bool _disposed = false;
  bool _nodeIdGuarded = false;

  /// Completes with the PipeWire node id once the stream is up, or with an
  /// error if the stream fails first.
  ///
  /// A stream torn down before it came up completes this with an error even
  /// when nobody is waiting any more (the caller already gave up and disposed
  /// it), so a listener is registered up front to keep that from surfacing as
  /// an unhandled async error and killing the isolate.
  Future<int> get nodeId => _nodeIdCompleter.future;

  int? _nodeId;

  /// The node id if already known — for callers pumping synchronously (the
  /// spike tool), where microtasks don't run between iterations.
  int? get nodeIdSync => _nodeId;

  /// True while a consumer is connected and pulling frames.
  bool get isStreaming => _state == pwStreamStateStreaming;

  /// Fired when the stream errors after startup (consumer gone is NOT an
  /// error — that's just the state dropping back to PAUSED).
  void Function(String reason)? onError;

  /// Starts the stream. Returns false on immediate failure (no PipeWire
  /// daemon, no library).
  bool start() {
    if (!ensureInit()) return false;
    if (!_nodeIdGuarded) {
      _nodeIdGuarded = true;
      _nodeIdCompleter.future.ignore();
    }
    final pw = PwFfi.instance;
    try {
      _loop = pw.loopNew(ffi.nullptr);
    } catch (e) {
      screencastLog('pw_loop_new failed: $e');
      return false;
    }
    if (_loop == ffi.nullptr) return false;
    pw.loopEnter(_loop);
    if (driveWithGlib) {
      try {
        _fdWatch = GlibFdWatch(pw.loopGetFd(_loop), (_) => iterate());
      } catch (e) {
        // No GLib in the process (a plain `dart` binary rather than the
        // Flutter embedder) — fall back to manual pumping.
        screencastLog('no GLib main loop, driving pw_loop manually: $e');
      }
    }
    if (_fdWatch == null) _manuallyDriven.add(this);

    _context = pw.contextNew(_loop, ffi.nullptr, 0);
    if (_context == ffi.nullptr) {
      _fail('pw_context_new failed');
      return false;
    }
    _core = pw.contextConnect(_context, ffi.nullptr, 0);
    if (_core == ffi.nullptr) {
      _fail('cannot connect to the PipeWire daemon');
      return false;
    }

    final propsStr = 'media.class=Video/Source node.name=$name'.toNativeUtf8();
    final props = pw.propertiesNewString(propsStr);
    malloc.free(propsStr);

    final namePtr = name.toNativeUtf8();
    _stream = pw.streamNew(_core, namePtr, props); // stream owns props
    malloc.free(namePtr);
    if (_stream == ffi.nullptr) {
      _fail('pw_stream_new failed');
      return false;
    }

    _installListener();

    final connectResult = pw.streamConnect(
      _stream,
      pwDirectionOutput,
      pwIdAny,
      pwStreamFlagDriver | pwStreamFlagMapBuffers,
      _paramsArray([
        buildVideoEnumFormat(
          videoFormat: spaVideoFormat,
          width: width,
          height: height,
          maxFrameRate: maxFrameRate,
        ),
      ]),
      1,
    );
    if (connectResult < 0) {
      _fail('pw_stream_connect failed: $connectResult');
      return false;
    }
    return true;
  }

  void _installListener() {
    // struct pw_stream_events v2: u32 version (+pad), then 11 function
    // pointers: destroy, state_changed, control_info, io_changed,
    // param_changed, add_buffer, remove_buffer, process, drained, command,
    // trigger_done. Only state_changed (slot 1) and param_changed (slot 4)
    // are wired.
    _events = calloc<ffi.Uint8>(8 + 11 * 8).cast();
    _events.cast<ffi.Uint32>().value = pwVersionStreamEvents;
    _stateCallable =
        ffi.NativeCallable<_StateChangedC>.isolateLocal(_onStateChanged);
    _paramCallable =
        ffi.NativeCallable<_ParamChangedC>.isolateLocal(_onParamChanged);
    final slots = _events.cast<ffi.Uint64>();
    (slots + 1 + 1).value = _stateCallable!.nativeFunction.address;
    (slots + 1 + 4).value = _paramCallable!.nativeFunction.address;

    _hook = calloc<ffi.Uint8>(64).cast(); // spa_hook, zeroed
    PwFfi.instance.streamAddListener(_stream, _hook, _events, ffi.nullptr);
  }

  void _onStateChanged(
      ffi.Pointer<ffi.Void> data, int old, int state, ffi.Pointer<Utf8> error) {
    _state = state;
    if (state == pwStreamStateError) {
      final message =
          error.address == 0 ? 'stream error' : error.toDartString();
      _fail(message);
      return;
    }
    if ((state == pwStreamStatePaused || state == pwStreamStateStreaming) &&
        !_nodeIdCompleter.isCompleted) {
      final id = PwFfi.instance.streamGetNodeId(_stream);
      if (id != pwIdAny) {
        screencastLog('PipeWire stream up, node id $id');
        _nodeId = id;
        _nodeIdCompleter.complete(id);
      }
    }
  }

  void _onParamChanged(
      ffi.Pointer<ffi.Void> data, int id, ffi.Pointer<ffi.Void> pod) {
    if (id != spaParamFormat || pod.address == 0) return;
    final header = pod.cast<ffi.Uint32>();
    final bodySize = header.value;
    final bytes =
        Uint8List.fromList(pod.cast<ffi.Uint8>().asTypedList(8 + bodySize));
    final negotiated = parseSpaFormat(bytes);
    if (negotiated == null) return;
    screencastLog('PipeWire format negotiated: $negotiated');
    PwFfi.instance.streamUpdateParams(
      _stream,
      _paramsArray(
          [buildVideoBuffers(width: negotiated.width, height: negotiated.height)]),
      1,
    );
  }

  /// Copies pod byte buffers into native memory (kept until dispose) and
  /// returns a `const spa_pod **`.
  ffi.Pointer<ffi.Pointer<ffi.Void>> _paramsArray(List<Uint8List> pods) {
    final array = calloc<ffi.Pointer<ffi.Void>>(pods.length);
    for (var i = 0; i < pods.length; i++) {
      final native = calloc<ffi.Uint8>(pods[i].length);
      native.asTypedList(pods[i].length).setAll(0, pods[i]);
      array[i] = native.cast();
      _nativePods.add(native.cast());
    }
    _nativePods.add(array.cast());
    return array;
  }

  /// Drains pending loop work. The GLib fd watch calls this; the spike tool
  /// calls it from its manual pump.
  void iterate() {
    if (_loop != ffi.nullptr && !_disposed) {
      PwFfi.instance.loopIterate(_loop, 0);
    }
  }

  /// Pushes one captured frame. Returns false when dropped (not streaming,
  /// or the consumer has no free buffer).
  bool pushFrame(CapturedFrame frame) {
    if (_disposed || _state != pwStreamStateStreaming) return false;
    final pw = PwFfi.instance;
    final pb = pw.streamDequeueBuffer(_stream);
    if (pb.address == 0) return false;

    final spaBuffer = pb.ref.buffer;
    if (spaBuffer.address == 0 || spaBuffer.ref.nDatas < 1) {
      pw.streamQueueBuffer(_stream, pb);
      return false;
    }
    final d = spaBuffer.ref.datas;
    final copyBytes =
        frame.sizeBytes < d.ref.maxsize ? frame.sizeBytes : d.ref.maxsize;
    if (d.ref.data.address == 0) {
      pw.streamQueueBuffer(_stream, pb);
      return false;
    }
    libc.memcpyPtr(d.ref.data, frame.data.cast(), copyBytes);
    final chunk = d.ref.chunk;
    if (chunk.address != 0) {
      chunk.ref.offset = 0;
      chunk.ref.size = copyBytes;
      chunk.ref.stride = frame.stride;
      chunk.ref.flags = 0;
    }
    pw.streamQueueBuffer(_stream, pb);
    return true;
  }

  /// Renegotiates after the capture source changed size (window resize).
  void updateSize(int newWidth, int newHeight) {
    if (_disposed || _stream == ffi.nullptr) return;
    width = newWidth;
    height = newHeight;
    PwFfi.instance.streamUpdateParams(
      _stream,
      _paramsArray([
        buildVideoEnumFormat(
          videoFormat: spaVideoFormat,
          width: newWidth,
          height: newHeight,
          maxFrameRate: maxFrameRate,
        ),
      ]),
      1,
    );
  }

  void _fail(String reason) {
    screencastLog('PipewireVideoStream: $reason');
    if (!_nodeIdCompleter.isCompleted) {
      _nodeIdCompleter.completeError(StateError(reason));
    } else {
      onError?.call(reason);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final pw = PwFfi.instance;
    if (_stream != ffi.nullptr) {
      pw.streamDisconnect(_stream);
      pw.streamDestroy(_stream);
      _stream = ffi.nullptr;
    }
    if (_core != ffi.nullptr) {
      pw.coreDisconnect(_core);
      _core = ffi.nullptr;
    }
    if (_context != ffi.nullptr) {
      pw.contextDestroy(_context);
      _context = ffi.nullptr;
    }
    _fdWatch?.dispose();
    _fdWatch = null;
    _manuallyDriven.remove(this);
    if (_loop != ffi.nullptr) {
      pw.loopLeave(_loop);
      pw.loopDestroy(_loop);
      _loop = ffi.nullptr;
    }
    _stateCallable?.close();
    _paramCallable?.close();
    if (_events != ffi.nullptr) calloc.free(_events);
    if (_hook != ffi.nullptr) calloc.free(_hook);
    for (final p in _nativePods) {
      calloc.free(p);
    }
    _nativePods.clear();
    if (!_nodeIdCompleter.isCompleted) {
      _nodeIdCompleter.completeError(StateError('disposed'));
    }
  }
}
