# Panels & Layout

Graceful Shell supports multiple panels simultaneously, each anchored to a different edge of the screen. Panels are defined under `[panels.<name>]` sections, where `<name>` is an arbitrary identifier you choose (e.g., `top`, `bottom`, `sidebar`).

## Defining a Panel

```toml
[panels.top]
height             = 32
padding_horizontal = 40
anchor             = "top"
layer              = "top"
```

### Panel Settings

| Key | Type | Default | Description |
|---|---|---|---|
| `height` | int | `32` | Panel thickness in pixels (height for top/bottom panels, width for left/right panels) |
| `padding_horizontal` | int | `40` | Padding applied to the left and right ends of the panel in pixels |
| `anchor` | string | `"top"` | Screen edge the panel attaches to: `"top"`, `"bottom"`, `"left"`, or `"right"` |
| `layer` | string | `"top"` | Wayland layer shell layer: `"background"`, `"bottom"`, `"top"`, or `"overlay"` |

### Anchor Values

The `anchor` determines which edges the panel is pinned to:

| Value | Behavior |
|---|---|
| `"top"` | Horizontal bar pinned to the top edge, stretching left-to-right |
| `"bottom"` | Horizontal bar pinned to the bottom edge, stretching left-to-right |
| `"left"` | Vertical bar pinned to the left edge, stretching top-to-bottom |
| `"right"` | Vertical bar pinned to the right edge, stretching top-to-bottom |

### Layer Values

The `layer` controls stacking relative to other windows:

| Value | Behavior |
|---|---|
| `"background"` | Behind all windows and the desktop |
| `"bottom"` | Below normal windows but above the background |
| `"top"` | Above normal windows (typical panel behavior) |
| `"overlay"` | Above everything, including fullscreen windows |

## Layout

Each panel has a `[panels.<name>.layout]` section that controls which modules appear and where. The panel has three zones arranged along its main axis:

- **left** — aligned to the start (left/top)
- **center** — centered, expands to fill available space
- **right** — aligned to the end (right/bottom)

```toml
[panels.top.layout]
left   = ["workspaces"]
center = ["media_player"]
right  = ["sound_control", "battery", "weather", "clock"]
```

Each key is an ordered array of module names. Modules render in the order listed.

### Available Module Names

| Name | Description |
|---|---|
| `"workspaces"` | Workspace switcher (requires Miracle WM) |
| `"media_player"` | MPRIS media player controls |
| `"sound_control"` | PulseAudio volume display and mixer popup |
| `"battery"` | Battery status monitor |
| `"weather"` | Current weather display |
| `"clock"` | Date and time |
| `"dock"` | Application launcher dock |
| `"notifications"` | Notification indicator |
| `"system_monitor"` | CPU / memory usage |
| `"system"` | System controls |

!!! note
    When a `[panels.<name>.layout]` section is present, all three keys (`left`, `center`, `right`) should be specified. An omitted key defaults to an empty list. A module not listed in any panel section is disabled entirely.

## Multiple Panels

Define as many panels as you need by adding more `[panels.<name>]` sections:

```toml
[panels.top]
height             = 32
padding_horizontal = 40
anchor             = "top"
layer              = "top"

[panels.top.layout]
left   = ["workspaces"]
center = ["media_player"]
right  = ["sound_control", "battery", "weather", "clock"]

[panels.bottom]
height             = 32
padding_horizontal = 20
anchor             = "bottom"
layer              = "top"

[panels.bottom.layout]
left   = []
center = ["clock"]
right  = ["weather"]
```

## Minimal Example

A single top panel with the default module layout:

```toml
[panels.top]
height             = 32
padding_horizontal = 40
anchor             = "top"
layer              = "top"

[panels.top.layout]
left   = ["workspaces"]
center = ["media_player"]
right  = ["sound_control", "battery", "weather", "clock"]
```
