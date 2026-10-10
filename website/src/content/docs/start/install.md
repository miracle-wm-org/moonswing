---
title: Install
description: Install the latest Moonswing nightly snap, and start it inside a Wayland session.
sidebar:
  order: 1
---

Moonswing ships as a **classic snap**, rebuilt nightly from `main`. That snap is the
only packaging supported by the project; anything else means
[building from source](/start/build/).

:::caution[Use this at your own risk]
The shell may be entirely unstable, and the config format is subject to change at any time.
:::

## Requirements

- **amd64.** The nightly snap is built for `x86_64` only. On any other architecture,
  [build from source](/start/build/).
- **A Wayland compositor that implements `wlr-layer-shell`.** miracle-wm, Miriway and Sway
  are the ones the shell is developed against.
- **`snapd`**, and `sudo` — installing a snap needs root.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/moonswing/main/install.sh | sh
```

The script looks up the rolling `nightly` release, downloads the newest
`moonswing_*.snap` asset and installs it with `--classic --dangerous`:

- `--classic` because the shell needs unconfined access to the Wayland compositor.
- `--dangerous` because the file is downloaded from a GitHub release, not store-signed.

If you would rather do it by hand, download the asset from the
[`nightly` release](https://github.com/miracle-wm-org/moonswing/releases/tag/nightly)
and run the same command the script does:

```sh
sudo snap install ./moonswing_*.snap --classic --dangerous
```

### Start it with miracle-wm

Add `--miracle-autostart` to have miracle-wm start the shell with every session:

```sh
curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/moonswing/main/install.sh | sh -s -- --miracle-autostart
```

`MOONSWING_MIRACLE_AUTOSTART=1` does the same. The script adds this entry to the
`startup_apps` of `~/.config/miracle-wm/config.yaml`:

```yaml
startup_apps:
  - command: /snap/bin/moonswing
    restart_on_death: true
    in_systemd_scope: true
```

- `restart_on_death` brings the shell back whenever it exits, crash or not.
- `in_systemd_scope` runs it under `systemd-run --user --scope`, in a scope of its own.
- The command is an absolute path because miracle-wm runs it on the compositor's own
  `PATH`, which need not include `/snap/bin`.

An existing config is edited in place: the entry goes first in an existing
`startup_apps` list, or a new `startup_apps` key is appended, and the original is kept
alongside as `config.yaml.<timestamp>.bak`. With no config the file is created holding
only this, and every other setting keeps miracle-wm's default. If any startup app
already runs `moonswing`, the file is not touched — so re-running the command to update
is safe. A `startup_apps` written as an inline `[...]` list is not rewritten; the script
prints the entry for you to add instead.

miracle-wm reads its startup apps when it starts, so the entry takes effect from your
next login.

## Run it

From inside your compositor session — miracle-wm, Miriway, Sway, or anything else speaking
`wlr-layer-shell`:

```sh
moonswing
```

There is nothing to configure first. The shell writes a default
`~/.config/moonswing/config.toml` and a set of themes on its first start, and every
setting has a working default. From there, see the
[configuration reference](/configuration/), or open **Settings** from the bar and edit
it live.

## On a compositor other than miracle-wm

Everything that is the compositor's business rather than the shell's — workspaces, the
scratchpad, switching windows, the window manager's own key bindings — is read from
miracle-wm's IPC, and on Sway, Miriway or anything else those parts step aside:

- **The `workspaces` and `scratchpad` modules are left out of the bar**, gap and all, even
  if `config.toml` names them.
- **Alt+Tab and the two scratchpad keys are not registered**, so the compositor's own
  bindings for them keep working.
- **Screenshots and recordings offer no "window" mode** — picking a window needs
  miracle-wm's window tree.
- **The keyboard-shortcut sheet says so** in place of miracle-wm's bindings, and says when
  the compositor offers no global shortcuts at all (`ext-input-trigger-v1`) — Sway does
  not, so none of the shell's own keys reach it there.
- **Settings › Window Manager** still edits `~/.config/miracle-wm/config.yaml` when
  miracle-wm is installed, and says it is not when it is not.

The shell decides once, at start-up: `MIRACLESOCK` set, or `XDG_CURRENT_DESKTOP` naming
`miracle-wm`, is miracle-wm; any other desktop name is not. With neither, but a
`SWAYSOCK` or `I3SOCK`, it asks that socket a question only miracle-wm answers — Sway
speaks the same IPC protocol and would otherwise be mistaken for it.

## Update

Re-run the install command. `snapd` replaces the installed revision in place:

```sh
curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/moonswing/main/install.sh | sh
```

## Remove

```sh
sudo snap remove moonswing
```

Removing the snap undoes the ScreenCast portal registration it made.

## What the snap sets up, and the one thing it cannot

Screen sharing is registered for you. The snap's install hook writes the ScreenCast backend
files machine-wide, the launcher adds the per-user half on first run, and it restarts
`xdg-desktop-portal` so both are picked up. A `*-portals.conf` of your own naming a
different backend is honoured, never overwritten.

The exception is **the PAM service file**. `/etc/pam.d/moonswing` needs root and lives
outside anything a snap may write, so the lock screen falls back to the system `login`
service. It still authenticates — it just attributes unlock attempts to `login` in the auth
logs. To install it properly you need a source checkout:

```sh
sudo make install-pam
```

## Troubleshooting

**`no nightly snap for <arch>`** — the nightly is amd64-only. Build from source.

**`could not reach .../releases/tags/nightly`** — while the repository is private the
anonymous GitHub API answers `404`. Export a token and re-run:

```sh
GH_TOKEN=$(gh auth token) sh -c "$(curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/moonswing/main/install.sh)"
```

**Panels do not appear** — the compositor must implement `wlr-layer-shell`. GNOME's Mutter
does not.

**Screen sharing offers no sources** — the portal frontend caches the backend list at
start-up. `systemctl --user restart xdg-desktop-portal`, then check the shell is the
registered backend:

```sh
gdbus call --session --dest org.freedesktop.portal.Desktop \
  --object-path /org/freedesktop/portal/desktop \
  --method org.freedesktop.DBus.Properties.Get \
  org.freedesktop.portal.ScreenCast AvailableSourceTypes
```

A `0` there means the frontend cached "no backend" and needs the restart.
