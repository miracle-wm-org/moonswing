# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
# Enable Flutter's experimental windowing API (one-time setup)
flutter config --enable-windowing

# Run in development mode
flutter run -d linux

# Build release bundle
flutter build linux --release
# or equivalently:
make build

# Install to ~/.local (default) or a custom prefix
make install
make install PREFIX=/usr/local

# Analyze / lint
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart
```

System dependencies required at build time: `libgtk3`, `gtk-layer-shell`, `libasound2-dev`, `libmpv-dev`.

## Architecture

Graceful Shell is a **Flutter Linux desktop application** that renders Wayland layer-shell panels (taskbars) and an optional wallpaper window using GTK and the `gtk-layer-shell` library.

### Startup flow (`lib/main.dart`)

1. All `Module` subclasses are registered in the global registry.
2. `AppConfig.load()` reads `~/.config/graceful-shell/config.toml`, calls `Module.loadAll()` to push per-module config into each registered module, and returns typed config objects.
3. A `MiracleConnection` is opened for Miracle WM IPC (workspace events).
4. Wayland outputs are enumerated via `WaylandClient` to correlate with GDK monitors.
5. Flutter's experimental multi-window API (`ExtendedWindowingOwnerLinux`) creates one `LayershellWindowController` per panel per monitor and optional background controllers.
6. `runWidget` builds a `ViewCollection` containing all layer-shell windows wrapped in their scope providers.

### Module system (`lib/module.dart`, `lib/modules/`)

`Module` is an abstract class with three responsibilities:
- `configKey` — unique string key matching the TOML `[modules.<key>]` section.
- `loadConfig(map)` — called once at startup with the module's TOML subtable.
- `builder` — a `WidgetBuilder` that returns the widget rendered inside the panel.

Modules are registered before config is loaded (`Module.register(...)` in `main()`) and retrieved by name at render time (`Module.lookup(name)`). Adding a new module means subclassing `Module`, implementing these three members, and calling `Module.register()` in `main.dart`.

### Layer-shell windowing (`lib/layer_shell.dart`)

This file bridges Flutter's internal windowing API (imported via `implementation_imports`) with `gtk-layer-shell`:

- **`LayershellWindowController`** — wraps `RegularWindowControllerLinux` and applies layer-shell properties (anchor edges, layer, exclusive zone, monitor) immediately after GTK window creation, before Flutter presents the window.
- **`PopupGtkWindowController`** — creates freestanding GTK windows on the `overlay` layer, positioned with top+left anchors and margins derived from the parent widget's screen rect.
- **`DynamicLayerShellViews`** — a singleton `ChangeNotifier` for adding/removing layer-shell views at runtime (used by the notifications module).
- **`PopupHost` mixin** — reusable `State` mixin that manages a single popup window lifecycle; modules that open popups (e.g. `SoundControl`) mix this in.
- **`PopupBounceIn`** — scale+fade animation widget used inside popup content.

### Scopes (`lib/scopes.dart`)

Four `InheritedWidget` scopes are provided around every panel's widget tree:

| Scope | Provides |
|-------|----------|
| `ThemeScope` | `ThemeConfig` (colors, font) |
| `MiracleScope` | `MiracleConnection` (workspace IPC) |
| `DisplayScope` | `WaylandOutput` (the monitor this panel is on) |
| `BarScope` | `anchor` string (`'top'`, `'bottom'`, `'left'`, `'right'`) |

### GTK FFI (`lib/gtk.dart`)

Raw FFI bindings for GTK3 and `gtk-layer-shell`. Provides `GtkWindow`, `GdkDisplay`, `FlView`, and `FlWindowMonitor` wrappers. This code is adapted from Flutter's internal Linux windowing implementation and wraps the C API used by `LayershellWindowController`.

### Configuration (`lib/config.dart`)

`AppConfig.load()` reads TOML and produces:
- `Map<String, PanelConfig>` — one entry per named panel section.
- `ThemeConfig` — colors and font parsed from `[theme]`.
- `BackgroundConfig?` — optional wallpaper config from `[background]`.

If the config file is absent, a default two-panel layout is written to disk and defaults are used. Parse errors fall back silently to defaults.

### Notification service (`lib/notification_service.dart`)

Implements the FreeDesktop `org.freedesktop.Notifications` D-Bus interface via the `dbus` package. `startNotificationService()` registers on the session bus so the shell receives desktop notifications, which the `NotificationsModule` displays.

### Background window (`lib/background.dart`)

Renders a full-screen wallpaper with time-of-day scheduling and crossfade transitions using `media_kit` for video support. One background window is created per monitor.
