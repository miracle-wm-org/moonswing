---
title: Native code, FFI and capture
description: There is no C in the repo — how the shell talks to libwayland, PipeWire and the capture protocols.
sidebar:
  order: 6
---

`lib/native/`, `lib/wayland_ffi/`, `lib/pipewire/`, `lib/screencast/` and `lib/capture/` are
all pure `dart:ffi`. **There is no C in the repository.** `lib/native/` holds the shared dlopen
plumbing: `processLibrary`, soname fallback, `g_signal_connect_data`, `g_unix_fd_add`,
`memfd_create`, `mmap`, `memcpy`.

- **Capture needs its own Wayland connection, over libwayland.** `package:wayland` cannot pass
  file descriptors, and `wl_shm.create_pool` requires one.
- **There is one `CaptureConnection` in the process** — `CaptureHost`'s — shared by the portal
  backend and the shell's own screenshot and recording. It memoises the connect, fans `onDied`
  out, and **clears the connection when it dies**, so a compositor restart costs one capture
  rather than the session.
- **One thread, fd watches.** The Dart UI isolate runs on the GLib main thread, so
  `g_unix_fd_add` on the capture display fd and on `pw_loop_get_fd` drives both — no
  `pw_thread_loop`, no isolates, and every callback lands on the Dart thread, which is what
  makes `NativeCallable.isolateLocal` correct throughout. With no GLib (the spike) the watch
  fails and the owner pumps manually.
- **Everything below the UI is Flutter-free on purpose**, so `tool/screencast_spike.dart`
  compiles the whole stack as a `dart compile exe` binary — the only way to exercise it against
  a live compositor. Use the `*Log` gates rather than `debugPrint`.
- **Only the `ext-*` protocols are hand-transcribed**; core interfaces come from libwayland's
  exported `wl_*_interface` symbols. A wrong signature is memory corruption inside libwayland,
  not an exception, which is why `test/wl_interfaces_test.dart` diffs the tables against the
  XML in `protocol/`. Copy a new XML there and extend the test.
- **The compositor paces the stream, not a timer.** `ext-image-copy-capture` holds each copy
  until content changes, so a still screen produces no frames at all. Anything needing a
  constant rate drives its own clock and computes how many writes are *owed* from elapsed time.
- Frames never go per-pixel through Dart: libc `memcpy` into a `pw_buffer`, or one bulk copy
  plus `ImageDescriptor.raw`.

## Exercising it

```sh
dart compile exe tool/screencast_spike.dart -o /tmp/spike

WAYLAND_DISPLAY=wayland-99 /tmp/spike --capture   # frames from each output
WAYLAND_DISPLAY=wayland-99 /tmp/spike --portal    # the real backend, auto-accepting

python3 tool/portal_client_test.py                # drives the portal contract
```
