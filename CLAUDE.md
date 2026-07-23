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
