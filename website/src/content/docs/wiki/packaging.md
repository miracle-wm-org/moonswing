---
title: Packaging
description: Why the snap is classic, what it stages, and how portal registration is split in two.
sidebar:
  order: 8
---

Moonswing ships as a **classic** snap, built from every commit on `main` and every release tag
by `.github/workflows/snap.yml`. Classic confinement puts the host's libraries on the
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

## Releases and channels

The channel is decided by what was pushed, and the version by the same fact:

| Pushed | Version | Grade | Published to |
|---|---|---|---|
| a commit on `main` | `<last release>+git<n>.<sha>` | `devel` | Snap Store `edge`, and the rolling `nightly` GitHub release |
| a `v*` tag | the tag, less its `v` | `stable` | Snap Store `stable` |

`snapcraft.yaml` has no `version:` or `grade:` of its own; the part's `override-pull` sets both
from `git describe`, which is why the workflow checks out full history. The store refuses a
`devel` grade on `stable`, so a release is cut by tagging a commit — `git tag v0.2.0 && git push
origin v0.2.0` — never by editing the file.

Uploads authenticate with the repository secret `SNAPCRAFT_STORE_CREDENTIALS`, exported by an
account that holds the `moonswing` name:

```sh
snapcraft export-login --snaps=moonswing \
  --acls package_access,package_push,package_update,package_release \
  --expires 2027-10-09 moonswing.creds
```

The contents of `moonswing.creds` go in **Settings › Secrets and variables › Actions** as
`SNAPCRAFT_STORE_CREDENTIALS`; the publish job runs in the `snap-store` environment, which can
be given required reviewers or hold the secret itself. The credentials expire, and an expired
one fails the publish job, not the build.

A classic snap's uploads are held for manual review until the store has granted the name
classic confinement, which is requested once on the
[snapcraft forum](https://forum.snapcraft.io/c/store-requests/19).
