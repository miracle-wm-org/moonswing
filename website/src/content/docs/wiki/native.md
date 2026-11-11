---
title: Native code, FFI and capture
description: All FFI, no C beyond the runner — how the shell talks to libwayland, PipeWire and the capture protocols.
sidebar:
  order: 6
---

`lib/native/`, `lib/wayland_ffi/`, `lib/pipewire/`, `lib/screencast/` and `lib/capture/` are
all pure `dart:ffi`. **There is no C in the repository** beyond the Flutter runner in
`linux/runner/`, which also carries the lock screen's PAM helper. `lib/native/` holds the shared dlopen
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
- **Only the non-core protocols are hand-transcribed**; core interfaces come from libwayland's
  exported `wl_*_interface` symbols. A wrong signature is memory corruption inside libwayland,
  not an exception, which is why `test/wl_interfaces_test.dart` diffs the tables against the
  XML in `protocol/`. Copy a new XML there and extend the test.
- **The compositor paces the stream, not a timer.** `ext-image-copy-capture` holds each copy
  until content changes, so a still screen produces no frames at all. Anything needing a
  constant rate drives its own clock and computes how many writes are *owed* from elapsed time.
- **A cursor sent as metadata needs buffers of its own.** In the ScreenCast portal's metadata
  cursor mode (what Chromium and Electron ask for on Linux) frames are captured without the
  pointer and every buffer carries a `SPA_META_Cursor`, read from an
  `ext_image_copy_capture_cursor_session_v1`. A pointer moving over a still screen produces no
  frame to carry it, so a move is sent in a buffer with an empty picture (`chunk.size` 0, as
  GNOME's screencast does), paced to the stream's frame rate by `CursorPacer`.
- Frames never go per-pixel through Dart: libc `memcpy` into a `pw_buffer`, or one bulk copy
  plus `ImageDescriptor.raw`.

## Input capture

The InputCapture portal backend (`lib/input_capture/`) is what DeskFlow and Input Leap use to
take this machine's keyboard and mouse while the pointer is on another computer. Nothing in the
compositor does barriers or capture for the shell, so it is built from pieces every wlroots-style
compositor has:

- **Its own Wayland connection** with surfaces of its own: a transparent one-pixel strip along
  each armed edge, and while capturing, a transparent surface on every output. Pointer focus,
  keyboard focus and pointer locks are all per-client, so these cannot share the screencast
  connection.
- **A barrier is crossed by pushing, not by arriving.** The compositor clamps the cursor to the
  screen, so the shell watches *relative* motion while the pointer is on a strip, and any push
  outward crosses.
- **Every output is covered while capturing**, not only the crossed one. The pointer lock that
  should hold the cursor still is not to be relied on — sway never grants one to a layer
  surface — and relative motion only reaches the client whose surface is under the cursor.
- **Input goes out over libeis**, dlopened like PAM. One EIS context per session; the socket
  is a raw fd, which `package:dbus` cannot send, so `lib/native/raw_fd_handle.dart` dup2s it
  onto a descriptor `dart:io` owns.
- **Super+Shift+Escape** always ends a capture and disables the session, so an application that
  hangs holding the keyboard cannot keep it.

## VPN import

Settings › Network keeps its VPNs in NetworkManager, over D-Bus — the list, the switch, adding
and removing are all `org.freedesktop.NetworkManager` calls. Importing a file is the one part
with no D-Bus call: each format is read by its own plugin, in the libnm half that `nmcli
connection import` loads, so `lib/vpn/libnm_import.dart` does what `nmcli` does, over FFI:

- **The plugin's registration, not its path.** The `.name` files under
  `/etc/NetworkManager/VPN` and `/usr/lib/NetworkManager/VPN` are read in Dart (they are also
  what decides whether a form warns that its plugin is missing); each is handed to
  `nm_vpn_plugin_info_new_from_file`, whose `load_editor_plugin` resolves the library against
  libnm's own plugin directory.
- **Every plugin is offered the file in turn**, and the first that can import it wins — a
  `.conf` is an OpenVPN file to one and nothing to the next.
- **The connection comes back as a GVariant** (`nm_connection_to_dbus`) and is walked into
  `package:dbus` values, which is what `AddConnection` is then sent. GLib is looked up through
  libnm's handle, so the walk works in `flutter_tester`, which has no GLib in the process.
- **A plugin fills in only what its format says.** The connection's type and uuid are left
  unset, as `nmcli` normalises them afterwards; the store does the same.

WireGuard files are the exception: `nmcli`'s reader for them is inside `nmcli`, so
`lib/vpn/wireguard_conf.dart` reads wg-quick's format in Dart, skipping what NetworkManager
cannot carry (`PostUp` and the like) and saying so. The public key shown beside a WireGuard
private key is X25519 in Dart (`lib/vpn/x25519.dart`), since NetworkManager never reports it.

## Exercising it

```sh
dart compile exe tool/screencast_spike.dart -o /tmp/spike

WAYLAND_DISPLAY=wayland-99 /tmp/spike --capture   # frames from each output
WAYLAND_DISPLAY=wayland-99 /tmp/spike --portal    # the real backend, auto-accepting

WAYLAND_DISPLAY=wayland-99 /tmp/spike --input-capture  # the InputCapture backend

python3 tool/portal_client_test.py                # drives the portal contract
python3 tool/input_capture_client_test.py         # InputCapture, through the frontend
```
