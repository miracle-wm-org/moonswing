import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

/// Thin libc bindings for the shared-memory plumbing the screencast capture
/// path needs: an anonymous memfd doubles as the `wl_shm` pool the compositor
/// copies frames into and (mapped) as the bytes handed to PipeWire/previews.
final ffi.DynamicLibrary _process = ffi.DynamicLibrary.process();

const int mfdCloexec = 0x0001;
const int protRead = 0x1;
const int protWrite = 0x2;
const int mapShared = 0x01;

// int memfd_create(const char *name, unsigned int flags);
final _memfdCreate = _process.lookupFunction<
    ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Uint32),
    int Function(ffi.Pointer<Utf8>, int)>('memfd_create');

// int ftruncate(int fd, off_t length);
final _ftruncate = _process.lookupFunction<
    ffi.Int32 Function(ffi.Int32, ffi.Int64),
    int Function(int, int)>('ftruncate');

// void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t o);
final _mmap = _process.lookupFunction<
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Size, ffi.Int32,
        ffi.Int32, ffi.Int32, ffi.Int64),
    ffi.Pointer<ffi.Void> Function(
        ffi.Pointer<ffi.Void>, int, int, int, int, int)>('mmap');

// int munmap(void *addr, size_t length);
final _munmap = _process.lookupFunction<
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Size),
    int Function(ffi.Pointer<ffi.Void>, int)>('munmap');

// int close(int fd);
final _close = _process.lookupFunction<ffi.Int32 Function(ffi.Int32),
    int Function(int)>('close');

// void *memcpy(void *dest, const void *src, size_t n);
final _memcpy = _process.lookupFunction<
    ffi.Pointer<ffi.Void> Function(
        ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Size),
    ffi.Pointer<ffi.Void> Function(
        ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int)>('memcpy');

/// Creates an anonymous memory file; returns the fd, or -1 on failure.
int memfdCreate(String name) {
  final namePtr = name.toNativeUtf8();
  try {
    return _memfdCreate(namePtr, mfdCloexec);
  } finally {
    malloc.free(namePtr);
  }
}

/// Grows [fd] to [length] bytes. Returns true on success.
bool ftruncateFd(int fd, int length) => _ftruncate(fd, length) == 0;

/// Maps [length] bytes of [fd] read/write + shared; null on failure.
ffi.Pointer<ffi.Uint8>? mmapShared(int fd, int length) {
  final ptr = _mmap(ffi.nullptr, length, protRead | protWrite, mapShared, fd, 0);
  // MAP_FAILED is (void *)-1.
  if (ptr.address == 0 || ptr.address == -1) return null;
  return ptr.cast();
}

void munmapPtr(ffi.Pointer<ffi.Uint8> addr, int length) =>
    _munmap(addr.cast(), length);

void closeFd(int fd) => _close(fd);

/// Pointer-to-pointer copy — the frame path must never round-trip pixels
/// through a Dart list.
void memcpyPtr(ffi.Pointer<ffi.Void> dest, ffi.Pointer<ffi.Void> src, int n) =>
    _memcpy(dest, src, n);

// int chmod(const char *pathname, mode_t mode);
final _chmod = _process.lookupFunction<
    ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Uint32),
    int Function(ffi.Pointer<Utf8>, int)>('chmod');

/// Sets [path]'s permission bits to [mode]. Returns true on success.
///
/// Here because `dart:io` has no way to say it and one thing the shell writes
/// is a secret: the GitHub access token
/// (`lib/github/github_token_store.dart`), which must not be readable by other
/// users on the machine. Creating the file and *then* narrowing it leaves a
/// window, so the caller creates it inside a directory this has already
/// narrowed — the same order `ssh-keygen` uses on `~/.ssh`.
bool chmodPath(String path, int mode) {
  final pathPtr = path.toNativeUtf8();
  try {
    return _chmod(pathPtr, mode) == 0;
  } catch (_) {
    return false;
  } finally {
    malloc.free(pathPtr);
  }
}
