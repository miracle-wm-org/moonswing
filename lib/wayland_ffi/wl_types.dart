import 'dart:ffi' as ffi;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

/// C struct layouts from `wayland-util.h`, used both for the interface metadata
/// we hand libwayland and for reading the core interface structs libwayland
/// itself exports as data symbols.
///
/// ```c
/// struct wl_message { const char *name; const char *signature;
///                     const struct wl_interface **types; };
/// ```
final class WlMessage extends ffi.Struct {
  external ffi.Pointer<Utf8> name;
  external ffi.Pointer<Utf8> signature;
  external ffi.Pointer<ffi.Pointer<WlInterface>> types;
}

/// ```c
/// struct wl_interface {
///   const char *name; int version;
///   int method_count; const struct wl_message *methods;
///   int event_count;  const struct wl_message *events;
/// };
/// ```
final class WlInterface extends ffi.Struct {
  external ffi.Pointer<Utf8> name;
  @ffi.Int32()
  external int version;
  @ffi.Int32()
  external int methodCount;
  external ffi.Pointer<WlMessage> methods;
  @ffi.Int32()
  external int eventCount;
  external ffi.Pointer<WlMessage> events;
}

/// ```c
/// struct wl_array { size_t size; size_t alloc; void *data; };
/// ```
final class WlArray extends ffi.Struct {
  @ffi.Size()
  external int size;
  @ffi.Size()
  external int alloc;
  external ffi.Pointer<ffi.Void> data;
}

/// A `union wl_argument` array for `wl_proxy_marshal_array_flags`.
///
/// Each argument is one 8-byte union slot. Integers (`i`/`u`/`h`) occupy the low
/// 32 bits (little-endian, so writing the whole Int64 is equivalent), objects and
/// strings are pointer addresses, and `new_id` slots are left 0 — the marshaller
/// fills them from the interface/version parameters.
class WlArgs {
  WlArgs(int count) : _ptr = calloc<ffi.Int64>(math.max(count, 1));

  final ffi.Pointer<ffi.Int64> _ptr;

  void setInt(int index, int value) => _ptr[index] = value;
  void setUint(int index, int value) => _ptr[index] = value;
  void setFd(int index, int fd) => _ptr[index] = fd;
  void setNewId(int index) => _ptr[index] = 0;

  void setObject(int index, ffi.Pointer<ffi.Void> proxy) =>
      _ptr[index] = proxy.address;

  /// A string argument that borrows an existing native string (e.g. an
  /// interface name from a `wl_interface` struct) — not freed by [free].
  void setStringPtr(int index, ffi.Pointer<Utf8> value) =>
      _ptr[index] = value.address;

  ffi.Pointer<ffi.Void> get pointer => _ptr.cast();

  void free() => calloc.free(_ptr);
}
