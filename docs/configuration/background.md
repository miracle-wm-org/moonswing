# Background

The `[background]` section enables a full-screen wallpaper window that sits behind all other surfaces. It supports static images, animated GIFs, and videos, with optional time-of-day scheduling and smooth crossfade transitions between entries.

If this section is absent from your config, no background window is created.

## Settings

| Key | Type | Default | Description |
|---|---|---|---|
| `fit` | string | `"fill"` | How the media is scaled to fill the screen |

### Fit Values

| Value | Description |
|---|---|
| `"fill"` | Scale to fill the entire screen, cropping edges if the aspect ratio differs (cover mode) |
| `"contain"` | Scale to fit entirely within the screen, adding letterbox bars if needed |
| `"natural"` | Display at the original resolution with no scaling |

## Background Entries

Each `[[background.entries]]` block defines a piece of media and the time of day it becomes active:

| Key | Type | Description |
|---|---|---|
| `path` | string | Absolute path to an image or video file |
| `time` | string | 24-hour time (`"HH:MM"`) when this entry becomes active |

Entries are sorted by time. At any given moment, the active entry is the one with the latest `time` at or before the current time. If the current time is before all entries (e.g., it is 03:00 and the earliest entry starts at 06:00), the last entry from the list wraps around and is shown.

### Supported Formats

- **Images:** JPEG, PNG, GIF, WebP, BMP, and any format Flutter's `Image` widget can decode
- **Videos:** MP4, MKV, WebM, MOV, AVI

Videos loop silently and play without any visible controls.

### Transitions

Switching between entries uses a **1.5-second crossfade animation**.

## Examples

### Single Static Wallpaper

```toml
[background]
fit = "fill"

[[background.entries]]
path = "/home/user/wallpapers/wallpaper.jpg"
time = "00:00"
```

### Time-of-Day Scheduling

```toml
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

In this example:

- From 07:00 to 17:59 → `morning.jpg` is displayed
- From 18:00 to 20:59 → `evening.jpg` is displayed
- From 21:00 to 06:59 (next day) → `night.mp4` loops

### Video Wallpaper (All Day)

```toml
[background]
fit = "fill"

[[background.entries]]
path = "/home/user/wallpapers/landscape.mp4"
time = "00:00"
```

### Letterboxed Image

```toml
[background]
fit = "contain"

[[background.entries]]
path = "/home/user/wallpapers/ultrawide.png"
time = "00:00"
```
