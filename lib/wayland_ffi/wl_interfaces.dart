import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'wl_ffi.dart';
import 'wl_types.dart';

/// The `wl_interface` graph for the capture protocols, hand-transcribed from the
/// XMLs in `protocol/` — exactly what `wayland-scanner` would emit as C, built
/// once into calloc'd memory that is deliberately never freed: libwayland holds
/// the pointers for the life of every proxy.
///
/// Core interfaces (`wl_output`, `wl_shm`, `wl_buffer`, …) are *not* transcribed
/// — libwayland-client exports them as data symbols and the real structs are used
/// directly, so only the ext protocols carry transcription risk.
/// `test/wl_interfaces_test.dart` diffs this table against the installed XMLs.
///
/// Signatures follow scanner rules: one character per argument (`i` int, `u`
/// uint, `s` string, `o` object, `n` new_id, `a` array, `h` fd), with a leading
/// since-version digit where the XML has one. The `types` array has one entry per
/// argument, null except for typed `o`/`n` slots.
class WlProtocolInterfaces {
  WlProtocolInterfaces._() {
    final w = WlFfi.instance;
    wlRegistry = w.coreInterface('wl_registry_interface');
    wlCallback = w.coreInterface('wl_callback_interface');
    wlOutput = w.coreInterface('wl_output_interface');
    wlShm = w.coreInterface('wl_shm_interface');
    wlShmPool = w.coreInterface('wl_shm_pool_interface');
    wlBuffer = w.coreInterface('wl_buffer_interface');
    wlPointer = w.coreInterface('wl_pointer_interface');

    // Phase 1: allocate every ext interface so cross-references (session →
    // frame, list → handle, …) can be written in phase 2 regardless of order.
    captureSource = calloc<WlInterface>();
    outputSourceManager = calloc<WlInterface>();
    toplevelSourceManager = calloc<WlInterface>();
    copyCaptureManager = calloc<WlInterface>();
    copyCaptureSession = calloc<WlInterface>();
    copyCaptureFrame = calloc<WlInterface>();
    copyCaptureCursorSession = calloc<WlInterface>();
    toplevelList = calloc<WlInterface>();
    toplevelHandle = calloc<WlInterface>();

    final ffi.Pointer<WlInterface> nil = ffi.nullptr;

    // Phase 2: fill.
    _fill(
      captureSource,
      'ext_image_capture_source_v1',
      1,
      methods: [_msg('destroy', '', [])],
      events: [],
    );
    _fill(
      outputSourceManager,
      'ext_output_image_capture_source_manager_v1',
      1,
      methods: [
        _msg('create_source', 'no', [captureSource, wlOutput]),
        _msg('destroy', '', []),
      ],
      events: [],
    );
    _fill(
      toplevelSourceManager,
      'ext_foreign_toplevel_image_capture_source_manager_v1',
      1,
      methods: [
        _msg('create_source', 'no', [captureSource, toplevelHandle]),
        _msg('destroy', '', []),
      ],
      events: [],
    );
    _fill(
      copyCaptureManager,
      'ext_image_copy_capture_manager_v1',
      1,
      methods: [
        _msg('create_session', 'nou', [copyCaptureSession, captureSource, nil]),
        _msg('create_pointer_cursor_session', 'noo',
            [copyCaptureCursorSession, captureSource, wlPointer]),
        _msg('destroy', '', []),
      ],
      events: [],
    );
    _fill(
      copyCaptureSession,
      'ext_image_copy_capture_session_v1',
      1,
      methods: [
        _msg('create_frame', 'n', [copyCaptureFrame]),
        _msg('destroy', '', []),
      ],
      events: [
        _msg('buffer_size', 'uu', [nil, nil]),
        _msg('shm_format', 'u', [nil]),
        _msg('dmabuf_device', 'a', [nil]),
        _msg('dmabuf_format', 'ua', [nil, nil]),
        _msg('done', '', []),
        _msg('stopped', '', []),
      ],
    );
    _fill(
      copyCaptureFrame,
      'ext_image_copy_capture_frame_v1',
      1,
      methods: [
        _msg('destroy', '', []),
        _msg('attach_buffer', 'o', [wlBuffer]),
        _msg('damage_buffer', 'iiii', [nil, nil, nil, nil]),
        _msg('capture', '', []),
      ],
      events: [
        _msg('transform', 'u', [nil]),
        _msg('damage', 'iiii', [nil, nil, nil, nil]),
        _msg('presentation_time', 'uuu', [nil, nil, nil]),
        _msg('ready', '', []),
        _msg('failed', 'u', [nil]),
      ],
    );
    _fill(
      copyCaptureCursorSession,
      'ext_image_copy_capture_cursor_session_v1',
      1,
      methods: [
        _msg('destroy', '', []),
        _msg('get_capture_session', 'n', [copyCaptureSession]),
      ],
      events: [
        _msg('enter', '', []),
        _msg('leave', '', []),
        _msg('position', 'ii', [nil, nil]),
        _msg('hotspot', 'ii', [nil, nil]),
      ],
    );
    _fill(
      toplevelList,
      'ext_foreign_toplevel_list_v1',
      1,
      methods: [
        _msg('stop', '', []),
        _msg('destroy', '', []),
      ],
      events: [
        _msg('toplevel', 'n', [toplevelHandle]),
        _msg('finished', '', []),
      ],
    );
    _fill(
      toplevelHandle,
      'ext_foreign_toplevel_handle_v1',
      1,
      methods: [_msg('destroy', '', [])],
      events: [
        _msg('closed', '', []),
        _msg('done', '', []),
        _msg('title', 's', [nil]),
        _msg('app_id', 's', [nil]),
        _msg('identifier', 's', [nil]),
      ],
    );
  }

  static WlProtocolInterfaces? _i;
  static WlProtocolInterfaces get instance => _i ??= WlProtocolInterfaces._();

  // Core (from libwayland's exported data symbols).
  late final ffi.Pointer<WlInterface> wlRegistry;
  late final ffi.Pointer<WlInterface> wlCallback;
  late final ffi.Pointer<WlInterface> wlOutput;
  late final ffi.Pointer<WlInterface> wlShm;
  late final ffi.Pointer<WlInterface> wlShmPool;
  late final ffi.Pointer<WlInterface> wlBuffer;
  late final ffi.Pointer<WlInterface> wlPointer;

  // Ext (hand-built).
  late final ffi.Pointer<WlInterface> captureSource;
  late final ffi.Pointer<WlInterface> outputSourceManager;
  late final ffi.Pointer<WlInterface> toplevelSourceManager;
  late final ffi.Pointer<WlInterface> copyCaptureManager;
  late final ffi.Pointer<WlInterface> copyCaptureSession;
  late final ffi.Pointer<WlInterface> copyCaptureFrame;
  late final ffi.Pointer<WlInterface> copyCaptureCursorSession;
  late final ffi.Pointer<WlInterface> toplevelList;
  late final ffi.Pointer<WlInterface> toplevelHandle;

  static (String, String, List<ffi.Pointer<WlInterface>>) _msg(
          String name, String signature, List<ffi.Pointer<WlInterface>> types) =>
      (name, signature, types);

  static void _fill(
    ffi.Pointer<WlInterface> iface,
    String name,
    int version, {
    required List<(String, String, List<ffi.Pointer<WlInterface>>)> methods,
    required List<(String, String, List<ffi.Pointer<WlInterface>>)> events,
  }) {
    iface.ref.name = name.toNativeUtf8();
    iface.ref.version = version;
    iface.ref.methodCount = methods.length;
    iface.ref.methods = _messages(methods);
    iface.ref.eventCount = events.length;
    iface.ref.events = _messages(events);
  }

  static ffi.Pointer<WlMessage> _messages(
      List<(String, String, List<ffi.Pointer<WlInterface>>)> defs) {
    if (defs.isEmpty) return ffi.nullptr;
    final arr = calloc<WlMessage>(defs.length);
    for (var i = 0; i < defs.length; i++) {
      final (name, signature, types) = defs[i];
      final m = arr + i;
      m.ref.name = name.toNativeUtf8();
      m.ref.signature = signature.toNativeUtf8();
      // One entry per argument; libwayland only dereferences typed slots but
      // the array is always at least one entry long, matching scanner output.
      final t = calloc<ffi.Pointer<WlInterface>>(
          types.isEmpty ? 1 : types.length);
      for (var j = 0; j < types.length; j++) {
        t[j] = types[j];
      }
      m.ref.types = t;
    }
    return arr;
  }
}
