import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

/// Raw `libpipewire-0.3` bindings — just the stream-producer surface.
///
/// Threading: no `pw_thread_loop` anywhere. The stream runs on a plain `pw_loop`
/// whose fd is watched from the GLib main loop (the Dart thread), and
/// `pw_loop_iterate(loop, 0)` is called on wakeup — so every stream event fires on
/// the Dart thread and `NativeCallable.isolateLocal` is safe. This needs
/// `pw_loop_get_fd`/`enter`/`leave`/`iterate` as real exports, which PipeWire has
/// since 1.0.
class PwFfi {
  PwFfi._(this._lib) {
    init = _lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>('pw_init');

    loopNew = _lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)>('pw_loop_new');
    loopDestroy = _lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('pw_loop_destroy');
    loopGetFd = _lib.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('pw_loop_get_fd');
    loopEnter = _lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('pw_loop_enter');
    loopLeave = _lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('pw_loop_leave');
    loopIterate = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Int32),
        int Function(ffi.Pointer<ffi.Void>, int)>('pw_loop_iterate');

    contextNew = _lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Size),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>, int)>('pw_context_new');
    contextDestroy = _lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('pw_context_destroy');
    contextConnect = _lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Size),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>, int)>('pw_context_connect');
    coreDisconnect = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('pw_core_disconnect');

    propertiesNewString = _lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>),
        ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<Utf8>)>('pw_properties_new_string');

    streamNew = _lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>, ffi.Pointer<ffi.Void>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<Utf8>, ffi.Pointer<ffi.Void>)>('pw_stream_new');
    streamDestroy = _lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('pw_stream_destroy');
    streamAddListener = _lib.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>(
        'pw_stream_add_listener');
    streamConnect = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Uint32,
            ffi.Uint32, ffi.Pointer<ffi.Pointer<ffi.Void>>, ffi.Uint32),
        int Function(ffi.Pointer<ffi.Void>, int, int, int,
            ffi.Pointer<ffi.Pointer<ffi.Void>>, int)>('pw_stream_connect');
    streamDisconnect = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('pw_stream_disconnect');
    streamUpdateParams = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Pointer<ffi.Void>>, ffi.Uint32),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Void>>,
            int)>('pw_stream_update_params');
    streamGetNodeId = _lib.lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('pw_stream_get_node_id');
    streamDequeueBuffer = _lib.lookupFunction<
        ffi.Pointer<PwBuffer> Function(ffi.Pointer<ffi.Void>),
        ffi.Pointer<PwBuffer> Function(
            ffi.Pointer<ffi.Void>)>('pw_stream_dequeue_buffer');
    streamQueueBuffer = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<PwBuffer>),
        int Function(ffi.Pointer<ffi.Void>,
            ffi.Pointer<PwBuffer>)>('pw_stream_queue_buffer');
    streamSetActive = _lib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Bool),
        int Function(ffi.Pointer<ffi.Void>, bool)>('pw_stream_set_active');
  }

  static PwFfi? _instance;

  /// Throws if `libpipewire-0.3.so.0` is unavailable — callers treat that as
  /// "screencast unsupported" and fail soft.
  static PwFfi get instance =>
      _instance ??= PwFfi._(ffi.DynamicLibrary.open('libpipewire-0.3.so.0'));

  final ffi.DynamicLibrary _lib;

  late final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) init;

  late final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>) loopNew;
  late final void Function(ffi.Pointer<ffi.Void>) loopDestroy;
  late final int Function(ffi.Pointer<ffi.Void>) loopGetFd;
  late final void Function(ffi.Pointer<ffi.Void>) loopEnter;
  late final void Function(ffi.Pointer<ffi.Void>) loopLeave;
  late final int Function(ffi.Pointer<ffi.Void>, int) loopIterate;

  late final ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int) contextNew;
  late final void Function(ffi.Pointer<ffi.Void>) contextDestroy;
  late final ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int) contextConnect;
  late final int Function(ffi.Pointer<ffi.Void>) coreDisconnect;

  late final ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>)
      propertiesNewString;

  late final ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>, ffi.Pointer<ffi.Void>) streamNew;
  late final void Function(ffi.Pointer<ffi.Void>) streamDestroy;
  late final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) streamAddListener;
  late final int Function(ffi.Pointer<ffi.Void>, int, int, int,
      ffi.Pointer<ffi.Pointer<ffi.Void>>, int) streamConnect;
  late final int Function(ffi.Pointer<ffi.Void>) streamDisconnect;
  late final int Function(
          ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Void>>, int)
      streamUpdateParams;
  late final int Function(ffi.Pointer<ffi.Void>) streamGetNodeId;
  late final ffi.Pointer<PwBuffer> Function(ffi.Pointer<ffi.Void>)
      streamDequeueBuffer;
  late final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<PwBuffer>)
      streamQueueBuffer;
  late final int Function(ffi.Pointer<ffi.Void>, bool) streamSetActive;
}

/// `struct pw_buffer` — only `buffer` is read.
final class PwBuffer extends ffi.Struct {
  external ffi.Pointer<SpaBuffer> buffer;
  external ffi.Pointer<ffi.Void> userData;
  @ffi.Uint64()
  external int size;
  @ffi.Uint64()
  external int requested;
  @ffi.Uint64()
  external int time;
}

final class SpaBuffer extends ffi.Struct {
  @ffi.Uint32()
  external int nMetas;
  @ffi.Uint32()
  external int nDatas;
  external ffi.Pointer<ffi.Void> metas;
  external ffi.Pointer<SpaData> datas;
}

final class SpaData extends ffi.Struct {
  @ffi.Uint32()
  external int type;
  @ffi.Uint32()
  external int flags;
  @ffi.Int64()
  external int fd;
  @ffi.Uint32()
  external int mapoffset;
  @ffi.Uint32()
  external int maxsize;
  external ffi.Pointer<ffi.Void> data;
  external ffi.Pointer<SpaChunk> chunk;
}

final class SpaChunk extends ffi.Struct {
  @ffi.Uint32()
  external int offset;
  @ffi.Uint32()
  external int size;
  @ffi.Int32()
  external int stride;
  @ffi.Int32()
  external int flags;
}
