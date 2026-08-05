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

Required at runtime for the lock screen: `libgtk-session-lock0` (`ext-session-lock-v1`) and `libpam` — both loaded with `dlopen`, so the shell builds and runs without them; only locking is unavailable.

## Architecture

Graceful Shell is a **Flutter Linux desktop application** that renders Wayland layer-shell panels (taskbars) and an optional wallpaper window using GTK and the `gtk-layer-shell` library.

### Startup flow (`lib/main.dart`)

1. All `Module` subclasses are registered in the global registry.
2. `AppConfig.load()` reads `~/.config/graceful-shell/config.toml`, calls `Module.loadAll()` to push per-module config into each registered module, and returns typed config objects.
3. `startThemeService()` seeds the shipped themes into `~/.config/graceful-shell/themes/` and resolves the one `config.toml` names, before anything paints.
4. A `MiracleConnection` is opened for Miracle WM IPC (workspace events).
5. Wayland outputs are enumerated via `WaylandClient` to correlate with GDK monitors.
6. Flutter's experimental multi-window API (`ExtendedWindowingOwnerLinux`) creates one `LayershellWindowController` per panel per monitor and optional background controllers.
7. `runWidget` builds a `ViewCollection` containing all layer-shell windows wrapped in their scope providers.

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
| `ThemeScope` | `ThemeConfig` (colors, font) — never constructed directly; see `ThemeProvider` below |
| `MiracleScope` | `MiracleConnection` (workspace IPC) |
| `DisplayScope` | `WaylandOutput` (the monitor this panel is on) |
| `BarScope` | `anchor` string (`'top'`, `'bottom'`, `'left'`, `'right'`) |

### GTK FFI (`lib/gtk.dart`)

Raw FFI bindings for GTK3 and `gtk-layer-shell`. Provides `GtkWindow`, `GdkDisplay`, `FlView`, and `FlWindowMonitor` wrappers. This code is adapted from Flutter's internal Linux windowing implementation and wraps the C API used by `LayershellWindowController`.

### Configuration (`lib/config.dart`)

`AppConfig.load()` reads TOML and produces:
- `Map<String, PanelConfig>` — one entry per named panel section.
- `String themeName` — the *name* of the active theme, not the palette. Resolving it is `ThemeStore`'s job (see Theming below).
- `BackgroundConfig?` — optional wallpaper config from `[background]`.

If the config file is absent, a default two-panel layout is written to disk and defaults are used. Parse errors fall back silently to defaults.

### Theming (`lib/theme/`)

A theme is a file, not a config section. Each one is a flat TOML table under `~/.config/graceful-shell/themes/`, and `config.toml` names the active one with a top-level `theme = "dracula"`. The file *is* the table, with the same key names the old `[theme]` section used, so `ThemeConfig.fromMap` parses a whole theme document unchanged.

| File | Responsibility |
|------|----------------|
| `builtin_themes.dart` | `kBuiltInThemes` — slug to full TOML text for `graceful` (the default, and the palette earlier versions hard-coded), `dracula`, and `glassy`. Embedded as constants rather than installed to a share dir because nothing in the shell resolves paths relative to the bundle; the wallpapers the Makefile *does* install are found only via a hardcoded `$HOME/.local/share`, which breaks under a custom `PREFIX`. Seeding from a constant works identically in `flutter run`, `make install`, and the snap. |
| `theme_store.dart` | `ThemeStore.instance` + `startThemeService()` — the same singleton-`ChangeNotifier` shape as `OsdStore`/`AppIndex`. Owns the resolved palette, the catalogue, seeding, `select`/`create`/`edit`/`delete`, and a debounced atomic write lifted from `ConfigStore.save()`. |
| `theme_provider.dart` | `ThemeProvider` — a `ListenableBuilder` on the store wrapping a `ThemeScope`. |

Four things a change here has to keep true:

- **`ThemeProvider` is the only thing that constructs a `ThemeScope`.** `grep -rn 'ThemeScope(' lib/` should match `scopes.dart` and `theme_provider.dart` and nothing else. The shell renders into many independent FlutterViews — one per panel per monitor, plus a window for every popup, overlay, OSD card and lock surface — and an `InheritedWidget` cannot span them, so each tree is given the theme separately. Every module used to do that by reading `ThemeScope.of` in the handler that opened the window and passing the value in, which froze it: an open popup never restyled. Listening instead of snapshotting is what fixes it, and it works even though `PopupHost.openPopup` builds the content once and captures it in a `WindowEntry` builder (`lib/popup.dart`) — the widget instance never comes back, but the `ListenableBuilder`'s element is mounted in that view's tree and rebuilds itself. `test/theme_provider_test.dart` pins this with a `const` child.
- **`ThemeStore` reads `ConfigStore` for the `theme` key alone.** Never `ConfigStore.appConfig` — that getter rebuilds the whole typed config and re-applies every module's options via `Module.loadAll`, which would fire on every keystroke anywhere in the settings UI.
- **Shipped themes are read-only, and re-seeded when they drift.** `edit` forks a built-in into a user copy first, so `themes/dracula.toml` stays byte-identical to what was seeded. Membership in `kBuiltInThemes` *is* the read-only test, so there is one source of truth for "shipped". `_seedBuiltIns` rewrites any shipped file whose content differs, which is what makes a palette fix reach an install that has already run: seeding used to skip an existing file, and the first panel-colour fix silently never landed because the stale `glassy.toml` on disk had none of the new keys. User themes are never touched.
- **The bar has its own colour, and one opacity.** `panelBackgroundDecoration` (`lib/panel_background.dart`) paints `panel_background`, whose alpha is honoured verbatim — it is the surface sitting directly on the desktop. The panel used to be derived from `workspace_background` at a hardcoded 93%, which made it the one thing in the shell no theme could open up while its own popups obeyed. `panel_gradient = false` gives a flat sheet (what `glassy` wants); true fades `accent` -> `surface_pressed` -> `panel_background` with **every stop taking its alpha from `panel_background`**, so an author sets the bar's transparency in one place and no stop can band across the middle.
- **`panel_margin` is a native margin, and it must not touch the exclusive zone.** `setPanelMargin` (`lib/popup.dart`) calls `controller.setMargin` on each edge `anchorEdgesForPosition` returns — never a Flutter `Padding`, because the shell has no input-region support and an inset inside a full-size surface would leave the surface swallowing every click in the gap instead of letting it reach the desktop. The zone stays `panelConfig.height`: per wlr-layer-shell's [`set_margin`](https://wayland.app/protocols/wlr-layer-shell-unstable-v1#zwlr_layer_surface_v1:request:set_margin), *"the exclusive zone includes the margin"*, so the compositor adds it and sending `height + margin` reserves it twice — the symptom is a dead strip under the bar that no window will occupy, which reads as a compositor bug. Unlike every other panel geometry field this one follows the theme live, from `_onThemeChanged` in `_GracefulShellRootState`: a theme switch that rounded the corners but did not lift the bar until the next restart would just look broken. The cached `_panelMargin` compare is load-bearing — `ThemeStore` notifies on every frame of a colour-picker drag, and re-committing every layer surface that often makes the bars flicker. Corner rounding follows from the same field: `panelCornerRadius` rounds all four corners only when the bar floats, because a flush bar with rounded outer corners cuts wallpaper wedges out of the display's own corners.
- **A full-screen layer-shell surface must call `spanFullOutput`.** gtk-layer-shell defaults the exclusive zone to 0, and per wlr-layer-shell that means "move me so I don't occlude surfaces that reserved space" — so the compositor shrinks the surface to the gap *between* the panels. `spanFullOutput` (`lib/popup.dart`) sets it to -1, "extend me to the edges I'm anchored to". The wallpaper window needs it or there is nothing behind a translucent panel but the compositor's empty background, and a see-through bar renders as a flat black strip identical on every monitor edge; the settings, launcher and power-menu overlays need it or their backdrop stops short of the bars. This was invisible for as long as every panel was opaque.
- **`blur` cannot frost the desktop.** A layer-shell surface is transparent and the compositor owns everything under it; Mir exposes no blur protocol. The field feeds the `BackdropFilter`s in `overlay/overlay.dart` and `launcher/launcher_overlay.dart`, which soften the `scrim` and nothing else. Translucency over the desktop comes from alpha, which is how `glassy` is built.

The settings UI for this is `_AppearanceSection` in `lib/overlay/settings/shell.dart`: a picker of swatch cards, a "New theme…" action, and a colour editor that is dimmed behind a "Duplicate to edit" button while a built-in is active. The HSV colour picker it uses (`SettingsColorField`, `SettingsColorPicker`, `formatHexColor`) lives in `lib/overlay/settings/controls.dart` beside the other shared controls.

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

The flip side, and the trap for the next tab author: **`IndexedStack` keeps every tab alive once built.** A tab that owns a `Timer` keeps running it while the user is on some other tab. A tab that polls must therefore be told when it is the visible one — see `SystemTab.active`, which drives the lease it holds on `SystemStatsStore`.

- **`lib/overlay/settings/`** — the settings tab: a sidebar (Network / Bluetooth / Display / Audio / Shell) over one page per category. `controls.dart` holds the themed form controls (`SettingsSection`, `SettingsRow`, `SettingsTextField`, `SettingsIconButton`, …) shared with the calendar and system tabs.
- **`lib/overlay/calendar/`** — the calendar tab, described below.
- **`lib/overlay/system/`** — the system monitor tab, described below.

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

### System monitor (`lib/system/`, `lib/overlay/system/`)

`lib/system/` is the UI-free sampling layer, shared by the `SystemMonitorModule` bar widget and the overlay's **System** tab. Every reader takes its `/proc` and `/sys` roots as constructor parameters — the same shape `BrightnessMonitor` uses — so tests point them at a temp directory and never touch the real ones.

| File | Responsibility |
|------|----------------|
| `models.dart` | `CpuSample`, `MemorySample`, `LoadAverage`, `NetSample`, `DiskUsage`, `ProcessRaw` (raw counters, what crosses the isolate boundary), `ProcessRow` (the resolved view row), `HistorySample`. |
| `proc_reader.dart` | The cheap reads: `/proc/{stat,meminfo,loadavg,uptime,cpuinfo,net/dev}` and `/sys/class/thermal`. Six small files, so they stay on the UI isolate. |
| `process_reader.dart` | The expensive `/proc/<pid>/stat` walk, plus the **pure** `computeProcessRows` that resolves two raw snapshots into rows. |
| `process_sampler.dart` | The seam between the store and the walk. `IsolateProcessSampler` runs it in `Isolate.run`; tests inject a synchronous fake and never spawn an isolate. |
| `process_killer.dart` | Signals processes, with the guards. |
| `disk_reader.dart` | `df -B1 -P` behind an injectable runner, on its own slow cadence. |
| `history.dart`, `format.dart` | Ring buffer for the graphs; byte/duration/temperature formatting. |
| `system_stats_store.dart` | `SystemStatsStore.instance` + `startSystemStatsService()` — same singleton `ChangeNotifier` pattern as `OsdStore`/`TrayStore`. |

Four things a change here has to keep true:

- **Leases, not timers.** The store polls only while somebody holds a lease. A *light* lease (CPU, memory, temperature, load, network) is what the bar module holds for its lifetime; a *detail* lease adds the per-process walk and is held only while the System tab is the visible tab. There is one sampler for the machine — before this, a two-monitor setup ran two independent `/proc` walks. Because the bar module holds a light lease from start-up, the history buffer is already full when the tab is first opened, so the graphs draw populated.
- **The process walk runs in an isolate; the arithmetic does not.** `Isolate.run` returns raw tick counters and the store diffs them on the UI isolate. That keeps the delta pure and unit-testable, and it is what lets the sampler be stateless.
- **`comm` in `/proc/<pid>/stat` can contain spaces *and* parentheses.** Splitting the line on whitespace is the classic bug; `parseStatLine` anchors on the **last** `)`.
- **Kills are keyed on `(pid, starttime)`, never on the PID alone.** A process can exit and have its PID recycled between the row being drawn and the user confirming — a start-time mismatch refuses the signal. `ProcessKiller` also hard-refuses the shell's own PID (killing it takes every panel down) and PID 1; both refusals live in the killer, not the UI, so they cannot be bypassed. There is no automatic SIGTERM→SIGKILL escalation: an editor answers SIGTERM with a save prompt, and killing it five seconds later would destroy the user's work, so the grace period only *offers* a force-quit.

`lib/overlay/system/` is the tab: `system_tab.dart` (Overview / Processes sub-tabs, and the lease), `overview_page.dart`, `process_table.dart` (sort, filter, kill), `kill_confirm.dart`, `time_series_chart.dart` (a `CustomPainter` area chart — there is no charting package), and `stat_tile.dart`. `lib/usage_bar.dart` holds the fill bar both the tab and the bar module's popup use.

### Application launcher (`lib/launcher/`, `lib/modules/launcher.dart`)

A centred search card on a full-screen overlay layer-shell window, opened by `Ctrl+Space` (configurable under `[shortcuts]`) or by the magnifier bar module. It searches installed applications, offers each one's desktop-entry *Actions* in a flyout, and evaluates a typed mathematical expression into a row above the results.

| File | Responsibility |
|------|----------------|
| `launcher_controller.dart` | `LauncherController.instance` — the seam between the two entry points and `_GracefulShellRootState`, which owns the window. Same shape as `LockController`. Deliberately *not* `InputTriggerStore`: that store reports compositor triggers and its listener toggles on any notification, so a second signal there would open the settings overlay instead. |
| `app_index.dart` | `AppIndex.instance` + `startAppIndexService()` — the process-wide app list, built at start-up and refreshed from a `GAppInfoMonitor` "changed" signal (the `MonitorWatcher` pattern). |
| `app_search.dart` | Pure ranking: exact > prefix > word-start > substring, weighted name > generic name > keywords > id. `SearchableApp` folds case once at index-build time. |
| `expression.dart` | The calculator, over `math_expressions`. `looksLikeExpression` is the load-bearing half — without it `e`, `pi`, and `42` all "evaluate". |
| `launcher_overlay.dart` | The card. Takes its app list and launch callbacks as parameters, so widget tests never touch GIO. |

Five things a change here has to keep true:

- **The window is created with no `monitor:`.** `layer_shell` then omits the `wl_output`, and miracle places shell surfaces on its *focused* output, which it retargets whenever the pointer crosses a monitor boundary — so the launcher appears where the user is. `_openSettings` does the opposite and pins to the first monitor.
- **Clicking the backdrop must dismiss.** The shell has no input-region support, so this surface swallows every click on the monitor, including the bar button that opened it. Without dismiss-on-backdrop a mouse-only user has no way out.
- **`Focus` nests *inside* `DefaultTextEditingShortcuts`.** Key events propagate upwards from the focused node, so the lower handler gets first refusal — that is what lets Up/Down/Enter/Escape win while Backspace and the arrows still edit text. Right only opens the flyout when the caret is collapsed at end-of-text, or it would make the caret unmovable.
- **The actions flyout is a `Stack` child, not an `OverlayPortal`.** Rows have a fixed `itemExtent`, so its position is arithmetic against the scroll offset. An `Overlay`'s entries do not rebuild on `setState` (see `overlay/overlay.dart`), which would be a trap for content that changes on every keystroke.
- **`AppIndex` does not share its `AppEntry`s with `modules/app_directory.dart`.** That widget unrefs its own list in `dispose`; sharing would unref `GAppInfo*`s the index still holds. For the same reason the root brackets the launcher's lifetime with `acquire()`/`release()`, which defers a refresh while rows are on screen.

### Screen sharing (`lib/screencast/`, `lib/wayland_ffi/`, `lib/pipewire/`, `lib/native/`)

The shell **is** the xdg-desktop-portal ScreenCast backend. When an app asks to share the screen, xdg-desktop-portal forwards the request here, a layer-shell overlay asks the user which monitor or window to share (with live previews of each), and the chosen sources are captured with `ext-image-copy-capture-v1` and published as PipeWire video streams. All of it is pure `dart:ffi` — no C in the repo.

| Layer | Files | Responsibility |
|-------|-------|----------------|
| Native shims | `native/glib_source.dart`, `native/libc.dart` | `GlibFdWatch` (`g_unix_fd_add`); `memfd_create`/`mmap`/`memcpy`. |
| Wayland FFI | `wayland_ffi/wl_ffi.dart`, `wl_types.dart`, `wl_interfaces.dart`, `wl_proxy.dart`, `wl_protocols.dart` | libwayland-client bindings, the `wl_interface` graph, listener vtables, and typed proxy wrappers. |
| Capture | `screencast/capture_connection.dart`, `capture_session.dart` | The registry/outputs/toplevels, and one continuous capture per source. |
| PipeWire | `pipewire/pw_ffi.dart`, `spa_pod.dart`, `spa_constants.dart`, `video_stream.dart` | libpipewire bindings, SPA pod build/parse, and the video-source stream. |
| Portal | `screencast/screencast_portal.dart`, `screencast_service.dart`, `pick_types.dart` | The `org.freedesktop.impl.portal.ScreenCast` objects and the engine wiring them to capture. |
| UI | `screencast/picker_controller.dart`, `picker_overlay.dart`, `picker_sources.dart`, `preview.dart` | The consent overlay and its live previews. |

Seven things a change here has to keep true:

- **The capture path needs its own Wayland connection, over libwayland.** `package:wayland` (what the rest of the shell uses) cannot pass file descriptors — its `writeFd`/`readFd` are stubs — and `wl_shm.create_pool` requires one. `WlDisplayConnection` is a second connection through `libwayland-client.so.0`, which does SCM_RIGHTS natively. Precedent for a second connection: `lib/overlay/settings/display.dart`.
- **Everything below the UI is Flutter-free, on purpose.** `pick_types.dart` exists so the portal, engine, capture and PipeWire layers import no Flutter, which is what lets `tool/screencast_spike.dart` exercise the entire stack as a `dart compile exe` binary — the only way to test this against a live compositor, since the picker overlay needs a Flutter engine. Keep new non-UI code Flutter-free; use `screencastLog` rather than `debugPrint`.
- **One thread, two fd watches.** The Dart UI isolate runs on the GLib main thread (see `lib/monitor_watcher.dart`), so `g_unix_fd_add` on the capture display fd and on `pw_loop_get_fd` is enough to drive both — no `pw_thread_loop`, no isolates, and every Wayland and `pw_stream` callback lands on the Dart thread, which is what makes `NativeCallable.isolateLocal` correct throughout. In a process with no GLib (the spike) the watch fails and the owner pumps manually; `PipewireVideoStream` registers itself in `_manuallyDriven` for exactly that.
- **Only the ext protocols are hand-transcribed.** Core interfaces (`wl_output`, `wl_shm`, `wl_buffer`, …) come from libwayland's exported `wl_*_interface` data symbols, so they carry no transcription risk. `test/wl_interfaces_test.dart` diffs the hand-written tables against the XMLs in `protocol/` — a wrong signature is memory corruption inside libwayland, not an exception, so that test is the guardrail. Copy new protocol XMLs into `protocol/` and extend the test.
- **The compositor paces the stream, not a timer.** After `ready` the session immediately creates the next frame; `ext-image-copy-capture` holds the copy until the content actually changes. That is why a static screen produces no frames — and why the spike needs something moving on screen. Previews are the exception: they pass `minFrameInterval`, because the picker runs a session per monitor *and* per window at once.
- **Dismissing the picker is a denial, not a deferral.** Backdrop tap, Escape, `Request.Close`, and a superseding request all resolve the pick with null, which becomes portal response 1. `ScreencastPickerController.pick` also declines immediately when nothing is listening (`hasListeners` false) — a backend that could answer without a visible consent surface is a backend that can silently record the screen. `startScreencastService` takes its `SourcePicker` as a required parameter for the same reason: there is no default.
- **`impl` version is 2, and the frame path never copies through Dart.** Version 2 predates restore/persist tokens (4) and virtual monitors (5), so the frontend never sends options this backend would have to understand. Frames go from the shm mapping to a `pw_buffer` with a libc `memcpy` on two raw pointers; previews take one bulk copy into a reusable `Uint8List` and decode via `ImageDescriptor.raw` with `PixelFormat.bgra8888` (XRGB/ARGB8888 are byte-identical to BGRx/BGRA little-endian), never a per-pixel reorder loop.

Install: `portal/graceful-shell.portal` and `portal/graceful-shell-portals.conf` go to `XDG_DATA_HOME` and `XDG_CONFIG_HOME` via `make install-portal` — not `PREFIX`, which xdg-desktop-portal does not search. The conf is only written when absent, so a user's existing backend preference is out-ranked (a `{desktop}-portals.conf` beats the generic one) but never overwritten. There is no D-Bus activation file: the shell owns the name from session start, so screen sharing cannot start the shell.

Verification, since none of this can be tested from the shell binary alone:

```sh
dart compile exe tool/screencast_spike.dart -o /tmp/spike
WAYLAND_DISPLAY=wayland-99 /tmp/spike                     # globals, outputs, toplevels
WAYLAND_DISPLAY=wayland-99 /tmp/spike --capture           # frames from each output
WAYLAND_DISPLAY=wayland-99 /tmp/spike --multi             # N sessions on one source
WAYLAND_DISPLAY=wayland-99 /tmp/spike --pipewire          # prints NODE_ID=<n>
WAYLAND_DISPLAY=wayland-99 /tmp/spike --portal            # the real backend, auto-accepting
python3 tool/portal_client_test.py [--window|--cancel]    # drives the portal contract
```

`--portal` grants every request without a picker (there is no Flutter engine to draw one), so it is a protocol harness, not a security-equivalent run.

### Background window (`lib/background.dart`)

Renders a full-screen wallpaper with time-of-day scheduling and crossfade transitions using `media_kit` for video support. One background window is created per monitor.

`MediaBackground({path, fit})` is the public "render this image or video" widget, shared with the lock screen; the image/video split is decided by extension (`isVideoPath`), and the `media_kit` `Player` lifecycle (muted, looping, disposed on unmount) lives entirely inside it.

### Lock screen (`lib/lock/`, `packages/ext_session_lock/`)

**Lock** in the system module's power menu locks the session with the `ext-session-lock-v1` Wayland protocol. The compositor then hides every other surface — the shell's own panels included — and, per the protocol, blanks any output that has no lock surface, so a monitor we fail to cover is never *exposed*, only blank.

The lock surface is a **new window-controller type**, not runner C code. `packages/ext_session_lock/` is a standalone package that does for `ext-session-lock-v1` what `layer_shell.dart` does for wlr-layer-shell: it `dlopen`s `libgtk-session-lock.so.0` and binds six functions. `SessionLockWindowController` mirrors `LayershellWindowController._internal` almost line for line, except that where the layer-shell one calls `gtk_layer_init_for_window()` it calls `gtk_session_lock_lock_new_surface(lock, window, monitor)` — and, like layer-shell init, **that must happen before the window is realized**.

It depends on `layer_shell` only to reuse the generic GTK/Flutter FFI wrappers and to subclass `ExtendedWindowingOwnerLinux`, so lock windows register into the *same* `LinuxWindowRegistrar` as every other window. `initSessionLock()` (called from `main()` in place of `initLayerShell()`) calls `initLayerShell()` first and then swaps in the subclass, which is why panels and popups are unaffected.

| File | Responsibility |
|------|----------------|
| `lock_controller.dart` | `LockController.instance` — the seam between the Lock button (deep in a panel's tree) and `_GracefulShellRootState` (which owns every window). Same singleton-`ChangeNotifier` shape as `OsdStore`/`TrayStore`. |
| `lock_screen.dart` | The UI: wallpaper via `MediaBackground`, clock/date, account name, and the reveal-on-any-key password field that blurs the wallpaper behind it. |
| `pam_authenticator.dart` | PAM over `dart:ffi`. |
| `user_identity.dart` | `getpwuid(getuid())` for the account name PAM needs and the GECOS name the UI shows. |

Five things a change here has to keep true:

- **Lock windows are created undecorated, before realize.** gtk-layer-shell calls `gtk_window_set_decorated(FALSE)` itself; the gtk-session-lock fork does not, and a decorated GTK3 window draws its CSD titlebar *inside* the lock surface. `SessionLockWindowController` makes the call explicitly.
- **Lock windows exist only while locked**, like the OSD windows and unlike the panels — `_GracefulShellRootState` creates one per monitor on request and destroys them on unlock, including for monitors hotplugged mid-lock.
- **Order teardown as detach → unlock → destroy windows, and unmap the role before each destroy.** Destroying a GTK window while Flutter still renders into its `FlView` is a use-after-free, so the views are detached a frame first. The unlock comes next — `unlockAndDestroy()` syncs with the compositor before anything else is torn down, matching gtk-session-lock's own example. Then, inside `SessionLockWindowController.destroy()`, `gtk_session_lock_unmap_lock_window()` runs before `gtk_widget_destroy()`: GTK destroys the `wl_surface` on unmap but gtk-session-lock only destroys the `ext_session_lock_surface_v1` in the window's finalizer, and Mir answers a surface dying before its role by deleting the role server-side — the finalizer's trailing destroy then hits an unknown object and the compositor kills the connection (`Error 22 dispatching to Wayland display`).
- **Never unlock on the way out.** `dispose()` drops the lock object without sending an unlock: if the shell is dying while the session is locked, the session must stay locked. The protocol guarantees exactly this — a client that disconnects without `unlock_and_destroy` leaves the session locked.
- **PAM's conversation callback is `isolateLocal` and the whole exchange runs in `Isolate.run`.** PAM invokes the callback synchronously on the thread that called `pam_authenticate`, and that call blocks for seconds on failure (`pam_unix` delays deliberately). The response array is allocated with the C allocator because PAM `free()`s it. This works unprivileged because `pam_unix` shells out to the setuid-root `unix_chkpwd`. An empty password is rejected before PAM is ever called, so an account configured `nullok` cannot be opened with a bare Enter.
