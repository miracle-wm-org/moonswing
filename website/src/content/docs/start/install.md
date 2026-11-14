---
title: Install
description: Install the nightly snap and start Moonswing in a Wayland session.
sidebar:
  order: 1
---

Moonswing ships as a classic snap, rebuilt nightly from `main`. It is the only supported
packaging; otherwise [build from source](/start/build/).

You need:

- an **amd64** machine;
- a Wayland compositor with **`wlr-layer-shell`** — miracle-wm, Miriway or Sway (not GNOME);
- **`snapd`** and `sudo`.

## Install or update

```sh
curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/moonswing/main/install.sh | sh
```

The script downloads the newest snap from the
[`nightly` release](https://github.com/miracle-wm-org/moonswing/releases/tag/nightly) and runs
`snap install --classic --dangerous` (it is not store-signed). Re-run it to update.

### Start it with miracle-wm

```sh
curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/moonswing/main/install.sh | sh -s -- --miracle-autostart
```

This adds Moonswing to `startup_apps` in `~/.config/miracle-wm/config.yaml`, restarted if it
exits, from your next login. Your old config is kept as `config.yaml.<timestamp>.bak`; an
existing `moonswing` entry is left alone.

## Run

From inside your compositor session:

```sh
moonswing
```

The first start writes `~/.config/moonswing/config.toml` and the shipped themes. Edit them, or
open **Settings** from the bar — changes apply live. See the [configuration reference](/configuration/).

## Without miracle-wm

Features that drive miracle-wm's IPC step aside on other compositors:

- the `workspaces` and `scratchpad` modules are left off the bar;
- Alt+Tab and the scratchpad shortcuts are not registered, so the compositor keeps those keys;
- screenshots and recordings have no "window" mode;
- the shortcut sheet shows only the shell's own keys. On a compositor without
  `ext-input-trigger-v1` (Sway), no shell shortcut works.

## Remove

```sh
sudo snap remove moonswing
```

## Lock screen PAM file

A snap cannot write `/etc/pam.d`, so the lock screen authenticates through the system `login`
service instead. That works; unlock attempts are just logged as `login`. To install the
dedicated service, from a source checkout:

```sh
sudo make install-pam
```

## Troubleshooting

- **`no nightly snap for <arch>`** — amd64 only; build from source.
- **No panels** — the compositor lacks `wlr-layer-shell`.
- **Screen sharing offers no sources** — the portal frontend caches its backends at start-up.
  Restart it:

  ```sh
  systemctl --user restart xdg-desktop-portal
  ```
