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

- `"workspaces"` - Workspace switcher (requires Miracle WM)
- `"media_player"` - MPRIS media player controls
- `"sound_control"` - PulseAudio volume display
- `"battery"` - Battery status monitor
- `"network"` - Network connectivity (ethernet or WiFi name and IP address)
- `"weather"` - Weather display
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
refresh_minutes = 10
```

| Key               | Type   | Default        | Description                             |
| ----------------- | ------ | -------------- | --------------------------------------- |
| `unit`            | string | `"fahrenheit"` | `"celsius"` or `"fahrenheit"`           |
| `refresh_minutes` | int    | `10`           | How often to re-fetch weather (minutes) |

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

No configurable settings.

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

## Theme

The `[theme]` section controls the color palette used across all panels and modules. All fields are optional — omitting the section entirely uses the built-in defaults.

Colors are specified as hex strings in `#RRGGBB` format (opaque) or `#AARRGGBB` format (with alpha, where `AA` is the alpha channel). For example, `"#33FFFFFF"` is white at ~20% opacity.

```toml
[theme]
font                 = "Ubuntu Sans"
foreground           = "#E0E0E0"
accent               = "#4A90E2"
surface_hover        = "#4A4A4A"
surface_pressed      = "#2A2A2A"
workspace_background = "#3A3A3A"
popup_background     = "#1E1E2E"
popup_foreground     = "#CDD6F4"
slider_track         = "#45475A"
muted                = "#E06C75"
divider              = "#33FFFFFF"
```

| Key                    | Default       | Description                                                   |
| ---------------------- | ------------- | ------------------------------------------------------------- |
| `font`                 | `Ubuntu Sans` | Font family used for all text across panels and popups        |
| `foreground`           | `#E0E0E0`     | Primary text and icon color used across all modules           |
| `accent`               | `#4A90E2`     | Focused workspace button background; volume slider fill color |
| `surface_hover`        | `#4A4A4A`     | Button background when hovered (dock, media player controls)  |
| `surface_pressed`      | `#2A2A2A`     | Button background when pressed (dock, media player controls)  |
| `workspace_background` | `#3A3A3A`     | Unfocused workspace button background                         |
| `popup_background`     | `#1E1E2E`     | Sound control popup window background                         |
| `popup_foreground`     | `#CDD6F4`     | Sound control popup text and active slider thumb color        |
| `slider_track`         | `#45475A`     | Volume slider track (the unfilled portion)                    |
| `muted`                | `#E06C75`     | Mute icon color when audio is muted                           |
| `divider`              | `#33FFFFFF`   | Separator lines between panel sections (supports alpha)       |

### Example: Gruvbox Theme

```toml
[theme]
foreground          = "#EBDBB2"
accent              = "#458588"
surface_hover       = "#504945"
surface_pressed     = "#3C3836"
workspace_background = "#3C3836"
popup_background    = "#282828"
popup_foreground    = "#EBDBB2"
slider_track        = "#504945"
muted               = "#CC241D"
divider             = "#33EBDBB2"
```

### Example: Light Theme

```toml
[theme]
foreground          = "#2E2E2E"
accent              = "#0066CC"
surface_hover       = "#E0E0E0"
surface_pressed     = "#C8C8C8"
workspace_background = "#D0D0D0"
popup_background    = "#F5F5F5"
popup_foreground    = "#2E2E2E"
slider_track        = "#BBBBBB"
muted               = "#CC3333"
divider             = "#33000000"
```

## Background

The `[background]` section enables a full-screen wallpaper window displayed behind all other surfaces. It supports images and videos, with optional time-of-day scheduling and animated crossfade transitions between entries.

If this section is absent, no background window is created.

```toml
[background]
fit = "fill"

[[background.entries]]
path = "/home/user/wallpapers/day.jpg"
time = "08:00"

[[background.entries]]
path = "/home/user/wallpapers/night.mp4"
time = "20:00"
```

### Background Settings

| Key   | Type   | Default  | Description                                    |
| ----- | ------ | -------- | ---------------------------------------------- |
| `fit` | string | `"fill"` | How the image/video is sized within the screen |

**`fit` values:**

| Value       | Description                                            |
| ----------- | ------------------------------------------------------ |
| `"fill"`    | Scale to fill the screen, cropping if needed (cover)   |
| `"contain"` | Scale to fit within the screen, letterboxing if needed |
| `"natural"` | Display at original resolution, no scaling             |

### Background Entries

Each `[[background.entries]]` block defines a piece of media and the time of day it becomes active.

| Key    | Type   | Description                                             |
| ------ | ------ | ------------------------------------------------------- |
| `path` | string | Absolute path to an image or video file                 |
| `time` | string | 24-hour time (`"HH:MM"`) when this entry becomes active |

Entries are selected by finding the latest entry whose `time` is at or before the current time. If the current time is before all entries' times (e.g., a 3am check with the earliest entry at 6am), the last entry from the previous day wraps around.

Supported image formats: JPEG, PNG, GIF, WebP, BMP, and anything Flutter's `Image` widget can decode.

Supported video formats: MP4, MKV, WebM, MOV, AVI.

Videos loop silently and play without controls.

Transitions between entries use a 1.5-second crossfade animation.

**Single entry (no scheduling):**

```toml
[background]
fit = "fill"

[[background.entries]]
path = "/home/user/wallpapers/wallpaper.jpg"
time = "00:00"
```

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

The `[calendar]` section configures the Calendar tab, reached by clicking the clock. The month grid works with no configuration at all; this section only matters for connecting an account.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `refresh_minutes` | integer | `15` | How often to re-fetch events. Clamped to a minimum of 1. |
| `week_start` | string | `"sunday"` | First column of the month grid: `"sunday"` or `"monday"`. |

### Google

Graceful Shell signs in with **your own** Google OAuth client rather than a shared one, so you will need to create it once:

1. In the [Google Cloud Console](https://console.cloud.google.com/), create a project and enable the **Google Calendar API**.
2. Under *Credentials*, create an **OAuth client ID** of type **Desktop app**.
3. Paste the generated client ID and secret into the Calendar tab's connect pane (or into the config directly), then click **Connect Google Calendar**.

```toml
[calendar]
refresh_minutes = 15
week_start = "monday"

[calendar.google]
client_id = "1234567890-abcdef.apps.googleusercontent.com"
client_secret = "GOCSPX-your-client-secret"
```

Access is **read-only** (`calendar.readonly`): the shell displays events but never modifies them.

Sign-in tokens are **not** stored in `config.toml`. They live in `$XDG_DATA_HOME/graceful-shell/calendar_tokens.json` (usually `~/.local/share/…`), with permissions restricted to your user, so that sharing or copying a config file never leaks account access. Clicking **Disconnect** revokes the token with Google and deletes it locally.

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

## Full Example

```toml
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
right  = ["clock"]

[modules.weather]
unit = "fahrenheit"
refresh_minutes = 10

[modules.battery]
poll_seconds = 30

[modules.clock]
show_date = true

[modules.media_player]
max_text_width = 200.0

[modules.dock]
apps = ["firefox", "org.gnome.Nautilus", "kitty"]
icon_size = 24

[theme]
foreground          = "#E0E0E0"
accent              = "#4A90E2"
surface_hover       = "#4A4A4A"
surface_pressed     = "#2A2A2A"
workspace_background = "#3A3A3A"
popup_background    = "#1E1E2E"
popup_foreground    = "#CDD6F4"
slider_track        = "#45475A"
muted               = "#E06C75"
divider             = "#33FFFFFF"

[background]
fit = "fill"

[[background.entries]]
path = "/home/user/wallpapers/morning.jpg"
time = "07:00"

[[background.entries]]
path = "/home/user/wallpapers/evening.jpg"
time = "18:00"

[[background.entries]]
path = "/home/user/wallpapers/night.mp4"
time = "21:00"
```
