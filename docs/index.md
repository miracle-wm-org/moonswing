# Graceful Shell

**The shell of your dreams, built with Flutter.**

Graceful Shell is a Wayland panel and desktop shell for Linux, designed for use with [Miracle WM](https://github.com/miracle-wm-org/miracle-wm). It provides a customizable panel with widgets for workspaces, media playback, system monitoring, notifications, and more — all configured through a single TOML file.

## Features

- **Multiple panels** — Place panels on any edge (top, bottom, left, right) of any monitor
- **Rich modules** — Workspaces, media player, volume, battery, weather, clock, dock, notifications, and system monitor
- **Theming** — Full color and font customization
- **Dynamic backgrounds** — Image and video wallpapers with time-of-day scheduling and crossfade transitions
- **Zero-config startup** — Works out of the box with sensible defaults

## Quick Start

Install Graceful Shell and run it. On first launch, a default configuration file is written to:

```
~/.config/graceful-shell/config.toml
```

Edit that file to customize your panels, modules, and theme. See the [Configuration Overview](configuration/index.md) for details.

## Navigation

| Section | Description |
|---|---|
| [Installation](installation.md) | Build and install Graceful Shell |
| [Configuration Overview](configuration/index.md) | How the config file works |
| [Panels & Layout](configuration/panels.md) | Define panels and arrange modules |
| [Modules](configuration/modules.md) | Per-module settings |
| [Theme](configuration/theme.md) | Colors and fonts |
| [Background](configuration/background.md) | Wallpapers and videos |
| [Full Example](configuration/example.md) | Complete config.toml example |
