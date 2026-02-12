# Graceful Panel Configuration

Graceful Panel is configured via a TOML file located at:

```
~/.config/graceful-panel/config.toml
```

If `$XDG_CONFIG_HOME` is set, the config file is read from `$XDG_CONFIG_HOME/graceful-panel/config.toml` instead.

The panel works out of the box with no configuration file. All settings have sensible defaults that match the standard layout. You only need to create a config file to customize behavior.

If the config file is missing or contains errors, the panel falls back to defaults silently.

## Example Configuration

```toml
[panel]
height = 32
padding_horizontal = 40

[layout]
left   = ["workspaces"]
center = ["media_player"]
right  = ["sound_control", "battery", "weather", "clock"]

[modules.weather]
unit = "fahrenheit"
refresh_minutes = 10

[modules.battery]
poll_seconds = 30

[modules.clock]
show_date = true

[modules.media_player]
max_text_width = 200.0
```

## Panel Settings

The `[panel]` section controls global panel appearance.

| Key                    | Type | Default | Description                     |
|------------------------|------|---------|---------------------------------|
| `height`               | int  | `32`    | Panel height in pixels          |
| `padding_horizontal`   | int  | `40`    | Left and right padding in pixels|

## Layout

The `[layout]` section controls which modules appear and where. The panel has three sections arranged horizontally: **left**, **center**, and **right**. The center section expands to fill available space.

```toml
[layout]
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

A module omitted from all three sections is disabled entirely. You can place any module in any section and in any order.

**Note:** When the `[layout]` section is present, all three keys (`left`, `center`, `right`) should be specified. An omitted key defaults to an empty list, not to the default modules.

### Examples

Move the clock to the left, disable battery:

```toml
[layout]
left   = ["workspaces", "clock"]
center = ["media_player"]
right  = ["sound_control", "weather"]
```

Minimal panel with only clock and weather:

```toml
[layout]
left   = []
center = []
right  = ["weather", "clock"]
```

## Module Settings

Per-module settings live under `[modules.<name>]`. Only modules present in the layout are instantiated; settings for disabled modules are ignored.

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

### Sound Control

No configurable settings.
