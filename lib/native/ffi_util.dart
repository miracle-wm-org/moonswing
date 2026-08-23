/// The shared dlopen/lookup plumbing the FFI corners of the shell used to
/// hand-roll separately. (`packages/ext_session_lock` keeps its own copies:
/// it cannot import the app package without a dependency cycle.)
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

/// The running process as a library.
///
/// GTK, GLib and GIO are already linked in — Flutter's Linux embedder pulls
/// them in and gtk-layer-shell links against them — so their symbols resolve
/// from the running process rather than a separately-opened library. Lookups
/// through this are lazy and throw only when first touched, which is what
/// lets `flutter_tester` (which links no GLib) run everything that guards
/// its native calls.
final ffi.DynamicLibrary processLibrary = ffi.DynamicLibrary.process();

/// Opens the first of [sonames] that loads, or null when none does — the
/// fallback loop for libraries that may be installed under a versioned or an
/// unversioned name (`libpam.so.0` vs `libpam.so`).
ffi.DynamicLibrary? openFirstLibrary(List<String> sonames) {
  for (final name in sonames) {
    try {
      return ffi.DynamicLibrary.open(name);
    } catch (_) {
      // Try the next candidate.
    }
  }
  return null;
}

typedef _GdkDisplayGetDefaultC = ffi.Pointer<ffi.Void> Function();
typedef GdkDisplayGetDefaultDart = ffi.Pointer<ffi.Void> Function();

/// `gdk_display_get_default()`.
final GdkDisplayGetDefaultDart gdkDisplayGetDefault = processLibrary
    .lookupFunction<_GdkDisplayGetDefaultC, GdkDisplayGetDefaultDart>(
        'gdk_display_get_default');

// gulong g_signal_connect_data(gpointer instance, const gchar *detailed_signal,
//     GCallback c_handler, gpointer data, GClosureNotify destroy_data,
//     GConnectFlags connect_flags);
typedef _GSignalConnectDataC = ffi.Uint64 Function(
  ffi.Pointer<ffi.Void> instance,
  ffi.Pointer<Utf8> detailedSignal,
  ffi.Pointer<ffi.Void> handler,
  ffi.Pointer<ffi.Void> data,
  ffi.Pointer<ffi.Void> destroyData,
  ffi.Uint32 connectFlags,
);
typedef GSignalConnectDataDart = int Function(
  ffi.Pointer<ffi.Void> instance,
  ffi.Pointer<Utf8> detailedSignal,
  ffi.Pointer<ffi.Void> handler,
  ffi.Pointer<ffi.Void> data,
  ffi.Pointer<ffi.Void> destroyData,
  int connectFlags,
);

/// `g_signal_connect_data()` — this block used to exist, byte-identical, in
/// three files.
final GSignalConnectDataDart gSignalConnectData = processLibrary
    .lookupFunction<_GSignalConnectDataC, GSignalConnectDataDart>(
        'g_signal_connect_data');
