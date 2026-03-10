# Theme

The `[theme]` section controls the color palette and font used across all panels and popups. The entire section is optional — omitting it uses the built-in dark theme defaults.

## Color Format

Colors are specified as hex strings:

| Format | Example | Description |
|---|---|---|
| `"#RRGGBB"` | `"#E0E0E0"` | Fully opaque color |
| `"#AARRGGBB"` | `"#33FFFFFF"` | Color with alpha (`AA` is the alpha byte; `00` = transparent, `FF` = opaque) |

## Settings

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

| Key | Default | Description |
|---|---|---|
| `font` | `"Ubuntu Sans"` | Font family used for all text across panels and popups |
| `foreground` | `#E0E0E0` | Primary text and icon color |
| `accent` | `#4A90E2` | Focused workspace button background; volume slider fill |
| `surface_hover` | `#4A4A4A` | Button background on hover (dock, media player controls) |
| `surface_pressed` | `#2A2A2A` | Button background when pressed |
| `workspace_background` | `#3A3A3A` | Unfocused workspace button background |
| `popup_background` | `#1E1E2E` | Sound control popup background |
| `popup_foreground` | `#CDD6F4` | Sound control popup text and active slider thumb |
| `slider_track` | `#45475A` | Volume slider unfilled track color |
| `muted` | `#E06C75` | Mute icon color when audio is muted |
| `divider` | `#33FFFFFF` | Separator lines between panel sections (supports alpha) |

## Example Themes

### Default (Dark)

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

### Gruvbox

```toml
[theme]
foreground           = "#EBDBB2"
accent               = "#458588"
surface_hover        = "#504945"
surface_pressed      = "#3C3836"
workspace_background = "#3C3836"
popup_background     = "#282828"
popup_foreground     = "#EBDBB2"
slider_track         = "#504945"
muted                = "#CC241D"
divider              = "#33EBDBB2"
```

### Light

```toml
[theme]
foreground           = "#2E2E2E"
accent               = "#0066CC"
surface_hover        = "#E0E0E0"
surface_pressed      = "#C8C8C8"
workspace_background = "#D0D0D0"
popup_background     = "#F5F5F5"
popup_foreground     = "#2E2E2E"
slider_track         = "#BBBBBB"
muted                = "#CC3333"
divider              = "#33000000"
```
