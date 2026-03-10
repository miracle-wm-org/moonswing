# Full Configuration Example

A complete `~/.config/graceful-shell/config.toml` demonstrating all available options:

```toml
# Two panels: a full-featured top bar and a minimal bottom bar
[panels.top]
height             = 32
padding_horizontal = 40
anchor             = "top"
layer              = "top"

[panels.top.layout]
left   = ["workspaces", "dock"]
center = ["media_player"]
right  = ["sound_control", "battery", "weather", "clock"]

[panels.bottom]
height             = 32
padding_horizontal = 20
anchor             = "bottom"
layer              = "top"

[panels.bottom.layout]
left   = []
center = []
right  = ["clock"]

# Module-specific settings
[modules.weather]
unit            = "fahrenheit"
refresh_minutes = 10

[modules.battery]
poll_seconds = 30

[modules.clock]
show_date = true

[modules.media_player]
max_text_width = 200.0

[modules.dock]
apps      = ["firefox", "org.gnome.Nautilus", "kitty"]
icon_size = 24

# Theme (default dark)
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

# Background with time-of-day wallpaper scheduling
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
