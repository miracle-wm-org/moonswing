# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## Graceful Shell

A Flutter Linux desktop shell. It renders wlr-layer-shell panels, a wallpaper + desktop-icon surface, full-screen overlays, popups, an OSD and a lock screen. Built on Flutter's experimental windowing API (`flutter config --enable-windowing`), tracking `master`, which renames those APIs without notice. The shell is also the session's notification daemon, StatusNotifierItem tray host, xdg-desktop-portal ScreenCast backend, polkit authentication agent and session locker.

## Commands

```sh
flutter config --enable-windowing   # one-time setup
flutter run -d linux                # development
flutter build linux --release       # or: make build
make install                        # to ~/.local, or PREFIX=/usr/local
make install-portal                 # ScreenCast registration (XDG dirs, not PREFIX)
flutter analyze
flutter test
flutter test test/widget_test.dart

# Profile against a live compositor (GRACEFUL_SHELL_IMPELLER=1 is the only way to Impeller).
flutter build linux --profile && GRACEFUL_SHELL_IMPELLER=1 \
  ./build/linux/x64/profile/bundle/graceful_shell

# Capture/screencast stack — untestable from the shell binary; needs a live compositor.
dart compile exe tool/screencast_spike.dart -o /tmp/spike
WAYLAND_DISPLAY=wayland-99 /tmp/spike --capture   # frames from each output
WAYLAND_DISPLAY=wayland-99 /tmp/spike --portal    # the real backend, auto-accepting
python3 tool/portal_client_test.py                # drives the portal contract
gdbus call --session --dest org.freedesktop.portal.Desktop \
  --object-path /org/freedesktop/portal/desktop \
  --method org.freedesktop.DBus.Properties.Get \
  org.freedesktop.portal.ScreenCast AvailableSourceTypes   # 0 = frontend cached no backend

dart run tool/pulse_spike.dart      # PulseAudio driver; GRACEFUL_PULSE_LOG=1 for logging
```

**Rendering backend (`linux/runner/my_application.cc`).** Impeller's GLES backend is the engine's Linux default and is switched **off in the runner**, not on the command line. It must stay a compiled-in default — `--no-enable-impeller` reaches the engine as an env var and so cannot help the snap or a `make install` build. `GRACEFUL_SHELL_IMPELLER=1` is the way back; re-measure with it after an engine bump, since this is expected to be temporary.

Build deps: `libgtk3`, `gtk-layer-shell`, `libasound2-dev`, `libmpv-dev`. Runtime, for lock only: `libgtk-session-lock0`, `libpam` — both `dlopen`ed, so the shell builds without them.

## Packaging (`snap/snapcraft.yaml`, `.github/workflows/`)

A **classic** snap, built nightly from `main`. Classic confinement puts the host's libraries on the loader path; `LD_LIBRARY_PATH` only *prepends* `$SNAP`.

- **Stage a library only when the host cannot be trusted to have a compatible one.** `libgtk-layer-shell0`, `libmpv1`, `libpulse0`, `libasound2` are staged; the GL/EGL/GBM/DRI set, `libpipewire`, `libpam`, `libudev`, `libwayland-client`, `libdbus` are excluded in `prime:` (bundled core22 Mesa against host DRI drivers gives `libEGL fatal: did not find extension DRI_Mesa version 1`). Staging is half the job: Debian keeps `pulseaudio/`, `blas/`, `lapack/` out of the triplet dir with the soname link made by a maintainer script snapcraft never runs, so each must be named in `environment:` — and BLAS/LAPACK cannot simply be excluded, since `DT_NEEDED` aborts start-up rather than falling back.
- **`libgtk-session-lock` is built from source and stages no GTK.** core22 has no package; without it Lock silently does nothing. It is dlopened into a process that already has the host GTK3 mapped, so staging `libgtk-3-0` would put a second GTK in that address space.
- **Portal registration is split in two halves, neither droppable.** `portals.conf(5)` directory precedence beats file specificity, so the root hooks write a machine default under `/usr/share` and `snap/local/graceful-shell-wrapper` writes the per-user copy that alone can out-rank an existing preference. Both write `miracle-wm-portals.conf` *and* `mir-portals.conf` (`XDG_CURRENT_DESKTOP` is `miracle-wm:mir`). Hooks are marker-guarded (`# graceful-shell-snap-managed`; anything without it is never rewritten or deleted) and never fatal (a non-zero `install` hook aborts `snap install`, and `/usr` may be read-only).
- **The wrapper `try-restart`s xdg-desktop-portal once per revision**, gated on a `SNAP_REVISION` stamp: the frontend reads `.portal` files only at start-up. `try-restart` so a session with no systemd user instance is not forced to start one, and the frontend only, never the backends. It never overwrites a conf it did not write.
- **The Flutter revision is pinned**; cloning `master` at HEAD once broke the release artifact overnight. `.github/workflows/flutter-master.yml` is the early warning, and the pin is bumped to a revision it has proven green.

## Architecture

### Startup (`lib/main.dart`, `lib/shell_services.dart`)

`main()` is split by `runWidget`, and which side of that line work sits on is the design. Above it: module registration, `AppConfig.load()`, and the theme/desktop/stats config reads — every native window's geometry comes out of them. Below it, from a post-frame callback, `ShellServices` runs everything else (outputs, shortcuts, Miracle IPC, notifications, tray, PulseAudio, backlight, ScreenCast, polkit, the logind inhibitor, the app index), each on its own event-loop turn; registration order is turn order, so I/O-bound tasks go first and the FFI-heavy app index last. Consumers read `ShellServicesScope` and show a loader until a `ServiceStatus` settles.

**Services throw; `run()` records.** A genuine failure (bus unreachable, missing protocol) propagates and settles `failed`; a *graceful decline* — another daemon owns the name, a feature switched off — logs and returns, settling `ready`. A service that swallows its own failures makes a loader resolve with the feature dead.

Consequence: panels paint before the shell knows which display each is on. `DisplayScope.output` is nullable, and a panel is matched to its output by **connector name** first (GDK's connector and `wl_output.name` are the same string and neither moves under repositioning), then by a make/model/position tuple, with a first-output fallback only when there is exactly one output.

### Windows (`package:layer_shell`, `lib/popup.dart`, `lib/main.dart`)

Every surface — panel, background, overlay, OSD, badge, selection surface, lock screen, popup — is a `WindowEntry` in the **one** root `WindowRegistry`, reachable via `WindowRegistry.of(context)`. The gtk-layer-shell bridge is the `layer_shell` git dependency, which also re-exports the `@internal` SDK windowing pieces; when a build fails with `Type 'X' not found` inside `_window.dart`, the fix is upstream-first (bump that pin to a green revision, then apply the same rename here).

- **The root's set is reconciled, never rebuilt** — diffed against live entries, keyed on controller, or a declarative list returned from `build` would take every module's popup down with it. Survivors keep the builder they were created with, so builders read the root's fields rather than capturing them. Entries render *unkeyed*, so dropping one shifts later ones down a slot; hence the registration order (per-monitor surfaces, then overlays, then popups last).
- **A native window may only be destroyed once Flutter has let go of its view.** `gtk_widget_destroy` on a window with a live view aborts the shell: the destroy cascade disposes the per-view renderer whose `frame_mutex` the raster thread holds, and `g_mutex_clear` on a held mutex is a glib `abort()`. `WindowTeardown` unmaps, polls `viewIsAttached` per frame, then waits one more; it **schedules its own frames** (an idle shell produces none), destroys anyway at `maxFrames`, and re-checks `isDestroyed`. Every teardown goes through it; lock passes `hide: false`.
- **A full-screen layer-shell surface must call `spanFullOutput`.** The default exclusive zone of 0 means "move me so I don't occlude surfaces that reserved space", so the compositor otherwise shrinks it into the gap between the panels.
- **Panels take no keyboard focus; a popup that types borrows it.** Panels are `LayerShellKeyboardMode.none`, which is what stops the bar pulling focus off whatever the user is typing in. Interactivity is inherited by popups, so `openPopup(needsKeyboard:)` flips the *panel* to `onDemand` and back on close and from `dispose`; only a borrow that actually flipped is given back, and the flip is force-committed or it sits queued on a mapped surface. The desktop surface does the same for an icon rename.
- **A margin is native, never a Flutter `Padding`** — no input-region support means an inset inside a full-size surface swallows every click in the gap. The exclusive zone stays the panel height: per wlr-layer-shell the zone *includes* the margin, so adding it reserves it twice.

### Popups (`lib/popup.dart`, `lib/popup_coordinator.dart`, `lib/popup_transition.dart`)

`PopupHost` (one popup) and `LayerShellHost` (a runtime layer-shell window) are `State` mixins; both end their close on `context.mounted`, not `State.mounted`, which stays true throughout `dispose()`. Popup content lays out under its own FlutterView, so it must carry its own `ShellTextRoot` — `Directionality.of` is a null-assert in release too.

Nothing in the stack says a popup should go away: the Linux popup controller takes no `gdk_seat_grab`, so no `popup_done` arrives, and no layer-shell surface reports focus loss. `PopupCoordinator.instance` is the only thing that closes them, `PopupDismissArea` the only thing that notices an outside click.

- A handle's **chain** is itself plus its transitive parents, and nothing in a chain dismisses anything else in it. Parentage is read from `TransientScope.maybeOf(context)`, never passed by a call site, so the `TransientScope` wrapper in the entry builder is load-bearing.
- The coordinator requests a **graceful** close (the owner's `onDismiss`), never `closeLayerWindow` itself, so exit animations still play.
- `TransientPolicy` is two booleans: `dismissesOthers` false is a hover tooltip; `dismissable` false is a consent prompt, because dismissing the screencast picker is a *denial*. Refusal is inherited down a chain.
- The **reopen guard** exists because `PopupDismissArea`'s ancestor `Listener` fires before any descendant recognizer; without it no bar popup could be dismissed by its own button. Primary button only, keyed on the host `State` (or an `ownerKey` where one host opens a different popup per trigger).
- A **closing popup outlives the host that closed it**: `closePopup` drops every reference synchronously (so close-then-open in one gesture works) and moves the handle, entry, window and `onClosed` to a record that finishes on the animation **or a timer**, and outright on `dispose`.
- Two clicks it cannot catch by construction: one on an ordinary application window (no grab), and bare desktop with no background surface. A full-screen invisible barrier is not the answer — no input-region support means it would swallow every click on the monitor.

`PopupTransition` plays one controller forward to open and backward to close, so an effect cannot describe an opening it has no closing for. The effect is the theme's (`popup_animation`), snapshotted at open; `PopupEffect.none` wraps nothing and creates no controller.

### Scopes (`lib/scopes.dart`)

| Scope | Provides |
|-------|----------|
| `ThemeScope` | `ThemeConfig` — never constructed directly; see `ThemeProvider` |
| `ShellServicesScope` | how far along each global start-up task is |
| `LiveConfigScope` | `AppConfig` as the user is editing it; see `LiveConfigProvider` |
| `MiracleScope` | `MiracleConnection` (workspace IPC) |
| `DisplayScope` | `WaylandOutput?` — null until enumeration lands; see `DisplayProvider` |
| `BarScope` | anchor string (`'top'`/`'bottom'`/`'left'`/`'right'`) |

The first three go on **every** window, paired once in `_windowChrome` with `ShellTextRoot` and `kExcludeSemantics`. Three are **provider-only**: `grep -rn 'ThemeScope('`, `'DisplayScope('`, `'LiveConfigScope('` should each match `scopes.dart` plus that scope's one provider. Each provider is a `ListenableBuilder` emitting the scope and passing `child` through **unrebuilt**; resolving any of them in the root's `build` instead is what made one output landing, or one settings keystroke, rebuild every panel on every monitor plus the backgrounds, OSD and overlays. The `_refreshWindows()` calls left in the root are where its *list of native windows* changed — those cannot be a scope, since an `InheritedWidget` cannot span FlutterViews. `DisplayProvider` listens to one store and reads the other from the scope above rather than merging: `ListenableBuilder` is an `AnimatedWidget`, so a merge built in `build` re-subscribes every rebuild.

### Registries (`lib/module.dart`, `lib/desktop/widgets/desktop_widget.dart`)

A `Module` is a panel strip sized by its content: a `configKey` matching `[modules.<key>]`, a `loadConfig(map)`, and a `builder`. Adding one is a top-level `final Module.simple(configKey:, fromMap:, builder:)` (or `Module.plain`) plus `Module.register(...)` in `main.dart`; `test/module_registry_test.dart` pins the registry. `DesktopWidgetRegistry` is the same shape for the desktop grid and deliberately separate: a desktop widget is a rectangle of cells the user resizes, so its spec carries span limits — clamped at **render** time, never written back, so a config authored under different limits survives, and an unknown type renders as a placeholder left exactly as authored.

**`Module.configChanges` keeps `[modules.*]` options live.** Config is pushed imperatively — `loadAll` mutates each module's config in place — so nothing about a module widget's inputs tells Flutter anything moved. `loadConfig` compares a stringified signature of the raw sub-map and `loadAll` fires the notifier once per sweep; a panel listens per module, so a `[modules.clock]` edit rebuilds the clock and nothing else. The guard also stops side-effecting `fromMap`s re-running per keystroke.

### The compositor's configuration (`lib/miracle_config/`, `lib/overlay/settings/miracle/`)

Settings › Window Manager edits `~/.config/miracle-wm/config.yaml` through
`MiracleConfig` — `package:miracle`'s FFI wrapper around `libmiracle-wm-c` — and
is the one pane that writes *another program's* file. Three things follow, and
none of them is how the Shell pane works.

- **Nothing is written until Save.** `ConfigStore` debounces every keystroke to
  disk because the shell re-reads its own config live; a compositor does not, so
  a half-typed border size written as it is typed is what the user's next
  `reload_config` would apply — and a compositor that will not start has no
  settings page to fix it from. `MiracleConfigStore` therefore accumulates edits
  in native memory, `save()` is a deliberate act and `reset()` re-reads the file.
  **A save is only half the job**: miracle does not watch its own configuration,
  so the pane names the shortcut that reloads it, read off
  `builtInKeyCommandOverrides` rather than hard-coded, because it can be rebound.
- **The lease frees native memory, except while dirty.** One loaded tree for the
  machine, `acquire()`/`release()` as everywhere else — but a release that would
  discard unsaved edits keeps the tree instead. The bound is the user's own Save
  or Reset.
- **Rows subscribe per value; lists subscribe on a signature.** `MiracleValue` is
  `StoreSelector` over one FFI getter, which is what stops one digit rebuilding
  twenty rows. A collection cannot be one: the live `List` views mint a fresh
  Dart object per read, so `MiracleCollection` compares a *spelling* of what the
  editor renders. And because a `SettingsTextField` seeds its controller once,
  anything that replaces or reorders a list goes through `editStructure`, whose
  revision keys the rows — without it, deleting the first of three bindings
  leaves the second row's field showing the first row's text, and Reset leaves
  every field showing the values it just discarded.

Two hazards the package documents and the pane has to respect: an unset keymap
must never have its options touched (the C library dereferences it unchecked and
aborts), and the key-repeat settings are dropped by a save unless a keymap is
set. `miracle_config/` is otherwise Flutter-free — the evdev table, the enum
labels and the colour conversion are plain Dart, because they are what
`test/miracle_config_test.dart` can reach on a machine with no compositor.

### Stores and leases

Shared state is a singleton `ChangeNotifier` (`ThemeStore`, `OsdStore`, `TrayStore`, `SystemStatsStore`, `NotificationStore`, `MprisStore`, `WeatherStore`, `AppIndex`, `TimersStore`, `DesktopStore`, …). Four rules run through all of them:

- **One poller, connection or timer for the machine, held by leases.** One FlutterView per panel per monitor means anything owned by a widget is owned N times — two bars used to mean two `/proc` walks, two `GET_TREE`s, two bus connections. Consumers `acquire()`/`release()`, the last release stops the work, and a lease can have tiers (a *detail* lease adds a per-process walk or a position poll). **A `Timer.periodic` in a widget `State` is the anti-pattern these exist to prevent**: an idle shell with a feature off must wake for it exactly never. `acquire()` must not notify synchronously — it runs inside the acquirer's `initState`.
- **Elapsed time is derived, never accumulated.** Hold a reference point and subtract against the wall clock; a ticker that added its own period drifts by however late each wakeup was and loses a suspend entirely. A backwards clock step is dropped, not subtracted.
- **A read that finds nothing new must not notify.** Every surface on every monitor listens, so compare a signature carrying only what a surface renders. Stores that mutate two lists at once must guard against their own synchronous notifications re-entering mid-write.
- **A failure is a visible state, not a silence.** Lost bus name, unreachable API, missing external tool: the last good value stays on screen, the reason is rendered, and a **retry** is offered — all of these recover without a restart and the shell cannot see it happen. A missing external tool names the *package*, never a package manager. An empty list from a failed service is indistinguishable from a genuinely empty one, which is why loaders and error states are not decoration.

### Controllers (`lib/request_controller.dart`)

The seam letting something deep in a surface ask the root for a window has two shapes. `RequestController<Req, Res>` carries a request/response pair and bakes in three rules no subclass may lose: **no listener means an immediate decline** (a headless run never awaits a window that will not appear — for the screencast picker this is the consent guarantee), a second request **supersedes the first as declined**, and **dispose answers the awaiting caller**. `SignalController` is fire-and-forget: a monotonic counter plus `notifyListeners`. Neither is `InputTriggerStore`, which reports compositor triggers and whose listeners toggle on any notification.

### Config (`lib/config.dart`, `lib/config_reader.dart`, `lib/config_store.dart`)

`AppConfig.load()` reads `~/.config/graceful-shell/config.toml` into typed objects, writing a default layout if absent. `ConfigStore.instance` is the live writable view the settings UI mutates, with a debounced atomic write.

**Every field read goes through `TomlReader`, whose invariant is the one rule of this layer: a wrongly-typed value costs that key, never the whole table.** A throw out of any `fromMap` — a module's included, since `Module.loadAll` runs inside `AppConfig.fromMap` — makes `load` discard the user's entire config. So readers type-test and coerce (`height = 32.0` is a TOML float), treat NaN/infinity as absent, and clamp via `min:`/`max:`; never a bare `as X?` cast. Only a TOML *syntax* error still costs the file, and that path logs. The same degrade-per-field discipline applies to data from outside — an unknown enum from a web API, a tree that will not parse, a bad row in a shipped table: it costs that row, never the surface.

**Every section class carries value equality**, which is load-bearing: the getter mints a fresh object graph per read and the store notifies on every keystroke, so without `==` the notifier behind `LiveConfigScope` could never refuse one. Maps hash on `length`, lists use `listEquals` + `Object.hashAll`. `test/config_golden_test.dart` pins defaults and degradation.

### Theme (`lib/theme/`, `lib/popup_surface.dart`)

A theme is a **file**, not a config section: a flat TOML table under `~/.config/graceful-shell/themes/`, named by a top-level `theme = "dracula"`. `ThemeStore` owns the resolved palette, catalogue, seeding, CRUD and the debounced write, and reads `ConfigStore` for the `theme` key alone (never `appConfig`, which re-runs `Module.loadAll`).

- **`ThemeProvider` is the only thing that constructs a `ThemeScope`.** Each FlutterView is given the theme separately, so a module that snapshotted `ThemeScope.of` when opening a window froze it; listening is what makes an open popup restyle.
- **`font_size` is a `TextScaler` on the `MediaQuery` `ThemeProvider` publishes**, so the whole `ShellFontSizes` scale moves as one and 13.0 is `noScaling` — a `DefaultTextStyle` size would reach only text that names none. So **a `TextPainter` deciding a layout must be given the scaler**. Pixels are *not* scaled: growing the type is not an instruction to grow the bar.
- **Shipped themes are embedded constants**, read-only, forked on edit, and **re-seeded when they drift**, so a palette fix reaches an install that has already run; membership in `kBuiltInThemes` *is* the read-only test. Constants because nothing in the shell resolves paths relative to the bundle — the same reason the emoji table and Tux's SVG are constants and `pubspec.yaml` has no `assets:` section.
- **Popup geometry is theme-driven and grows the compositor surface.** A shadow or attach flare paints outside the card's box, but a popup is its own surface sized to its content, so `openPopup` pads the measured box by `popupSurfaceInsets`, offsets the positioner by the same, and grows the GTK geometry hints — all three, or every menu lands off its button. `popup_gap = 0` is the attached mode (joined edge squares off, drops its rim, clamps the shadow, reaches a collar into the panel). Read `lib/popup_surface.dart` and `lib/popup.dart` rather than re-deriving the arithmetic.
- **`lib/theme/tokens.dart`** sits below the theme: `ShellDurations`, `ShellRadii`, `ShellFontSizes` (a scale *relative* to `body`), `ShellSizes` (pointer-target boxes, never glyph sizes), `kErrorColor`, `kOnAccent`. A literal that matches a token is a token.
- Alpha is overridden where prose is read: `panelBackgroundDecoration` honours `panel_background`'s alpha verbatim, while the settings panel and everything floating over it (`OpaquePopupScope`) force opacity. There is deliberately **no blur key**: a `BackdropFilter` reaches only what Flutter already painted beneath it, which in an overlay window is nothing — it changed no pixel while costing a full-output Gaussian per frame.

### Shared primitives

- **`HoverRegion`** (`lib/hover_region.dart`) — `builder: (context, hovered) => …` plus tap callbacks; the shell has no Material and dozens of `StatefulWidget`s existed only to carry `bool _hovered`. It emits the `GestureDetector` too, at `HitTestBehavior.opaque`, and that half is load-bearing: a detector with no `behavior:` is `deferToChild`, and `Padding`, `Align`, `ConstrainedBox`, `ClipRRect`, `Row`/`Column`/`Stack`, `RenderImage` and an undecorated `Container` all answer `hitTestSelf == false` — so a 26px button hovered over 26 and *fired* over the 11px glyph. Greppable rule: **every `GestureDetector(` in `lib/` carries a `behavior:` or is inside `HoverRegion`.** A decorated `Container` is hit-testable only inside its `borderRadius`; `Container(color: cond ? c : null)` only while `cond` holds; opaque is not enough without a box of at least `ShellSizes.minTapTarget`; the builder-only form emits no detector, or it would swallow hits meant for a `Stack` sibling. `onTapDown` is not interchangeable with `onTap` — every popup toggle opens on tap-*down*, inside the pointer-down the reopen guard is consumed in. `test/tap_target_test.dart` taps **corners**, because a centre tap passes on every one of these bugs.
- **`BarButton`**, **`SkyIconButton`** — bar-module chrome (theme hover fill), and the round action on a picture-backed desktop card (colours from the picture; a tap, so the card stays draggable under it).
- **`ShellTextRoot`** — `Directionality` + theme-font `DefaultTextStyle`, applied once per window.
- **`FadeOverlayScaffold`** — scrim + centred scale-in card, and owner of the `closing` handshake (reverse, *then* `onClosed`, which may tear the window down). Nothing may wrap the scaffold in an `Opacity`: these windows span the output, so that layer is a full-output offscreen per frame. The scrim fades by its own alpha; only the card keeps a layer, built outside the `AnimatedBuilder`.
- **`AnchoredSearchDropdown`** (`lib/search_list.dart`) — the one dropdown. Floats in the **root** overlay (an inline one pushes the form down as it opens and cannot open off the bottom of the screen), matches the trigger's width or right-aligns, flips above when the room below will not hold the list, shows a filter field only past a threshold, and supports async search (debounced, applied in request order).
- **`OverlaySearchField`** — the launcher/emoji/settings search field, with `RenderEditable` mouse wiring a hand-rolled copy would get wrong.
- **`lib/overlay/settings/controls.dart`** — the themed form controls. **Pages import them; they never redeclare one.** Private clones are how the audio and bluetooth pages lost the theme font and the display page froze its palette. A control the library lacks gets *added to the library*; `test/settings_shared_controls_test.dart` pins the theme-font half. An **add** button goes at the top right of the collection it adds to, never under it.

### Repaint discipline

Panels, overlays and the desktop surface have **no repaint boundary of their own**, so any render object marked needing paint re-records the whole surface picture and damages the whole output. The two things that do this most are the two done most often: something tinting under the pointer, and something ticking once a second.

- **A boundary per cell, tile, card or button** contains the damage — two of them where an animating layer sits inside a labelled one, so the label stays out of it.
- **Hand unchanged children in rather than rebuilding them.** An identical child widget is skipped outright, so a hover rebuild updates a decoration instead of re-shaping a paragraph.
- **Per-item `ValueNotifier` instead of `setState` on the parent.** Selection following a pointer, a band crossing icons, a grid cell ringing: as parent state each rebuilds every child, including any that measure text as they build. `MouseRegion` fires enter/exit as *content* moves under a stationary cursor too, so a scroll does it every frame.
- **A repaint boundary contains a repaint; only a *relayout* boundary contains a relayout.** Changing a `Text` marks needs-layout, which stops at the nearest tightly-constrained ancestor — and that ancestor then marks itself needing paint, stepping over any boundary nested inside it.
- **Measure text with the ambient `TextScaler`** and the style actually rendered; anything deciding a layout from a measurement (marquees, text-fit ladders, "does this row fit") measures a different font otherwise.
- Long lists are `ListView`/`GridView` with a fixed extent, never a `Column` (which overflows the moment the user adds one more item), with `cacheExtent` set deliberately — the 250px default is several screens of rows at small item heights.
- Nothing animates at rest: a ticker is created when there is something to show and disposed when there is not. Tests pin this with a settle plus `transientCallbackCount == 0`.

### Services and D-Bus (`lib/dbus_service_object.dart`, `lib/dbus_clients.dart`)

Four exported surfaces: `org.freedesktop.Notifications`, `org.kde.StatusNotifierWatcher` + host (with a `com.canonical.dbusmenu` client for tray menus), `org.freedesktop.PolicyKit1.AuthenticationAgent`, and the ScreenCast portal backend on its own name. Every exported object extends `DBusServiceObject`: **one interface table** drives `handleMethodCall`'s guard and dispatch, `getProperty`, `getAllProperties` and `introspect` — objects used to list their members two or three times each, which is how one lost its interface guard and another's `GetAll` returned nothing. One-shot queries use the process-wide clients in `dbus_clients.dart` (BlueZ is the documented exception: it scopes discovery to the requesting connection); long-lived services own their connections. That file is Flutter-free, because the portal must compile into `tool/screencast_spike.dart`.

Losing a name to another daemon is a **graceful decline** for `ShellServices` but a **visible failure** for the feature, which carries its own status: notifications going to a daemon the shell cannot see must not render as a quiet day. Registrations a peer restart silently drops (polkitd) are re-established from `nameOwnerChanged`.

### Native and FFI (`lib/native/`, `lib/wayland_ffi/`, `lib/pipewire/`, `lib/screencast/`, `lib/capture/`)

All pure `dart:ffi`; **there is no C in the repo**. `lib/native/` holds the shared dlopen plumbing (`processLibrary`, soname fallback, `g_signal_connect_data`, `g_unix_fd_add`, `memfd_create`/`mmap`/`memcpy`).

- **Capture needs its own Wayland connection, over libwayland.** `package:wayland` cannot pass file descriptors, and `wl_shm.create_pool` requires one.
- **There is one `CaptureConnection` in the process**, `CaptureHost`'s (`lib/screencast/capture_host.dart`), shared by the portal backend and the shell's own screenshot/recording; it memoises the connect, fans `onDied` out, and **clears the connection when it dies**, so a compositor restart costs one capture rather than the session.
- **One thread, fd watches.** The Dart UI isolate runs on the GLib main thread, so `g_unix_fd_add` on the capture display fd and on `pw_loop_get_fd` drives both — no `pw_thread_loop`, no isolates, and every callback lands on the Dart thread, which is what makes `NativeCallable.isolateLocal` correct throughout. With no GLib (the spike) the watch fails and the owner pumps manually.
- **Everything below the UI is Flutter-free on purpose**, so `tool/screencast_spike.dart` compiles the whole stack as a `dart compile exe` binary — the only way to exercise it against a live compositor. Use the `*Log` gates, not `debugPrint`.
- **Only the `ext-*` protocols are hand-transcribed**; core interfaces come from libwayland's exported `wl_*_interface` symbols. A wrong signature is memory corruption inside libwayland, not an exception, so `test/wl_interfaces_test.dart` diffs the tables against the XMLs in `protocol/` — copy new XMLs there and extend it.
- **The compositor paces the stream, not a timer.** `ext-image-copy-capture` holds each copy until content changes, so a still screen produces no frames; anything needing a constant rate drives its own clock and computes how many writes are *owed* from elapsed time. Frames never go per-pixel through Dart — libc `memcpy` into a `pw_buffer`, or one bulk copy plus `ImageDescriptor.raw`.
- PAM (`lib/lock/pam_authenticator.dart`) runs the whole exchange in `Isolate.run` with an `isolateLocal` conversation callback — PAM invokes it synchronously on the calling thread and blocks for seconds on failure. The response array uses the C allocator because PAM `free()`s it.
- polkit: the shell **never authenticates anybody itself**. Only the setuid-root `polkit-agent-helper-1` can tell polkitd an authentication happened, and the cookie goes to it on **stdin, never `argv`** — that is CVE-2015-3255.

### Lock (`lib/lock/`, `packages/ext_session_lock/`)

`ext-session-lock-v1` via a standalone package that dlopens `libgtk-session-lock.so.0` and does for that protocol what `layer_shell` does for wlr-layer-shell; `initSessionLock()` swaps in a subclass of `ExtendedWindowingOwnerLinux`, so lock windows register into the same registrar as every other window. The compositor hides every other surface while locked and blanks any output with no lock surface, so a monitor we fail to cover is blank, never exposed. Four ordering rules, each a crash or a security hole:

- **Create lock windows undecorated, before realize.** gtk-layer-shell calls `gtk_window_set_decorated(FALSE)` itself; the gtk-session-lock fork does not, and a decorated GTK3 window draws its CSD titlebar *inside* the lock surface.
- **Lock windows exist only while locked** — one per monitor, including monitors hotplugged mid-lock.
- **Tear down as detach → unlock → destroy, unmapping the role before each destroy.** Destroying a GTK window while Flutter still renders into its `FlView` is a use-after-free; `unlockAndDestroy()` syncs with the compositor first; and GTK destroys the `wl_surface` on unmap while gtk-session-lock destroys the `ext_session_lock_surface_v1` only in the finalizer, so without `gtk_session_lock_unmap_lock_window()` first the compositor kills the connection (`Error 22 dispatching to Wayland display`).
- **Never unlock on the way out.** `dispose()` drops the lock without sending an unlock: a client that disconnects without `unlock_and_destroy` leaves the session locked, which is what should happen if the shell dies while locked.

### Layout of `lib/`

| Directory | Responsibility |
|---|---|
| `modules/` | Bar modules — one file per `[modules.<key>]` strip |
| `desktop/` | Desktop grid: layout maths, store, surface, icons, menus, `widgets/` |
| `overlay/` | The settings/calendar/system overlay, `settings/controls.dart`, the file picker |
| `miracle_config/` | The compositor's own configuration: the store behind `overlay/settings/miracle/`, the evdev key table, enum labels |
| `theme/` | `ThemeConfig`, `ThemeStore`, `ThemeProvider`, built-in themes, tokens, fonts |
| `launcher/`, `emoji/` | The two search overlays: index, pure ranking, controller, card |
| `weather/`, `moon/`, `media/`, `fortune/`, `tux/`, `clock/` | Data layers behind a bar module and/or desktop widget: store + pure model + painters |
| `system/` | UI-free `/proc`,`/sys` sampling; `overlay/system/` is its tab |
| `timers/` | Countdowns and stopwatches: pure format, store, shared widgets |
| `osd/` | The volume/brightness card, its store and its sources |
| `capture/` | Screenshots and recording: targets, selection, ffmpeg, store |
| `screencast/` | The ScreenCast portal backend, capture sessions, the consent picker |
| `polkit/`, `power/`, `lock/` | Authentication agent, power-key policy and menu, session lock |
| `native/`, `wayland_ffi/`, `pipewire/` | dlopen plumbing, libwayland bindings, libpipewire + SPA |
| `input_trigger/`, `keyboard/` | Compositor global shortcuts; keyboard layout over locale1 |
| `keybinds/` | The cheat sheet behind the bar's keyboard icon: miracle's own bindings over `GET_KEYBINDS`, the pure model that turns one into key caps, its store and its overlay |

Feature-level rationale that used to live in this file is in the git history of `CLAUDE.md` and in the doc comments of the files themselves.
