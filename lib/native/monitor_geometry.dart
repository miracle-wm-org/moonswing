/// A monitor's size, in the logical pixels a surface on it is laid out in.
///
/// `MonitorInfo` (from `package:layer_shell`) carries a monitor's position but
/// not its size, and the one thing that needs the size is the bars: whether a
/// bar was stretched across a corner or stopped short of it at another bar is
/// the compositor's call, and its length against the screen's is the only
/// evidence of which (`panel_join.dart`).
library;

import 'dart:ffi' as ffi;
import 'dart:ui' show Size;

import 'package:ffi/ffi.dart';

import 'package:moonswing/native/ffi_util.dart';

/// `GdkRectangle`.
final class _GdkRectangle extends ffi.Struct {
  @ffi.Int32()
  external int x;
  @ffi.Int32()
  external int y;
  @ffi.Int32()
  external int width;
  @ffi.Int32()
  external int height;
}

typedef _GetGeometryC =
    ffi.Void Function(
      ffi.Pointer<ffi.NativeType> monitor,
      ffi.Pointer<_GdkRectangle> geometry,
    );
typedef _GetGeometryDart =
    void Function(
      ffi.Pointer<ffi.NativeType> monitor,
      ffi.Pointer<_GdkRectangle> geometry,
    );

// Resolved lazily from the running process, which has GDK linked in; under
// flutter_tester it is not, and the first touch throws — which
// [monitorLogicalSize] turns into null.
final _getGeometry = processLibrary
    .lookupFunction<_GetGeometryC, _GetGeometryDart>(
      'gdk_monitor_get_geometry',
    );

/// [monitor]'s size in application (logical) pixels, as GDK reports it, or null
/// when it cannot be asked — a null monitor, a test binary, a GDK reporting an
/// empty rectangle.
Size? monitorLogicalSize(ffi.Pointer<ffi.NativeType> monitor) {
  if (monitor.address == 0) return null;
  try {
    final r = calloc<_GdkRectangle>();
    try {
      _getGeometry(monitor, r);
      final width = r.ref.width;
      final height = r.ref.height;
      if (width <= 0 || height <= 0) return null;
      return Size(width.toDouble(), height.toDouble());
    } finally {
      calloc.free(r);
    }
  } catch (_) {
    return null;
  }
}
