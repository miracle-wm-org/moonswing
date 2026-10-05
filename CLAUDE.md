# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## Moonswing

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

# Profile against a live compositor (MOONSWING_IMPELLER=1 is the only way to Impeller).
flutter build linux --profile && MOONSWING_IMPELLER=1 \
  ./build/linux/x64/profile/bundle/moonswing

# Capture/screencast stack — untestable from the shell binary; needs a live compositor.
dart compile exe tool/screencast_spike.dart -o /tmp/spike
WAYLAND_DISPLAY=wayland-99 /tmp/spike --capture   # frames from each output
WAYLAND_DISPLAY=wayland-99 /tmp/spike --portal    # the real backend, auto-accepting
python3 tool/portal_client_test.py                # drives the portal contract
gdbus call --session --dest org.freedesktop.portal.Desktop \
  --object-path /org/freedesktop/portal/desktop \
  --method org.freedesktop.DBus.Properties.Get \
  org.freedesktop.portal.ScreenCast AvailableSourceTypes   # 0 = frontend cached no backend

dart run tool/pulse_spike.dart      # PulseAudio driver; MOONSWING_PULSE_LOG=1 for logging
```

```sh
# The website and wiki. `dev` and `build` regenerate the pages taken from CONFIG.md first.
cd website && npm install && npm run dev   # http://localhost:4321/moonswing/
npm run build && npm run preview
```

**Rendering backend (`linux/runner/my_application.cc`).** Impeller's GLES backend is the engine's Linux default and is switched **off in the runner**, not on the command line. It must stay a compiled-in default — `--no-enable-impeller` reaches the engine as an env var and so cannot help the snap or a `make install` build. `MOONSWING_IMPELLER=1` is the way back; re-measure with it after an engine bump, since this is expected to be temporary.

Build deps: `libgtk3`, `gtk-layer-shell`, `libasound2-dev`, `libmpv-dev`. Runtime, for lock only: `libgtk-session-lock0`, `libpam` — both `dlopen`ed, so the shell builds without them.

## Pull requests

**Always open a pull request.** When Claude Code has committed and pushed changes to a branch, it opens a pull request against `main` for them in the same session — no need to be asked. It never pushes to `main` directly. If a pull request for the branch is already open, push to it instead of opening another; if that one has been merged, start a new branch from `main` and open a new pull request.

## Packaging (`snap/snapcraft.yaml`, `.github/workflows/`)

A **classic** snap, built nightly from `main`. Classic confinement puts the host's libraries on the loader path; `LD_LIBRARY_PATH` only *prepends* `$SNAP`.

- **Stage a library only when the host cannot be trusted to have a compatible one.** `libgtk-layer-shell0`, `libmpv1`, `libpulse0`, `libasound2` are staged; the GL/EGL/GBM/DRI set, `libpipewire`, `libpam`, `libudev`, `libwayland-client`, `libdbus` are excluded in `prime:` (bundled core22 Mesa against host DRI drivers gives `libEGL fatal: did not find extension DRI_Mesa version 1`). Staging is half the job: Debian keeps `pulseaudio/`, `blas/`, `lapack/` out of the triplet dir with the soname link made by a maintainer script snapcraft never runs, so each must be named in `environment:` — and BLAS/LAPACK cannot simply be excluded, since `DT_NEEDED` aborts start-up rather than falling back.
- **SQLite is the snap's own, not the host's.** `package:sqlite3` 3.x's build hook downloads a prebuilt, sha256-checked `libsqlite3` into the bundle's `lib/` (`$SNAP/lib`). The embedder `dlopen`s it by the *bare name* `libsqlite3.so`, so it is found by the loader's search — `LD_LIBRARY_PATH` before `libflutter_linux_gtk.so`'s `$ORIGIN` RUNPATH — and the snap's `LD_LIBRARY_PATH` puts the staged triplet dir ahead of `$SNAP/lib`; hence the `prime:` exclusion of the unversioned `libsqlite3.so` link, which is the only thing staged there that could shadow it. Outside the snap a user's own `LD_LIBRARY_PATH` can still win, and `TodoDatabase` refuses a library older than 3.34 with a message saying so. Never set its `source: system` user define: the board's trigram FTS5 index needs SQLite 3.34+ and would fail to set up on an older host. The build therefore needs GitHub reachable, as it already does to clone Flutter.
- **`libgtk-session-lock` is built from source and stages no GTK.** core22 has no package; without it Lock silently does nothing. It is dlopened into a process that already has the host GTK3 mapped, so staging `libgtk-3-0` would put a second GTK in that address space.
- **Portal registration is split in two halves, neither droppable.** `portals.conf(5)` directory precedence beats file specificity, so the root hooks write a machine default under `/usr/share` and `snap/local/moonswing-wrapper` writes the per-user copy that alone can out-rank an existing preference. Both write `miracle-wm-portals.conf` *and* `mir-portals.conf` (`XDG_CURRENT_DESKTOP` is `miracle-wm:mir`). Hooks are marker-guarded (`# moonswing-snap-managed`; anything without it is never rewritten or deleted) and never fatal (a non-zero `install` hook aborts `snap install`, and `/usr` may be read-only).
- **The wrapper `try-restart`s xdg-desktop-portal once per revision**, gated on a `SNAP_REVISION` stamp: the frontend reads `.portal` files only at start-up. `try-restart` so a session with no systemd user instance is not forced to start one, and the frontend only, never the backends. It never overwrites a conf it did not write.
- **The Flutter revision is pinned**; cloning `master` at HEAD once broke the release artifact overnight. `.github/workflows/flutter-master.yml` is the early warning, and the pin is bumped to a revision it has proven green.

## The website (`website/`)

Astro + Starlight, published to GitHub Pages by `.github/workflows/website.yml`. `npm run dev`
in `website/` serves it at `/moonswing/` — the `base`, so **links written as component
props or hero actions need relative hrefs**; only markdown links get `base` prefixed for them.

**Nothing about the shell is documented twice.** `scripts/sync.mjs` runs before `dev` and
`build` and generates the configuration pages by splitting `CONFIG.md` on its `## ` headings,
plus the favicon, hero and social card from `assets/*.svg`. All of it is gitignored, and which
section lands on which page is the `PAGES` table in that script — a `## ` section no page claims
**fails the build**, so a new config section cannot quietly vanish from the site. Edit
`CONFIG.md`, never `src/content/docs/configuration/`.

The rest — the landing page, `start/`, `wiki/` — is hand-written, and is where the feature-level
rationale in this file is retold for someone who does not have the repository open.

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

`PopupTransition` plays one controller forward to open and backward to close, so an effect cannot describe an opening it has no closing for. The effect is the theme's (`popup_animation`) and so is its pace (`popup_animation_duration`, one number that the exit takes four fifths of), both snapshotted at open; `PopupEffect.none` wraps nothing and creates no controller.

### Scopes (`lib/scopes.dart`)

| Scope | Provides |
|-------|----------|
| `ThemeScope` | `ThemeConfig` — never constructed directly; see `ThemeProvider` |
| `ShellServicesScope` | how far along each global start-up task is |
| `LiveConfigScope` | `AppConfig` as the user is editing it; see `LiveConfigProvider` |
| `MiracleScope` | `MiracleConnection` (workspace IPC) |
| `DisplayScope` | `WaylandOutput?` — null until enumeration lands; see `DisplayProvider` |
| `BarScope` | anchor string (`'top'`/`'bottom'`/`'left'`/`'right'`) |
| `AccountsScope` | the linked accounts and the content read through them — `GoogleAccountStore`, `GoogleCalendarStore`, `GithubAccountStore`, `GithubStore`, `GithubLinkStore`, `CalDavAccountStore`, `CalDavCalendarStore` |

The first three go on **every** window, paired once in `_windowChrome` with `ShellTextRoot` and `kExcludeSemantics`. Three are **provider-only**: `grep -rn 'ThemeScope('`, `'DisplayScope('`, `'LiveConfigScope('` should each match `scopes.dart` plus that scope's one provider. Each provider is a `ListenableBuilder` emitting the scope and passing `child` through **unrebuilt**; resolving any of them in the root's `build` instead is what made one output landing, or one settings keystroke, rebuild every panel on every monitor plus the backgrounds, OSD and overlays. The `_refreshWindows()` calls left in the root are where its *list of native windows* changed — those cannot be a scope, since an `InheritedWidget` cannot span FlutterViews. `DisplayProvider` listens to one store and reads the other from the scope above rather than merging: `ListenableBuilder` is an `AnimatedWidget`, so a merge built in `build` re-subscribes every rebuild.

**`AccountsScope` (`lib/accounts/`) is how a module or desktop widget reaches an account**: `AccountsScope.githubOf(context).withToken(…)`, `AccountsScope.googleOf(context).withAccessToken(id, …)`, or a content store to lease. Never a sign-in of its own — Settings › Accounts is the only place one runs, and a signed-out consumer sends the user there (`SettingsRoute.accounts`). It hands out *stores*, fixed per window, so its lookups register no dependency and are safe from `initState`; a consumer listens to the store it reads. `_windowChrome` puts `AccountsScope.shell` on every root-owned window, and a lookup with no scope above it (popup content) falls back to the process-wide instance, so a popup sees the account its opener does. Tests inject through it. The services are drawn in their own colours — `BrandMark`, `BrandSignInButton` (`lib/accounts/brand_marks.dart`, arithmetic, no assets) — the one deliberate exception to the theme's palette.

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
set. `miracle_config/` is otherwise Flutter-free — the keysym table, the enum
labels and the colour conversion are plain Dart, because they are what
`test/miracle_config_test.dart` can reach on a machine with no compositor.

### Stores and leases

Shared state is a singleton `ChangeNotifier` (`ThemeStore`, `OsdStore`, `TrayStore`, `SystemStatsStore`, `NotificationStore`, `MprisStore`, `WeatherStore`, `AppIndex`, `TimersStore`, `DesktopStore`, …). Four rules run through all of them:

- **One poller, connection or timer for the machine, held by leases.** One FlutterView per panel per monitor means anything owned by a widget is owned N times — two bars used to mean two `/proc` walks, two `GET_TREE`s, two bus connections. Consumers `acquire()`/`release()`, the last release stops the work, and a lease can have tiers (a *detail* lease adds a per-process walk or a position poll). **A `Timer.periodic` in a widget `State` is the anti-pattern these exist to prevent**: an idle shell with a feature off must wake for it exactly never. `acquire()` must not notify synchronously — it runs inside the acquirer's `initState`.
- **Elapsed time is derived, never accumulated.** Hold a reference point and subtract against the wall clock; a ticker that added its own period drifts by however late each wakeup was and loses a suspend entirely. A backwards clock step is dropped, not subtracted.
- **A read that finds nothing new must not notify.** Every surface on every monitor listens, so compare a signature carrying only what a surface renders. Stores that mutate two lists at once must guard against their own synchronous notifications re-entering mid-write.
- **A failure is a visible state, not a silence.** Lost bus name, unreachable API, missing external tool: the last good value stays on screen, the reason is rendered, and a **retry** is offered — all of these recover without a restart and the shell cannot see it happen. A missing external tool names the *package*, never a package manager. An empty list from a failed service is indistinguishable from a genuinely empty one, which is why loaders and error states are not decoration.

**A countdown reaching zero rings *and* posts.** `TimersStore.onFinished` is one event — `announceFinishedTimer` — because the two halves answer different failures: the alarm reaches somebody who has walked away from the screen, which is what a timer is for, and the notification is what is still on the list when they come back, because a sound that has already played tells somebody who missed it nothing. The notification is posted **chimeless** (`NotificationStore.addOrReplace(chime: false)`, read as a delta by `NotificationSoundStore`), or one event would make two sounds a frame apart; that flag is for the shell's own posts only, since a notification arriving over D-Bus is somebody else's and the user's chime setting is the only thing that decides whether it is heard.

**The window switcher is the one shortcut that is *held*, and no single layer can see the whole gesture.** The first Alt+Tab and every Tab after it arrive as the compositor's trigger `begin` — they have to, because Mir *consumes* the key events a trigger matched, so a focused shell surface never sees them. Letting go of Alt is the half no trigger reports: `ext_input_trigger_action_v1.end` fires when the *combination* stops being held, which is Tab coming up with Alt still down. So one of the switcher's surfaces takes `LayerShellKeyboardMode.exclusive` and reads the release off the keyboard — the only reason it takes focus at all — and what it watches for is any modifier release that leaves none held, never Alt by name, because the binding is `[shortcuts]` and `super+tab` has to end on Super. The list is `ext-foreign-toplevel-list-v1` off the one `CaptureConnection`, which reports no focus at all, so the most-recently-used order is kept from miracle's `window` events and the switch itself goes back through miracle's IPC — **`xdg-activation-v1` cannot do it**: `activate` takes a `wl_surface`, a client can only name its own, and Mir resolves exactly that argument. **And the grab has to go back before the switch is asked for.** An exclusive layer surface is `mir_focus_mode_grabbing` to Mir, and miral refuses every focus change while a grabbing window is the active one — `select_active_window` answers the previous window untouched — while miracle's `focus` reports success regardless, so a switch sent with the switcher still holding the keyboard is dropped in silence and the compositor puts focus back where the user started as the surface goes away. `commit()` releases first, and `activateWindow`'s `GET_TREE` round trip is what orders the release ahead of the focus; a session reopened inside the previous one's fade takes the grab back, or its own release would be read by nobody.

### Controllers (`lib/request_controller.dart`)

The seam letting something deep in a surface ask the root for a window has two shapes. `RequestController<Req, Res>` carries a request/response pair and bakes in three rules no subclass may lose: **no listener means an immediate decline** (a headless run never awaits a window that will not appear — for the screencast picker this is the consent guarantee), a second request **supersedes the first as declined**, and **dispose answers the awaiting caller**. `SignalController` is fire-and-forget: a monotonic counter plus `notifyListeners`. Neither is `InputTriggerStore`, which reports compositor triggers and whose listeners toggle on any notification.

### Config (`lib/config.dart`, `lib/config_reader.dart`, `lib/config_store.dart`)

`AppConfig.load()` reads `~/.config/moonswing/config.toml` into typed objects, writing a default layout if absent. `ConfigStore.instance` is the live writable view the settings UI mutates, with a debounced atomic write.

**Every field read goes through `TomlReader`, whose invariant is the one rule of this layer: a wrongly-typed value costs that key, never the whole table.** A throw out of any `fromMap` — a module's included, since `Module.loadAll` runs inside `AppConfig.fromMap` — makes `load` discard the user's entire config. So readers type-test and coerce (`height = 32.0` is a TOML float), treat NaN/infinity as absent, and clamp via `min:`/`max:`; never a bare `as X?` cast. Only a TOML *syntax* error still costs the file, and that path logs. The same degrade-per-field discipline applies to data from outside — an unknown enum from a web API, a tree that will not parse, a bad row in a shipped table: it costs that row, never the surface.

**Every section class carries value equality**, which is load-bearing: the getter mints a fresh object graph per read and the store notifies on every keystroke, so without `==` the notifier behind `LiveConfigScope` could never refuse one. Maps hash on `length`, lists use `listEquals` + `Object.hashAll`. `test/config_golden_test.dart` pins defaults and degradation.

### Theme (`lib/theme/`, `lib/popup_surface.dart`)

A theme is a **file**, not a config section: a flat TOML table under `~/.config/moonswing/themes/`, named by a top-level `theme = "dracula"`. `ThemeStore` owns the resolved palette, catalogue, seeding, CRUD and the debounced write, and reads `ConfigStore` for the `theme` key alone (never `appConfig`, which re-runs `Module.loadAll`).

- **`ThemeProvider` is the only thing that constructs a `ThemeScope`.** Each FlutterView is given the theme separately, so a module that snapshotted `ThemeScope.of` when opening a window froze it; listening is what makes an open popup restyle.
- **`font_size` is a `TextScaler` on the `MediaQuery` `ThemeProvider` publishes**, so the whole `ShellFontSizes` scale moves as one and 13.0 is `noScaling` — a `DefaultTextStyle` size would reach only text that names none. So **a `TextPainter` deciding a layout must be given the scaler**. Pixels are *not* scaled: growing the type is not an instruction to grow the bar.
- **Shipped themes are embedded constants**, read-only, forked on edit, and **re-seeded when they drift**, so a palette fix reaches an install that has already run; membership in `kBuiltInThemes` *is* the read-only test. Constants because nothing in the shell resolves paths relative to the bundle — the same reason the emoji table and Tux's SVG are constants and `pubspec.yaml` has no `assets:` section. **The shipped sounds obey the same rule by being arithmetic** — `lib/shell_sound.dart` holds the RIFF writer, the XDG sound-theme search, the cache directory and the mpv wrapper that the chime (`lib/notification_sound.dart`), the screenshot shutter (`lib/capture/capture_sound.dart`) and the timer alarm (`lib/timers/timer_sound.dart`) all sit on, and each of those holds only its own catalogue of numbers. The alarm also borrows the *chime's* renderer, because a ding is a struck bell and the shutter is the only one of the three that is noise rather than a note; its cache files are namespaced `timer-…` all the same, so two families whose slugs collided cannot share a file. Synthesis is also what makes that set shippable, since a recorded chime or camera click is somebody else's licence to carry; and the player is one **per family, not per process**, because mpv plays one file at a time and a shared one would have a notification arriving mid-screenshot cut the shutter off.
- **Popup geometry is theme-driven and grows the compositor surface.** A shadow or attach flare paints outside the card's box, but a popup is its own surface sized to its content, so `openPopup` pads the measured box by `popupSurfaceInsets`, offsets the positioner by the same, and grows the GTK geometry hints — all three, or every menu lands off its button. `popup_gap = 0` is the attached mode (joined edge squares off, drops its rim, clamps the shadow). Read `lib/popup_surface.dart` and `lib/popup.dart` rather than re-deriving the arithmetic.
- **A rimmed bar leaves its own rim out across the mouth of an open menu**, because nothing the card paints can reach that line: the compositor places a bar popup *below* its panel, never over it. Two attempts from the card's end are recorded in the code so nobody tries a third — a *collar* painting outside the card's box with a matching negative `WindowPositioner.offset` (`popup_surface.dart`), and an inset on `barAnchorRect` (`popup.dart`). `PanelRimBreaks` (`lib/panel_rim.dart`) is the mechanism: the popup publishes the range its mouth covers, keyed on the panel's own `FlutterView` — one isolate, two surfaces — and `PanelRimPainter` strokes the outline `Border.all` would with that one band clipped away, which is what keeps `panel_radius` free. The mouth is the card *plus its flare*, and it predicts the compositor's slide, since the modules at either end of a bar are exactly the ones whose popups get slid back onto the output. Gated on rimmed *and* attached (`panelPaintsOwnRim` — `carbon` alone among the shipped themes), which turns the decoration's own border off through `includeRim`; the break is published from the post-frame callback that measures the window and cleared **synchronously** in `closePopup`, since several call sites close one popup and open another in the same gesture. The rim goes on as a `CustomPaint` **`foregroundPainter:` over the bar's content, never a layer stacked over it** — a *background* painter is opaque to hits (see the hit-testing rules below), and a full-width one over a bar took every click on every module in it.
- **`lib/theme/tokens.dart`** sits below the theme: `ShellDurations`, `ShellRadii`, `ShellFontSizes` (a scale *relative* to `body`), `ShellSizes` (pointer-target boxes, never glyph sizes), `kErrorColor`, `kOnAccent`. A literal that matches a token is a token.
- Alpha is overridden where prose is read: `panelBackgroundDecoration` honours `panel_background`'s alpha verbatim, while the settings panel and everything floating over it (`OpaquePopupScope`) force opacity. There is deliberately **no blur key**: a `BackdropFilter` reaches only what Flutter already painted beneath it, which in an overlay window is nothing — it changed no pixel while costing a full-output Gaussian per frame.

### Shared primitives

- **`HoverRegion`** (`lib/hover_region.dart`) — `builder: (context, hovered) => …` plus tap callbacks; the shell has no Material and dozens of `StatefulWidget`s existed only to carry `bool _hovered`. It emits the `GestureDetector` too, at `HitTestBehavior.opaque`, and that half is load-bearing: a detector with no `behavior:` is `deferToChild`, and `Padding`, `Align`, `ConstrainedBox`, `ClipRRect`, `Row`/`Column`/`Stack`, `RenderImage` and an undecorated `Container` all answer `hitTestSelf == false` — so a 26px button hovered over 26 and *fired* over the 11px glyph. `CustomPaint` is the one that goes the other way: `CustomPainter.hitTest` defaults to **every point a hit for a `painter:`** and none for a `foregroundPainter:`, so a decoration painted over something interactive is a `foregroundPainter:` on it, and a childless `CustomPaint` in a `Stack` swallows everything under it. Greppable rule: **every `GestureDetector(` in `lib/` carries a `behavior:` or is inside `HoverRegion`.** A decorated `Container` is hit-testable only inside its `borderRadius`; `Container(color: cond ? c : null)` only while `cond` holds; opaque is not enough without a box of at least `ShellSizes.minTapTarget`; the builder-only form emits no detector, or it would swallow hits meant for a `Stack` sibling. `onTapDown` is not interchangeable with `onTap` — every popup toggle opens on tap-*down*, inside the pointer-down the reopen guard is consumed in. `test/tap_target_test.dart` taps **corners**, because a centre tap passes on every one of these bugs.
- **`BarButton`**, **`SkyIconButton`** — bar-module chrome (theme hover fill), and the round action on a picture-backed desktop card (colours from the picture; a tap, so the card stays draggable under it).
- **`ShellTextRoot`** — `Directionality` + theme-font `DefaultTextStyle`, applied once per window.
- **`FadeOverlayScaffold`** — scrim + centred card, and owner of the `closing` handshake (reverse, *then* `onClosed`, which may tear the window down). Nothing may wrap the scaffold in an `Opacity`: these windows span the output, so that layer is a full-output offscreen per frame. The scrim fades by its own alpha; only the card keeps a layer, built outside the `AnimatedBuilder` — and for the same arithmetic **no effect moves the scrim**, only the card. The entrance is the theme's, the way a popup's is: `overlay_animation` and `overlay_animation_curve` multiply out to the shape (`lib/overlay_transition.dart` plays it, `lib/theme/overlay_effect.dart` is the pure table), `overlay_animation_duration` paces it and `overlay_animation_exit_ratio` says how the exit relates — a ratio, never a second duration, so the two cannot drift. Snapshotted at open, as a popup's is; `none` builds no controller and answers `onClosed` on the frame it is asked. A call site gets `durationScale`, a *proportion* of the theme's pace, and nothing else: the settings overlay is statelier by 240/160 rather than by a duration of its own, because an overlay must not opt out of the user's choice.
- **`AnchoredSearchDropdown`** (`lib/search_list.dart`) — the one dropdown. Floats in the **root** overlay (an inline one pushes the form down as it opens and cannot open off the bottom of the screen), matches the trigger's width or right-aligns, flips above when the room below will not hold the list, shows a filter field only past a threshold, and supports async search (debounced, applied in request order).
- **`OverlaySearchField`** — the launcher/emoji/settings search field, with `RenderEditable` mouse wiring a hand-rolled copy would get wrong.
- **`lib/overlay/settings/controls.dart`** — the themed form controls. **Pages import them; they never redeclare one.** Private clones are how the audio and bluetooth pages lost the theme font and the display page froze its palette. A control the library lacks gets *added to the library*; `test/settings_shared_controls_test.dart` pins the theme-font half. An **add** button goes at the top right of the collection it adds to, never under it. A field bound to a setting is a `SettingsCommitField` (or `SettingsNumberField`, which is one): it reports on Enter, blur or a click outside, never per keystroke, because every settings write is live and a half-typed value would be applied on the way to the one meant. Explanatory prose goes behind a `SettingsInfoTip` (a row's or section's `info:`), not in a `SettingsHint` under the rows — hints are for empty states and warnings; a pane wrapped in `SettingsPaneStyle(roomy:, fieldInfo:)` spaces its rows wider and gives every `SettingsRow.field` its catalogue description as the tip, which is how Window Manager is built.

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

**Launching an application is a D-Bus act too (`lib/app_info.dart`, `lib/app_scope.dart`).** GIO spawns a desktop entry's command out of this process, so the application inherits the shell's cgroup — under the snap that is `snap.moonswing.…scope`, which is how snapd decides the snap "has running apps" and refuses to refresh it, and why stopping the shell's unit used to take everything ever launched from it down as well. So every launch is followed by an adoption: `StartTransientUnit` on the session's systemd user manager moves the pid into an `app-…-<pid>.scope` of its own under `app.slice`. The one hook that catches *every* launch is `GAppLaunchContext::launched` — the same context `g_app_info_launch`, `g_app_info_launch_uris`, `g_app_info_launch_default_for_uri` and `g_desktop_app_info_launch_action` are all already given for their startup-notification token, which is why `_launchContext()` now falls back to a plain `g_app_launch_context_new()` rather than launching with none. The adoption is best-effort by construction: it runs after the application has started, a session with no systemd user manager (or a shell cgroup outside its delegated subtree) costs the scope and nothing else, and a `ServiceUnknown` is remembered so twenty launches are not twenty doomed round trips. **That same context also carries the environment the application is spawned with**, which is the other thing it inherits from this process and the one that cannot be repaired afterwards: under the snap `LD_LIBRARY_PATH` leads with `$SNAP/usr/lib/<triplet>`, and a *host* application resolving a soname there is `lib/host_process.dart`'s ffmpeg bug with a quieter failure — the reported shape is a GTK application that runs with no icons at all, window controls included, because the host's SVG pixbuf loader will not load against a staged gdk-pixbuf. So `_launchContext()` applies `hostProgramEnvironment()` through `g_app_launch_context_setenv`/`unsetenv`, which is where the *unset* half of that map earns its keep: a process API that can only override spells the removal as an empty string, a launch context need not.

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
| `miracle_config/` | The compositor's own configuration: the store behind `overlay/settings/miracle/`, the keysym key table, enum labels |
| `theme/` | `ThemeConfig`, `ThemeStore`, `ThemeProvider`, built-in themes, tokens, fonts |
| `launcher/`, `emoji/` | The two search overlays: index, pure ranking, controller, card |
| `weather/`, `moon/`, `media/`, `fortune/`, `tux/`, `clock/` | Data layers behind a bar module and/or desktop widget: store + pure model + painters |
| `stocks/` | The stock market strip and desktop widget's one source: Yahoo Finance read the way `ticker` reads it (`stock_api.dart` — the `A3` cookie, the crumb, the EU consent post, one retry after a refusal), the pure quote parse with `ticker`'s which-price-wins rule (`stock_quote.dart`), the leased store that owns the watchlist and slows its poll while every market on it is shut, and the crawl (`stock_crawl.dart` — a render object that moves a layer per frame, never re-records the strip) |
| `accounts/` | `AccountsScope` and the brand marks; Settings › Accounts itself is `overlay/settings/accounts.dart` + `accounts/` beside it |
| `caldav/` | CalDAV and iCalendar, Flutter-free below the account store: `ical.dart` (a parser that keeps every property and component it does not understand, a writer that folds by octets, per-line degradation), `caldav_client.dart` (discovery through `.well-known` and the principal, a change token from `getctag`/`sync-token`, `calendar-query`, `calendar-multiget`, conditional `PUT`/`DELETE`; it follows redirects itself, since `http.Client` does only for GET), `CalDavAccountStore` — any number of accounts behind Settings › Accounts › CalDAV, each kept only once its server has answered with calendars, passwords in the XDG state dir at 0600, the todo sync signing in with the account its linked list was found on — and `CalDavCalendarStore`, the chosen `[caldav] calendars` fetched per calendar under the same leased-window shape as `GoogleCalendarStore` (`caldav_events.dart` is the pure `VEVENT` → event half, with a fallback `RRULE` expander for a server that ignores `<c:expand>`). The Calendar tab reads both through `CalendarEventSource` (`lib/accounts/calendar_event_source.dart`), merged by `MergedCalendarEvents`; the tab's model is `GoogleEvent` for either, and an event is told apart by its calendar id — a CalDAV one is the collection's URL |
| `github/` | The GitHub account behind Settings › Accounts — `GithubAccountStore`: the device-flow sign-in (not tied to a lease; it ends when the code expires), the token file, `withToken` (a rejected token signs the account out visibly, once, for every consumer) — and the polled notification list, `GithubStore`, which follows the account and drops a list fetched under a token that has since changed — and `GithubLinkStore`, the title and state behind a link to an issue or pull request (`github_links.dart` is the pure URL parse), with no poller: a link is read when a surface `watch`es it, kept ten minutes (a failure one), at most four reads in flight, one `ValueListenable` per link so a title landing rebuilds its own chip, and every answer dropped when the token changes. `GithubLinkChip` draws one inline as a `WidgetSpan`, built with no text scaling of its own because the span already scales its child; the todo board's cards swap their GitHub links for it through `highlightMatchesWithChips` while signed in. `fetchIssue` never throws `GithubAuthException` for one repository refusing — only a 401 signs the account out |
| `google/` | The Google accounts behind Settings › Accounts — any number, and every consumer reads all of them — for any module to use: the loopback + PKCE sign-in (Google's device flow refuses Calendar scopes) run as the project's own Desktop OAuth client — its ID and secret are source constants in `google_client.dart`, public by design, and `docs/google-cloud-setup.md` is how that Cloud app is run — with only the grants (and the client each was issued to, so a rotation drops it visibly) in the XDG state dir at 0600 (never `config.toml`), `GoogleAccountStore.withAccessToken(accountId, …)` (one shared refresh per account, one retry on a 401, a dead grant signs *that* account out visibly), the calendar store whose leases name a time window — one `[google] calendars` list for every account (ids are unique across accounts; `primary` is each account's own), each calendar fetched and failing on its own, and a primary event keyed by its account so the key cannot collide (`legacyKey` lets the todo sync adopt a card made under the single-account `primary/…` key) — and the todo sync — one lease on *today*, a one-shot timer to the next start or end, the arithmetic in `todo/todo_calendar_sync.dart`. A card the user moves is `manual` and the sync stops moving it; a field the user edited is left alone; a deleted card's event is remembered in `meta` |
| `system/` | UI-free `/proc`,`/sys` sampling; `overlay/system/` is its tab |
| `timers/` | Countdowns and stopwatches: pure format, store, the alarm a finished one rings, shared widgets |
| `todo/` | The todo board and notes: the pure model (columns, move history, recurrence arithmetic, notes, search terms, the old JSON format now read only to import it), the SQLite database `~/.local/share/moonswing/notes.db` — one `entries` table for cards *and* notes, one trigram FTS5 index kept by triggers, so any substring finds either — the store that holds the board in memory, writes a diffed transaction per debounced edit, mirrors every landed write to `backup/todo-backup.json` (and rebuilds a missing or *damaged* — never a newer-schema — database from it), makes recurring copies and posts the due-today reminder, the two-way sync with a CalDAV task list (`todo_caldav_sync.dart` drives it, `todo_caldav_map.dart` is the pure half: card ↔ `VTODO`, a three-way merge against the task as the server last had it — `TodoRemote.raw`, which is also what a write patches, so properties the board does not own survive — and the pull plan; the board stays the source for everything on screen, a card deleted here is a `remote_tombstones` row until the server has the delete, every write is `If-Match`/`If-None-Match`, and nothing runs while no list is linked), the board's search (a filter in place), the standup summary (`todo_standup.dart`: finished, in progress and to-do since the last one, calendar cards never counted, taken only by the card's own button — opening it takes nothing — whose time is a `meta` row; every summary taken is a `standups` row, and invalidating the latest deletes it and puts that time back to where it counted from), the display order (`todo_layout.dart`: overdue first in open columns, Finished and Abandoned folded by day — a view only, the store's order is the user's), the controller carrying the clicked output, and the overlay |
| `osd/` | The volume/brightness card, its store and its sources |
| `capture/` | Screenshots and recording: targets, selection, ffmpeg, store, the shutter sound |
| `screencast/` | The ScreenCast portal backend, capture sessions, the consent picker |
| `polkit/`, `power/`, `lock/` | Authentication agent, power-key policy and menu, session lock |
| `native/`, `wayland_ffi/`, `pipewire/` | dlopen plumbing, libwayland bindings, libpipewire + SPA |
| `scratchpad/` | The window manager's scratchpad: the one store the bar button and both `[shortcuts]` keys send miracle's `scratchpad show` / `move scratchpad` through. No count or shown state — miracle keeps stashed windows out of `GET_TREE` |
| `switcher/` | Alt+Tab: the open-window list over `ext-foreign-toplevel-list`, its recency order, the overlay and the switch itself |
| `input_trigger/`, `keyboard/` | Compositor global shortcuts; keyboard layout over locale1 |
| `keybinds/` | The cheat sheet behind the bar's keyboard icon: miracle's own bindings over `GET_KEYBINDS` and the shell's own `[shortcuts]`, the pure models that turn either into key caps, their two stores, the key-press capture and the overlay |

Feature-level rationale that used to live in this file is in the git history of `CLAUDE.md` and in the doc comments of the files themselves.
