---
title: Packaging
description: Why the snap is classic, what it stages, and how portal registration is split in two.
sidebar:
  order: 8
---

Graceful Shell ships as a **classic** snap, built nightly from `main` by
`.github/workflows/nightly-snap.yml`. Classic confinement puts the host's libraries on the
loader path, and `LD_LIBRARY_PATH` only *prepends* `$SNAP` — which is the constraint everything
below follows from.

## Stage a library only when the host cannot be trusted to have a compatible one

`libgtk-layer-shell0`, `libmpv1`, `libpulse0` and `libasound2` are staged. The GL/EGL/GBM/DRI
set, `libpipewire`, `libpam`, `libudev`, `libwayland-client` and `libdbus` are excluded in
`prime:` — a bundled core22 Mesa against host DRI drivers gives
`libEGL fatal: did not find extension DRI_Mesa version 1`.

Staging is only half the job. Debian keeps `pulseaudio/`, `blas/` and `lapack/` out of the
triplet directory, with the soname link made by a maintainer script snapcraft never runs, so
each must be named in `environment:`. BLAS and LAPACK cannot simply be excluded either:
`DT_NEEDED` aborts start-up rather than falling back.

**`libgtk-session-lock` is built from source and stages no GTK.** core22 has no package for it,
and without it Lock silently does nothing. It is dlopened into a process that already has the
host GTK3 mapped, so staging `libgtk-3-0` would put a second GTK in that address space.

## Portal registration is split in two halves, neither droppable

`portals.conf(5)` directory precedence beats file specificity. So the root hooks write a machine
default under `/usr/share`, and `snap/local/graceful-shell-wrapper` writes the per-user copy
that alone can out-rank an existing preference.

Both write `miracle-wm-portals.conf` *and* `mir-portals.conf`, because `XDG_CURRENT_DESKTOP` is
`miracle-wm:mir`.

Hooks are marker-guarded with `# graceful-shell-snap-managed` — anything without that marker is
never rewritten or deleted — and never fatal: a non-zero `install` hook aborts `snap install`,
and `/usr` may be read-only.

**The wrapper `try-restart`s xdg-desktop-portal once per revision**, gated on a `SNAP_REVISION`
stamp, because the frontend reads `.portal` files only at start-up. `try-restart` so that a
session with no systemd user instance is not forced to start one, and the frontend only, never
the backends. It never overwrites a conf it did not write.

## The Flutter revision is pinned

Cloning `master` at HEAD once broke the release artifact overnight.
`.github/workflows/flutter-master.yml` is the early warning, and the pin is only ever bumped to
a revision that workflow has proven green.
