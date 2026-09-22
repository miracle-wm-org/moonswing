---
title: Build from source
description: Dependencies, Flutter setup, and installing Moonswing to a prefix.
sidebar:
  order: 2
---

Building is how you get Moonswing on a non-amd64 machine, on a distribution without
`snapd`, or with a change of your own in it.

## Dependencies

Build-time:

- `libgtk3`
- `gtk-layer-shell`
- `libasound2-dev`
- `libmpv-dev`

On Ubuntu 26.04:

```sh
sudo apt install libgtk-3-dev libgtk-layer-shell-dev libasound2-dev libmpv-dev
```

Two more are needed only at runtime, and only by the lock screen. Both are `dlopen`ed, so
the shell builds and runs without them — Lock simply does nothing:

```sh
sudo apt install libgtk-session-lock0   # plus libpam, which you already have
```

## Flutter

The shell is built on Flutter's **experimental windowing API** and tracks the `master`
channel, which renames those APIs without notice.

```sh
sudo snap install flutter --classic
flutter channel master
flutter upgrade
flutter config --enable-windowing
```

`flutter config --enable-windowing` is a one-time, machine-wide setting. Without it the
build fails: every surface the shell draws is a native window.

:::note[If the build fails inside `_window.dart`]
A `Type 'X' not found` there is Flutter `master` having renamed a windowing API. The fix is
upstream-first: bump the [`layer_shell`](https://github.com/mattkae/layer_shell.dart) pin in
`pubspec.yaml` to a revision that builds, then apply the same rename here. The
`flutter-master.yml` workflow exists to catch this before a release does.
:::

## Build and install

```sh
make install                    # to ~/.local
make install PREFIX=/usr/local  # or anywhere else
```

`make install` builds the release bundle, copies it to `$PREFIX/lib/moonswing`, installs
the default wallpapers to `$PREFIX/share/moonswing`, writes a `moonswing` launcher
into `$PREFIX/bin`, and registers the ScreenCast portal backend. Make sure `$PREFIX/bin` is on
your `PATH`, then:

```sh
moonswing
```

To build without installing:

```sh
flutter build linux --release   # or: make build
```

## The two targets that write outside the prefix

### The PAM service file

```sh
sudo make install-pam
```

Writes `/etc/pam.d/moonswing`. It needs root, and writes to `/etc/pam.d` rather than the
prefix, which is why it is a separate target. Without it the lock screen falls back to the
system `login` service: it still authenticates, it just attributes unlock attempts to `login`
in the auth logs.

### The ScreenCast portal backend

```sh
make install-portal
```

Run by `make install` already. It is separate because `xdg-desktop-portal` discovers backends
through `XDG_DATA_HOME` and `XDG_CONFIG_HOME`, never through `PREFIX` — a custom prefix cannot
move them. It installs `moonswing.portal` and, if you have no `mir-portals.conf` of your
own, one naming the shell as the preferred ScreenCast backend. An existing file is kept, and
the target prints what to add to it:

```ini
[preferred]
org.freedesktop.impl.portal.ScreenCast=moonswing
```

Then pick it up:

```sh
systemctl --user restart xdg-desktop-portal
```

There is deliberately **no D-Bus activation file**: the shell owns the name from session
start, and screen sharing should not be able to start the shell.

## Uninstall

```sh
make uninstall
sudo make uninstall-pam   # if you installed the PAM service file
```

`make uninstall` removes the binary, the app directory and the portal registration file. It
leaves `mir-portals.conf` in place — that one is user configuration.

## Rendering backend

Impeller's GLES backend is the engine's Linux default, and is switched **off in the runner**
(`linux/runner/my_application.cc`) rather than on the command line — `--no-enable-impeller`
reaches the engine as an environment variable, which cannot help a snap or a `make install`
build. To measure with Impeller on:

```sh
flutter build linux --profile
MOONSWING_IMPELLER=1 ./build/linux/x64/profile/bundle/moonswing
```

This is expected to be temporary; it is worth re-measuring after an engine bump.
