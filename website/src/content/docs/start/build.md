---
title: Build from source
description: Dependencies, Flutter setup, and installing Moonswing to a prefix.
sidebar:
  order: 2
---

## Dependencies

Ubuntu 26.04:

```sh
sudo apt install libgtk-3-dev libgtk-layer-shell-dev libasound2-dev libmpv-dev
```

Optional, loaded at run time — each feature is unavailable without its library:

| Package | Needed for |
|---|---|
| `libgtk-session-lock0`, `libpam` | the lock screen |
| `libeis1` | input capture (Deskflow, Input Leap) |
| `libnm0` | importing a VPN file (OpenVPN and PPTP also need their `NetworkManager-*` plugin) |
| `power-profiles-daemon` or `tuned-ppd` | Settings › Power modes |

## Flutter

Moonswing uses Flutter's experimental windowing API on the `master` channel:

```sh
sudo snap install flutter --classic
flutter channel master
flutter upgrade
flutter config --enable-windowing   # once per machine; the build fails without it
```

:::note[Build fails with `Type 'X' not found` in `_window.dart`?]
Flutter `master` renamed a windowing API. Bump the
[`layer_shell`](https://github.com/mattkae/layer_shell.dart) pin in `pubspec.yaml` to a
revision that builds, then apply the same rename here.
:::

## Build and install

```sh
make install                    # to ~/.local
make install PREFIX=/usr/local  # or elsewhere
```

This installs the bundle to `$PREFIX/lib/moonswing`, wallpapers to `$PREFIX/share/moonswing`,
a `moonswing` launcher to `$PREFIX/bin` (put it on your `PATH`), and registers the portal
backend. To build only: `make build`.

### Outside the prefix

**Portal backend** (`make install-portal`, run by `make install`) — installs
`moonswing.portal` under `XDG_DATA_HOME`, and a `mir-portals.conf` under `XDG_CONFIG_HOME`
unless you already have one. If you do, add:

```ini
[preferred]
org.freedesktop.impl.portal.ScreenCast=moonswing
org.freedesktop.impl.portal.InputCapture=moonswing
```

Then `systemctl --user restart xdg-desktop-portal`.

**PAM service** — `sudo make install-pam` writes `/etc/pam.d/moonswing`. Without it the lock
screen uses the `login` service.

## Uninstall

```sh
make uninstall
sudo make uninstall-pam
```

`mir-portals.conf` is left in place.
