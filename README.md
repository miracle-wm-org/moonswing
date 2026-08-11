# Graceful

A largely AI-coded, very unserious, just for funzies desktop
environment for Linux, built entirely in Flutter.

The purpose of this project is to:

1. Stress test Flutter
2. Explore the bounds of building new desktops for Wayland
3. Experiment with new Wayland protocols, portals, and everything else
4. Have fun and build something fun

**Use this project at your own risk!** This project will never have real
releases and may be entirely unstable. The nightly snap will be the only
supported packaging from my end. The config format is subject to change
at any time.

![Graceful Shell demo](demo.png)

## Install

One command installs the latest nightly snap (amd64):

```sh
curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/graceful-shell/main/install.sh | sh
```

It downloads the newest `graceful-shell_*.snap` from the [nightly release](https://github.com/miracle-wm-org/graceful-shell/releases/tag/nightly)
and installs it with `--classic` (the shell needs full access to the Wayland
compositor) and `--dangerous` (the file is downloaded, not store-signed). It
asks for `sudo` because `snap install` needs root. Then run:

```sh
graceful-shell
```

Re-run the same command to update, and to remove:

```sh
sudo snap remove graceful-shell
```

Prefer to do it by hand? Download the `.snap` from that release page and:

```sh
sudo snap install ./graceful-shell_*.snap --classic --dangerous
```

### What the snap brings, and what it doesn't

The snap bundles `libgtk-session-lock` and the wallpapers, so the lock screen and
the wallpaper work out of the box — you do not need anything from
[Dependencies](#dependencies) below, which is a build-from-source list. So does
**screen sharing**: the install hook registers the ScreenCast portal backend
machine-wide, the first run adds the per-user half, and the shell restarts
`xdg-desktop-portal` itself so both are picked up — no follow-up commands. `sudo
snap remove` undoes all of it. If you already have an
`~/.config/xdg-desktop-portal/*-portals.conf` naming a different ScreenCast
backend, that file is your choice and is left alone; the shell says so on
start-up and tells you the one line to change.

One thing it cannot install for you:

- **The PAM service file.** `/etc/pam.d/graceful-shell` needs root, so the lock
  screen falls back to the system `login` service — it still authenticates, it
  just attributes unlock attempts to `login` in the auth logs.

Everything else — PipeWire, PAM, udev, D-Bus, icon themes, the `Ubuntu Sans` font,
and the helper binaries the audio and System panes shell out to (`pw-metadata`,
`speaker-test`, `lspci`) — comes from the host, which is what classic confinement
is for.

## Dependencies

**Only needed to build from source** — skip this whole section if you installed
the snap.

### Build

- `libgtk3`
- `gtk-layer-shell`
- `libasound2-dev`
- `libmpv-dev`

On Ubuntu 26.04:

```sh
sudo apt install libgtk-3-dev libgtk-layer-shell-dev libasound2-dev libmpv-dev
```

You also need the [Flutter SDK](https://docs.flutter.dev/get-started/install/linux)
on the `master` channel:

```sh
flutter channel master
flutter upgrade
```

### Runtime

Each of these gates one feature; without it the shell runs normally and only
that feature is unavailable.

- **Lock screen** — `libgtk-session-lock0` (the `ext-session-lock-v1`
  implementation) and `libpam0g` (password verification, part of the base system
  so already installed). Both are loaded with `dlopen`, so the shell builds and
  runs fine without them. Your compositor must also implement
  `ext-session-lock-v1` (Mir/Miracle does).

  ```sh
  sudo apt install libgtk-session-lock0
  ```

- **Screen sharing** — **PipeWire 1.0+** (already running on any current
  desktop) and a compositor implementing `ext-image-copy-capture-v1`
  (miracle-wm built against MirAL 5.6 or newer). Both are checked at start-up.
  `make install` registers the shell as the ScreenCast portal backend; see
  [CONFIG.md](CONFIG.md#screen-sharing).

## Building from source

One-time setup — enable Flutter's experimental windowing API:

```sh
flutter config --enable-windowing
```

Build and install to `~/.local` (default), or to a custom prefix:

```sh
make install
make install PREFIX=/usr/local
```

This copies the binary, libraries, and the default wallpapers to the prefix. Make
sure `$PREFIX/bin` is in your `PATH`. Then run:

```sh
graceful-shell
```

Optionally, install the lock screen's PAM service file (needs root, and writes
to `/etc/pam.d` rather than the prefix):

```sh
sudo make install-pam
```

Without it the lock screen falls back to the system `login` service, which works
but attributes unlock attempts to `login` in the auth logs.

To uninstall:

```sh
make uninstall
sudo make uninstall-pam   # if you installed the PAM service file
```

## Running in development

```sh
flutter run -d linux
```
