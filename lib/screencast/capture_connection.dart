import '../wayland_ffi/wl_ffi.dart';
import '../wayland_ffi/wl_interfaces.dart';
import '../wayland_ffi/wl_protocols.dart';

/// The capture-side Wayland connection: registry, `wl_shm`, the capture managers,
/// live outputs, and the foreign-toplevel tracker.
///
/// A second connection alongside the shell's pure-Dart `package:wayland` one,
/// which cannot pass fds. It owns everything the screencast feature binds; if the
/// compositor does not advertise the capture globals, [supported] is false and
/// the feature is disabled.
class CaptureConnection {
  CaptureConnection._(this.conn);

  /// Connects and performs the two startup roundtrips (globals burst, then output
  /// geometry / initial toplevels). Returns null if the display is unreachable or
  /// libwayland is missing.
  ///
  /// [attachToGlibLoop] drives the event pump from the GLib main loop — the shell
  /// always wants this; the spike tool pumps manually.
  static CaptureConnection? connect({bool attachToGlibLoop = true}) {
    final display = WlDisplayConnection.connect();
    if (display == null) return null;
    final c = CaptureConnection._(display);
    c._init();
    if (attachToGlibLoop) display.attachToGlibLoop();
    return c;
  }

  final WlDisplayConnection conn;

  late final WlRegistryFfi _registry;
  WlShmFfi? shm;
  ExtOutputImageCaptureSourceManagerV1? outputSourceManager;
  ExtForeignToplevelImageCaptureSourceManagerV1? toplevelSourceManager;
  ExtImageCopyCaptureManagerV1? copyCaptureManager;
  ExtForeignToplevelListV1? _toplevelList;

  final List<WlOutputFfi> outputs = [];
  final List<ExtForeignToplevelHandleV1> toplevels = [];

  /// Fired on output hotplug and on toplevel open/close/retitle — the picker
  /// listens while it is on screen.
  void Function()? onOutputsChanged;
  void Function()? onToplevelsChanged;

  /// Fired once if the compositor connection dies. Every session is already
  /// dead at that point; the service tears down.
  void Function()? onDied;

  /// Monitor capture is the feature floor; window capture additionally needs
  /// [windowCaptureSupported].
  bool get supported =>
      shm != null && outputSourceManager != null && copyCaptureManager != null;

  bool get windowCaptureSupported =>
      supported && toplevelSourceManager != null && _toplevelList != null;

  void _init() {
    conn.onError = () => onDied?.call();
    final ifaces = WlProtocolInterfaces.instance;
    _registry = WlRegistryFfi.of(conn);
    _registry.onGlobal = (name, interface, version) {
      switch (interface) {
        case 'wl_output':
          final output = WlOutputFfi(conn,
              _registry.bind(name, ifaces.wlOutput, version < 4 ? version : 4),
              name);
          output.onDone = () => onOutputsChanged?.call();
          outputs.add(output);
        case 'wl_shm':
          shm ??= WlShmFfi(conn, _registry.bind(name, ifaces.wlShm, 1));
        case 'ext_output_image_capture_source_manager_v1':
          outputSourceManager ??= ExtOutputImageCaptureSourceManagerV1(
              conn, _registry.bind(name, ifaces.outputSourceManager, 1));
        case 'ext_foreign_toplevel_image_capture_source_manager_v1':
          toplevelSourceManager ??=
              ExtForeignToplevelImageCaptureSourceManagerV1(
                  conn, _registry.bind(name, ifaces.toplevelSourceManager, 1));
        case 'ext_image_copy_capture_manager_v1':
          copyCaptureManager ??= ExtImageCopyCaptureManagerV1(
              conn, _registry.bind(name, ifaces.copyCaptureManager, 1));
        case 'ext_foreign_toplevel_list_v1':
          final list = ExtForeignToplevelListV1(
              conn, _registry.bind(name, ifaces.toplevelList, 1));
          list.onToplevel = _onToplevel;
          _toplevelList ??= list;
      }
    };
    _registry.onGlobalRemove = (name) {
      final index = outputs.indexWhere((o) => o.globalName == name);
      if (index == -1) return;
      outputs.removeAt(index).release();
      onOutputsChanged?.call();
    };

    conn.roundtrip(); // globals burst; binds happen during dispatch
    conn.roundtrip(); // output geometry + initial toplevel burst
  }

  void _onToplevel(ExtForeignToplevelHandleV1 handle) {
    toplevels.add(handle);
    // Properties arrive after the `toplevel` event, committed by `done` —
    // notify then, not now, so the picker never sees a nameless row.
    handle.onDone = () => onToplevelsChanged?.call();
    handle.onClosed = () {
      toplevels.remove(handle);
      handle.destroy();
      onToplevelsChanged?.call();
    };
  }

  /// Finds a toplevel by its stable identifier (the value the picker carries
  /// across the pick → stream handoff).
  ExtForeignToplevelHandleV1? toplevelByIdentifier(String identifier) {
    for (final t in toplevels) {
      if (t.identifier == identifier) return t;
    }
    return null;
  }

  void dispose() {
    onDied = null;
    conn.disconnect();
  }
}
