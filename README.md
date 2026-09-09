<p align="center">
  <img src="assets/graceful-banner.svg" alt="A hooded character in the graceful outfit, head-on, on a gradient background" width="720">
</p>

<h1 align="center">Graceful</h1>

<p align="center">
  A largely AI-coded, very unserious, just for funzies desktop<br>
  environment for Linux, built entirely in Flutter.
</p>

<p align="center">
  <a href="https://miracle-wm-org.github.io/graceful-shell/"><b>Website &amp; wiki</b></a> &middot;
  <a href="https://miracle-wm-org.github.io/graceful-shell/start/install/">Install</a> &middot;
  <a href="https://miracle-wm-org.github.io/graceful-shell/configuration/">Configuration</a>
</p>

The purpose of this project is to:

1. Stress test Flutter
2. Explore the bounds of building new desktops for Wayland
3. Experiment with new Wayland protocols, portals, and everything else
4. Have fun and build something fun

**Use this project at your own risk!** This project may be entirely unstable.
The snap will be the only supported packaging from my end. The config format is subject to change
at any time.

![Graceful Shell demo](demo.png)

## Install

To get the latest nightly snap (amd64):

```sh
curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/graceful-shell/main/install.sh | sh
```

Then, in your environment of choice (miracle-wm, Miriway, Sway, etc.), run:
```sh
graceful-shell
```

Re-run the same command to update, and to remove:

```sh
sudo snap remove graceful-shell
```

FYI! The snap cannot install the PAM service file for you.

- **The PAM service file.** `/etc/pam.d/graceful-shell` needs root, so the lock
  screen falls back to the system `login` service — it still authenticates, it
  just attributes unlock attempts to `login` in the auth logs.

## Building Locally

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

## Documentation

The full configuration reference is in [`CONFIG.md`](CONFIG.md), and the same content — plus
install, build and wiki pages — is published at
<https://miracle-wm-org.github.io/graceful-shell/>.

The site lives in [`website/`](website/) and is built with
[Astro](https://astro.build) and [Starlight](https://starlight.astro.build). To run it
locally:

```sh
cd website
npm install
npm run dev          # http://localhost:4321/graceful-shell/
```

Its configuration pages are generated from `CONFIG.md` and its artwork from `assets/`, so
neither is maintained twice. See [`website/README.md`](website/README.md).
