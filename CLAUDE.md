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
- **`LayerShellHost` mixin** (`lib/popup.dart`) — reusable `State` mixin for modules that open a full layer-shell window (panel/overlay/dialog) at runtime. The module creates the `LayershellWindowController` and hands it to `openLayerWindow`, which registers a `WindowEntry` into the panel's `WindowRegistry` (supplied by the per-panel `WindowManager` in `main.dart`); `closeLayerWindow` unregisters and destroys it. Used by the notifications, clock, and system modules. This is the same `WindowManager`/`WindowRegistry` path popups use — there is no separate runtime-view registry.
- **`PopupHost` mixin** (`lib/popup.dart`) — reusable `State` mixin that manages a single popup window lifecycle; modules that open popups (e.g. `SoundControl`) mix this in.
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

### System tray service (`lib/status_notifier_service.dart`, `lib/dbus_menu.dart`)

Implements the freedesktop/KDE **StatusNotifierItem (SNI)** system tray. `startStatusNotifierService()` (called from `main.dart` right after `startNotificationService()`) makes the shell own `org.kde.StatusNotifierWatcher` on the session bus and register itself as a `StatusNotifierHost`, so tray applications (Discord, Steam, network/VPN applets, etc.) attach to it. Each registered item is tracked via a `DBusRemoteObject` — its icon/title/status/menu properties are read and kept live through the item's `NewIcon`/`NewStatus`/… change signals — and published through the `TrayStore` singleton (`ChangeNotifier`, same pattern as `NotificationStore`). Item removal is detected via `nameOwnerChanged`. Like the notification daemon, it fails silently if another tray watcher already owns the name.

`lib/dbus_menu.dart` is the client for the `com.canonical.dbusmenu` protocol: it fetches an item's context menu (`GetLayout`) into a `MenuNode` tree and reports clicks (`Event`). Icons arrive either as themed names (rendered with `XdgIcon`) or as raw ARGB32 pixmaps (decoded to a Flutter `ui.Image`).

The `SystemTrayModule` (`lib/modules/system_tray.dart`, `configKey = 'system_tray'`, in the default top panel) renders the icons in a condensed, overlapping strip that spreads apart on hover; clicking an icon opens that app's menu in a themed popup (via `PopupHost`). Config options under `[modules.system_tray]`:

| Key | Type | Default | Meaning |
|-----|------|---------|---------|
| `icon_size` | number | `16` | Rendered icon width/height (logical px). |
| `collapsed_overlap` | number | `10` | How far each icon overlaps its neighbour at rest. |
| `expanded_spacing` | number | `6` | Gap between icons when the strip is hovered. |
| `hidden_items` | string list | `[]` | SNI `Id` or `Title` values to hide from the tray. |

### The overlay (`lib/overlay/`)

Clicking the clock opens a full-screen layer-shell overlay (`lib/overlay/overlay.dart`, class `SettingsOverlay`) — a blurred backdrop over a fixed 800x560 panel with **top tabs**. Adding a tab means one entry in the top-level `_tabs` list plus one child in the `IndexedStack` that builds the body.

The body is an `IndexedStack`, not a `switch`: the settings tab hosts `ShellSettingsPage`, which owns a nested `Navigator`, and rebuilding the body on every tab change would tear it down and drop the user back to the category landing page.

- **`lib/overlay/settings/`** — the settings tab: a sidebar (Network / Bluetooth / Display / Audio / Shell) over one page per category. `controls.dart` holds the themed form controls (`SettingsSection`, `SettingsRow`, `SettingsTextField`, `SettingsIconButton`, …) shared with the calendar tab.
- **`lib/overlay/calendar/`** — the calendar tab, described below.

`lib/config_store.dart` (`ConfigStore.instance`) is the live, writable view of `config.toml` that the settings UI mutates; it is a `ChangeNotifier` with a debounced atomic write.

### Calendar (`lib/overlay/calendar/`)

The Calendar tab shows a month grid (usable with no account connected), an agenda for the selected day, and a pane for connecting an account.

| File | Responsibility |
|------|----------------|
| `month.dart` | Pure month math — `buildMonthGrid` returns a fixed 6x7 `MonthGrid`, so the panel never changes height between months. Days are built with `DateTime(y, m, n)`, never `add(Duration(days: 1))`, which drifts across DST. |
| `event.dart` | Provider-agnostic `CalendarEvent` plus `groupByDay` bucketing (a multi-day event lands in every day it covers). |
| `provider.dart` | The `CalendarProvider` abstraction. Adding CalDAV/Outlook means a new implementation and a new connect pane — the grid, agenda, and store are untouched. `CalendarAuthException` means the grant is dead (drop the account); `CalendarFetchException` is transient (keep tokens and events). |
| `google_oauth.dart` | Google's installed-app loopback flow with PKCE: binds `127.0.0.1:0`, opens consent with `xdg-open`, exchanges the code for tokens. Uses the user's own "Desktop app" client — see `CONFIG.md`. |
| `google_provider.dart` | Google Calendar REST v3. Note `end.date` on an all-day event is **exclusive** on the wire and is converted to an inclusive end. |
| `token_store.dart` | OAuth tokens in a 0600 file under `XDG_DATA_HOME`, deliberately *not* in `config.toml` (which the settings UI rewrites and users share). A TODO tracks moving to the Secret Service D-Bus API. |
| `calendar_store.dart` | `CalendarStore.instance`, the singleton `ChangeNotifier` the UI watches — same pattern as `NotificationStore`/`TrayStore`. `startCalendarService()` runs from `main()` and only restores tokens from disk; the first network fetch happens when the tab is opened. |

### On-screen indicator (`lib/osd/`)

The OSD is the card that appears when volume, microphone volume, or brightness changes: an icon for what changed and a bar for its level, bottom-centred on every monitor, fading out after a period of inactivity.

| File | Responsibility |
|------|----------------|
| `osd_store.dart` | `OsdStore.instance` — the singleton `ChangeNotifier` the card watches, same pattern as `NotificationStore`/`TrayStore`. It holds **one** `OsdRequest`, so a `show()` replaces whatever is on screen; that is what makes brightness supersede a still-visible volume bar instead of stacking a second card. `visible` going false is the cue to fade out; the card answers with `onFadeOutComplete()`, which clears `current` and lets the host drop the window. |
| `brightness_monitor.dart` | Reads `/sys/class/backlight/<device>/{brightness,max_brightness}` and watches the `backlight` udev subsystem for change events — the same event-driven approach `modules/battery.dart` takes with `power_supply`. The sysfs root is injectable so tests never touch the real `/sys`. |
| `osd_service.dart` | `startOsdService()` (from `main()`) wires the sources into the store. Volume and mic come free from the existing `PulseClient` subscription (`onSinkChanged` / `onSourceChanged`); the service seeds last-known levels at startup and only shows the card on an **actual** change, because PulseAudio emits sink events for unrelated reasons (a stream connecting, a port switch) that would otherwise flash the card. |
| `osd.dart` | `OsdWindow`, the card itself. Uses the `reverse().then(...)` fade-out handshake `SettingsOverlay` uses. |

The windows are owned by `_GracefulShellRootState` (`lib/main.dart`) alongside the background, not by a panel module — the indicator is not tied to any panel. They exist only while `OsdStore.current` is non-null: the shell has no input-region support, so a permanently-mapped overlay surface would swallow clicks. For the same reason the window is kept tight around the card (`kOsdWindowSize`), anchored to the bottom edge only, which also lets layer-shell centre it horizontally for free.

### Background window (`lib/background.dart`)

Renders a full-screen wallpaper with time-of-day scheduling and crossfade transitions using `media_kit` for video support. One background window is created per monitor.
