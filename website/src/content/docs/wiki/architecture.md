---
title: Architecture
description: How Moonswing starts, what it registers, and the scopes every surface reads from.
sidebar:
  order: 1
---

Moonswing is one Flutter process that draws an entire session: `wlr-layer-shell`
panels, a wallpaper and desktop-icon surface, full-screen overlays, popups, an on-screen
display and a lock screen. It is also the session's notification daemon, its
StatusNotifierItem tray host, its `xdg-desktop-portal` ScreenCast backend, its polkit
authentication agent and its session locker.

It is built on Flutter's experimental windowing API, tracking `master`.

## Startup

`main()` is split by `runWidget`, and which side of that line a piece of work sits on is the
design.

**Above `runWidget`:** module registration, `AppConfig.load()`, and the theme, desktop and
stats config reads. Every native window's geometry comes out of them, so they have to have
happened before the first window exists.

**Below it**, from a post-frame callback, `ShellServices` runs everything else — outputs,
shortcuts, the miracle-wm IPC connection, notifications, tray, PulseAudio, backlight,
ScreenCast, polkit, the logind inhibitor and the app index — each on its own event-loop
turn. Registration order is turn order, so I/O-bound tasks go first and the FFI-heavy app
index last. Consumers read `ShellServicesScope` and show a loader until a `ServiceStatus`
settles.

### Services throw; `run()` records

The distinction a service has to get right:

- A **genuine failure** — bus unreachable, a missing protocol — propagates, and the service
  settles `failed`.
- A **graceful decline** — another daemon already owns the name, a feature switched off —
  logs and returns, settling `ready`.

A service that swallows its own failures makes a loader resolve with the feature dead
behind it.

### Panels paint before the shell knows where they are

A consequence of that split: output enumeration is a service, so panels exist before the
shell knows which display each one is on. `DisplayScope.output` is therefore nullable, and a
panel is matched to its output by **connector name** first — GDK's connector name and
`wl_output.name` are the same string, and neither moves when the user rearranges displays —
then by a make/model/position tuple, with a first-output fallback only when there is exactly
one output.

## Scopes

| Scope | Provides |
|---|---|
| `ThemeScope` | `ThemeConfig` — never constructed directly; see `ThemeProvider` |
| `ShellServicesScope` | how far along each global start-up task is |
| `LiveConfigScope` | `AppConfig` as the user is editing it; see `LiveConfigProvider` |
| `MiracleScope` | `MiracleConnection` (workspace IPC) |
| `DisplayScope` | `WaylandOutput?` — null until enumeration lands; see `DisplayProvider` |
| `BarScope` | anchor string (`'top'` / `'bottom'` / `'left'` / `'right'`) |

The first three go on **every** window, paired once with `ShellTextRoot` and
`kExcludeSemantics`.

Three of them are **provider-only** — `ThemeScope`, `DisplayScope` and `LiveConfigScope` are
constructed by exactly one provider each and nowhere else. Each provider is a
`ListenableBuilder` that emits the scope and passes `child` through **unrebuilt**. Resolving
any of them in the root's `build` instead is what once made a single output landing, or a
single settings keystroke, rebuild every panel on every monitor plus the backgrounds, the OSD
and the overlays.

The `_refreshWindows()` calls left in the root are the places where its *list of native
windows* changed. Those cannot be a scope: an `InheritedWidget` cannot span FlutterViews.

## Configuration

`AppConfig.load()` reads `~/.config/moonswing/config.toml` into typed objects, writing a
default layout if the file is absent. `ConfigStore.instance` is the live writable view the
settings UI mutates, with a debounced atomic write behind it.

Every field read goes through `TomlReader`, and its invariant is the one rule of that layer:

> **A wrongly-typed value costs that key, never the whole table.**

A throw out of any `fromMap` — a module's included, since `Module.loadAll` runs inside
`AppConfig.fromMap` — would make `load` discard the user's entire config. So readers
type-test and coerce (`height = 32.0` is a TOML float), treat NaN and infinity as absent, and
clamp through `min:`/`max:`; never a bare `as X?` cast. Only a TOML *syntax* error still costs
the file, and that path logs.

The same degrade-per-field discipline applies to everything from outside: an unknown enum
from a web API, a tree that will not parse, a bad row in a shipped table. It costs that row,
never the surface.

Every section class carries value equality, which is load-bearing rather than tidy: the
getter mints a fresh object graph per read and the store notifies on every keystroke, so
without `==` the notifier behind `LiveConfigScope` could never refuse one.

## Where things live

| Directory | Responsibility |
|---|---|
| `modules/` | Bar modules — one file per `[modules.<key>]` strip |
| `desktop/` | Desktop grid: layout maths, store, surface, icons, menus, `widgets/` |
| `overlay/` | The settings/calendar/system overlay, the shared form controls, the file picker |
| `miracle_config/` | The compositor's own configuration: store, evdev key table, enum labels |
| `theme/` | `ThemeConfig`, `ThemeStore`, `ThemeProvider`, built-in themes, tokens, fonts |
| `launcher/`, `emoji/` | The two search overlays: index, pure ranking, controller, card |
| `weather/`, `moon/`, `media/`, `fortune/`, `tux/`, `clock/` | Data layers behind a bar module and/or desktop widget |
| `system/` | UI-free `/proc` and `/sys` sampling |
| `timers/` | Countdowns and stopwatches |
| `osd/` | The volume/brightness card, its store and its sources |
| `capture/` | Screenshots and recording: targets, selection, ffmpeg, store |
| `screencast/` | The ScreenCast portal backend, capture sessions, the consent picker |
| `polkit/`, `power/`, `lock/` | Authentication agent, power-key policy and menu, session lock |
| `native/`, `wayland_ffi/`, `pipewire/` | dlopen plumbing, libwayland bindings, libpipewire + SPA |
| `input_trigger/`, `keyboard/` | Compositor global shortcuts; keyboard layout over locale1 |
| `keybinds/` | The cheat sheet behind the bar's keyboard icon — the compositor's bindings, read only, and the shell's own, editable in place |
