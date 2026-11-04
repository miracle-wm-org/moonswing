---
title: Packaging
description: Why the snap is classic, what it stages, and how portal registration is split in two.
sidebar:
  order: 8
---

Moonswing ships as a **classic** snap, built nightly from `main` by
`.github/workflows/nightly-snap.yml`. Classic confinement puts the host's libraries on the
loader path, and `LD_LIBRARY_PATH` only *prepends* `$SNAP` — which is the constraint everything
below follows from.

## Why classic, and not strict

Strict confinement has been looked at and does not fit a shell on an ordinary distribution.
The reason is not Wayland, which is what it is usually blamed for. The `wayland` interface
reaches the compositor from inside the sandbox, and miracle-wm enables every extension it
supports for every client: there is no per-client filter in its `main.cpp`, only a TODO for one.
So layer-shell, session-lock, image-copy-capture and foreign-toplevel would all still be offered
to a confined shell. (Ubuntu Frame and Miriway *do* filter privileged extensions, so a strict
shell would need allow-listing there.)

What breaks is that a strict snap's `/` is its base (core22). The host's `/usr` is not visible
from inside it, and this shell's core jobs are about the host:

| Feature | Under strict confinement |
|---|---|
| Launcher, dock, desktop icons | The host's `.desktop` files and binaries are not in the sandbox. `desktop-launch` (super-privileged) starts **other snaps** only, so deb, Flatpak and AppImage applications cannot be launched |
| Lock screen | PAM would run core22's modules against the host's `/etc/pam.d`. This mismatch is why snapd's own `polkit-agent` interface targets Ubuntu Core only |
| polkit agent | `polkit-agent-helper-1` is a setuid host binary. The `polkit-agent` interface is super-privileged and documented as unlikely to work on classic for the PAM reason above |
| Power › Fine Tuning | Runs `pkexec`, which is setuid. Not possible in the sandbox |
| Window Manager settings, IPC | `libmiracle-wm-c` is dlopened from the host, and `~/.config/miracle-wm` is a dot directory (`personal-files`). Miracle's IPC socket is not the Wayland socket, and the `wayland` interface grants exactly `wayland-N` |
| Portal registration | Hooks run confined and cannot write the host's `/usr/share/xdg-desktop-portal`. The per-user half needs `personal-files` |
| Notifications, tray, portal bus names | Owning each one needs a `dbus` slot, which needs a store declaration |
| App scopes, portal restart, journal, `pw-metadata`, `speaker-test` | These are calls into the host's systemd user manager or host tools. No interface grants them |
| Recording, clipboard, fonts, `df`, `fortune` | The host's `ffmpeg`, `wl-clipboard` and so on are invisible. They could be staged, at the cost of size |

`devmode` is no escape hatch either. It relaxes AppArmor but keeps the core22 mount namespace,
so every row above that comes from missing host files still applies, and a devmode snap cannot
be published to `stable`.

The one setting where strict confinement is coherent is a system where **every application is
itself a snap**: the Ubuntu Core Desktop model, where `ubuntu-desktop-session` runs GNOME Shell
confined. Even there it needs `desktop-launch`, `polkit-agent`, `personal-files` and `dbus`
slots, all super-privileged and each granted by store review. It would also need code changes:
reading the snap desktop files under `/var/lib/snapd/desktop/applications` and launching through
userd. That would be a separate snap under its own name, since confinement belongs to the snap
and not to the install. Until then, the shell's sandbox is the session itself, as it is for every
other compositor's shell.

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
default under `/usr/share`, and `snap/local/moonswing-wrapper` writes the per-user copy
that alone can out-rank an existing preference.

Both write `miracle-wm-portals.conf` *and* `mir-portals.conf`, because `XDG_CURRENT_DESKTOP` is
`miracle-wm:mir`.

Hooks are marker-guarded with `# moonswing-snap-managed` — anything without that marker is
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
