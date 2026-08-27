# Graceful Panel Configuration

Graceful Panel is configured via a TOML file located at:

```
~/.config/graceful-shell/config.toml
```

If `$XDG_CONFIG_HOME` is set, the config file is read from `$XDG_CONFIG_HOME/graceful-shell/config.toml` instead.

The panel works out of the box with no configuration file. All settings have sensible defaults that match the standard layout. You only need to create a config file to customize behavior.

If the config file is missing or contains errors, the panel falls back to defaults silently.

## Panels

The application supports multiple panels, each anchored to a different edge of the screen. Panels are defined under `[panels.<name>]` sections, where `<name>` is an arbitrary identifier (e.g., `top`, `bottom`, `dock`).

Each panel has its own height, padding, anchor position, layer, and module layout.

### Example: Single Panel

```toml
[panels.top]
height = 32
padding_horizontal = 40
anchor = "top"
layer = "top"

[panels.top.layout]
left   = ["workspaces"]
center = ["media_player"]
right  = ["sound_control", "battery", "weather", "clock"]
```

### Example: Two Panels (Top and Bottom)

```toml
[panels.top]
height = 32
padding_horizontal = 40
anchor = "top"
layer = "top"

[panels.top.layout]
left   = ["workspaces"]
center = ["media_player"]
right  = ["sound_control", "battery", "weather", "clock"]

[panels.bottom]
height = 32
padding_horizontal = 20
anchor = "bottom"
layer = "top"

[panels.bottom.layout]
left   = []
center = ["clock"]
right  = ["weather"]
```

### Panel Settings

| Key                  | Type   | Default | Description                                                             |
| -------------------- | ------ | ------- | ----------------------------------------------------------------------- |
| `height`             | int    | `32`    | Panel thickness in pixels (height for top/bottom, width for left/right) |
| `padding_horizontal` | int    | `40`    | Left and right padding in pixels                                        |
| `anchor`             | string | `"top"` | Screen edge: `"top"`, `"bottom"`, `"left"`, or `"right"`                |
| `layer`              | string | `"top"` | Layer shell layer: `"background"`, `"bottom"`, `"top"`, or `"overlay"`  |

The `anchor` value determines which edges the panel is attached to:

- `"top"` — anchored to the top, left, and right edges (horizontal bar at top)
- `"bottom"` — anchored to the bottom, left, and right edges (horizontal bar at bottom)
- `"left"` — anchored to the left, top, and bottom edges (vertical bar on left)
- `"right"` — anchored to the right, top, and bottom edges (vertical bar on right)

## Layout

Each panel has a `[panels.<name>.layout]` section that controls which modules appear and where. The panel has three sections arranged horizontally: **left**, **center**, and **right**. The center section expands to fill available space.

```toml
[panels.top.layout]
left   = ["workspaces"]
center = ["media_player"]
right  = ["sound_control", "battery", "weather", "clock"]
```

Each key is an ordered array of module names. Valid module names are:

- `"workspaces"` - Workspace switcher, with the icons of what is open on each (requires Miracle WM)
- `"media_player"` - MPRIS media player controls
- `"sound_control"` - PulseAudio volume display
- `"battery"` - Battery status monitor
- `"network"` - Network connectivity (ethernet or WiFi name and IP address)
- `"weather"` - Weather display
- `"notifications"` - Notification bell and the notification panel
- `"clock"` - Date and time
- `"dock"` - Application launcher dock

A module omitted from all sections of all panels is disabled entirely. You can place any module in any section and in any order. The same module can appear in multiple panels.

**Note:** When a layout section is present, all three keys (`left`, `center`, `right`) should be specified. An omitted key defaults to an empty list, not to the default modules.

## Module Settings

Per-module settings live under `[modules.<name>]`. These are global and shared across all panels.

### Weather

```toml
[modules.weather]
unit = "fahrenheit"
refresh_minutes = 30
```

| Key               | Type   | Default        | Description                             |
| ----------------- | ------ | -------------- | --------------------------------------- |
| `unit`            | string | `"fahrenheit"` | `"celsius"` or `"fahrenheit"`           |
| `refresh_minutes` | int    | `30`           | How often to re-fetch weather (minutes) |

### Battery

```toml
[modules.battery]
poll_seconds = 30
```

| Key            | Type | Default | Description                                   |
| -------------- | ---- | ------- | --------------------------------------------- |
| `poll_seconds` | int  | `30`    | Polling interval for battery status (seconds) |

### Clock

```toml
[modules.clock]
show_date = true
```

| Key         | Type | Default | Description                             |
| ----------- | ---- | ------- | --------------------------------------- |
| `show_date` | bool | `true`  | Whether to show the date alongside time |

### Media Player

```toml
[modules.media_player]
max_text_width = 200.0
```

| Key              | Type  | Default | Description                                  |
| ---------------- | ----- | ------- | -------------------------------------------- |
| `max_text_width` | float | `200.0` | Width in pixels before text starts scrolling |

### Workspaces

```toml
[modules.workspaces]
show_app_icons = true
icon_size = 14
max_icons = 4
```

| Key              | Type | Default | Description                                                           |
| ---------------- | ---- | ------- | --------------------------------------------------------------------- |
| `show_app_icons` | bool | `true`  | Show the icons of the applications open on each workspace             |
| `icon_size`      | int  | `14`    | Icon size in pixels (8–64)                                            |
| `max_icons`      | int  | `4`     | Icons one workspace shows before the rest collapse into a `+N` (1–16) |

With `show_app_icons` on, each workspace button carries its number or name
*and* the icons of what is open on it, so the buttons are no longer all the
same width — a workspace holding three windows is wider than an empty one. The
icons come from Miracle's window tree, and an application is drawn once however
many of its windows are on the workspace.

The tree is re-read in response to Miracle's own `window`, `workspace` and
`output` events — never on a timer — and only the window changes that can move
a window between workspaces count, so switching focus costs nothing. Nothing
is read at all while `show_app_icons` is off, and one reader serves every panel
on every monitor.

### Dock

```toml
[modules.dock]
apps = ["firefox", "org.gnome.Nautilus", "kitty", "code"]
icon_size = 24
```

| Key         | Type         | Default | Description                                          |
| ----------- | ------------ | ------- | ---------------------------------------------------- |
| `apps`      | string array | `[]`    | Desktop entry IDs of apps to show in the dock        |
| `icon_size` | int          | `24`    | Icon size in pixels (should fit within panel height) |

Each entry in `apps` is a desktop file ID (the filename without `.desktop`). For example, `"firefox"` corresponds to `firefox.desktop`, and `"org.gnome.Nautilus"` corresponds to `org.gnome.Nautilus.desktop`.

Desktop files are looked up from standard XDG application directories. Apps with missing desktop files are silently skipped.

### Network

```toml
[modules.network]
poll_seconds = 10
```

| Key            | Type | Default | Description                                         |
| -------------- | ---- | ------- | --------------------------------------------------- |
| `poll_seconds` | int  | `10`    | How often to re-check network status (seconds)      |

### Launcher

A magnifying-glass button that opens the application launcher — the same overlay the `open_launcher` shortcut opens (see [Shortcuts](#shortcuts)), and only ever one of them at a time.

```toml
[modules.launcher]
icon_size = 18
```

| Key         | Type | Default | Description                             |
| ----------- | ---- | ------- | --------------------------------------- |
| `icon_size` | int  | `18`    | Icon size in pixels                     |

The launcher itself lists every installed application, ranks them as you type (matching the name, generic name, `Keywords=`, and desktop ID, in that order of preference), and launches the selected one with Enter. Applications that declare `[Desktop Action …]` groups — "New Private Window", "New Document" — show a chevron; hovering it, or pressing Right with the caret at the end of your query, opens those as a submenu.

Typing a calculation shows its result above the application results:

```
2^10/4      →  256
(1+2)*3     →  9
sqrt(16)+1  →  5
```

`+ - * / ^ % !`, parentheses, and the usual functions (`sqrt`, `sin`, `cos`, `tan`, `ln`, `log`, `abs`, `ceil`, `floor`, …) are understood, along with the constants `pi` and `e`. A query has to contain both a digit and an operator to be treated as arithmetic, so searching for an application never turns into a calculation.

Escape or a click on the blurred backdrop dismisses the launcher.

**This module is in the default bottom panel, but adding it to an existing config is manual** — the default config file is only written when none exists. Add `"launcher"` to a panel's layout:

```toml
[panels.bottom.layout]
right = ["media_player", "notifications", "launcher"]
```

The launcher lists the same applications any menu would: those `g_app_info_should_show()` accepts. An entry with `NoDisplay=true`, or one restricted with `OnlyShowIn=GNOME;`, will not appear.

### Notifications

A bell that shakes and shows a count when a notification arrives, and opens the
notification panel on click — a full-height surface that slides in from the
right edge over everything else on screen, listing what has arrived with each
notification's actions and a **Clear all**. The shell is the desktop's
notification daemon, so this is where notifications from every application land.

No configurable settings.

**This module is in the default bottom panel, but adding it to an existing
config is manual** — the default config file is only written when none exists.
Add `"notifications"` to a panel's layout:

```toml
[panels.bottom.layout]
right = ["media_player", "notifications", "launcher"]
```

The panel ignores the bars' exclusive zones and draws on the overlay layer, so
it covers the full height of the output and passes over the panels rather than
being pushed between them.

### Sound Control

No configurable settings.

### System Monitor

Drives both the panel module (CPU, memory, and temperature, with a popup) and the **System** tab in the overlay, which adds usage graphs, swap, load average, network throughput, disk usage, and a sortable process table you can kill from. The two share one sampler, so these settings apply to both.

```toml
[modules.system_monitor]
poll_seconds = 2
temp_unit = "celsius"
history_samples = 120
cpu_percent_mode = "machine"
show_kernel_threads = false
confirm_kill = true
kill_grace_seconds = 5
disk_poll_seconds = 30
```

| Key                   | Type   | Default     | Description                                                                                              |
| --------------------- | ------ | ----------- | -------------------------------------------------------------------------------------------------------- |
| `poll_seconds`        | int    | `2`         | How often stats are re-read (1–60)                                                                        |
| `temp_unit`           | string | `"celsius"` | `"celsius"` or `"fahrenheit"`                                                                             |
| `history_samples`     | int    | `120`       | How many samples the graphs keep (10–600). At the default cadence, 120 is four minutes                    |
| `cpu_percent_mode`    | string | `"machine"` | `"machine"`: 0–100% of the whole machine, so the process rows sum to the total. `"core"`: `top`-style, where 100% is one saturated core |
| `show_kernel_threads` | bool   | `false`     | Show kernel threads in the process table                                                                  |
| `confirm_kill`        | bool   | `true`      | Ask before quitting a process. A *force* quit always confirms regardless                                  |
| `kill_grace_seconds`  | int    | `5`         | How long a process gets to honour the request to quit before the row offers to force it (1–60)            |
| `disk_poll_seconds`   | int    | `30`        | How often filesystem usage is re-read (5–600). Separate because it shells out to `df`                     |

Nothing is read until something needs it: the shell only samples `/proc` while the panel module is on a panel or the System tab is open, and the per-process scan runs only while that tab is actually the visible one.

Two processes can never be killed from here, whatever the config says: the shell itself, and `init`.

## Shortcuts

The `[shortcuts]` section binds the shell's global keyboard shortcuts. These are registered with the compositor (Mir's `ext-input-trigger` protocols), so they fire no matter which window has focus.

```toml
[shortcuts]
open_settings = "ctrl+shift+s"
open_launcher = "ctrl+space"
power_button = "poweroff"
```

| Key             | Type   | Default            | Description                                    |
| --------------- | ------ | ------------------ | ---------------------------------------------- |
| `open_settings` | string | `"ctrl+shift+s"`   | Opens (and closes) the settings overlay        |
| `open_launcher` | string | `"ctrl+space"`     | Opens (and closes) the application launcher    |
| `power_button`  | string | `"poweroff"`       | The machine's own power button — what it *does* is [`[power]`](#power-button) |

**Changing these requires restarting the shell.** Shortcuts are registered once at start-up; unlike the theme or panel layout they do not reload live.

### Syntax

A shortcut is modifiers and a key joined by `+`, in any case:

| Part      | Accepted spellings                                    |
| --------- | ----------------------------------------------------- |
| Modifiers | `ctrl` / `control`, `shift`, `alt`, `super` / `meta` / `win` / `logo` |
| Key       | a letter `a`–`z`, a digit `0`–`9`, `f1`–`f24`, or a named key |

Named keys: `space`, `return` / `enter`, `tab`, `escape` / `esc`, `backspace`, `delete` / `del`, `insert`, `home`, `end`, `pageup`, `pagedown`, `left`, `right`, `up`, `down`, `print`, `pause`, `menu`, `poweroff` / `power`, `sleep`, and the punctuation names `minus`, `equal`, `plus`, `comma`, `period`, `slash`, `backslash`, `semicolon`, `apostrophe`, `grave`, `bracketleft`, `bracketright`.

Left/right modifier variants are deliberately not offered: a trigger fires only when *exactly* the registered modifiers are held, so binding the left Control key would stop the shortcut working on the right one.

**Shift must be written out.** `"ctrl+S"` means Ctrl and the S key — it is read identically to `"ctrl+s"`. Write `"ctrl+shift+s"` if you want Shift in the combination.

### Layouts

The compositor matches on the character your layout actually produces, so a shortcut containing `shift` is resolved before it is registered: `"ctrl+shift+s"` registers `S`, and `"ctrl+shift+1"` registers `!`. That resolution uses a **US layout** table. On other layouts, shifted digits and punctuation will be wrong — letters are fine everywhere.

Two escape hatches cover the rest:

```toml
[shortcuts]
open_settings = "ctrl+0x1b"      # a raw xkbcommon keysym
open_settings = "ctrl+code:31"   # a raw evdev keycode — layout-independent
```

The `code:` form binds the physical key, so it keeps working when you switch layouts.

### Disabling a shortcut

Set it to an empty string (or `"none"`) to register nothing — useful when a combination collides with an input method such as fcitx or IBus:

```toml
[shortcuts]
open_settings = ""
```

An unparseable value is not treated as "disabled": it falls back to the default and logs why, so a typo does not silently cost you a shortcut.

If another client already owns a combination, the shell logs it and moves on — it never fails to start over a shortcut.

## Power Button

The `[power]` section decides what pressing the machine's own power button does. Out of the box the shell intercepts it and shows the power menu — a dialog offering Lock, Log Out, Sleep, Restart and Shut Down — instead of the machine powering off where it stands.

```toml
[power]
key_action = "menu"
inhibit_logind = true
```

| Key              | Type    | Default  | Description                                            |
| ---------------- | ------- | -------- | ------------------------------------------------------ |
| `key_action`     | string  | `"menu"` | What a press does                                      |
| `inhibit_logind` | boolean | `true`   | Hold systemd-logind's `handle-power-key` lock while the shell handles the key |

`key_action` takes one of:

| Value        | What happens                                                             |
| ------------ | ------------------------------------------------------------------------ |
| `"menu"`     | Show the power menu. Escape, or a click outside it, cancels; Enter answers with Shut Down |
| `"shutdown"` | Power off, with no confirmation                                           |
| `"reboot"`   | Restart, with no confirmation                                             |
| `"suspend"`  | Suspend to RAM                                                            |
| `"lock"`     | Lock the session                                                          |
| `"logout"`   | End the session                                                           |
| `"none"`     | Nothing — the key is left to systemd-logind, which is what handles it on a machine with no shell running |

`"off"`, `"restart"`, `"sleep"` and `"ignore"` are accepted as spellings of `shutdown`, `reboot`, `suspend` and `none`. A value the shell does not recognise falls back to `"menu"` and logs why, rather than silently leaving you with a power button that does nothing.

Both keys are live: changing them in Settings → Shell → Power Button takes effect on the next press. The *binding* — `[shortcuts] power_button` — is not, because global shortcuts are registered once at start-up.

### Why `inhibit_logind` exists

systemd-logind watches the power button directly, and `HandlePowerKey` in `logind.conf` is `poweroff` on a stock system. It does not care that a compositor also delivered the key to the shell — so a shell that only listened would draw its power menu onto a machine that was already going down.

While the shell is handling the key it therefore takes logind's `handle-power-key` inhibitor lock, in `block` mode, which stops logind acting on presses for as long as the shell holds it. The lock is released the moment the shell exits — including if it crashes — so it can never leave a machine that will not power off.

Two things it deliberately does **not** claim: `handle-power-key-long-press` (holding the button down keeps doing whatever logind is configured to do, which is the "get me out of here" gesture), and the key on a compositor that never delivered it. The shell takes the lock only once the compositor has confirmed the shortcut registration, so on a compositor without Mir's `ext-input-trigger` protocols — or where another client already owns the key — the button keeps working exactly as it did before.

Turn `inhibit_logind` off if your `logind.conf` already says `HandlePowerKey=ignore`; otherwise, with it off, logind's shutdown and the shell's dialog race.

### If the button does nothing

- Check that the compositor is delivering it: the shell logs `input-trigger: "graceful-shell.power-button" owned` on start-up when it has the key, and says so when another client owns it instead.
- Some keyboards' power keys emit a keysym this table's `poweroff` does not match. Bind the physical key instead, which is layout- and keysym-independent:

  ```toml
  [shortcuts]
  power_button = "code:116"   # evdev KEY_POWER
  ```

- A laptop lid or a "sleep" key is a different key entirely (`sleep`, `code:142`); this section is only about the power button.

## Theme

Themes live in their own files, one per theme, under `~/.config/graceful-shell/themes/`. `config.toml` picks one by name — the file's basename without `.toml`:

```toml
theme = "dracula"
```

Six themes ship with the shell and are written into that directory the first time it starts:

| Name       | Looks like                                                        |
| ---------- | ----------------------------------------------------------------- |
| `graceful` | Deep maroon over near-black. The default, and the palette earlier versions hard-coded. |
| `forest`   | Pine and moss over a near-black green, floating on a lit sage rim. |
| `dracula`  | The canonical [Dracula](https://draculatheme.com) palette.         |
| `glassy`   | Cool translucent surfaces that let the wallpaper through.          |
| `midnight` | Indigo over deep water, one type size up, and lit: its cards glow rather than casting a shadow. |
| `carbon`   | Machined graphite. Flat, square, unlifted — and every bar menu grows out of the bar on a flared join. |

If `theme` is absent, names a theme that does not exist, or names a file that will not parse, the shell falls back to `graceful` rather than starting unstyled. A single bad value inside a theme file costs only that key.

The **Appearance** page in Settings → Shell is the easy way in: it lists every theme with a preview of its colors, switches on click with no restart, and offers **New theme…**. The six shipped themes are read-only there — editing one offers to duplicate it first.

Because the shell owns those six files, it rewrites any of them that differs from what it ships every time it starts, so a fix to a shipped palette reaches you on the next launch. Editing `dracula.toml` by hand will not stick; duplicate it and edit the copy. Your own theme files are never touched.

### Writing a theme file

A theme file is a flat table — no section header. Every key is optional.

```toml
# ~/.config/graceful-shell/themes/gruvbox.toml
name = "Gruvbox"

font = "Ubuntu Sans"
font_size = 13.0
blur = 24.0

accent               = "#458588"
foreground           = "#EBDBB2"
surface_hover        = "#504945"
surface_pressed      = "#3C3836"
workspace_background = "#3C3836"
popup_background     = "#282828"
popup_foreground     = "#EBDBB2"
control_surface      = "#504945"
slider_track         = "#504945"
muted                = "#928374"
divider              = "#33EBDBB2"
scrim                = "#88282828"

panel_background     = "#EE282828"
panel_gradient       = true
panel_margin         = 0
panel_radius         = 0.0
panel_border         = "#33EBDBB2"
panel_border_width   = 0.0

popup_radius         = 8.0
popup_gap            = 0.0
popup_attach_radius  = 0.0
popup_border         = "#33EBDBB2"
popup_border_width   = 1.0

popup_shadow_color   = "#66000000"
popup_shadow_blur    = 16.0
popup_shadow_spread  = 0.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 6.0
```

Colors are hex strings in `#RRGGBB` (opaque) or `#AARRGGBB` (with alpha, where `AA` is the alpha channel). `"#33FFFFFF"` is white at ~20% opacity. Alpha is what makes a translucent theme translucent: panel and popup surfaces composite against the desktop behind them.

| Key                    | Default       | Description                                                                 |
| ---------------------- | ------------- | --------------------------------------------------------------------------- |
| `name`                 | the filename  | Display name shown in the settings picker                                   |
| `font`                 | `Ubuntu Sans` | Font family used for all text across panels and popups. Any fontconfig family name; the settings picker lists the ones installed (via `fc-list`), and falls back to a free-typed field where there is no fontconfig |
| `font_size`            | `13.0`        | Size of the shell's body text, in logical pixels, and with it the whole type scale — labels, captions and headings keep their proportions either side of it. Clamped to 6–32. See the note below |
| `blur`                 | `24.0`        | Blur applied behind the settings and launcher overlays (see the note below) |
| `accent`               | `#853953`     | Focused workspace button, slider fill, selection highlights, chart series   |
| `foreground`           | `#F3F4F4`     | Primary text and icon color in the panels                                   |
| `surface_hover`        | `#853953`     | Button background when hovered                                              |
| `surface_pressed`      | `#612D53`     | Button background when pressed; the mid stop of the panel gradient          |
| `workspace_background` | `#2C2C2C`     | Unfocused workspace button; the dark end of the panel gradient              |
| `popup_background`     | `#2C2C2C`     | Background of popups, flyouts, menus, the OSD card and the overlay panel    |
| `popup_foreground`     | `#F3F4F4`     | Text and icons inside popups                                                |
| `control_surface`      | `#39393D`     | Cards, inputs and tiles inside popups and the settings pages                |
| `slider_track`         | `#612D53`     | The unfilled portion of sliders and usage bars                              |
| `muted`                | `#853953`     | Secondary, de-emphasised text                                               |
| `divider`              | `#33F3F4F4`   | Separator lines, and the resting fill of subtle list rows (supports alpha)  |
| `panel_background`     | `#EE2C2C2C`   | The bar's background, and the opacity of the whole bar (see below)          |
| `panel_gradient`       | `true`        | Whether the bar fades from `accent`, or is a flat `panel_background`        |
| `panel_margin`         | `0`           | Pixels between each bar and the screen edges it is anchored to              |
| `panel_radius`         | `0.0`         | Corner rounding of each bar (see below for which corners)                   |
| `panel_border`         | `#33F3F4F4`   | The bar's rim color; drawn only when `panel_border_width` is above zero     |
| `panel_border_width`   | `0.0`         | The bar's rim thickness, or `0` for no rim                                  |
| `popup_radius`         | `8.0`         | Corner rounding of popups, menus, flyouts and the OSD card                 |
| `popup_gap`            | `0.0`         | Pixels between a bar popup and the bar; `0` attaches it to the bar          |
| `popup_attach_radius`  | `0.0`         | How far an attached popup flares outward into the bar; read only at gap `0` |
| `popup_border`         | `#33F3F4F4`   | Their rim color; drawn only when `popup_border_width` is above zero        |
| `popup_border_width`   | `1.0`         | Their rim thickness, or `0` for no rim                                     |
| `popup_shadow_color`   | `#66000000`   | Their shadow's color; an alpha of `0` turns the shadow off entirely        |
| `popup_shadow_blur`    | `16.0`        | How far the shadow's falloff reaches past the card (CSS's blur radius)     |
| `popup_shadow_spread`  | `0.0`         | How far the shadow's shape is grown before blurring; negative shrinks it   |
| `popup_shadow_offset_x`| `0.0`         | Horizontal displacement; positive is right, negative is left               |
| `popup_shadow_offset_y`| `6.0`         | Vertical displacement; positive is down, negative is up                    |
| `scrim`                | `#882C2C2C`   | The wash drawn over the screen behind a full-screen overlay                 |

Note that `divider` is used both as a hairline *and* as a background fill for quiet rows, so it wants enough alpha to read as a surface.

### The panel

The bar has its own color, `panel_background`, and its alpha is used exactly as written — this is the surface that sits directly on the desktop, so it is the one that decides how much of your wallpaper shows through.

`panel_gradient` decides its shape:

- **`false`** — a flat sheet of `panel_background`. This is what `glassy` does.
- **`true`** (the default) — a fade from `accent` at the bar's own edge, through `surface_pressed`, to `panel_background`. The bright end sits against the anchored edge: left-aligned on a top bar, top-aligned on a left bar, and so on.

A translucent bar shows the wallpaper the shell itself draws (`[background]`). Over a bare desktop with no `[background]` section there is nothing behind the bar but whatever your compositor paints, which may simply be black.

In gradient mode **every stop is drawn at `panel_background`'s alpha**, not its own. The bar has exactly one opacity, so setting `panel_background = "#402C2C2C"` makes the whole bar 25% opaque without having to give `accent` and `surface_pressed` a matching alpha — and no stop can end up more opaque than the rest and read as a band across the middle.

### Floating the bar

`panel_margin` moves each bar away from the screen edges it is anchored to, turning a full-bleed strip into a floating pane. This is what `glassy` does, at `8`.

The gap is real, not painted: the bar's surface genuinely shrinks, so **windows will not tile into it** and **clicks that land in the gap reach the desktop** rather than being swallowed by an invisible part of the bar. The space the bar reserves grows with the margin automatically — a 32px bar with an 8px margin keeps maximized windows 40px clear of the screen edge.

`panel_radius` rounds the bar's corners, and which corners depends on whether it floats:

- **`panel_margin` above zero** — all four corners round, because the bar is a card sitting on the wallpaper.
- **`panel_margin = 0`** — only the two corners facing the middle of the screen round. A flush bar with rounded outer corners would cut wallpaper wedges out of the display's own corners, which reads as misalignment rather than styling.

`panel_border` and `panel_border_width` draw a rim around the bar. **Width is the switch**, not alpha: leave `panel_border_width = 0` and no rim is drawn whatever the color says. A 1px rim is usually what a translucent bar wants — without one a glass bar has no visible boundary over a busy wallpaper.

All three follow a theme switch live; no restart is needed.

### Popups

`popup_radius`, `popup_border` and `popup_border_width` are the bar's three shape keys again, for everything that floats *over* it: popups, context menus, category flyouts, the tray menus, the app chooser, the confirmation dialogs and the on-screen indicator. They read exactly like their `panel_` counterparts — **width is the switch** for the rim, and a translucent card wants one for the same reason a translucent bar does.

The one difference is corners, and it is the same rule the bar has for the same reason. A popup that **floats** rounds all four: nothing sits behind it to cut a wedge out of. A popup **attached to the bar** — see below — squares off the two corners on the join, because the bar *does* sit behind those, and flares them outward into it when `popup_attach_radius` is above zero.

**A popup opened from the bar is anchored to the bar's inner edge, centred on the button that opened it.** Not to the button itself: modules carry different amounts of padding, so anchoring to the button put each module's popup at a slightly different height and left all of them overlapping the bar by a pixel or two.

`popup_gap` is how far off that edge the card sits, and it is the popup analogue of `panel_margin` one layer up — that floats the bar off the screen, this floats a popup off the bar.

**A gap of `0` is the attached mode**, not merely a small gap. The card goes flush against the bar, the two corners touching it are squared off, and the rim and the shadow on that edge are dropped, so the popup reads as growing out of the bar rather than floating over it. There is no separate switch; this key is it.

`popup_attach_radius` then shapes that join, and it is the **inverse** of the corner radius its name suggests. A rounded corner curves *away* from the surface behind it, which leaves a transparent wedge on either side of the join and makes the card read as resting against the bar. This sweeps each side *outward* instead as it reaches the panel, so the card is at its widest exactly where the two meet — the way a branch runs into a trunk. At its default of `0` there is no flare at all and the join is a square butt joint, the card's sides continuing the bar's. It is unread at any other gap, because with a gap there is no join to shape.

The flare is drawn *outside* the card's own box, so the shell grows the popup's window to make room for it exactly as it does for the shadow, and takes the larger of the two rather than the sum.

`carbon` is the shipped example of the pair: `popup_gap = 0` with `popup_attach_radius = 12`, on an opaque bar with no shadow anywhere in the theme, so the flared join is the only shaping in the picture and every menu reads as an extension of the panel rather than a card in front of it.

Two things to know before attaching a theme. A theme with a **translucent `popup_background`** should keep a gap: at zero the popup's fill and the bar's composite separately against the wallpaper, so the join shows a step in tone that nothing here can remove, and a flare only makes that step wider — which is why `glassy` sets `popup_gap = 8` to match its own `panel_margin` rather than attaching. And a theme with `panel_border_width` above zero draws the bar's rim on its inner edge too, so an attached popup butts against that line — which is why `carbon`, `graceful` and `dracula` all leave that width at `0`: the rim would be a hairline drawn straight across the join the other keys are working to erase.

Hover tooltips take the edge anchor but never attach: a label that comes and goes with the pointer reads as a floating card, not as part of the furniture. Menus anchored to the *pointer* — the desktop's context menu, the app-directory's category flyouts — have no panel edge to sit off and are unaffected by either key.

Sensible defaults are shipped rather than zero — `8.0` with a 1px rim — because that is the shape the shell's menus have always drawn. A theme that says nothing about popups gets that, including a theme file written before these keys existed.

The five `popup_shadow_*` keys are a CSS box-shadow, spelled out: a color, a blur radius, a spread, and an offset on each axis. There is one shadow per theme rather than the stack CSS allows.

**A shadow makes a popup's window bigger.** A popup is its own compositor surface, sized to its content, and a shadow paints *outside* the card — so the shell grows the surface by the shadow's reach (`blur + spread`, shifted by the offset, on each side independently) and then repositions the popup by that same amount, so the card lands exactly where it would have without one. Two consequences worth knowing: a click landing in the shadow's margin hits the popup rather than passing through to what is underneath, and a very large blur on a popup near a screen edge gives the compositor more to slide back on-screen. Setting `popup_shadow_color`'s alpha to `0` removes the margin along with the shadow, restoring the exact geometry of a shell with no shadow at all — which is what `carbon` does.

Nothing says the shadow has to read as one. Give it a colour off the palette rather than a black, leave both offsets at `0` so it is not displaced from the card, and take `popup_shadow_spread` above zero so the falloff starts outside the card's edge, and the same key paints a symmetrical bloom around the card instead of weight beneath it. That is `midnight`, and the geometry follows it: with no displacement the window grows by `blur + spread` on all four sides equally, and on a bar popup the joined side is still clamped to `popup_gap`, so the glow fills the gap between card and bar and stops at the panel.

A bar popup never paints its shadow over the bar: on the joined edge the margin is clamped to `popup_gap`, so at a small gap the shadow fills it and stops, and at `0` the surface is flush and the shadow is cut exactly at the join. A gap of `popup_shadow_blur + popup_shadow_spread` or more leaves the shadow untouched.

Popup *sizes* are not themable. Each module fixes its own width, and some of them fix it deliberately: the sound popup pins its width because a popup that resizes after it has been placed walks away from the button that opened it.

### About `font_size`

`font_size` is the size of the shell's *body* text — the tier most of the shell is set in — and every other size follows it. A caption stays a caption and a heading stays a heading: the whole scale is multiplied through by `font_size / 13`, so `font_size = 16` makes everything about a quarter larger and `font_size = 10` makes everything smaller, in the panels and in every popup, menu, overlay and desktop widget they open. `13.0` is the shipped value, so a theme file that does not spell the key renders exactly as it always did; `midnight` is the one shipped theme that moves it, at `14.0`.

Two things it deliberately does not change. **Panel thickness** is `[panels.<name>] height` in `config.toml`, not a theme key — a bar left at its default height crops a much larger font, and the fix is to raise `height` alongside. **Icons** keep the size they are drawn at: a tray icon or a weather glyph is a picture, not type, and their sizes are `[modules.*]` options where they are configurable at all.

Sizes are in logical pixels and clamped to 6–32. The settings editor's **Font size** field is the same key, live: the shell re-lays itself as you type, with no restart.

### About `blur`

`blur` softens what sits behind the settings and launcher panels — that is, the `scrim` — and nothing else. It cannot frost the desktop: a shell surface is transparent and the compositor owns everything under it, and Mir exposes no blur protocol for a client to ask for one. A theme that wants to look like glass does it with alpha, as `glassy` does. Set `blur = 0` to skip the filter entirely.

### Migrating from an inline `[theme]` table

Older versions kept the palette in a `[theme]` table inside `config.toml`. That table is now ignored — `theme` is a name, not a table. To keep a palette you had customized, copy the contents of your old `[theme]` table into `~/.config/graceful-shell/themes/mine.toml` (dropping the `[theme]` header line), delete the table from `config.toml`, and set `theme = "mine"`. An un-migrated `[theme]` table is harmless: it costs you the theme, not the rest of your config.

## Background

The `[background]` section enables a full-screen wallpaper window displayed behind all other surfaces. It rotates through a list of images on a timer, with an animated crossfade between them.

If this section is absent, no background window is created.

```toml
[background]
fit = "fill"

interval_minutes = 5

[[background.entries]]
path = "/home/user/wallpapers/day.jpg"
shown = true

[[background.entries]]
path = "/home/user/wallpapers/dusk.jpg"
shown = true
```

### Background Settings

| Key                | Type   | Default  | Description                                            |
| ------------------ | ------ | -------- | ------------------------------------------------------ |
| `fit`              | string | `"fill"` | How the image is sized within the screen                |
| `interval_minutes` | number | `5`      | Minutes between wallpapers when more than one is shown |

**`fit` values:**

| Value       | Description                                            |
| ----------- | ------------------------------------------------------ |
| `"fill"`    | Scale to fill the screen, cropping if needed (cover)   |
| `"contain"` | Scale to fit within the screen, letterboxing if needed |
| `"natural"` | Display at original resolution, no scaling             |

### Background Entries

Each `[[background.entries]]` block names one wallpaper.

| Key     | Type    | Default | Description                                            |
| ------- | ------- | ------- | ------------------------------------------------------ |
| `path`  | string  |         | Absolute path to an image file                          |
| `shown` | boolean | `true`  | Whether this wallpaper is in the rotation               |

Wallpapers are shown in the order they appear, advancing every `interval_minutes`; with one shown entry there is no rotation at all. List order is the presentation order and is never sorted.

### Installed wallpapers

Settings > Shell > Background also lists every wallpaper the distribution installed — Ubuntu's `/usr/share/backgrounds`, Fedora's per-release sets, the KDE packages under `/usr/share/wallpapers`, and the same two directory names under any other `$XDG_DATA_DIRS` entry (plus Debian's `desktop-base` theme and `/usr/share/pixmaps/backgrounds`). Nothing has to be configured for them to appear, and picking one adds the ordinary `[[background.entries]]` block above.

These are discovered on every visit rather than written to `config.toml`, which is what makes them permanent: they carry no remove button in the settings UI, and deselecting one simply returns it to the Available list. Removal is offered for wallpapers you added yourself. A KDE wallpaper package is listed once, at its largest resolution, rather than once per resolution it ships.

Supported image formats: JPEG, PNG, GIF, WebP, BMP, and anything Flutter's `Image` widget can decode. Entries whose path is missing, or is not one of those formats, are pruned by the settings UI.

Transitions between wallpapers use a 1.5-second crossfade animation.

**A single, fixed wallpaper:**

```toml
[background]
fit = "fill"

[[background.entries]]
path = "/home/user/wallpapers/wallpaper.jpg"
shown = true
```

## Desktop Icons

The `[desktop]` section puts a grid of pinned icons on the wallpaper: applications, files and folders. Double-clicking an item opens it — an application launches, a file opens in its default handler, and a folder opens your file manager. Clicking selects, dragging rearranges, and dropping one icon onto another swaps their places. The grid lines are only drawn while you are dragging.

Right-clicking an icon offers **Open**, **Open with…** (files and folders), **Rename** and **Remove from desktop**. Right-clicking bare desktop offers **Add application…**, **Add file or folder…**, **Organize** (compact the icons) and **Change background…** (jump to the wallpaper settings).

**Add application…** opens a searchable list of everything installed, each with its own icon — type to filter, arrow keys and Enter to pick, Escape to dismiss. It searches names, generic names and the keywords a desktop entry declares, so "internet" finds your browser. **Add file or folder…** opens the file picker, where folders are selectable as well as browsable.

Everything here is also editable under **Settings → Shell → Desktop**, which is where the pinned list is easiest to manage.

```toml
[desktop]
enabled = true
cell_width = 96
cell_height = 96
spacing = 12
padding = 24
icon_size = 48
show_labels = true

[[desktop.items]]
kind = "app"
target = "/usr/share/applications/firefox.desktop"
column = 0
row = 0

[[desktop.items]]
kind = "folder"
target = "/home/user/Documents"
label = "Docs"
column = 1
row = 0
```

### Desktop Settings

| Key           | Type    | Default | Description                                                     |
| ------------- | ------- | ------- | --------------------------------------------------------------- |
| `enabled`     | boolean | `false` | Whether the icon grid is drawn at all                            |
| `cell_width`  | number  | `96`    | Width of one grid cell, in logical pixels (minimum 32)          |
| `cell_height` | number  | `96`    | Height of one grid cell (minimum 32)                             |
| `spacing`     | number  | `12`    | Gap between cells                                                |
| `padding`     | number  | `24`    | Inset from the usable edges of the screen                        |
| `icon_size`   | number  | `48`    | Rendered icon size within a cell (minimum 8)                     |
| `show_labels` | boolean | `true`  | Whether each icon's name is drawn under it                       |

The **number of columns and rows is not configurable** — it is derived from each monitor's usable area, so the same icon list fits displays of different sizes. The usable area excludes whatever your panels reserve, so an icon is never hidden behind a bar.

Turning `enabled` on or off takes effect **after a restart** when no wallpaper is configured, because it decides whether the background surface is created at all. With a `[background]` wallpaper already set, the surface exists either way and the change applies live. Every other key here applies live.

### Desktop Items

Each `[[desktop.items]]` block pins one thing. The settings UI and the desktop's own "Add…" menu write these for you.

| Key      | Type   | Default   | Description                                                     |
| -------- | ------ | --------- | --------------------------------------------------------------- |
| `target` | string |           | Absolute path. Required — an entry without one is ignored        |
| `kind`   | string | inferred  | `"app"`, `"file"` or `"folder"`                                  |
| `label`  | string | derived   | Renames the icon. Omit to use the app's own name or the basename |
| `column` | number | `0`       | Grid column, counting from 0 at the left                         |
| `row`    | number | `0`       | Grid row, counting from 0 at the top                             |

`target` is a **path** in every case, including applications — an app is pinned by the path to its `.desktop` file (usually under `/usr/share/applications`), not by a desktop id, so an entry in your own home directory works too.

`kind` is re-derived from the target whenever it disagrees with what is actually on disk, so a hand-edited file cannot end up opening a directory as though it were a document. Clearing a `label` in the rename field restores the original name.

An item whose target no longer exists is drawn dimmed rather than removed, so an unplugged drive or an offline network mount does not cost you your arrangement.

Items on a cell that does not exist on a smaller monitor are drawn in the nearest free cell on that monitor only; the position you gave them is kept, so plugging the larger display back in restores the layout.

## Desktop Widgets

Alongside the icons, the grid holds **widgets** — cards that take a rectangle of cells rather than a single one, and that you resize by dragging a corner. Right-click bare desktop and choose **Add widget…** to place one; right-click a widget for **Remove**. Widgets are dragged from anywhere on the card, and their own buttons still work: a press that moves is a drag, one that does not is a click.

Three types ship:

| `type` | Name | What it draws |
| ------ | ---- | ------------- |
| `media_player` | Media player | What is playing over MPRIS: art, title, transport, and a progress bar as the card grows |
| `weather` | Weather | The current conditions and a forecast strip, over a sky animated to match |
| `moon_phase` | Moon phase | Tonight's Moon drawn at its actual phase, with the times it rises and sets and what the phase means for tides, night light and eclipses |

```toml
[[desktop.widgets]]
type = "moon_phase"
id = "moon_phase"
column = 4
row = 0
column_span = 3
row_span = 2
```

| Key           | Type   | Default    | Description                                                          |
| ------------- | ------ | ---------- | -------------------------------------------------------------------- |
| `type`        | string |            | One of the types above. Required — an entry without one is ignored    |
| `id`          | string | the type   | This widget's identity, so two of a kind can be told apart            |
| `column`      | number | `0`        | Grid column of the top-left cell                                      |
| `row`         | number | `0`        | Grid row of the top-left cell                                         |
| `column_span` | number | `1`        | Width in cells, clamped to what the type allows                       |
| `row_span`    | number | `1`        | Height in cells, clamped to what the type allows                      |

A span outside what a type allows is clamped when it is drawn rather than rewritten in the file, so a layout authored when a widget allowed more room comes back at full size if that changes again. A `type` this build does not know is drawn as a placeholder and kept in the file, so an entry from a newer version survives a downgrade and there is still something to right-click.

An icon in a widget's way is moved aside; a widget in an icon's way refuses the drop, since there is no exchange of places to make between one cell and six. **Organize** compacts the icons and never moves a widget.

### The Moon phase widget

The phase, the illuminated fraction and the age of the Moon are the same everywhere on Earth, so this widget needs no configuration and works out of the box. Two things do depend on where you are, and both come from the location you set for the weather (**Settings → Shell → Modules → Weather**, or `[modules.weather] location`):

- **Moonrise and moonset**, printed for the current day. A day with neither — which happens about once a month, and for weeks at a time inside the polar circles — says so rather than showing blanks.
- **Which way up the disc is drawn.** South of the equator the Moon is seen rotated half a turn, so a waxing crescent is lit on the left.

With no weather location set, the shell uses the same one-off IP lookup the weather does; if that is unavailable too, the card drops those two lines and keeps everything else.

## Lock Screen

The `[lock]` section configures the lock screen, reached from **Lock** in the power menu (the power icon in the top panel). Locking uses the `ext-session-lock-v1` Wayland protocol, so the compositor hides every other surface — including the shell's own panels — and blanks any monitor that has no lock surface.

```toml
[lock]
background = "/home/user/wallpapers/lock.jpg"
fit = "fill"
show_username = true
blur_sigma = 18.0
```

| Key             | Type    | Default            | Description                                                        |
| --------------- | ------- | ------------------ | ------------------------------------------------------------------ |
| `background`    | string  | shipped wallpaper  | Absolute path to an image **or** video shown behind the lock screen |
| `fit`           | string  | `"fill"`           | How the wallpaper is sized (same values as `[background]`)         |
| `show_username` | boolean | `true`             | Show the account's name above the unlock button                     |
| `blur_sigma`    | number  | `18.0`             | Blur applied to the wallpaper once the password field appears; `0` leaves it sharp |

Unlike `[background]`, this is a single wallpaper rather than a rotating list — but it accepts the same image and video formats, and videos loop silently. If `background` is unset or the file is missing, the shipped default (`$PREFIX/share/graceful-shell/lock-wallpaper.jpg`) is used, falling back to a plain dark fill.

`blur_sigma` is clamped to `0`–`100`.

### Behaviour

The lock screen starts as a clock, date, and the account name over the wallpaper. Pressing the unlock button, Enter, or **any other key** reveals the password field and blurs the wallpaper; a printable first keystroke is carried into the field rather than swallowed. Pressing Escape once returns focus out of the field, and a second Escape hides it again.

### Requirements

- **`libgtk-session-lock0`** must be installed (`sudo apt install libgtk-session-lock0`). Without it the Lock button reports that locking is unavailable rather than failing silently.
- The compositor must implement `ext-session-lock-v1` (Mir/Miracle does).
- Passwords are checked with **PAM**. Installing the bundled service file with `sudo make install-pam` is recommended; without it the shell falls back to the system `login` service, which works but attributes attempts to `login` in the auth logs.

## Calendar

The `[calendar]` section configures the Calendar tab, reached by clicking the clock. The tab is a month grid beside the current local time — there is no account integration, so nothing is fetched over the network and no credentials are needed.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `week_start` | string | `"sunday"` | First column of the month grid: `"sunday"` or `"monday"`. |

### World Clocks

The column on the right of the tab shows the local time as an analog dial and a digital readout, and under it one row per `[[calendar.world_clocks]]` entry. The **+** button on that column writes these entries for you and each row's **✕** removes it, so there is nothing to configure in the Settings tab — the keys are documented because the file is yours to edit.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `zone` | string | | An IANA time zone name, e.g. `Europe/London`. Required — an entry without one is ignored. |
| `label` | string | derived | Renames the row. Omit it to use the zone's city (`Europe/London` → London). |

Rows are drawn in the order they appear in the file. Offsets follow daylight saving automatically, from the IANA database bundled with the shell, and a row whose calendar date differs from yours is badged `+1d` or `-1d`. A `zone` this build's database does not know renders as "Unknown time zone" — with its remove button intact — rather than being silently deleted.

```toml
[calendar]
week_start = "monday"

[[calendar.world_clocks]]
zone = "Europe/London"

[[calendar.world_clocks]]
zone = "Asia/Tokyo"
label = "HQ"
```

## On-Screen Indicator

The `[osd]` section configures the indicator that appears when the volume, microphone volume, or screen brightness changes — an icon for what changed plus a bar for its current level, floating above the bottom edge of every monitor. It fades out once the changes stop.

The shell only *watches* these values; it does not bind the keys. Whatever already applies the change (your compositor's media-key bindings, or the shell's own volume slider) keeps doing so, and the indicator follows. Brightness is read from `/sys/class/backlight`, so machines without a panel backlight simply never see the sun indicator.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | boolean | `true` | Whether to show the indicator at all. |
| `hide_delay_ms` | integer | `1500` | How long the indicator stays up after the last change. Clamped to a minimum of 100. |
| `margin` | integer | `96` | Distance from the bottom edge of the screen, in pixels. |

```toml
[osd]
enabled = true
hide_delay_ms = 1500
margin = 96
```

## Screen Sharing

The `[screenshare]` section configures the shell's **xdg-desktop-portal ScreenCast backend**. With it installed, an application asking to share your screen (a browser calling `getDisplayMedia`, a video call, OBS) raises the shell's own picker: a full-screen overlay showing a live preview of every monitor and every open window. Nothing is shared until you choose a source and press Share — dismissing the picker with Escape or a click outside denies the request.

Both monitors and individual windows can be shared. Frames reach the application as a PipeWire video stream.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | boolean | `true` | Whether to claim the ScreenCast backend at all. Set false to leave screen sharing to another backend such as `xdg-desktop-portal-wlr`. |
| `preview_fps` | integer | `10` | Frame rate for the picker's live previews. Clamped to 1–60. Deliberately low: the picker captures every monitor *and* every window at once. |
| `max_fps` | integer | `0` | Cap on the shared stream's frame rate. `0` follows the monitor's refresh rate. |

```toml
[screenshare]
enabled = true
preview_fps = 10
max_fps = 0
```

### Requirements

- **A compositor with `ext-image-copy-capture-v1`** — miracle-wm built against MirAL 5.6 or newer. Without it the feature disables itself and logs why.
- **PipeWire 1.0 or newer**, which every current desktop already runs.
- **The portal files installed.** Two of them: a `.portal` that tells xdg-desktop-portal the shell implements ScreenCast, and a `-portals.conf` that prefers it over any other backend claiming the same interface.

  From a source build, `make install` (or `make install-portal`) writes:
  - `~/.local/share/xdg-desktop-portal/portals/graceful-shell.portal`
  - `~/.config/xdg-desktop-portal/mir-portals.conf` (only written if absent, so an existing preference is never overwritten)

  then run `systemctl --user restart xdg-desktop-portal` once.

  **The snap does all of this for you.** Its install hook writes `/usr/share/xdg-desktop-portal/portals/graceful-shell.portal` and `/usr/share/xdg-desktop-portal/{miracle-wm,mir}-portals.conf`; the launcher writes the same pair under `~/.local/share` and `~/.config` on first run, and restarts xdg-desktop-portal itself. `snap remove` deletes both sets again. Nothing is manual.

  Two names for the conf because `XDG_CURRENT_DESKTOP` is `miracle-wm:mir`, and xdg-desktop-portal tries `<desktop>-portals.conf` for each name in that list before falling back to the generic `portals.conf`. Two *locations* because of precedence: `portals.conf(5)` searches `$XDG_CONFIG_HOME`, then `$XDG_CONFIG_DIRS`, then `/etc`, then `$XDG_DATA_HOME`, then `$XDG_DATA_DIRS`. `/usr/share` is the last of those, which makes the system-wide copy a machine default that never out-ranks a choice you made; only the per-user copy is high enough to beat an existing `~/.config/xdg-desktop-portal/portals.conf`.

  Nothing you wrote is ever edited. If a `~/.config/xdg-desktop-portal/*-portals.conf` already points ScreenCast at another backend it wins, and the shell logs which file and which line to change. Setting `enabled = false` above also stops the snap registering the backend at all, so opting out does not leave a dangling preference behind.

There is deliberately no D-Bus activation file: the shell owns the backend name from session start, so screen sharing cannot start the shell. If the shell is not running, screen sharing is simply unavailable.

## Full Example

```toml
theme = "dracula"

[panels.top]
height = 32
padding_horizontal = 40
anchor = "top"
layer = "top"

[panels.top.layout]
left   = ["workspaces", "dock"]
center = ["media_player"]
right  = ["sound_control", "battery", "network", "weather", "clock"]

[panels.bottom]
height = 32
padding_horizontal = 20
anchor = "bottom"
layer = "top"

[panels.bottom.layout]
left   = []
center = []
right  = ["clock", "launcher"]

[modules.weather]
unit = "fahrenheit"
refresh_minutes = 30

[modules.battery]
poll_seconds = 30

[modules.clock]
show_date = true

[modules.media_player]
max_text_width = 200.0

[modules.dock]
apps = ["firefox", "org.gnome.Nautilus", "kitty"]
icon_size = 24

[shortcuts]
open_settings = "ctrl+shift+s"
open_launcher = "ctrl+space"
power_button = "poweroff"

[power]
key_action = "menu"
inhibit_logind = true

[screenshare]
enabled = true
preview_fps = 10
max_fps = 0

[background]
fit = "fill"
interval_minutes = 15

[[background.entries]]
path = "/home/user/wallpapers/morning.jpg"
shown = true

[[background.entries]]
path = "/home/user/wallpapers/evening.jpg"
shown = true

[desktop]
enabled = true
cell_width = 96
cell_height = 96

[[desktop.items]]
kind = "app"
target = "/usr/share/applications/firefox.desktop"
column = 0
row = 0
```
