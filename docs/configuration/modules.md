# Modules

Per-module settings are defined under `[modules.<name>]` sections. These settings are **global** — they apply to all panels where that module appears.

Modules with no configurable settings do not need a `[modules.<name>]` section at all.

---

## clock

Displays the current time and optionally the date.

```toml
[modules.clock]
show_date = true
```

| Key | Type | Default | Description |
|---|---|---|---|
| `show_date` | bool | `true` | Show the date (e.g., `Mon 10`) alongside the time |

---

## weather

Fetches and displays the current weather conditions for your location.

```toml
[modules.weather]
unit            = "fahrenheit"
refresh_minutes = 10
```

| Key | Type | Default | Description |
|---|---|---|---|
| `unit` | string | `"fahrenheit"` | Temperature unit: `"celsius"` or `"fahrenheit"` |
| `refresh_minutes` | int | `10` | How often to re-fetch weather data (minutes) |

---

## battery

Polls and displays the current battery charge level and charging state.

```toml
[modules.battery]
poll_seconds = 30
```

| Key | Type | Default | Description |
|---|---|---|---|
| `poll_seconds` | int | `30` | How often to poll battery status (seconds) |

---

## media_player

Shows the currently playing track from any MPRIS-compatible media player (e.g., Spotify, VLC, Firefox) and provides playback controls.

```toml
[modules.media_player]
max_text_width = 200.0
```

| Key | Type | Default | Description |
|---|---|---|---|
| `max_text_width` | float | `200.0` | Maximum width in pixels for track title/artist text before scrolling begins |

---

## dock

An application launcher that shows icons for a fixed list of apps. Clicking an icon launches the app or raises its window if already running.

```toml
[modules.dock]
apps      = ["firefox", "org.gnome.Nautilus", "kitty", "code"]
icon_size = 24
```

| Key | Type | Default | Description |
|---|---|---|---|
| `apps` | string array | `[]` | Desktop entry IDs of apps to show |
| `icon_size` | int | `24` | Icon size in pixels |

Each entry in `apps` is a **desktop file ID** — the filename without `.desktop`. Examples:

| Desktop File | ID to use |
|---|---|
| `firefox.desktop` | `"firefox"` |
| `org.gnome.Nautilus.desktop` | `"org.gnome.Nautilus"` |
| `com.mitchellh.ghostty.desktop` | `"com.mitchellh.ghostty"` |

Desktop files are resolved from the standard XDG application directories (`/usr/share/applications`, `~/.local/share/applications`, etc.). Apps whose desktop file cannot be found are silently skipped.

!!! tip
    To find the desktop file ID for an installed app, run:
    ```sh
    ls /usr/share/applications/ ~/.local/share/applications/
    ```

---

## sound_control

Displays the current output volume. Clicking it opens a popup mixer for adjusting volume and toggling mute.

No configurable settings.

---

## workspaces

Displays workspace buttons for switching between Miracle WM workspaces. Clicking a button activates that workspace.

Requires Miracle WM as the compositor. No configurable settings.

---

## notifications

A notification indicator that integrates with the D-Bus notification daemon. No configurable settings.

---

## system_monitor

Displays CPU and memory usage. No configurable settings.

---

## system

System controls (e.g., power menu). No configurable settings.
