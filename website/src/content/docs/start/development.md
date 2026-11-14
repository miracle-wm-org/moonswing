---
title: Development
description: Running from a checkout, tests, and the parts that need a live compositor.
sidebar:
  order: 3
---

Run inside a nested compositor (a second miracle-wm, Miriway or Sway on its own
`WAYLAND_DISPLAY`) — the shell takes over the panels, wallpaper and portal of whatever
session it runs in.

```sh
flutter run -d linux
flutter analyze
flutter test                         # or: flutter test test/widget_test.dart
```

## Capture and portals

The capture, screencast and input-capture stack needs a live compositor, so it is driven by a
standalone binary:

```sh
dart compile exe tool/screencast_spike.dart -o /tmp/spike
WAYLAND_DISPLAY=wayland-99 /tmp/spike --capture         # frames from each output
WAYLAND_DISPLAY=wayland-99 /tmp/spike --portal          # ScreenCast backend, auto-accepting
WAYLAND_DISPLAY=wayland-99 /tmp/spike --input-capture   # InputCapture backend, auto-accepting
python3 tool/portal_client_test.py
python3 tool/input_capture_client_test.py
```

PulseAudio: `dart run tool/pulse_spike.dart` (`MOONSWING_PULSE_LOG=1` to log).

## Profiling

Impeller is off by default (set in `linux/runner/my_application.cc`). To measure with it on:

```sh
flutter build linux --profile
MOONSWING_IMPELLER=1 ./build/linux/x64/profile/bundle/moonswing
```

## Contributing

Code conventions and architecture are in
[`CLAUDE.md`](https://github.com/miracle-wm-org/moonswing/blob/main/CLAUDE.md).
