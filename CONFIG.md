# Graceful Panel Configuration

Graceful Panel is configured via a TOML file located at:

```
~/.config/graceful-panel/config.toml
```

If `$XDG_CONFIG_HOME` is set, the config file is read from `$XDG_CONFIG_HOME/graceful-panel/config.toml` instead.

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

| Key                  | Type   | Default | Description                                       |
|----------------------|--------|---------|---------------------------------------------------|
| `height`             | int    | `32`    | Panel thickness in pixels (height for top/bottom, width for left/right) |
| `padding_horizontal` | int    | `40`    | Left and right padding in pixels                  |
| `anchor`             | string | `"top"` | Screen edge: `"top"`, `"bottom"`, `"left"`, or `"right"` |
| `layer`              | string | `"top"` | Layer shell layer: `"background"`, `"bottom"`, `"top"`, or `"overlay"` |

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

| Key               | Type   | Default        | Description                          |
|-------------------|--------|----------------|--------------------------------------|
| `unit`            | string | `"fahrenheit"` | `"celsius"` or `"fahrenheit"`        |
| `refresh_minutes` | int    | `10`           | How often to re-fetch weather (minutes) |

### Battery

```toml
[modules.battery]
poll_seconds = 30
```

| Key            | Type | Default | Description                              |
|----------------|------|---------|------------------------------------------|
| `poll_seconds` | int  | `30`    | Polling interval for battery status (seconds) |

### Clock

```toml
[modules.clock]
show_date = true
```

| Key         | Type | Default | Description                        |
|-------------|------|---------|------------------------------------|
| `show_date` | bool | `true`  | Whether to show the date alongside time |

### Media Player

```toml
[modules.media_player]
max_text_width = 200.0
```

| Key              | Type  | Default | Description                                 |
|------------------|-------|---------|---------------------------------------------|
| `max_text_width` | float | `200.0` | Width in pixels before text starts scrolling |

### Workspaces

No configurable settings.

### Dock

```toml
[modules.dock]
apps = ["firefox", "org.gnome.Nautilus", "kitty", "code"]
icon_size = 24
```

| Key         | Type         | Default | Description                                         |
|-------------|--------------|---------|-----------------------------------------------------|
| `apps`      | string array | `[]`    | Desktop entry IDs of apps to show in the dock       |
| `icon_size` | int          | `24`    | Icon size in pixels (should fit within panel height) |

Each entry in `apps` is a desktop file ID (the filename without `.desktop`). For example, `"firefox"` corresponds to `firefox.desktop`, and `"org.gnome.Nautilus"` corresponds to `org.gnome.Nautilus.desktop`.

Desktop files are looked up from standard XDG application directories. Apps with missing desktop files are silently skipped.

### Sound Control

No configurable settings.

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
right  = ["sound_control", "battery", "weather", "clock"]

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
```
