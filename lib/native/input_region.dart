/// A surface's **input region**: the part of it that takes the pointer.
///
/// The shell went a long way without one, and the rule that followed —
/// "a surface swallows every click inside it, so never draw an inset inside a
/// full-size surface" — shaped the margin, the popup shadow's arithmetic and
/// the badges. That rule still holds for every surface that does not opt in
/// here. What this adds is the one exception decoration needs: a bar whose
/// leaves hang over the windows beneath it grows its surface by the overhang
/// and hands the overhang back to the windows, so the leaves are paint and the
/// clicks under them land where they were aimed.
///
/// GTK3 does the Wayland half itself: `gtk_widget_input_shape_combine_region`
/// on the toplevel records the shape on the widget (so a re-realize keeps it)
/// and on its `GdkWindow`, and GDK's Wayland backend sends it as
/// `wl_surface.set_input_region` with the next commit. A layer-shell window is
/// never client-side-decorated, so nothing in GTK replaces it afterwards.
/// Flutter's view draws through GDK's GL into the toplevel's own surface — no
/// subsurface of its own to give a region to.
library;

import 'dart:ffi' as ffi;
import 'dart:ui' show Rect, Size;

import 'package:ffi/ffi.dart';

import 'package:moonswing/native/ffi_util.dart';

/// `cairo_rectangle_int_t`.
final class _CairoRectangleInt extends ffi.Struct {
  @ffi.Int32()
  external int x;
  @ffi.Int32()
  external int y;
  @ffi.Int32()
  external int width;
  @ffi.Int32()
  external int height;
}

typedef _RegionCreateC = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<_CairoRectangleInt>);
typedef _RegionDestroyC = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _RegionDestroyDart = void Function(ffi.Pointer<ffi.Void>);
typedef _CombineC = ffi.Void Function(
    ffi.Pointer<ffi.Void> widget, ffi.Pointer<ffi.Void> region);
typedef _CombineDart = void Function(
    ffi.Pointer<ffi.Void> widget, ffi.Pointer<ffi.Void> region);

// Resolved lazily, from the running process: cairo and GTK are linked in by
// the embedder. Under flutter_tester neither is, and the first touch throws —
// which [setInputRegion] turns into `false`.
final _regionCreate =
    processLibrary.lookupFunction<_RegionCreateC, _RegionCreateC>(
        'cairo_region_create_rectangle');
final _regionDestroy =
    processLibrary.lookupFunction<_RegionDestroyC, _RegionDestroyDart>(
        'cairo_region_destroy');
final _combine = processLibrary.lookupFunction<_CombineC, _CombineDart>(
    'gtk_widget_input_shape_combine_region');

/// Limits the GTK toplevel [gtkWindow]'s input to [rect], in surface-local
/// logical pixels — or gives it the whole surface back when [rect] is null.
///
/// Answers whether the region was set. False means the platform could not be
/// asked at all (a test binary, a GTK without the symbol), and a caller that
/// grew its surface on the strength of a region must then not grow it: an
/// overhang that took the pointer would swallow every click beneath it.
bool setInputRegion(ffi.Pointer<ffi.Void> gtkWindow, Rect? rect) {
  if (gtkWindow.address == 0) return false;
  try {
    if (rect == null) {
      _combine(gtkWindow, ffi.nullptr);
      return true;
    }
    final r = calloc<_CairoRectangleInt>();
    try {
      r.ref
        ..x = rect.left.floor()
        ..y = rect.top.floor()
        ..width = rect.width.ceil()
        ..height = rect.height.ceil();
      final region = _regionCreate(r);
      if (region.address == 0) return false;
      try {
        _combine(gtkWindow, region);
      } finally {
        _regionDestroy(region);
      }
      return true;
    } finally {
      calloc.free(r);
    }
  } catch (_) {
    return false;
  }
}

/// Wider than any output: the length of a bar along its own axis is the
/// compositor's to decide (it stretches between two anchored edges), so the
/// region is given a length nothing can exceed and the surface clips it.
const double _kUnbounded = 32768.0;

/// The part of a bar's surface that is the bar: [thickness] deep against the
/// screen edge it is [anchor]ed to, leaving the [reach] beyond it to whatever
/// is underneath.
///
/// The bar sits against the screen edge and the overhang points into the
/// screen, so a top bar takes the top of its surface and a bottom bar the
/// bottom — which is where a bottom bar's [reach] has to be skipped.
Rect panelInputRect({
  required String anchor,
  required double thickness,
  required double reach,
}) =>
    switch (anchor) {
      'bottom' => Rect.fromLTWH(0, reach, _kUnbounded, thickness),
      'left' => Rect.fromLTWH(0, 0, thickness, _kUnbounded),
      'right' => Rect.fromLTWH(reach, 0, thickness, _kUnbounded),
      _ => Rect.fromLTWH(0, 0, _kUnbounded, thickness),
    };

/// Where the bar sits inside a surface of [surface] size: [panelInputRect]
/// clipped to the surface, which is what the panel lays its modules out in.
Rect panelBarRect({
  required Size surface,
  required String anchor,
  required double thickness,
}) {
  final t = thickness.clamp(0.0, switch (anchor) {
    'left' || 'right' => surface.width,
    _ => surface.height,
  });
  return switch (anchor) {
    'bottom' => Rect.fromLTWH(0, surface.height - t, surface.width, t),
    'left' => Rect.fromLTWH(0, 0, t, surface.height),
    'right' => Rect.fromLTWH(surface.width - t, 0, t, surface.height),
    _ => Rect.fromLTWH(0, 0, surface.width, t),
  };
}
