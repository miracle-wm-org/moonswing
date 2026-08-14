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

FYI! The snap cannot install the PAM service file for you.

- **The PAM service file.** `/etc/pam.d/graceful-shell` needs root, so the lock
  screen falls back to the system `login` service — it still authenticates, it
  just attributes unlock attempts to `login` in the auth logs.

## Local Install

### Dependencies

- `libgtk3`
- `gtk-layer-shell`
- `libasound2-dev`
- `libmpv-dev`

On Ubuntu 26.04:

```sh
sudo apt install libgtk-3-dev libgtk-layer-shell-dev libasound2-dev libmpv-dev
```

You will also need Flutter:

```sh
sudo snap install flutter --classic
flutter channel master
flutter upgrade
flutter config --enable-windowing
```

Some dependencies are needed for the runtime to work properly, but they
are not necessary if you plan to to not use these features:

```sh
sudo apt install libgtk-session-lock0  # Lock screen
```

### Building

Build and install to `~/.local` (default), or to a custom prefix:

```sh
make install
make install PREFIX=/usr/local
```

Then run:

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
flutter run
```
