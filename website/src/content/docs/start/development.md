---
title: Development
description: Running the shell from a checkout, the test suite, and the parts that need a live compositor.
sidebar:
  order: 3
---

## Running from a checkout

```sh
flutter run -d linux
```

You will want a nested compositor rather than your own session — the shell takes over
panels, wallpaper and the portal backend for whatever session it runs in. Running a second
miracle-wm, Miriway or Sway on its own `WAYLAND_DISPLAY` gives you somewhere to iterate.

## Tests and analysis

```sh
flutter analyze
flutter test
flutter test test/widget_test.dart   # or any single file
```

The suite is large and pins the things that are easy to break silently: the module registry,
the config golden (defaults *and* how a bad value degrades), the built-in themes, the
hand-transcribed Wayland interface tables against the XML in `protocol/`, and the tap-target
tests — which tap **corners**, because a centre tap passes on every hit-testing bug they
exist to catch.

## What tests cannot reach

The capture and screencast stack needs a live compositor, so it is exercised by a standalone
binary rather than from the shell:

```sh
dart compile exe tool/screencast_spike.dart -o /tmp/spike

WAYLAND_DISPLAY=wayland-99 /tmp/spike --capture   # frames from each output
WAYLAND_DISPLAY=wayland-99 /tmp/spike --portal    # the real backend, auto-accepting

python3 tool/portal_client_test.py                # drives the portal contract
```

That the whole stack compiles as a `dart compile exe` binary is why everything below the UI
is Flutter-free on purpose.

The PulseAudio driver has its own:

```sh
dart run tool/pulse_spike.dart          # GRACEFUL_PULSE_LOG=1 for logging
```

## Profiling

```sh
flutter build linux --profile
GRACEFUL_SHELL_IMPELLER=1 ./build/linux/x64/profile/bundle/graceful_shell
```

Worth knowing before you read a frame graph: panels, overlays and the desktop surface have
**no repaint boundary of their own**, so any render object marked needing paint re-records
the whole surface picture and damages the whole output. See
[Repaint discipline](/wiki/rendering/).

## Contributing

The shell's own conventions — how to add a bar module, what a store owes its consumers, why
a `GestureDetector` always carries a `behavior:` — are in the [wiki](/wiki/architecture/) and,
at more length, in [`CLAUDE.md`](https://github.com/miracle-wm-org/graceful-shell/blob/main/CLAUDE.md)
at the root of the repository.
