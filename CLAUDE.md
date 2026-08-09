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

### Packaging (`snap/snapcraft.yaml`, `.github/workflows/`)

A **classic** snap, built nightly from `main` and published as a rolling `nightly` release. Classic confinement is what makes the rules here unusual: the snap runs in the host namespace, so the host's libraries are on the default loader path and `LD_LIBRARY_PATH` only *prepends* `$SNAP`.

Five things a change here has to keep true:

- **Bundle a library only when the host cannot be trusted to have it, or to have a compatible one.** `libgtk-layer-shell0`, `libmpv1`, `libpulse0`, `libasound2` are staged; `libpipewire-0.3`, `libpam`, `libudev`, `libwayland-client`, `libdbus` and the whole GL/EGL/GBM/DRI set are deliberately *not* — the `prime:` exclusion list exists because a bundled core22 Mesa against host DRI drivers produces `libEGL fatal: did not find extension DRI_Mesa version 1`, and the same reasoning kills every other candidate for a client/server version split.
- **`libgtk-session-lock` is built from source, and stages no GTK.** There is no `libgtk-session-lock0` in core22 (it first appears in resolute), and without it **Lock silently does nothing**. It is dlopened into a process that already has the host GTK3 mapped, so it links by soname at build time and resolves to the host at run time; staging `libgtk-3-0` would put a second, different GTK in the same address space.
- **Portal registration is split in two halves because precedence forces it, and neither half can be dropped.** `portals.conf(5)` searches `$XDG_CONFIG_HOME` → `$XDG_CONFIG_DIRS` → `/etc` → `$XDG_DATA_HOME` → `$XDG_DATA_DIRS`, and **directory precedence beats file specificity**: a user's generic `~/.config/xdg-desktop-portal/portals.conf` out-ranks a desktop-specific `/usr/share/xdg-desktop-portal/mir-portals.conf`. So `snap/hooks/{install,post-refresh,remove}` — thin shims over `snap/local/portal-setup`, staged as `$SNAP/bin/graceful-shell-portal-setup` — write the `/usr/share` copy as a *machine default* for every account, and `snap/local/graceful-shell-wrapper` writes the per-user copy that is the only one high enough to actually override an existing preference. A hook cannot do the second half: it runs as root with no `SNAP_REAL_HOME` and no idea whose session it is registering for. Both write `miracle-wm-portals.conf` **and** `mir-portals.conf`, because `XDG_CURRENT_DESKTOP` is `miracle-wm:mir` and which name is reached first follows that list. Three invariants inside this: the hooks are **marker-guarded** (`# graceful-shell-snap-managed` appended to every file they write; anything without it is a distro's or a user's and is neither rewritten nor deleted), they are **never fatal** (a non-zero `install` hook aborts `snap install`, and `/usr` is read-only on an immutable host — the per-user copy is the fallback), and `remove` deletes per-user files only from the manifest the wrapper records in `SNAP_USER_COMMON`, filtered to `.portal` files, so it cannot eat a `make install-portal` file or a conf the user edited. `/etc/pam.d/graceful-shell` still needs root at a path snapd will not manage; `PamAuthenticator` falls back to the `login` service.
- **The wrapper restarts xdg-desktop-portal, once per revision, and never edits a conf it did not write.** xdg-desktop-portal reads `.portal` files and preferences only at start-up, so writing them is half the job — the wrapper used to print instructions telling the user to do the other half. It now runs `systemctl --user try-restart xdg-desktop-portal.service` (`try-restart`, so a session with no systemd user instance is not forced to start one; only the frontend, never the backends) and gates on a `SNAP_REVISION` stamp in `SNAP_USER_COMMON`, because a refresh can change what is shipped but a restart on every shell start is noise. Two refusals are deliberate: `[screenshare] enabled = false` skips registration entirely — the Dart side then declines the bus name, so registering anyway would point the config at a name nobody owns and break ScreenCast rather than leave it on wlr — and an existing `*-portals.conf` routing ScreenCast elsewhere is reported, not overwritten, which also means the *other* name is left unwritten (writing it would silently out-rank the file we just promised to honour).
- **The Flutter revision is pinned, and `flutter-master.yml` is why that is safe.** The shell is built on Flutter's experimental windowing API; the snap used to clone `master` at HEAD, so an upstream rename landing overnight broke the *release artifact*. The daily `flutter-master.yml` job now carries the early-warning role, and the pin is bumped to a revision that job has proven green.

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

### Layer-shell windowing (`package:layer_shell`, `lib/window_manager.dart`, `lib/popup.dart`)

The gtk-layer-shell bridge is no longer in this repo — it is the `layer_shell` git dependency (`mattkae/layer_shell.dart`, pinned by `pubspec.lock`), which owns `LayershellWindowController`, `LayerShellWindow`, `ExtendedWindowingOwnerLinux`, and the generic GTK/GDK/Flutter FFI wrappers (`GtkWindow`, `FlView`, `FlEngine`, `FlWindowMonitor`) that `packages/ext_session_lock` reuses. It also re-exports the `@internal` SDK windowing pieces (`WindowRegistry`, `WindowEntry`, `WindowScope`, `PopupWindow`, `WindowPositioner`), which are unreachable through `package:flutter/widgets.dart`.

That dependency tracks Flutter `master`, and Flutter renames these APIs without notice. **When a build fails with `Type 'X' not found` inside `_window.dart`, the fix is upstream-first**: bump the `layer_shell` pin to a revision whose own *Build against Flutter master* workflow is green, then apply the same rename here. `.github/workflows/flutter-master.yml` is this repo's copy of that early-warning job.

- **`PanelWindowManager`** (`lib/window_manager.dart`) — a vendored stand-in for Flutter's `WindowManager`, one per panel. The SDK widget used to render a `child` *plus* every window registered into its `WindowRegistry`; on master it takes `initialWindows` and renders only those, so panel content nested inside it disappears. This is a port of the pre-rename implementation — a `ViewAnchor` whose `child` is the panel and whose anchored views are the registered windows — with its own registry scope, because Flutter's `_WindowRegistryScope` is private and nothing outside the SDK can satisfy `WindowRegistry.of`. Reach it with `PanelWindowManager.registryOf(context)`.
- **`LayerShellHost` mixin** (`lib/popup.dart`) — reusable `State` mixin for modules that open a full layer-shell window (panel/overlay/dialog) at runtime. The module creates the `LayershellWindowController` and hands it to `openLayerWindow`, which registers a `WindowEntry` into the panel's `WindowRegistry`; `closeLayerWindow` unregisters and destroys it. Used by the notifications, clock, and system modules. This is the same registry path popups use — there is no separate runtime-view registry.
- **`PopupHost` mixin** (`lib/popup.dart`) — reusable `State` mixin that manages a single popup window lifecycle; modules that open popups (e.g. `SoundControl`) mix this in. Note the cast to `BaseWindowControllerLinux` when making the surface transparent: `WindowControllerLinux` is the *regular*-window controller and a popup's is not one, so the wrong cast compiles and then throws on the first popup.
- **`PopupBounceIn`** — scale+fade animation widget used inside popup content.

#### Dismissal (`lib/popup_coordinator.dart`)

Nothing in the stack tells the shell a popup should go away. The Linux popup controller takes no `gdk_seat_grab`, so the compositor never sends `popup_done` on a click outside; `PopupDelegate.onWindowDestroyed` only fires once the window is already gone; and no layer-shell surface reports focus loss. Every popup therefore closes because its own `State` decided to — which is why two of them used to sit on screen at once. `PopupCoordinator.instance` is the one thing that closes them, and `PopupDismissArea` (wrapped around each panel and the desktop surface in `main.dart`) is the one thing that notices a click elsewhere.

Six things a change here has to keep true:

- **A handle's *chain* is itself plus its transitive parents, and nothing in a chain dismisses anything else in it.** That is the whole group concept, and it is what keeps the app-directory popup alive under its category flyout and the flyout alive under the pin-to-dock menu. Parentage is never passed by a call site: `openPopup` reads `TransientScope.maybeOf(context)`, the same context walk that already finds `WindowScope` and `PanelWindowManager.registryOf` from three levels deep. **The `TransientScope` wrapper in the `WindowEntry` builder is therefore load-bearing** — drop it and every nested popup starts closing its own parent.
- **The coordinator requests a *graceful* close, and must never call `closeLayerWindow` itself.** It calls the `onDismiss` the owner registered — for `clock.dart` and `notifications.dart` that is the `_closingNotifier` flip, so the fade/slide-out still plays and the module tears the window down afterwards, exactly as before. `LayerShellHost.openLayerWindow` takes `onDismissRequested` for this. A `closing` flag stops a second dismissal mid-animation from restarting it, and the handle stays registered until `close()`.
- **`TransientPolicy` is two booleans, not an enum.** `dismissesOthers` false is a hover tooltip: crossing the dock must not tear down the menu the pointer is travelling towards. `dismissable` false is a consent prompt or an awaited picker — it displaces, and nothing displaces it, because dismissing the screencast picker is a *denial* and nothing may answer it for the user. Refusal is inherited down a chain, so a surface nested in a modal is safe too.
- **The reopen guard exists because `PopupDismissArea` fires before `onTapDown`.** `GestureBinding` is the last entry on the hit-test path, so an ancestor `Listener` always beats a descendant recognizer — without the guard, clicking the icon whose popup is open would close it and immediately reopen it, and no bar popup could be dismissed by its own button. It is armed on the **primary** button only, because every popup toggle in the shell is a primary tap and every context menu is `onSecondaryTapDown`; a right-click that dismisses something must still be free to open its menu. It is keyed on the host `State`, so a host that opens a *different* popup per trigger passes `ownerKey` — `system_tray.dart` does, keyed on the item, or clicking a second tray icon would be read as re-clicking the first.
- **Root-owned overlays register too, and that replaced the ad-hoc pairs.** `_openSettings` / `_openLauncher` / `_openAppChooser` / `_openScreencastPicker` / `_onFilePickRequested` each take a handle with a sentinel owner, so the three hand-rolled "close the other one" lines in `main.dart` are gone. Lock calls `dismissAll()`: the compositor hides every other surface, so anything left registered would be a popup the user cannot reach and would find still open on unlock.
- **Two clicks it cannot catch, by construction.** A click on an ordinary application window reaches no shell surface and there is no grab, so a popup survives it — the fix is a `gdk_seat_grab` in Flutter's `PopupWindowControllerLinux`, two upstreams away. And with `background.entries.isEmpty && !desktop.enabled` there is no background surface at all, so bare desktop cannot be observed. A full-screen invisible barrier is not the answer: the shell has no input-region support, so it would swallow every click on the monitor.

### Scopes (`lib/scopes.dart`)

Four `InheritedWidget` scopes are provided around every panel's widget tree:

| Scope | Provides |
|-------|----------|
| `ThemeScope` | `ThemeConfig` (colors, font) — never constructed directly; see `ThemeProvider` below |
| `MiracleScope` | `MiracleConnection` (workspace IPC) |
| `DisplayScope` | `WaylandOutput` (the monitor this panel is on) |
| `BarScope` | `anchor` string (`'top'`, `'bottom'`, `'left'`, `'right'`) |

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
| `font_catalog.dart` | `FontCatalog.instance` — the installed families, from `fc-list --format '%{family[0]}\n'`. Injectable runner and empty-on-failure, the `DiskReader` shape; the *future* is memoised so racing callers share one fork. Loaded lazily by the settings font picker, never from `main()`. |

Four things a change here has to keep true:

- **`ThemeProvider` is the only thing that constructs a `ThemeScope`.** `grep -rn 'ThemeScope(' lib/` should match `scopes.dart` and `theme_provider.dart` and nothing else. The shell renders into many independent FlutterViews — one per panel per monitor, plus a window for every popup, overlay, OSD card and lock surface — and an `InheritedWidget` cannot span them, so each tree is given the theme separately. Every module used to do that by reading `ThemeScope.of` in the handler that opened the window and passing the value in, which froze it: an open popup never restyled. Listening instead of snapshotting is what fixes it, and it works even though `PopupHost.openPopup` builds the content once and captures it in a `WindowEntry` builder (`lib/popup.dart`) — the widget instance never comes back, but the `ListenableBuilder`'s element is mounted in that view's tree and rebuilds itself. `test/theme_provider_test.dart` pins this with a `const` child.
- **`ThemeStore` reads `ConfigStore` for the `theme` key alone.** Never `ConfigStore.appConfig` — that getter rebuilds the whole typed config and re-applies every module's options via `Module.loadAll`, which would fire on every keystroke anywhere in the settings UI.
- **Shipped themes are read-only, and re-seeded when they drift.** `edit` forks a built-in into a user copy first, so `themes/dracula.toml` stays byte-identical to what was seeded. Membership in `kBuiltInThemes` *is* the read-only test, so there is one source of truth for "shipped". `_seedBuiltIns` rewrites any shipped file whose content differs, which is what makes a palette fix reach an install that has already run: seeding used to skip an existing file, and the first panel-colour fix silently never landed because the stale `glassy.toml` on disk had none of the new keys. User themes are never touched.
- **The bar has its own colour, and one opacity.** `panelBackgroundDecoration` (`lib/panel_background.dart`) paints `panel_background`, whose alpha is honoured verbatim — it is the surface sitting directly on the desktop. The panel used to be derived from `workspace_background` at a hardcoded 93%, which made it the one thing in the shell no theme could open up while its own popups obeyed. `panel_gradient = false` gives a flat sheet (what `glassy` wants); true fades `accent` -> `surface_pressed` -> `panel_background` with **every stop taking its alpha from `panel_background`**, so an author sets the bar's transparency in one place and no stop can band across the middle.
- **`panel_margin` is a native margin, and it must not touch the exclusive zone.** `setPanelMargin` (`lib/popup.dart`) calls `controller.setMargin` on each edge `anchorEdgesForPosition` returns — never a Flutter `Padding`, because the shell has no input-region support and an inset inside a full-size surface would leave the surface swallowing every click in the gap instead of letting it reach the desktop. The zone stays `panelConfig.height`: per wlr-layer-shell's [`set_margin`](https://wayland.app/protocols/wlr-layer-shell-unstable-v1#zwlr_layer_surface_v1:request:set_margin), *"the exclusive zone includes the margin"*, so the compositor adds it and sending `height + margin` reserves it twice — the symptom is a dead strip under the bar that no window will occupy, which reads as a compositor bug. Unlike every other panel geometry field this one follows the theme live, from `_onThemeChanged` in `_GracefulShellRootState`: a theme switch that rounded the corners but did not lift the bar until the next restart would just look broken. The cached `_panelMargin` compare is load-bearing — `ThemeStore` notifies on every frame of a colour-picker drag, and re-committing every layer surface that often makes the bars flicker. Corner rounding follows from the same field: `panelCornerRadius` rounds all four corners only when the bar floats, because a flush bar with rounded outer corners cuts wallpaper wedges out of the display's own corners.
- **A full-screen layer-shell surface must call `spanFullOutput`.** gtk-layer-shell defaults the exclusive zone to 0, and per wlr-layer-shell that means "move me so I don't occlude surfaces that reserved space" — so the compositor shrinks the surface to the gap *between* the panels. `spanFullOutput` (`lib/popup.dart`) sets it to -1, "extend me to the edges I'm anchored to". The wallpaper window needs it or there is nothing behind a translucent panel but the compositor's empty background, and a see-through bar renders as a flat black strip identical on every monitor edge; the settings, launcher and power-menu overlays need it or their backdrop stops short of the bars. This was invisible for as long as every panel was opaque.
- **`blur` cannot frost the desktop.** A layer-shell surface is transparent and the compositor owns everything under it; Mir exposes no blur protocol. The field feeds the `BackdropFilter`s in `overlay/overlay.dart` and `launcher/launcher_overlay.dart`, which soften the `scrim` and nothing else. Translucency over the desktop comes from alpha, which is how `glassy` is built.

The settings UI for this is `_AppearanceSection` in `lib/overlay/settings/shell.dart`: a picker of swatch cards, a "New theme…" action, and a colour editor that is dimmed behind a "Duplicate to edit" button while a built-in is active. The HSV colour picker it uses (`SettingsColorField`, `SettingsColorPicker`, `formatHexColor`) lives in `lib/overlay/settings/controls.dart` beside the other shared controls, as does the font picker (`SettingsFontField`).

Two things the font row has to keep true. **It floats in the *root* overlay and takes its list as a parameter**, for the reasons `SettingsColorField` documents: the settings content pane is a nested `Navigator` whose `Overlay` would clip a list hanging below the row, and a control that read `FontCatalog` itself could not be widget-tested without forking `fc-list`. The `Future` is started in the state's field initialiser, never in `build` — this section rebuilds on every `ThemeStore` notify, which includes every frame of a colour-picker drag. **The row degrades rather than locks out.** With no fontconfig the catalogue is empty and the row falls back to the free-typed `SettingsTextField` it used to be, so `font` is never a key the UI can no longer set; and a theme naming a family this machine does not have is prepended to the list rather than dropped, or the picker would silently disown the value it is showing.

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

The Calendar tab is a month grid the user can page through, and nothing else. Account integration (Google Calendar, over OAuth) was removed and is unsupported — the tab does no network I/O, holds no credentials, and needs no start-up service, so `main()` starts nothing for it.

| File | Responsibility |
|------|----------------|
| `month.dart` | Pure month math — `buildMonthGrid` returns a fixed 6x7 `MonthGrid`, so the panel never changes height between months. Days are built with `DateTime(y, m, n)`, never `add(Duration(days: 1))`, which drifts across DST. |
| `calendar_tab.dart` | The tab: header, weekday row, and the 42 day cells. `weekStart` is a constructor parameter that falls back to `[calendar] week_start` from `ConfigStore`; widget tests inject it, because the singleton throws before `initShared()`. The `ConfigStore` listener is what makes a week-start change in the settings tab re-lay the grid without closing the overlay. |

### On-screen indicator (`lib/osd/`)

The OSD is the card that appears when volume, microphone volume, or brightness changes: an icon for what changed and a bar for its level, bottom-centred on every monitor, fading out after a period of inactivity.

| File | Responsibility |
|------|----------------|
| `osd_store.dart` | `OsdStore.instance` — the singleton `ChangeNotifier` the card watches, same pattern as `NotificationStore`/`TrayStore`. It holds **one** `OsdRequest`, so a `show()` replaces whatever is on screen; that is what makes brightness supersede a still-visible volume bar instead of stacking a second card. `visible` going false is the cue to fade out; the card answers with `onFadeOutComplete()`, which clears `current` and lets the host drop the window. |
| `brightness_monitor.dart` | Reads `/sys/class/backlight/<device>/{brightness,max_brightness}` and watches the `backlight` udev subsystem for change events — the same event-driven approach `modules/battery.dart` takes with `power_supply`. The sysfs root is injectable so tests never touch the real `/sys`. |
| `osd_service.dart` | `startOsdService()` (from `main()`) wires the sources into the store. Volume and mic come free from the existing `PulseClient` subscription (`onSinkChanged` / `onSourceChanged`); the service seeds last-known levels at startup and only shows the card on an **actual** change, because PulseAudio emits sink events for unrelated reasons (a stream connecting, a port switch) that would otherwise flash the card. |
| `osd.dart` | `OsdWindow`, the card itself. Uses the `reverse().then(...)` fade-out handshake `SettingsOverlay` uses. |

Volume and mic reach the store over `PulseClient`'s subscription, and `lib/pulse_client.dart` runs libpulse in its own isolate. Three things a change to that driver has to keep true, because getting any of them wrong is invisible until an *external* volume change (the keyboard's knob, `pactl`) silently stops arriving — a change made *through* the client always works, so the bug hides:

- **`dispatch` is not optional after `prepare` succeeds.** `pa_mainloop_prepare` asserts `state == STATE_PASSIVE` and `abort()`s otherwise, and only `pa_mainloop_dispatch` puts the loop back into that state. Bailing out between the two — on a poll error, say — means the *next* `prepare` takes the whole shell down with SIGABRT rather than returning an error. The one value that may skip it is `-2`, "quit requested", which parks the loop in `STATE_QUIT` for good; `_dead` exists so the driver never touches it again.
- **A productive `dispatch` means keep cycling, not yield.** Delivering one external volume change takes several cycles back to back: read the subscription event, flush the `get_sink_info_by_index` its callback issued, read that reply. Re-arming through `Timer.run` after the first of those strands the rest — which is exactly what `9338ade` did, and why only shell-initiated changes reached the OSD. `_cycle`'s rule is stated on the pair (poll result, dispatched count): work → keep cycling; `poll > 0` with nothing dispatched → the wakeup pipe, so yield and let `_handleMsg` run; both zero → idle or `EINTR`, so **retry in place**. That last case is the anti-spin one — `pa_mainloop_poll` maps a signal-interrupted `ppoll` onto "returned, nothing ready" and does not retry, and the Dart VM's thread interrupter fires at 1 kHz under `flutter run`, so re-arming on each turned an idle 20 Hz loop into an ~820 Hz spin worth 7 of the shell's 9% idle CPU.
- **`pa_mainloop_wakeup` is worth calling but cannot be relied on.** The pipe it writes has no `pa_io_event`, so the wake is invisible to `dispatch` and only the `poll > 0, dispatched == 0` rule notices it; and `prepare` drains that pipe unconditionally, so a byte written while the isolate is between turns is swallowed. A request that loses that race just waits for the message queue.

`tool/pulse_spike.dart` is how this is verified, and the reason `pulse_client.dart` imports no Flutter: it exercises subscribe → dispatch → stream against the real server with no engine to draw with. Run it, change the volume from anywhere else, and it exits non-zero if nothing arrived. `GRACEFUL_PULSE_LOG=1` turns on `pulseLog` (`lib/pulse_log.dart`) in both isolates — it gates on the environment rather than on a hook `main()` installs, because a top-level assignment would not cross the isolate boundary.

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

Install: `portal/graceful-shell.portal` and `portal/graceful-shell-portals.conf` go to `XDG_DATA_HOME` and `XDG_CONFIG_HOME` via `make install-portal` — not `PREFIX`, which xdg-desktop-portal does not search. The conf is only written when absent, so a user's existing backend preference is out-ranked (a `{desktop}-portals.conf` beats the generic one) but never overwritten. The snap adds a machine-wide copy under `/usr/share/xdg-desktop-portal/` from its install hook and does the restart itself — see the packaging section above for why both halves exist. There is no D-Bus activation file: the shell owns the name from session start, so screen sharing cannot start the shell.

The backend the shell **displaces** is `org.freedesktop.impl.portal.desktop.wlr`, which `/usr/share/xdg-desktop-portal/portals/{mir,miracle}.portal` claim by default. That happens at the config layer only. Never try to own or replace that bus name: it cannot be taken without `allowReplacement` from its current owner, and those `.portal` files claim `org.freedesktop.impl.portal.Screenshot` on it too — an interface this shell does not implement, so taking the name would break screenshots. The shell requests its own, `kScreencastBusName` (`screencast_service.dart`), with `doNotQueue`, and nothing else contends for it.

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

### Desktop icons (`lib/desktop/`)

A configurable grid of pinned items — `.desktop` entries, files and folders — drawn on the background surface over the wallpaper. Double-click opens (an app launches; a file or folder goes to its default handler, which for a directory is the file manager), single click selects, drag rearranges and **dropping one icon on another swaps them**. Right-click gives a real popup menu; right-clicking bare desktop offers Add / Organize / Change background.

| File | Responsibility |
|------|----------------|
| `desktop_layout.dart` | Pure geometry: `DesktopGridGeometry`, `computeGridGeometry`, `panelInsetsFor`, `cellAt`/`nearestCell`, `firstFreeCell`/`nearestFreeCell`, `moveItemTo` (swap-aware), `placeItem`, `organizeItems`, `reflowIntoGrid`. The unit-test target. |
| `desktop_store.dart` | `DesktopStore.instance` + `startDesktopService()` — the singleton `ChangeNotifier`, same shape as `ThemeStore`. |
| `desktop_actions.dart` | The verbs: `openDesktopItem`, `openWithCandidates`, `labelForItem`, `iconNameForItem`, `desktopItemExists`. Flutter-free. |
| `desktop_surface.dart` | What the background window renders: wallpaper + grid, and the `PopupHost` the menus open through. |
| `desktop_grid.dart` | `DesktopLayer` — hit testing, selection, drag/swap, the drag-only grid lines. |
| `desktop_icon.dart` | `DesktopIconTile`, `DesktopItemIcon`, `DesktopRenameField`. |
| `desktop_menu.dart` | `DesktopItemMenu` (two pages), `DesktopEmptyMenu`, `DesktopMenuCard`. |
| `app_chooser.dart` | `AppChooserCard` / `AppChooserOverlay` / `showAppChooser` — the searchable list of installed applications behind "Add application…". |

Config lives in `[desktop]` / `[[desktop.items]]`; the settings UI is the **Desktop** category in `lib/overlay/settings/shell.dart`.

Seven things a change here has to keep true:

- **The background surface now exists for two reasons, and `needsRestart` signs the *decision*, not its causes.** `_hasBackgroundSurface` (`main.dart`) is `background.entries.isNotEmpty || desktop.enabled`, so icons work with no wallpaper — and in that case the surface must render `SizedBox.expand()`, **not** `BackgroundWindow`, whose empty state is an opaque `0xFF1A1A1A` fill that would black out a desktop the compositor was painting. `ConfigStore._restartSignature` encodes `bg:<either>` rather than two parts, so enabling the grid on a config that already has a wallpaper does not demand a restart.
- **The grid must clear the panels, and it is the only thing on that surface that does.** The surface calls `spanFullOutput` (exclusive zone −1) so a translucent bar has wallpaper behind it, which means it reaches *under* the bars. `panelInsetsFor` sums each panel's `height + panelMargin` onto the edge its anchor names; the margin is read live from `ThemeScope`, so a theme change that re-floats the bars re-insets the grid on the same frame with no listener of its own. That works only because the background window is now wrapped in `ThemeProvider`.
- **Nothing in `build` may touch GIO.** `loadAppByPath` **refs** what it returns and `iconNameForItem` guesses a content type; both are resolved once per change of the item set in `DesktopLayerState._syncResolved`, which disposes the previous entries after installing the new ones (the `DockState._loadApps` contract). Resolving in `build` leaks one `GAppInfo` per frame. Every GIO call there is also wrapped in a `try`, because `flutter_tester` does not link GLib — the fallback is a font glyph, which is also what a machine with no icon theme gets.
- **`DesktopStore` splits persisted from ephemeral, and never reads `ConfigStore.appConfig`.** Items and geometry are written back; selection, drag and in-flight rename are not and must never reach disk. Every `ConfigStore.set` notifies synchronously and rebuilds every panel on every monitor, so a drag persists once **on drop** — routing pointer positions through the config would rebuild the shell dozens of times per gesture. `_onConfigChanged` compares a signature and early-returns, because that listener fires on every keystroke anywhere in the settings UI.
- **Dragging is hand-rolled, and selection comes from a `Listener`.** Flutter's `Draggable` requires an `Overlay` ancestor, which a background-layer surface has no business hosting; the ghost is another `Stack` child and the drop resolves through `nearestCell` + `moveItemTo`. Selection is painted from `onPointerDown` rather than `onTap`/`onTapDown`: registering `onDoubleTap` makes `onTap` wait out the double-tap window, and `onTapDown` is still deferred until the tap recognizer beats the pan, either of which leaves the highlight visibly lagging the click.
- **Renaming borrows the keyboard, and gives it back.** The surface is created `keyboardMode: none`, so an `EditableText` on it would never see a key event. `DesktopLayer` asks the root (`_setDesktopKeyboard`) to flip that one monitor's surface to `onDemand` for the duration of a rename and back afterwards — including from `dispose`, so a monitor unplugged mid-rename cannot leave a surface holding focus. It is not simply left `onDemand`: a full-output background surface that can take focus would let a stray desktop click steal it from the focused application. The toggle is cached and force-committed for the reasons `setPanelMargin` documents.
- **"Add application…" is a list, not a file picker, and it pins a *path*.** The chooser reuses `AppIndex` and `rankApps`, so it gets keyword matching for free and pays nothing to build. Its rows hold `GAppInfo` pointers the index owns and whose refresh unrefs, so every host brackets it with `AppIndex.acquire()` / `release()` — the contract `_openLauncher` follows. `AppEntry.filename` (`g_desktop_app_info_get_filename`, transfer-none) is what gets stored, because `DesktopItem.target` is a path in every case; an entry with no filename is filtered out of the list rather than offered and then refused. The desktop opens it as a root-owned overlay-layer window and the settings pane through `showAppChooser` into its own `Overlay` — the same split as `FilePickerController` vs `showFilePicker`, and for the same reason.
- **The file picker cannot live on this surface.** `showFilePicker` inserts into the nearest root `Overlay`; on the background layer that modal would be drawn underneath every application window and every panel. `FilePickerController` (`lib/overlay/file_picker_controller.dart`) asks the root for an overlay-layer window instead, and declines immediately when nothing is listening — the rule `ScreencastPickerController` follows, so a headless run never awaits a window that will not appear.

Verified against a live miracle: an `xdg_popup` parented to a background-layer surface stacks **above** both the panels and ordinary application windows, so the menus need no top-layer fallback.

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
