# Moonswing Configuration

Moonswing reads one TOML file:

```
~/.config/moonswing/config.toml        # or $XDG_CONFIG_HOME/moonswing/config.toml
```

- If the file is missing, the shell writes a default one on first start.
- A wrongly typed value costs only that key: the default is used instead. Numbers out of range are clamped.
- A TOML syntax error costs the whole file: the shell logs the error to stderr and runs on defaults.
- Changes made in Settings (or a right-click menu) apply live and are written back to the file. Settings rewrites the whole file, so comments are not kept.
- The shell does not watch the file. After editing it by hand, restart the shell, and don't change anything in Settings in between: Settings would overwrite your edit.

## Panels

Each `[panels.<name>]` table is one bar, shown on every monitor. `<name>` is any identifier (`top`, `bottom`, `dock`, …).

```toml
[panels.top]
height = 32
padding_horizontal = 8
anchor = "top"
layer = "top"

[panels.top.layout]
left   = ["workspaces"]
center = ["clock"]
right  = ["sound_control", "battery", "weather", "system"]

[panels.bottom]
height = 32
padding_horizontal = 0
anchor = "bottom"
layer = "top"

[panels.bottom.layout]
left   = ["clipboard"]
center = ["dock"]
right  = ["media_player", "notifications", "launcher"]
```

| Key                  | Type   | Default | Description |
| -------------------- | ------ | ------- | ----------- |
| `height`             | int    | `32`    | Thickness in pixels (width, on a left or right bar). Also the space reserved at the screen edge |
| `padding_horizontal` | int    | `8`     | Space at each end of the bar, in pixels |
| `anchor`             | string | `"top"` | `"top"`, `"bottom"`, `"left"` or `"right"` |
| `layer`              | string | `"top"` | Layer-shell layer: `"background"`, `"bottom"`, `"top"` or `"overlay"` |

- With no `[panels]` table at all, the shell shows one top bar with the [Layout](#layout) defaults.
- Changes from Settings apply at once on every monitor. Changing `height`, `anchor` or `layer` recreates the bar, so it blinks.
- On a left or right bar, modules stack down the bar, short readings sit under their icons, and running text (the clock, track titles) is turned on its side. `left`/`center`/`right` become top/middle/bottom.
- A bar's margin, corner radius and how two bars join are theme keys: see [Floating the bar](#floating-the-bar) and [Where two bars meet](#where-two-bars-meet).

## Layout

`[panels.<name>.layout]` lists the modules in each of the bar's three sections, in order.

```toml
[panels.top.layout]
left   = ["workspaces"]
center = ["clock"]
right  = ["sound_control", "battery", "weather", "system"]
```

| Key      | Type             | Default |
| -------- | ---------------- | ------- |
| `left`   | array of strings | `["workspaces"]` |
| `center` | array of strings | `["media_player"]` |
| `right`  | array of strings | `["sound_control", "battery", "weather", "clock", "system"]` |

The defaults apply only when the `layout` table is missing. If it is present, a missing key is an empty section.

Module names:

| Name              | What it shows |
| ----------------- | ------------- |
| `workspaces`      | Workspace switcher with each workspace's open apps (Miracle WM only) |
| `media_player`    | MPRIS media controls |
| `sound_control`   | Volume |
| `brightness`      | Backlight level; scroll or click to change |
| `battery`         | Battery status |
| `network`         | Connection name and IP address |
| `quick_settings`  | Wi-Fi, Bluetooth, power mode, audio devices, brightness and the power menu |
| `weather`         | Current weather |
| `clock`           | Date and time; click for the overview |
| `dock`            | Pinned applications |
| `system_monitor`  | CPU, memory and temperature |
| `system`          | Power button; opens the power menu |
| `system_tray`     | Tray icons (StatusNotifierItem) |
| `launcher`        | Opens the application launcher |
| `screenshot`      | Screenshot an area, a window or a screen |
| `screen_recorder` | Record an area, a window or a screen |
| `keyboard_layout` | Current input source; click to switch |
| `keybinds`        | Opens the overview's Shortcuts tab |
| `github`          | GitHub notifications |
| `notifications`   | Notification bell and panel |
| `scratchpad`      | Shows or hides the scratchpad (Miracle WM only) |
| `todo`            | Opens the todo board; shows what is due today |
| `stocks`          | Stock quotes |
| `clipboard`       | Clipboard history panel |

- A module in no panel is off. A module may appear in several panels.
- A module with nothing to show on this machine (no battery, no backlight, an empty tray) takes no space.
- Miracle-only modules are dropped on other compositors.

### Right-clicking a panel

- **Right-click a module** for a few quick toggles (the clock's date and seconds, the weather unit, the bell's silence, …), a link to its settings page, **Panel settings…**, **Add module…** (inserts after this one) and **Remove from panel**.
- **Right-click blank bar** for **Add module to left/center/right…** (whichever third you clicked; top/middle/bottom on a side bar), **Panel settings…** and **Settings…**.
- **Drag a module** along its section to reorder it. To move it to another section, remove it and add it there. Dragging a dock icon reorders the dock instead.

All of these write the panel's `layout` immediately.

## Module Settings

Per-module settings live under `[modules.<name>]`. They are global: every panel that carries a module uses the same settings.

### Weather

The current temperature and conditions. Click for today's details and a daily forecast. Data comes from Open-Meteo; no API key is needed. In the default top panel.

```toml
[modules.weather]
unit = "celsius"
refresh_minutes = 30
location = "Berlin"
latitude = 52.52
longitude = 13.41
```

| Key               | Type   | Default        | Description                                             |
| ----------------- | ------ | -------------- | ------------------------------------------------------- |
| `unit`            | string | `"fahrenheit"` | `"celsius"` or `"fahrenheit"`; anything else is fahrenheit |
| `refresh_minutes` | int    | `30`           | How often to re-fetch (1–1440)                          |
| `location`        | string | `""`           | Display name for the place                              |
| `latitude`        | float  | none           | -90 to 90                                               |
| `longitude`       | float  | none           | -180 to 180                                             |

- With no `latitude`/`longitude` (or only one of them, or one out of range), the location is detected from your IP address via ipapi.co.
- Settings › Shell › Modules › Weather searches for a place by name and writes all three location keys.

### Battery

The charge level. Click for time remaining (or until full), power draw, and each battery's health, cycle count, technology and model where the firmware reports them. Takes no room on a machine with no battery. In the default top panel.

```toml
[modules.battery]
poll_seconds = 30
```

| Key            | Type | Default | Description                         |
| -------------- | ---- | ------- | ----------------------------------- |
| `poll_seconds` | int  | `30`    | How often to re-read the battery    |

Plugging in or unplugging is picked up at once through udev; the poll covers the slow drift in between.

### Clock

The date and time, in the centre of the default top panel. Clicking it opens the overview. It is also where the shell's timers live.

```toml
[modules.clock]
show_weekday = false
show_date = true
show_year = false
show_week_number = false
show_time = true
show_seconds = false
hour_format = "24"
timer_sound = "ding"
timer_volume = 0.7

[[modules.clock.quick_timers]]
name = "Tea"
duration = "3m"
```

| Key                | Type   | Default  | Description                                        |
| ------------------ | ------ | -------- | -------------------------------------------------- |
| `show_weekday`     | bool   | `false`  | Day name, `Mon`                                    |
| `show_date`        | bool   | `true`   | Month and day, `Nov 2`                             |
| `show_year`        | bool   | `false`  | Year, `2026`                                       |
| `show_week_number` | bool   | `false`  | ISO 8601 week, `W45`                               |
| `show_time`        | bool   | `true`   | Hour and minute                                    |
| `show_seconds`     | bool   | `false`  | Seconds; ignored while `show_time` is off          |
| `hour_format`      | string | `"24"`   | `"24"` (`14:05`) or `"12"` (`2:05 PM`)             |
| `timer_sound`      | string | `"ding"` | What a finished countdown rings — see below        |
| `timer_volume`     | float  | `0.7`    | Alarm volume, 0–1                                  |
| `quick_timers`     | array  | none     | One-click countdowns — see [Quick timers](#quick-timers) |

- Parts are shown in table order: with all on, `Mon Nov 2 2026 W45 14:05:09`.
- With every part off, the bar shows a clock icon so there is still something to click.
- Edits apply at once. Settings › Shell › Modules › Clock has a switch for each part.

#### The overview

Clicking the clock opens the **overview** on the clicked bar's screen: one panel with tabs for **Calendar**, **Settings**, **Monitor**, **System Info**, **Kanban**, **Code** and **Shortcuts**. The todo and keyboard-shortcut buttons open the same panel on their own tab.

- Pressing a button whose tab is showing closes the overview; pressing another switches tab.
- **Escape** or **✕** closes it.
- Drag the tab strip to move the panel. It stays there until the shell restarts. It cannot be resized.

#### Timers

Start a timer from the hourglass or stopwatch button in the overview's top-left corner. Running timers float around the overview panel as cards: drag one anywhere, or right-click it to pause, resume, reset or remove it. While one runs, its readout also appears beside the clock in the bar; click it to pause or stop timers.

When a countdown reaches zero it:

1. **Rings** `timer_sound`. Several finishing at once ring once.
2. **Posts a notification** — *Timer finished* — that stays until you dismiss it. It never plays the [notification chime](#notifications), so `timer_sound = "none"` gives a silent, notified timer.

`timer_sound` accepts:

- **A shipped alarm**: `ding` (one strike), `ding-dong` (two falling notes), `alarm` (two bursts of three tones), `gong` (one low strike, long tail). Synthesised on first use into `~/.cache/moonswing/sounds/`.
- **`none`**, `off` or `silent`: no sound.
- **A path**: anything with a `/` (or a leading `~`), in any format mpv plays.
- **A sound-theme name**, looked up like the [notification chime](#notifications): `"complete"` finds `/usr/share/sounds/freedesktop/stereo/complete.oga`.

If the sound can't be found, the timer card in the overview says so; the notification still arrives.

#### Quick timers

The hourglass card has a **Name** field. A name labels the timer (*Tea · 03:00*, and *Tea (03:00) is up.* in the notification). **Save as quick timer** keeps the name and length as a chip at the top of the card: click the chip to start it, click its **×** to forget it. Saving an existing name updates its length.

Quick timers are stored in `config.toml` and survive a restart; running timers do not.

```toml
[[modules.clock.quick_timers]]
name = "Tea"
duration = "3m"

[[modules.clock.quick_timers]]
name = "Pasta"
duration = "10:00"
```

| Key        | Type          | Description                                                                 |
| ---------- | ------------- | --------------------------------------------------------------------------- |
| `name`     | string        | Label; up to 40 characters, one line                                        |
| `duration` | string or int | `3m`, `1:30`, `1h30m`, bare `5` (minutes), or an int of seconds. Max 99 hours |

A row with no name or an unparseable duration is skipped and left in the file untouched.

### Media Player

Playback buttons and the current track title for the active MPRIS player. Takes no room when nothing is playing or paused. In the default bottom panel.

```toml
[modules.media_player]
max_text_width = 200.0
```

| Key              | Type  | Default | Description                                                    |
| ---------------- | ----- | ------- | -------------------------------------------------------------- |
| `max_text_width` | float | `200.0` | Title length in pixels before it scrolls (runs down a side bar) |

### Workspaces

One dot per workspace on the bar's monitor. The selected one is longer and drawn in the theme's `accent` (fainter when the focus is on another monitor). In the default top panel.

**Requires Miracle WM.** On other compositors the module is left out of the bar.

```toml
[modules.workspaces]
show_labels = true
show_app_icons = true
selected_apps_only = false
icon_size = 14
max_icons = 4
flash_urgent = true
urgent_flash_seconds = 5.0
show_policy_toggle = true
```

| Key                    | Type  | Default | Description                                                    |
| ---------------------- | ----- | ------- | -------------------------------------------------------------- |
| `show_labels`          | bool  | `true`  | Workspace number (or name) in each dot                         |
| `show_app_icons`       | bool  | `true`  | Icons of the apps open on each workspace (one per app)         |
| `selected_apps_only`   | bool  | `false` | Only the selected workspace shows its icons                    |
| `icon_size`            | int   | `14`    | Icon size in pixels (8–64)                                     |
| `max_icons`            | int   | `4`     | Icons per workspace before the rest become `+N` (1–16)         |
| `flash_urgent`         | bool  | `true`  | A workspace with an urgent window pulses in the accent colour  |
| `urgent_flash_seconds` | float | `5.0`   | Length of one pulse (1–30)                                     |
| `show_policy_toggle`   | bool  | `true`  | Tile/float rows in a workspace's right-click menu              |

**Right-clicking a dot** opens a menu for that workspace (not necessarily the focused one), above the usual module rows (see [Right-clicking a panel](#right-clicking-a-panel)):

- *Tile new windows* / *Float new windows* (with `show_policy_toggle`): sets where the **next** window opens; existing windows stay put. If Miracle is too old to support it, the mark doesn't move.
- *Move to output…*: lists the other displays by connector name (with make and model). Greyed out with only one display. The focus returns to where it was afterwards.

### Dock

Pinned applications, in the centre of the default bottom panel, with an app-directory button at the end.

```toml
[modules.dock]
apps = ["firefox", "org.gnome.Nautilus", "kitty", "code"]
icon_size = 24
show_app_directory = true
```

| Key                  | Type         | Default | Description                                      |
| -------------------- | ------------ | ------- | ------------------------------------------------ |
| `apps`               | string array | `[]`    | Desktop file IDs to pin, in order                |
| `icon_size`          | int          | `24`    | Icon size in pixels; keep it within the bar height |
| `show_app_directory` | bool         | `true`  | Show the app-directory button at the end         |

- An ID is the desktop file's name without `.desktop`: `"org.gnome.Nautilus"` is `org.gnome.Nautilus.desktop`, looked up in the XDG application directories. Unknown IDs are skipped silently.
- A new config pins `firefox_firefox`, `org.gnome.Ptyxis` and `org.gnome.Nautilus`.
- **Double-click** an icon to launch it; a single click only selects it. Drag to reorder. Right-click for *Unpin from dock*.
- While launching, the icon dims and a ring spins until the app's first window appears (at most 20 s; 4 s if it was already open; 3 s on a compositor whose window list the shell can't read). Double-clicking again meanwhile starts nothing.
- The app-directory button lists every installed app with search and categories; right-click an app there for *Pin to dock*.

### Network

The connection icon (Ethernet or Wi-Fi with signal), from NetworkManager. Click for the connection name, IP address and signal strength. Not in the default layout.

```toml
[modules.network]
poll_seconds = 10
```

| Key            | Type | Default | Description                           |
| -------------- | ---- | ------- | ------------------------------------- |
| `poll_seconds` | int  | `10`    | How often to re-check the connection  |

### Launcher

A bar button (magnifying glass) that opens the application launcher — the same one the `open_launcher` [shortcut](#shortcuts) opens. In the default bottom panel.

```toml
[modules.launcher]
icon_size = 18
```

| Key         | Type | Default | Description         |
| ----------- | ---- | ------- | ------------------- |
| `icon_size` | int  | `18`    | Icon size in pixels |

The launcher:

- Lists every app that would show in a menu (not `NoDisplay=true`, not excluded by `OnlyShowIn=`/`NotShowIn=`).
- Ranks matches on name, then generic name, then `Keywords=`, then desktop ID. **Enter** launches the selection.
- Shows a chevron for apps with desktop actions ("New Private Window"); hover it, or press **Right** with the caret at the end, to open them.
- Evaluates arithmetic when the query has a digit and an operator: `2^10/4` → `256`, `sqrt(16)+1` → `5`. Supports `+ - * / ^ % !`, parentheses, `sqrt`, `sin`, `cos`, `tan`, `ln`, `log`, `abs`, `ceil`, `floor` and more, and `pi` and `e`.
- Converts units: `5 km` lists equivalents; `5 km to mi` (or `in`, `into`, `as`, `>`) gives one. Covers length, mass, temperature, volume, area, speed, time, data, pressure, energy and angle.
- Closes on **Escape** or a click outside the card.

The default config is only written when none exists, so to add the button to an older config put `"launcher"` in a panel's layout, e.g. `right = ["media_player", "notifications", "launcher"]` under `[panels.bottom.layout]`.

### GitHub

The GitHub mark with your unread notification count. Click for the inbox: each thread with the reason it arrived. Click a thread to open it in the browser (and mark it read); the tick on a row marks it read; the double tick in the header marks all read. Not in the default layout.

```toml
[modules.github]
refresh_seconds = 60
show_count = true
participating_only = false
include_read = false
mark_read_on_open = true
```

| Key                  | Type   | Default            | Description                                              |
| -------------------- | ------ | ------------------ | -------------------------------------------------------- |
| `refresh_seconds`    | int    | `60`               | Poll interval (60–3600); GitHub may ask for longer       |
| `show_count`         | bool   | `true`             | Show the unread count                                    |
| `participating_only` | bool   | `false`            | Only threads you're mentioned in, assigned or asked to review |
| `include_read`       | bool   | `false`            | Keep threads listed after they're read                   |
| `mark_read_on_open`  | bool   | `true`             | Mark a thread read when you open it                      |
| `client_id`          | string | GitHub CLI's       | OAuth app used for sign-in — see below                   |
| `scopes`             | string | `"notifications"`  | Space-separated scopes the sign-in requests              |

To add it, put `"github"` in a panel's layout. Nothing is polled while no bar or overview tab needs it. An unchanged list costs no rate-limit quota.

#### Signing in

Sign in under **Settings › Accounts › GitHub** (the module's popup links there when signed out). The shell uses GitHub's device flow: it shows a code, opens github.com/login/device, and you enter the code there. The shell never sees your password. The same account is used by the todo board's issue/PR links and the overview's Code tab.

- The token is stored in `~/.local/state/moonswing/github-token` (mode 0600), not in `config.toml`.
- **Sign out** deletes it from this machine but doesn't revoke access; the key button beside it opens [github.com/settings/applications](https://github.com/settings/applications) to do that.
- Copying the code needs `wl-copy` (package `wl-clipboard`); without it, type the code by hand.
- The consent screen says **GitHub CLI** because that is the default `client_id`. To use your own OAuth app, register one with *Enable Device Flow* ticked and set `client_id = "Iv1.0123456789abcdef"`.
- The default `notifications` scope doesn't cover **private** repositories. For those (and private-repo link titles on the todo board), set `scopes = "notifications repo"` — this grants full repository access.
- After changing `client_id` or `scopes`, sign out and in again.

### Stock market

Your watchlist scrolling along the bar like a news ticker: symbol, price and today's move in green or red. Hover to pause it. Click for the list: search by symbol or company name to add, reorder with the arrows, remove with **×**, or click a row to open it on Yahoo Finance. Not in the default layout.

```toml
[modules.stocks]
symbols = ["^GSPC", "^DJI", "^IXIC", "AAPL", "MSFT", "BTC-USD"]
refresh_seconds = 15
scroll = true
scroll_speed = 40
width = 320
```

| Key               | Type         | Default | Description                                                  |
| ----------------- | ------------ | ------- | ------------------------------------------------------------ |
| `symbols`         | string array | `[]`    | Watchlist in display order, as Yahoo Finance spells them     |
| `refresh_seconds` | int          | `15`    | Poll interval while a market on the list is open (5–3600)    |
| `scroll`          | bool         | `true`  | `false` shows only the first symbol, standing still          |
| `scroll_speed`    | float        | `40`    | Pixels per second (5–400)                                    |
| `width`           | float        | `320`   | Strip width on a horizontal bar (80–2000); a shorter list doesn't scroll |

- Symbols: `AAPL`, `^GSPC` (S&P 500), `BRK-B`, `SAP.DE`, `EURUSD=X`, `BTC-USD`. Case doesn't matter; duplicates are dropped.
- Outside regular hours the price shown is pre-market or after-hours once anything has traded.
- While every market on the list is closed, prices refresh every two minutes. Nothing is fetched while neither the strip nor the Stock market desktop widget is on screen.
- On a side bar the module is a chart icon coloured by the first symbol's move.
- An empty list offers the S&P 500, Dow and Nasdaq in one click. The popup and Settings › Shell › Modules › Stock market both edit `symbols`.
- To add it, put `"stocks"` in a panel's layout, or use Settings › Shell › Panels & Layout.

### Notifications

The shell is the desktop's notification daemon. The bell shows a count and
shakes when something arrives; clicking it (or `open_notifications`, Super+N)
opens the **notification panel**, docked against the right edge of the screen
whose bar you clicked.

```toml
[modules.notifications]
sound = "chime"
sound_volume = 0.7
side = "right"
width = 400
animation = "slide"
```

| Key            | Type   | Default   | Description                                                      |
| -------------- | ------ | --------- | ---------------------------------------------------------------- |
| `sound`        | string | `"chime"` | What plays when a notification arrives — see below               |
| `sound_volume` | float  | `0.7`     | Volume, 0–1                                                      |
| `side`         | string | `"right"` | Edge the panel docks against: `"left"` or `"right"`              |
| `width`        | int    | `400`     | Panel width in pixels (240–1200)                                 |
| `animation*`   |        |           | How the panel opens and closes — see [below](#the-panels-animation) |

`side`, `width` and the animation keys apply the next time the panel opens.
They take effect even with no bell in any bar, since the floating notification
card opens the same panel.

**`sound`** accepts:

- a shipped sound: `chime`, `ping`, `glass`, `bell` or `knock` (generated by
  the shell and cached in `~/.cache/moonswing/sounds/`);
- `none`, `off` or `silent`;
- a path (anything containing `/`; `~` is expanded), in any format mpv plays;
- a name from the system sound theme, searched under the XDG sound directories
  (`~/.local/share/sounds`, `/usr/share/sounds`, `$XDG_DATA_DIRS`), e.g.
  `"message"` finds `/usr/share/sounds/freedesktop/stereo/message.oga`.

A name that matches nothing is reported on the panel's **Notification sound**
row; click the row to preview. The chime needs mpv, plays only while a
`notifications` module is in some panel, never plays while notifications are
silenced, and plays once for a burst.

**The panel:**

- Each card has its actions, a **✓** to mark it read and a **✕** to remove
  it; the header's **✓✓** marks everything read. The foot holds the silence
  switch (also in the bell's right-click menu; stored as `[notifications]
  silenced`) and the sound row.
- Marking read removes nothing. It clears the bell's count and the floating
  card. Opening the panel marks nothing read.
- It never takes keyboard focus and stays open until you click its ×, the
  bell, or press the shortcut. Clicking a notification that opens something
  closes it.
- It sits above your windows without moving them, between the top and bottom
  bars. Clicks on its shadow reach the window beneath. Docked against the same
  edge as the [clipboard history](#clipboard), the two sit side by side.

The bell is in the default bottom panel. An existing config is never rewritten,
so to add it yourself:

```toml
[panels.bottom.layout]
right = ["media_player", "notifications", "launcher"]
```

#### The panel's animation

Both the notification panel and the [clipboard history](#clipboard) take these
keys, each in its own table.

```toml
[modules.notifications]
animation = "slide"
animation_curve = "ease_out"
animation_duration = 150
animation_exit_ratio = 0.75
animation_travel = 1.0
animation_fade = false
```

| Key                    | Type   | Default      | Description                                                                                       |
| ---------------------- | ------ | ------------ | ------------------------------------------------------------------------------------------------- |
| `animation`            | string | `"slide"`    | `slide`, `fade`, `reveal`, `stretch` or `none`                                                    |
| `animation_curve`      | string | `"ease_out"` | `linear`, `ease_in`, `ease_out`, `ease_in_out`, `emphasized`, `overshoot`, `bounce` or `elastic` |
| `animation_duration`   | int    | `150`        | Opening time in ms (0–2000); `0` turns the animation off                                          |
| `animation_exit_ratio` | float  | `0.75`       | Closing time as a fraction of opening time (0–2)                                                  |
| `animation_travel`     | float  | `1.0`        | Fraction of the panel's width the movement covers (0.05–1)                                        |
| `animation_fade`       | bool   | `false`      | Also fade while moving                                                                            |

- `slide` comes out of the screen edge; `fade` fades in place; `reveal`
  uncovers the panel from the edge inwards; `stretch` grows it out of the
  edge; `none` shows it at once.
- Closing plays the curve in reverse. The panel never leaves the screen edge,
  so an overshoot holds at the edge instead.
- `animation_travel` below 1 starts the panel part-way in; pair it with
  `animation_fade = true` to avoid a jump. Travel and fade do nothing for
  `fade` and `none`.

### Sound Control

The speaker icon. Click for a volume slider and mute button for the default
output; scroll over it to change the volume. No settings.

### Quick Settings

One button showing the connection, Bluetooth (while on) and volume; scroll over
it to change the volume. Click it for a panel with:

- **Wi-Fi** and **Bluetooth** switches. The arrow beside each lists networks in
  range (saved or open ones join in one click; a new secured network opens
  Settings › Network for its password) or paired devices (click to connect or
  disconnect).
- **Power mode**: Power Saver, Balanced or Performance. Needs
  `power-profiles-daemon` or `tuned-ppd`.
- **Output** and **Input**: volume, mute, and a list to pick the default device.
- **Brightness**, on machines with a backlight.
- A gear that opens Settings and a power icon that opens the power menu.

Each section's ⚙ opens its Settings page. No settings of its own, and not in
the default layout: add `"quick_settings"` to a panel.

### System Monitor

CPU, memory and temperature in the bar, with a popup. The same settings drive
the overview's **System** tab (graphs, swap, load, network, disk usage and a
process table you can kill from).

```toml
[modules.system_monitor]
poll_seconds = 1
temp_unit = "celsius"
history_samples = 120
cpu_percent_mode = "machine"
show_kernel_threads = false
confirm_kill = true
kill_grace_seconds = 5
disk_poll_seconds = 30
```

| Key                   | Type   | Default     | Description                                                                                       |
| --------------------- | ------ | ----------- | ------------------------------------------------------------------------------------------------- |
| `poll_seconds`        | int    | `1`         | How often stats are read (1–60)                                                                   |
| `temp_unit`           | string | `"celsius"` | `"celsius"` or `"fahrenheit"`                                                                     |
| `history_samples`     | int    | `120`       | Samples kept for the graphs (10–600)                                                              |
| `cpu_percent_mode`    | string | `"machine"` | `"machine"`: % of the whole machine. `"core"`: `top`-style, 100% = one core                       |
| `show_kernel_threads` | bool   | `false`     | Show kernel threads in the process table                                                          |
| `confirm_kill`        | bool   | `true`      | Ask before ending a process. Force-quit always asks                                               |
| `kill_grace_seconds`  | int    | `5`         | Wait before offering to force-quit a process that ignored the request (1–60)                      |
| `disk_poll_seconds`   | int    | `30`        | How often disk usage is read, via `df` (5–600)                                                    |

Nothing is sampled unless the module is in a bar or the System tab is open.
The shell itself and `init` cannot be killed.

### Screenshot

The camera icon: choose an area, a window or a screen, and the PNG is saved and
copied to the clipboard. `screenshot_area` (Print Screen) uses the same
settings, with or without the module in a bar. Picking a window needs Miracle
WM.

```toml
[modules.screenshot]
directory = "~/Pictures/Screenshots"
filename_prefix = "Screenshot"
copy_to_clipboard = true
delay_seconds = 0
show_cursor = false
shutter_sound = "shutter"
shutter_volume = 0.6
```

| Key                 | Type   | Default                    | Description                                                        |
| ------------------- | ------ | -------------------------- | ------------------------------------------------------------------ |
| `directory`         | string | `"~/Pictures/Screenshots"` | Save folder. `~` and `$HOME` expand; a relative path is under home |
| `filename_prefix`   | string | `"Screenshot"`             | File name before the date, e.g. `Screenshot_2026-11-14_09-30-00.png` |
| `copy_to_clipboard` | bool   | `true`                     | Also copy the shot, via `wl-copy`                                  |
| `delay_seconds`     | int    | `0`                        | Pause before capturing (0–60)                                      |
| `show_cursor`       | bool   | `false`                    | Include the pointer                                                |
| `shutter_sound`     | string | `"shutter"`                | Sound played once the file is saved                                |
| `shutter_volume`    | float  | `0.6`                      | Volume, 0–1                                                        |

`shutter_sound` takes a shipped sound (`shutter`, `snap`, `clack`, `tick`),
`none`/`off`/`silent`, a path, or a sound-theme name, resolved as for
[the notification chime](#notifications); `"camera-shutter"` finds
`/usr/share/sounds/freedesktop/stereo/camera-shutter.oga`. It plays when the
file is written, so a failed capture is silent. A name that matches nothing is
shown in the screenshot menu.

### Screen Recorder

The video camera icon: choose an area, a window or a screen to record. While
recording the icon is a red dot with a timer; click it and choose **Stop**.
`record_screen` (Super+Print Screen) records the current screen and stops on a
second press. Video only, no audio. Needs `ffmpeg`.

```toml
[modules.screen_recorder]
directory = "~/Videos/Screencasts"
filename_prefix = "Screencast"
fps = 30
container = "mp4"
quality = 23
show_cursor = true
```

| Key               | Type   | Default                  | Description                                                                 |
| ----------------- | ------ | ------------------------ | --------------------------------------------------------------------------- |
| `directory`       | string | `"~/Videos/Screencasts"` | Save folder, expanded as for screenshots                                    |
| `filename_prefix` | string | `"Screencast"`           | File name before the date                                                   |
| `fps`             | int    | `30`                     | Frame rate of the file (1–120)                                              |
| `container`       | string | `"mp4"`                  | `mp4`, `webm` or `mkv`; anything else is `mp4`                              |
| `encoder`         | string | `""`                     | ffmpeg encoder; empty is `libvpx-vp9` for webm, `libx264` otherwise         |
| `quality`         | int    | `23`                     | CRF, 0–51; lower is better. Only used by `libx264`, `libx265`, `libvpx(-vp9)` |
| `show_cursor`     | bool   | `true`                   | Include the pointer                                                         |

### Scratchpad

The note icon shows or hides the window manager's scratchpad: windows stashed
off every workspace. Needs Miracle WM; on other compositors the module is left
out of the bar.

- Click: show or hide every stashed window (same as `toggle_scratchpad`,
  Super+Z).
- `move_to_scratchpad` (Super+Shift+Z) stashes the focused window. There is no
  button for it.
- Hover to see both [shortcuts](#shortcuts).

No settings and no count (the window manager does not report one). If the
window manager cannot be reached the icon dims and the tooltip says why; the
next click retries.

### Clipboard

The clipboard icon opens your **clipboard history**, docked against the left
edge of the screen whose bar you clicked. It keeps text, pictures and files
copied in a file manager, newest first.

- Click a card to copy it again. The outlined top card is what is on the
  clipboard now.
- The pin keeps an entry through trimming and **Clear**; the bin deletes one.
- The panel never takes keyboard focus, so your window keeps its cursor. It
  stays open until you click its × or the icon again.
- It sits above your windows without moving them, like the
  [notification panel](#notifications); docked on the same edge, the two sit
  side by side.

```toml
[modules.clipboard]
side = "left"
width = 360
max_entries = 100
persist = true
max_item_mb = 32
animation = "slide"
```

| Key           | Type   | Default  | Description                                                              |
| ------------- | ------ | -------- | ------------------------------------------------------------------------ |
| `side`        | string | `"left"` | Edge the panel docks against: `"left"` or `"right"`                      |
| `width`       | int    | `360`    | Panel width in pixels (240–1200)                                         |
| `max_entries` | int    | `100`    | Entries kept before the oldest go (1–1000); pinned ones don't count      |
| `persist`     | bool   | `true`   | Keep history across restarts. `false` deletes the saved history          |
| `max_item_mb` | int    | `32`     | Skip anything larger than this, in MB (1–1024). Text is capped at 2 MB   |
| `animation*`  |        |          | How the panel opens and closes — see [the panel's animation](#the-panels-animation) |

- `side`, `width` and the animation keys apply the next time the panel opens.
- Copied files are kept as paths, so `max_item_mb` limits pictures and media
  copied directly.
- History is recorded only while some bar has the clipboard icon. It is
  stored, private to you, in `~/.local/state/moonswing/clipboard/` (or under
  `$XDG_STATE_HOME`). Entries a password manager marks as secret (KeePassXC
  does) are never recorded.
- **Requires `wl-clipboard`** (`wl-paste`, `wl-copy`) and a compositor with the
  wlr- or ext-data-control protocol. Without them the icon dims and the panel
  says what is missing, with a retry.

The icon is in the default bottom panel. To add it to an existing config, use
**Settings › Shell › Panels & Layout** or:

```toml
[panels.bottom.layout]
left = ["clipboard"]
```

### Todo

The checklist icon opens the overview's **Kanban** tab (see
[the overview](#the-overview)). The number beside it counts open cards due today
or overdue. No settings in `config.toml`.

**The board** has five columns: **Inbox**, **Todo**, **In Progress**,
**Finished**, **Abandoned**.

- Drag cards between columns; **+** adds one. Click a card to edit its title,
  details, column, due date and repeat, or read its history of column moves.
- Lines like `- [ ] Send it` in the details are drawn as a checklist.
- Overdue cards sit at the top of Inbox, Todo and In Progress. Finished shows
  today's cards and folds earlier ones by day; Abandoned folds every day.
- At start-up and each midnight the shell posts one notification of what is due
  today and still open from earlier.
- **Repeat** every N days, weeks or months from a start day. Each scheduled day
  a copy, due that day, is added to the top of Todo and carries the repeat;
  edit or delete the newest copy to change or stop it. A monthly repeat on the
  31st uses the last day of shorter months. Days missed while the shell was off
  produce one copy, for the latest.
- **Search** (Ctrl+F) filters every column to cards whose title or details
  contain all the words typed, anywhere in a word, ignoring case. Escape clears
  it, then closes the overview.
- Web addresses in a card are links. While a GitHub account is signed in, links
  to GitHub issues and pull requests show as chips with title, number and
  state, refreshed when the board is opened more than ten minutes later. Links
  into private repositories need the `repo` scope (see [GitHub](#github)).

**Standup.** The megaphone lists your summaries; **New summary** writes one:
cards moved to Finished since the last summary, everything In Progress (marked
*started* if new), everything in Todo with due dates, and cards moved to
Abandoned. The first covers the last 24 hours. Inbox and Google calendar
meetings are left out. Select and copy with Ctrl+C (needs `wl-clipboard`).
Nothing is sent anywhere.

**Storage.** The board is saved as you go to
`~/.local/share/moonswing/notes.db` (SQLite, bundled; or under
`$XDG_DATA_HOME`). An old `todo.json` is imported once and renamed
`todo.json.imported`. If the database cannot be read, the board says why and
saves nothing until it can.

#### Backups

Every change is also written to
`~/.local/share/moonswing/backup/todo-backup.json`, shown at the bottom of the
board.

- If `notes.db` is missing at start-up, the board is restored from the backup.
  If it is damaged, it is renamed `notes.db.damaged-<time>` and rebuilt from
  the backup. Either way the board tells you. A database from a newer shell
  version is left alone.
- The folder holds only that file, so you can keep it in Git. The file is
  pretty-printed in board order and rewritten only on change, so each commit
  is a clean diff. A symlink in its place is written through.

  ```sh
  cd ~/.local/share/moonswing/backup
  git init
  git add todo-backup.json
  git commit -m "Todo backup"
  ```

- **Backups…** (or the cloud icon by the search field) shows the file, and
  **Restore from this file…** replaces the board with it after saving the
  current board beside it.

#### Task list sync

The board can sync with a CalDAV task list (Radicale, Baïkal, Nextcloud,
Fastmail, iCloud, …), so phones (DAVx⁵ with jtx Board or Tasks.org) and other
clients (Thunderbird, Evolution) share the cards. The local database stays the
source of what is on screen and works offline.

**Sign in** under **Settings › Accounts › CalDAV** with the server or
collection address, user name and password (an app password where offered). The
server is checked before the account is saved. **Add account** adds another;
signing in again with the same address and user replaces it. Credentials are
stored, private to you, in `~/.local/state/moonswing/caldav-account.json`. The
same accounts can show events on the [Calendar](#calendar) tab.

**Self-signed certificates.** Certificates are checked against
`/etc/ssl/certs`. One it cannot verify is refused with
`CERTIFICATE_VERIFY_FAILED` and its SHA-256 fingerprint shown. Compare it with
`openssl x509 -in cert.pem -noout -fingerprint -sha256` on the server, then
click **Trust certificate and connect** (or **Trust** on an existing account).
Only that exact certificate is pinned; a renewed one must be trusted again.
Alternatively serve the full chain or add your CA to the system store
(`update-ca-certificates` on Debian/Ubuntu, `trust anchor` on Fedora/Arch).

**Link** a list from **Backups…** on the board. With several accounts, every
account's lists are offered. Linking merges both sides; with the switch on it
replaces the board with the list instead (saving the board beside the backup
first). **Unlink** stops syncing and changes nothing.

What syncs:

- Title, notes, column, due day and simple repeats (every N days, weeks,
  months or years). Columns map to status: Todo = *needs action*, In Progress
  = *in process*, Finished = *completed*, Abandoned = *cancelled*; Inbox is
  *needs action* plus a marker other apps ignore.
- Complex repeats stay on the server; the card does not repeat.
- Move history and in-column order stay local. Server fields the board doesn't
  use (alarms, categories, …) are kept. Google calendar meetings are never
  sent.

When it syncs: a few seconds after a change, on opening the board, on **Sync
now**, and every five minutes while a list is linked.

Conflicts:

- Changes to different fields on both sides are both kept. The same field
  changed on both sides takes the server's value, and the board lists the
  affected cards.
- A task deleted on the server deletes its card, unless the card changed here
  since (it is re-sent). A card deleted here deletes the task, unless the task
  changed there since.
- An unreachable server shows in red at the bottom of the board; pending
  changes go on the next successful sync.

## Shortcuts

`[shortcuts]` binds the shell's global shortcuts. They work whichever window has focus. They need a compositor with Mir's `ext-input-trigger` protocols (Miracle WM, Miriway); elsewhere none are registered.

```toml
[shortcuts]
open_settings = "super+s"
open_launcher = "super+d"
open_emoji = "ctrl+shift+e"
open_notifications = "super+n"
open_power_menu = "shift+super+e"
switch_windows = "alt+tab"
switch_windows_back = "alt+shift+tab"
screenshot_area = "print"
record_screen = "super+print"
toggle_scratchpad = "super+z"
move_to_scratchpad = "shift+super+z"
power_button = "poweroff"
```

| Key                   | Default           | Action |
| --------------------- | ----------------- | ------ |
| `open_settings`       | `"super+s"`       | Toggle Settings |
| `open_launcher`       | `"super+d"`       | Toggle the application launcher |
| `open_emoji`          | `"ctrl+shift+e"`  | Toggle the [emoji picker](#emoji-picker) |
| `open_notifications`  | `"super+n"`       | Toggle the [notification panel](#notifications) |
| `open_power_menu`     | `"shift+super+e"` | Toggle the power menu |
| `switch_windows`      | `"alt+tab"`       | [Window switcher](#the-window-switcher), forwards (Miracle WM only) |
| `switch_windows_back` | `"alt+shift+tab"` | Window switcher, backwards (Miracle WM only) |
| `screenshot_area`     | `"print"`         | Screenshot an area you drag out |
| `record_screen`       | `"super+print"`   | Start recording the focused screen; press again to stop |
| `toggle_scratchpad`   | `"super+z"`       | Show or hide the [scratchpad](#scratchpad) (Miracle WM only) |
| `move_to_scratchpad`  | `"shift+super+z"` | Move the focused window to the scratchpad (Miracle WM only) |
| `power_button`        | `"poweroff"`      | The machine's power button; what it does is set in [`[power]`](#power-button) |

All values are strings.

- **Changes need a shell restart.** Shortcuts are registered once at start-up.
- Set a key to `""` or `"none"` to disable it (for example, when it clashes with an input method).
- An invalid value falls back to the default and is logged.
- If two keys use the same combination, only the first is registered. If another client already owns a combination, it is skipped and logged.
- `record_screen` records the screen with the focused workspace. Without Miracle WM it asks you to click a screen instead.

### The window switcher

Hold Alt and press Tab: an overlay lists open windows, most recent first. Press Tab again (or the arrow keys) to move; release Alt to switch. Escape or a click on the backdrop cancels; a click on an icon switches to that window. Switching to a window on another workspace changes workspace too.

The switcher ends when the last held modifier is released, so a binding must include a modifier (`"f13"` alone would never close it).

### Changing shortcuts in the overview

The keyboard icon on the bar opens the overview's **Shortcuts** tab. The shell's shortcuts are listed under **Shell**; click one and press a new combination:

- **Esc** cancels.
- **Backspace** disables the shortcut.
- The arrow beside a changed row restores the default.

The sheet refuses a combination another shell shortcut already uses and warns when the window manager uses it. Changes still need a restart. The window manager's own bindings are shown read-only; edit them under **Settings › Window Manager › Key Bindings**.

### Syntax

Modifiers and one key joined by `+`, case-insensitive.

| Part      | Accepted |
| --------- | -------- |
| Modifiers | `ctrl`/`control`, `shift`, `alt`, `super`/`meta`/`win`/`logo` |
| Key       | `a`–`z`, `0`–`9`, `f1`–`f24`, a named key, a raw keysym `0x…`, or an evdev keycode `code:N` |

Named keys: `space`, `return`/`enter`, `tab`, `escape`/`esc`, `backspace`, `delete`/`del`, `insert`, `home`, `end`, `pageup`, `pagedown`, `left`, `right`, `up`, `down`, `print`, `pause`, `menu`, `poweroff`/`power`, `sleep`, and `minus`, `equal`, `plus`, `comma`, `period`, `slash`, `backslash`, `semicolon`, `apostrophe`, `grave`, `bracketleft`, `bracketright`.

- There are no left/right modifier variants; `ctrl` matches either Control key.
- Write Shift explicitly: `"ctrl+S"` is the same as `"ctrl+s"`. Use `"ctrl+shift+s"`.
- With `shift`, digits and punctuation are translated using a **US layout** (`"ctrl+shift+1"` registers `!`). On other layouts use a raw keysym or keycode:

```toml
[shortcuts]
open_launcher = "0x1008ff1b"       # raw keysym (XF86Search)
open_settings = "super+code:31"    # evdev keycode: the physical S key, on any layout
```

## Emoji Picker

`open_emoji` (Ctrl+Shift+E) opens a searchable emoji grid. Type to search, move with the arrow keys, press **Enter** to copy the highlighted emoji and close. **Escape** or a click on the backdrop closes without copying.

- Search matches the name, keywords, category or the emoji itself (`pizza`, `italian`, `food` and `🍕` all find 🍕).
- Matching is fuzzy: letters only need to appear in order (`thmbs` finds "thumbs up"; `face joy` finds "face with tears of joy").
- Exact matches rank first, then name over keywords over category.
- Copying needs `wl-copy` from the **wl-clipboard** package. Without it, a notification says so.

To rebind it, see [Shortcuts](#shortcuts).

## Power Button

`[power]` sets what the machine's power button does. By default it shows the power menu (Lock, Log Out, Sleep, Restart, Shut Down) instead of powering off.

```toml
[power]
key_action = "menu"
inhibit_logind = true
```

| Key              | Type    | Default  | Description |
| ---------------- | ------- | -------- | ----------- |
| `key_action`     | string  | `"menu"` | What a press does (below) |
| `inhibit_logind` | boolean | `true`   | Stop systemd-logind acting on the key while the shell handles it |

| `key_action` | Effect |
| ------------ | ------ |
| `"menu"`     | Show the power menu. Escape or a click outside cancels; Enter picks the highlighted action (Shut Down at first) |
| `"shutdown"` | Power off immediately |
| `"reboot"`   | Restart immediately |
| `"suspend"`  | Suspend |
| `"lock"`     | Lock the session |
| `"logout"`   | End the session |
| `"none"`     | Do nothing; logind handles the key as usual |

Also accepted: `off`/`poweroff` (shutdown), `restart` (reboot), `sleep` (suspend), `log_out`/`logoff` (logout), `dialog`/`power_menu` (menu), `ignore`/`disabled`/`""` (none). An unknown value falls back to `"menu"` and is logged.

- Both keys apply live (Settings › Shell › Power Button). The key binding itself, `[shortcuts] power_button`, needs a restart.
- The bar's power button and `open_power_menu` always open the menu, whatever `key_action` says.
- With `inhibit_logind`, the shell holds logind's `handle-power-key` lock only while it actually owns the key, and drops it on exit or crash. A long press is left to logind.
- Turn `inhibit_logind` off only if `logind.conf` already has `HandlePowerKey=ignore`; otherwise logind powers off behind the menu.

If the button does nothing:

- Check the log for `input-trigger: "moonswing.power-button" owned` at start-up; another client may own the key instead.
- If your power key sends a different keysym, bind the physical key: `power_button = "code:116"` (evdev `KEY_POWER`).

## Authentication Prompts

`[polkit]` makes the shell the session's polkit agent: the "Authentication required" dialog shown when an application asks for administrator rights. Without an agent, those requests are refused silently. Miracle WM ships none.

```toml
[polkit]
enabled = true
max_attempts = 3
```

| Key            | Type    | Default | Description |
| -------------- | ------- | ------- | ----------- |
| `enabled`      | boolean | `true`  | Register as the polkit authentication agent |
| `max_attempts` | int     | `3`     | Wrong passwords allowed before the dialog gives up (1–5) |

- Read at start-up; restart the shell to apply.
- Escape, a click outside, or Cancel denies the request.
- If another agent is already registered when the shell starts, the shell leaves it alone. Set `enabled = false` if your agent starts after the shell.
- With `enabled = false` and no other agent, nothing can ask for administrator rights.

If prompts do not appear:

- Look for `polkit: registered as the authentication agent for session <id>` in the log.
- The password check needs `polkit-agent-helper-1`, part of polkit (`polkitd` on Debian/Ubuntu, `polkit` on Fedora, Arch, openSUSE). The dialog says if it is missing.
- A logind session is required: `echo $XDG_SESSION_ID` must print something.

## Theme

A theme is a file of its own under `~/.config/moonswing/themes/`. `config.toml` picks one by its filename without `.toml`:

```toml
theme = "dracula"
```

Seven themes ship with the shell:

| Name        | Looks like                                                                 |
| ----------- | -------------------------------------------------------------------------- |
| `glassy`    | Cool translucent islands floating over the wallpaper. The default.          |
| `forest`    | A carved oak beam on mossy capstones, overgrown with ivy and ferns; menus grow out of it like bark-rimmed trunks. |
| `autumn`    | Forest in October: a chestnut beam, turning leaves in the top corners, pumpkins along a bottom bar. |
| `dracula`   | The [Dracula](https://draculatheme.com) palette.                            |
| `midnight`  | Indigo, one type size up, with cards that glow instead of casting a shadow. |
| `carbon`    | Flat, square graphite; bar menus grow out of the bar on a flared join.      |
| `classic95` | The 1995 desktop: grey taskbar, raised square menus, teal desktop. The only light theme. |

Each comes with its own wallpaper, shown while the **Theme default** wallpaper is selected — see [The theme's wallpaper](#the-themes-wallpaper).

- The easy way in is **Settings › Shell › Theme**: pick a theme (applies at once), edit any key live, or **New theme…**.
- The shipped themes are read-only. The shell rewrites their files on every start, so hand edits to `dracula.toml` are lost. Editing one in Settings makes a copy (**Duplicate to edit**); your own files are never touched.
- If `theme` is missing, names no file, or names a file that does not parse, you get `glassy`. A single bad value inside a theme costs only that key.
- **Switching** themes blends the colours and `font_size` over a moment; everything else (geometry, fonts, icons, animations, materials and their tints) changes at once. Editing a key applies immediately.
- An old inline `[theme]` table in `config.toml` is ignored and gives you `glassy`. To keep it, move its contents (without the `[theme]` line) into `themes/mine.toml` and set `theme = "mine"`.

### Writing a theme file

A theme file is a flat table with no section header. Every key is optional.

```toml
# ~/.config/moonswing/themes/gruvbox.toml
name = "Gruvbox"

font = "Ubuntu Sans"
font_size = 13.0
icon_pack = "font_awesome"

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
panel_gradient       = "accent"
panel_margin         = 0
panel_radius         = 0.0
panel_border         = "#33EBDBB2"
panel_border_width   = 0.0

popup_radius         = 8.0
popup_gap            = 0.0
popup_border         = "#33EBDBB2"
popup_border_width   = 1.0
popup_shadow_color   = "#66000000"
popup_animation      = "slide"

overlay_radius       = 12.0
overlay_animation    = "scale"
```

Colours are `#RRGGBB` or `#AARRGGBB` (`AA` is alpha: `"#33FFFFFF"` is white at ~20%). Alpha is how a theme becomes translucent; there is no blur key.

| Key                    | Type   | Default        | Description |
| ---------------------- | ------ | -------------- | ----------- |
| `name`                 | string | the filename   | Name shown in the theme picker |
| `font`                 | string | `Ubuntu Sans`  | Font family for all shell text (any fontconfig family) |
| `font_size`            | float  | `13.0`         | Body text size in logical pixels; the whole type scale follows it. 6–32 |
| `icon_pack`            | enum   | `font_awesome` | Interface icon font; see below |
| `wallpaper`            | string | `""`           | The theme's wallpaper; see [The theme's wallpaper](#the-themes-wallpaper) |
| `accent`               | colour | `#853953`      | Focused workspace, slider fill, selections, charts |
| `foreground`           | colour | `#F3F4F4`      | Text and icons on the bar |
| `surface_hover`        | colour | `#853953`      | Button background on hover |
| `surface_pressed`      | colour | `#612D53`      | Button background when pressed; middle of the `accent` gradient |
| `workspace_background` | colour | `#2C2C2C`      | The workspaces pod |
| `popup_background`     | colour | `#2C2C2C`      | Popups, menus, the OSD and the overview |
| `popup_foreground`     | colour | `#F3F4F4`      | Text and icons in popups |
| `control_surface`      | colour | `#39393D`      | Cards, inputs and tiles in popups and Settings |
| `slider_track`         | colour | `#612D53`      | Unfilled part of sliders and usage bars |
| `muted`                | colour | `#C4A8B2`      | Secondary text: headers, timestamps, units |
| `divider`              | colour | `#33F3F4F4`    | Separator lines, and the fill of quiet rows — give it enough alpha to read as a surface |
| `notification_badge`   | colour | `#F2B441`      | Unread notifications: the floating badge, the bell's count, the unread dot |
| `notification_badge_foreground` | colour | `#2C1218` | Text on `notification_badge` |
| `scrim`                | colour | `#882C2C2C`    | Wash over the screen behind a full-screen overlay |

Notes:

- **`accent` is a fill colour.** Where the shell writes text in the accent (a checked row, the current tab, today's date), it lightens it as far as needed to read on `popup_background`. There is nothing to set.
- **`font_size`** scales text only — in the bar, popups, overlays and desktop widgets. Bar thickness is `[panels.<name>] height`; raise it with a much larger font. Icons keep their size.
- **`notification_badge`** is meant to be louder than the rest of the palette; the shipped themes use a hue they use nowhere else.

**`icon_pack`** values:

| Value               | Pack                      | Look |
| ------------------- | ------------------------- | ---- |
| `font_awesome`      | Font Awesome Free         | Solid, heavy glyphs. The default and every pack's fallback |
| `material_rounded`  | Material Symbols Rounded  | Rounded corners and ends |
| `material_outlined` | Material Symbols Outlined | Outlined, crisp corners |
| `material_sharp`    | Material Symbols Sharp    | Square corners and ends (`classic95` uses it) |
| `lucide`            | Lucide                    | Thin, even strokes, no filled forms |
| `remix`             | Remix Icon                | Neutral line icons, filled for "on" states |

An icon a pack lacks (brand logos under Material Symbols and Lucide, for example) is drawn from Font Awesome. Icons keep the same size under every pack. Application, tray and file icons come from your desktop icon theme, and weather pictures are their own; neither changes with this key.

### The panel

These keys shape every bar. All of them apply live.

| Key                    | Type   | Default     | Description |
| ---------------------- | ------ | ----------- | ----------- |
| `panel_background`     | colour | `#EE2C2C2C` | The bar's fill; its alpha is the whole bar's opacity |
| `panel_gradient`       | enum   | `accent`    | `none` (flat), `accent` (fade from `accent`) or `corners` (a colour per corner) |
| `panel_gradient_top_left` | colour | `#EE853953` | Top-left colour under `corners` |
| `panel_gradient_top_right` | colour | `#EE612D53` | Top-right colour under `corners` |
| `panel_gradient_bottom_right` | colour | `#EE2C2C2C` | Bottom-right colour under `corners` |
| `panel_gradient_bottom_left` | colour | `#EE612D53` | Bottom-left colour under `corners` |
| `panel_margin`         | int or table | `0`   | Gap between the bar and the screen edges, 0–256; see [Floating the bar](#floating-the-bar) |
| `panel_radius`         | float or table | `0.0` | Corner rounding, 0–64 |
| `panel_corners`        | string or list | `auto` | Which corners round: `auto`, `all`, `none`, or a list of `top_left`, `top_right`, `bottom_right`, `bottom_left` |
| `panel_square_flush_corners` | bool | `false` | Keep square every corner that touches a screen edge with no margin |
| `panel_border`         | colour | `#33F3F4F4` | Rim colour |
| `panel_border_width`   | float  | `0.0`       | Rim thickness, 0–16; `0` is no rim |
| `panel_join_radius`    | float  | `0.0`       | Fillet where two bars meet, 0–64; see [Where two bars meet](#where-two-bars-meet) |
| `panel_join`           | bool   | `false`     | Join all bars into one frame; see [Where two bars meet](#where-two-bars-meet) |

- **`accent` gradient:** fades from `accent` at the bar's start (left of a top bar, top of a side bar) through `surface_pressed` to `panel_background`, every stop at `panel_background`'s alpha. `panel_background = "#402C2C2C"` makes the whole bar 25% opaque. `true`/`false` from older themes read as `accent`/`none`.
- **`corners` gradient:** each colour keeps its own alpha and they blend across the bar. Corners are the screen's, so every bar is lit from the same side. Matching the two left and the two right corners gives a left-to-right fade:

  ```toml
  panel_gradient = "corners"
  panel_gradient_top_left     = "#EE853953"
  panel_gradient_bottom_left  = "#EE853953"
  panel_gradient_top_right    = "#EE2C2C2C"
  panel_gradient_bottom_right = "#EE2C2C2C"
  ```

- **Rim:** width is the switch, not alpha. The rim is left off any side flush against the screen edge. A 1px rim helps a translucent bar stand out from a busy wallpaper.
- A translucent bar shows the shell's own wallpaper (`[background]`); without one, whatever the compositor paints (often black).

### Floating the bar

`panel_margin` moves each bar off the screen edges it is anchored to (`glassy` uses `8`). The gap is real: windows do not tile into it, and clicks there reach the desktop. Reserved space grows with the margin — a 32px bar with an 8px margin keeps windows 40px from the edge.

A table gives each side its own margin; a side left out is `0`:

```toml
# Every bar's far end stops 8px short; everything else is flush.
panel_margin = { top = 0, right = 8, bottom = 0, left = 0 }
```

Sides are named in the **bar's own frame**. A side bar is a top bar turned a quarter turn anticlockwise:

| Key      | Top or bottom bar | Left or right bar |
| -------- | ----------------- | ----------------- |
| `right`  | right end         | **top** end       |
| `left`   | left end          | **bottom** end    |
| `top`    | top side          | side towards the screen's left |
| `bottom` | bottom side       | side towards the screen's right |

So `right` is always the far end. Only the side against the screen edge and the two ends are read; the side facing the screen's middle is ignored.

**Corners** use the same frame: `top_right` is where the bar's `top` side meets its `right` end. `panel_radius` takes one number or a table:

```toml
panel_radius  = { top_left = 0, top_right = 12, bottom_right = 12, bottom_left = 4 }
panel_corners = ["top_right", "bottom_right"]   # round only the far end
```

- `auto` (Settings: **Automatic**) rounds the two corners facing the screen's middle, and a corner on the screen edge only where the bar floats off the display's own corner there. A bar floating on every side rounds all four; a flush one rounds only the inner two.
- A list (Settings: **Chosen**), `all` or `none` applies to every bar as written. A corner with radius `0` stays square either way.
- Where two bars join, the inside corner stays square.

### Sections as islands

`panel_sections = true` draws each section of a bar — the `left`, `center` and `right` lists of `[panels.<name>.layout]` — on its own island, sized to what it holds. `glassy` and `midnight` do this.

```toml
panel_background     = "#00000000"   # the bar itself draws nothing
panel_gradient       = "none"
panel_radius         = 0.0

panel_sections       = true
panel_section_background = "#40121722"
panel_section_radius = 12.0
panel_section_padding = 10.0
panel_section_border = "#40FFFFFF"
panel_section_border_width = 1.0
```

| Key                          | Type   | Default     | Description |
| ---------------------------- | ------ | ----------- | ----------- |
| `panel_sections`             | bool   | `false`     | Draw each section as an island |
| `panel_section_background`   | colour | `#EE2C2C2C` | Island fill |
| `panel_section_gradient`     | enum   | `none`      | `none`, `accent` or `corners`, as `panel_gradient` (`corners` uses the `panel_gradient_*` colours) |
| `panel_section_radius`       | float  | `8.0`       | Corner rounding, 0–64; past half the bar's depth it is a capsule |
| `panel_section_padding`      | float  | `8.0`       | Space past the first and last module, 0–64 |
| `panel_section_border`       | colour | `#33F3F4F4` | Island rim colour |
| `panel_section_border_width` | float  | `0.0`       | Island rim thickness, 0–16; `0` is no rim |

- The bar is still drawn under the islands. To show islands alone, set `panel_background`'s alpha to `0`, `panel_gradient = "none"` and `panel_radius = 0`, as above.
- A section with nothing to show (say, only a battery module on a desktop) draws no island.
- The space between islands is still the bar: it reserves space and right-clicking it opens the bar's menu.

### Where two bars meet

With bars on two adjacent edges, `panel_join_radius` fills the inside corner where they meet with a quarter round in the bar's colour, so the pair reads as one frame (`dracula` uses `12`).

- Two bars meet only when both are flush in that corner (no margin on the three sides involved), and only when each is the only bar on its edge.
- The fillet does not take clicks; windows still tile up to the bars. If the shell cannot set an input region, the corner stays square.
- It continues the bar's gradient and rim, but not `panel_texture` or `panel_image`.
- Joined bars draw one outline: the rim between them is left out.

**`panel_join = true`** makes all bars one frame. Every top or bottom bar meets the side bars at its ends whatever the margins, and `panel_join_radius` rounds every inside corner.

```toml
panel_join   = true
panel_margin = { bottom = 10 }   # the frame stands 10px off the bottom of the screen
```

- Under `panel_join`, `panel_margin`, `panel_radius` and `panel_corners` name the **screen's** sides and corners. `bottom = 10` lifts the bottom bar, and the side bars' bottom ends follow it.
- Top and bottom bars run across the corners; side bars stop against them. Keep joined bars on the same `layer`.

### Popups

These keys style everything that floats over the bar: popups, menus, flyouts, tray menus, dialogs and the OSD.

| Key                     | Type   | Default     | Description |
| ----------------------- | ------ | ----------- | ----------- |
| `popup_radius`          | float  | `8.0`       | Corner rounding, 0–64 |
| `popup_gap`             | float  | `0.0`       | Distance from the bar, 0–64; `0` attaches the popup to the bar |
| `popup_attach_radius`   | float  | `0.0`       | Outward flare where an attached popup meets the bar, 0–64; gap `0` only |
| `popup_border`          | colour | `#33F3F4F4` | Rim colour |
| `popup_border_width`    | float  | `1.0`       | Rim thickness, 0–16; `0` is no rim |
| `popup_shadow_color`    | colour | `#66000000` | Shadow colour; alpha `0` turns the shadow off |
| `popup_shadow_blur`     | float  | `16.0`      | Blur radius, 0–64 |
| `popup_shadow_spread`   | float  | `0.0`       | Grow (or, negative, shrink) before blurring, −32–32 |
| `popup_shadow_offset_x` | float  | `0.0`       | Horizontal offset, −64–64; positive is right |
| `popup_shadow_offset_y` | float  | `6.0`       | Vertical offset, −64–64; positive is down |
| `popup_animation`       | enum   | `slide`     | Entrance effect, played in reverse to close |
| `popup_animation_duration` | int | `120`       | Entrance length in ms, 0–2000; the exit takes 3/4 of it |

- A bar popup opens at the bar's inner edge, centred on its button.
- **`popup_gap = 0` is attached mode:** the card sits flush, squares its corners on the bar side and drops its rim and shadow there. `carbon` pairs it with `popup_attach_radius = 12`. Keep a gap with a translucent `popup_background` (as `glassy` does with `8`): attached, the two translucent fills show a step in tone.
- A rimmed bar leaves its rim out where an attached menu is open, so the outline runs round the card.
- The shadow enlarges the popup's window, and clicks in that margin hit the popup. On the bar side it never reaches past the gap.
- An off-palette shadow colour with zero offsets and some spread is a glow (`midnight`).
- The [notification panel](#notifications) and the clipboard history cast the same shadow on their inner edge, using only colour, blur and spread.
- Tooltips never attach. Menus opened at the pointer (desktop menu, category flyouts) ignore the gap. Popup sizes are not themable.

**`popup_animation`** values:

| Value    | Effect |
| -------- | ------ |
| `none`   | No animation |
| `fade`   | Opacity only |
| `slide`  | A short slide out of the bar, with a fade (default) |
| `scale`  | Grows from its centre, with a fade |
| `grow`   | Unrolls from the bar edge |
| `flip`   | Swings open, hinged on the bar edge |
| `spin`   | Turns slightly as it scales in, with a fade |
| `sprout` | Grows out of the bar like a trunk, then sways |

`slide`, `grow` and `flip` move away from the bar the popup came from; pointer menus act as if hanging below their anchor. `none` is the real off switch (a duration of `0` still runs the effect, instantly). The dock's labels and menu, and the scratchpad tooltip, never animate.

### Materials, pictures and foliage

These keys say what a surface is made of and what grows on it. All are off by default, and off costs nothing. `forest` uses all of them; `autumn` is a variation.

| Key                   | Type   | Default     | Description |
| --------------------- | ------ | ----------- | ----------- |
| `panel_texture`       | enum   | `none`      | The bar's material |
| `panel_texture_color` | colour | `#6B4A2E`   | Its tint; alpha is the material's strength |
| `panel_end_texture`   | enum   | `none`      | A second material capping each end of the bar |
| `panel_end_color`     | colour | `#6E726B`   | The caps' tint; alpha is strength |
| `panel_end_length`    | float  | `0.0`       | How far each cap reaches along the bar, 0–256; `0` is none |
| `panel_bevel`         | float  | `0.0`       | Carved depth of the bar's long edges, 0 (flat) – 1 |
| `panel_image`         | string | `""`        | A picture tiled over the bar instead of `panel_texture` |
| `panel_foliage`       | enum   | `none`      | What grows off the bar's inner edge |
| `foliage_color`       | colour | `#3E7A3A`   | Leaf colour (in `harvest`, the still-green leaves) |
| `foliage_bloom`       | colour | `#E0A13A`   | Berries and flowers (in `harvest`, turned leaves and pumpkins) |
| `foliage_density`     | float  | `1.0`       | Amount, as a multiple of the style's own, 0–3 |
| `panel_overhang`      | int    | `0`         | How far foliage may hang past the bar, 0–160 px |
| `popup_texture`       | enum   | `none`      | A popup card's material, under its content |
| `popup_texture_color` | colour | `#206B4A2E` | Its tint; keep the alpha low so text stays readable |
| `popup_border_texture` | enum  | `none`      | Material for the popup rim instead of `popup_border` |
| `popup_border_texture_color` | colour | `#5A4030` | The rim material's tint |
| `popup_image`         | string | `""`        | A picture tiled over popup cards instead of `popup_texture` |
| `popup_roots`         | float  | `0.0`       | How far roots spread along the bar from an attached popup, 0–96; gap `0` only |

**Materials** (`*_texture`): `none`, `wood` (planks with grain and knots), `stone` (coursed blocks with mossy joints), `bark` (ridged plates), `moss` (a soft bed). They are generated, not image files, and drawn in the tint you give.

**Foliage** (`panel_foliage`): `none`, `ivy` (trailing vines), `moss` (fine hanging strands, the quietest), `wildwood` (vines, moss, ferns, leaves, and berries/flowers in `foliage_bloom`), `harvest` (autumn leaves heaped in the corners under a top or side bar; pumpkin patches along a bottom bar).

- Plants grow away from the bar: they hang from a top bar, stand up from a bottom one. They rustle when the pointer reaches the bar or a popup opens, and are still otherwise.
- The overhang does not take clicks and windows still tile up to the bar. If the shell cannot set an input region, nothing hangs.
- **Pictures:** a path is absolute, starts with `~/`, or is relative to the themes directory. Until it loads (or if it fails) the material is drawn; Settings › Shell › Theme shows why and offers **Retry**.
- **Roots** (`popup_roots`) are drawn in `popup_border_texture` and grow as the popup opens. Pair them with `popup_animation = "sprout"`.

### Overlays

The full-screen overlays are the overview (calendar, settings, board and the other tabs), the launcher, the emoji picker, the power menu, the window switcher, the authentication and input-capture prompts and the screen-share picker.

| Key                    | Type  | Default    | Description |
| ---------------------- | ----- | ---------- | ----------- |
| `overlay_radius`       | float | `12.0`     | Corner rounding of the overview, launcher, emoji picker and screen-share picker cards, 0–64 |
| `overlay_aspect`       | float | `1.5`      | The overview's width over its height, 0.5–2 |
| `overlay_animation`    | enum  | `scale`    | Entrance effect, played in reverse to close |
| `overlay_animation_duration` | int | `130` | Entrance length in ms, 0–4000 |
| `overlay_animation_exit_ratio` | float | `0.8` | Exit length as a fraction of the entrance, 0–2 |
| `overlay_animation_curve` | enum | `ease_out` | Easing |

- The power menu, the window switcher and the prompts use `popup_radius` for their cards.
- The overview stays within 88% of the screen's height and 90% of its width, 720–1400 px wide; on a small screen it fits first and keeps its shape second.
- The settings panel opens 1.5× slower than the other overlays, scaled from your duration.
- `none` is the real off switch. The scrim only fades.
- The notification panel and clipboard history have their own animation keys and ignore these.

**`overlay_animation`**: `none`, `fade`, `scale` (grows slightly from centre; default), `zoom` (settles back from slightly larger), `rise` (from below), `drop` (from above), `unfold` (vertically from its middle), `flip` (hinged on its horizontal middle), `swing` (hinged on its vertical middle, like a door), `spin` (turns slightly as it scales). Every effect but `none` also fades.

**`overlay_animation_curve`**: `linear`, `ease_in`, `ease_out` (default), `ease_in_out`, `emphasized` (sharp start, soft landing), `overshoot` (past the target and back), `bounce`, `elastic` (springs and settles; give it a longer duration than 130 ms).

## Background

`[background]` is the desktop wallpaper: a list of images shown in order, changing every `interval_minutes` with an animated [transition](#wallpaper-transitions). Edit it under **Settings → Shell → Wallpaper**.

```toml
[background]
fit = "fill"
interval_minutes = 5
transition = "random"
transition_duration = 1500

[[background.entries]]
theme = true            # the active theme's wallpaper
shown = true

[[background.entries]]
path = "/home/user/wallpapers/dusk.jpg"
shown = true
```

| Key                   | Type   | Default  | Description                                              |
| --------------------- | ------ | -------- | -------------------------------------------------------- |
| `fit`                 | string | `"fill"` | `"fill"` (cover, cropping), `"contain"` (letterbox) or `"natural"` (no scaling) |
| `interval_minutes`    | int    | `5`      | Minutes between wallpapers (minimum 1)                   |
| `transition`          | string | `"fade"` | How one wallpaper replaces the next — see below          |
| `transition_duration` | int    | `1500`   | Length of the transition in ms, 0–10000; `0` is a cut    |

Each `[[background.entries]]` table is one wallpaper:

| Key     | Type    | Default | Description                                         |
| ------- | ------- | ------- | --------------------------------------------------- |
| `path`  | string  |         | Absolute path to an image                           |
| `theme` | boolean | `false` | Use the active theme's wallpaper instead of `path`  |
| `shown` | boolean | `true`  | Whether it is in the rotation                       |

- Entries rotate in file order. With one shown entry there is no rotation.
- Images only: JPEG, PNG, WebP, GIF, BMP. The settings page drops entries whose file is missing or not one of these.
- The wallpaper surface is created at start-up if `[background]` has entries or the [desktop grid](#desktop-icons) is on. Changing that needs a restart; everything else applies live.

### The theme's wallpaper

An entry with `theme = true` shows whatever wallpaper the active theme names (its `wallpaper` key), looked up when drawn. Switching theme then switches the wallpaper, and `config.toml` does not change. A theme with no wallpaper adds nothing to the rotation. The default config contains exactly this entry.

In Settings it is the **Theme default** tile, always first. It cannot be removed; deselecting it returns it to Available.

A theme's `wallpaper` is an absolute path, a `~/` path, or a name beside the theme file. A bare name not found there is looked up among the shell's installed wallpapers (`$PREFIX/share/moonswing` after `make install`, or the snap). The shipped themes use `wallpaper.jpg`, `wallpaper-forest.jpg`, `wallpaper-autumn.jpg`, `wallpaper-dracula.jpg`, `wallpaper-midnight.jpg`, `wallpaper-carbon.jpg` and `wallpaper-classic95.jpg`. Set your own theme's wallpaper in the theme file or with the **Theme wallpaper** row on the Theme page.

### Installed wallpapers

The Wallpaper page also lists the wallpapers your distribution installed: `backgrounds/` and `wallpapers/` under each `$XDG_DATA_DIRS` entry (Ubuntu, Fedora, KDE and others), plus `/usr/share/desktop-base` and `/usr/share/pixmaps/backgrounds`. A KDE package appears once, at its largest size. Picking one adds an ordinary entry. These tiles cannot be removed, only deselected; removal is for wallpapers you added.

### Wallpaper transitions

`transition` plays on every wallpaper change: the rotation advancing, a theme switch with the theme's wallpaper shown, or an edit to what is shown.

| Value            | Effect                                                               |
| ---------------- | -------------------------------------------------------------------- |
| `"fade"`         | Crossfade (default)                                                  |
| `"checkerboard"` | A chequered grid of squares wipes across                             |
| `"circle"`       | A circle opens from the centre                                       |
| `"flip"`         | The old wallpaper turns over like a card                             |
| `"slide"`        | The new wallpaper slides in from a random edge                       |
| `"wipe"`         | An edge sweeps across from a random side                             |
| `"blinds"`       | Horizontal slats open                                                |
| `"zoom"`         | The new wallpaper fades in while settling from slightly larger       |
| `"dissolve"`     | The new wallpaper arrives as scattered tiles                         |
| `"none"`         | Instant replacement                                                  |
| `"random"`       | A different effect each time (never `none`, never the same twice in a row) |

An unknown value reads as `"fade"`. The first wallpaper at start-up has no transition, and changing either transition key takes effect from the next change.

## Desktop Icons

`[desktop]` puts a grid of pinned applications, files and folders on the wallpaper. It is on by default.

- Double-click opens an item: an app launches, a file opens in its default application, a folder opens in your file manager.
- Click selects, drag moves, and dropping one icon on another swaps them.
- Right-click an icon: **Open**, **Open with…** (files and folders), **Rename**, **Remove from desktop**.
- Right-click bare desktop: **Add application…**, **Add file or folder…**, **Add widget…**, **Organize** (compact the icons), **Change background…**, **Desktop settings…**, **Settings…**. With the grid off, only **Change background…** and **Settings…**.
- **Add application…** searches names, generic names and keywords ("internet" finds your browser).

Also editable under **Settings → Shell → Desktop Grid**.

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

| Key           | Type    | Default | Description                                  |
| ------------- | ------- | ------- | -------------------------------------------- |
| `enabled`     | boolean | `true`  | Show the icon grid and widgets               |
| `cell_width`  | number  | `96`    | Cell width in logical pixels (minimum 32)    |
| `cell_height` | number  | `96`    | Cell height (minimum 32)                     |
| `spacing`     | number  | `12`    | Gap between cells (minimum 0)                |
| `padding`     | number  | `24`    | Inset from the screen edges inside the panels (minimum 0) |
| `icon_size`   | number  | `48`    | Icon size within a cell (minimum 8)          |
| `show_labels` | boolean | `true`  | Draw each icon's name                        |

The number of columns and rows is derived from each monitor's area left free by the panels. Every key applies live, except turning `enabled` on or off with no `[background]` entries, which needs a restart.

Each `[[desktop.items]]` table pins one item. The desktop menu and settings page write these for you.

| Key      | Type   | Default  | Description                                               |
| -------- | ------ | -------- | --------------------------------------------------------- |
| `target` | string |          | Absolute path (required). For an app, its `.desktop` file |
| `kind`   | string | inferred | `"app"`, `"file"` or `"folder"`; corrected from the disk if wrong |
| `label`  | string | derived  | Display name; omit for the app's name or the file's basename |
| `column` | int    | `0`      | Grid column from the left                                 |
| `row`    | int    | `0`      | Grid row from the top                                     |

- An item whose target no longer exists is dimmed, not removed.
- On a monitor too small for an item's cell, it is drawn in the nearest free cell; the stored position is kept.

## Desktop Widgets

Widgets are cards on the desktop grid that span several cells. Add one with **Add widget…** on the desktop's right-click menu. Drag a card to move it and a corner to resize it. Right-click a widget for its quick options (the weather unit, the news outlets), **Reset size**, **Remove widget**, and a link to its settings.

| `type`         | Shows                                                   | Min | Default | Max |
| -------------- | ------------------------------------------------------- | --- | ------- | --- |
| `media_player` | What is playing over MPRIS, with controls               | 2×1 | 3×2     | 6×4 |
| `weather`      | Current conditions and forecast over an animated sky    | 2×1 | 3×2     | 6×4 |
| `moon_phase`   | The Moon's phase, rise and set times                    | 2×1 | 3×2     | 6×4 |
| `fortune`      | A line from `fortune` (needs the `fortune-mod` package) | 2×1 | 3×2     | 6×4 |
| `tux`          | A penguin with something nice to say each day           | 1×1 | 1×1     | 4×3 |
| `analog_clock` | The time on a dial, hour and minute hands               | 1×1 | 2×2     | 4×4 |
| `stocks`       | Your stock watchlist                                    | 2×1 | 3×3     | 6×6 |
| `news`         | Latest headlines, newest first                          | 2×1 | 3×3     | 6×6 |

Spans are columns × rows.

```toml
[[desktop.widgets]]
type = "moon_phase"
id = "moon_phase"
column = 4
row = 0
column_span = 3
row_span = 2
```

| Key           | Type   | Default  | Description                                        |
| ------------- | ------ | -------- | -------------------------------------------------- |
| `type`        | string |          | A type from the table above (required)             |
| `id`          | string | the type | Unique name; a duplicate is renamed `<type>-2`, …  |
| `column`      | int    | `0`      | Column of the top-left cell                        |
| `row`         | int    | `0`      | Row of the top-left cell                           |
| `column_span` | int    | `1`      | Width in cells                                     |
| `row_span`    | int    | `1`      | Height in cells                                    |

- Spans are clamped to the type's limits when drawn; the file is not rewritten.
- An unknown `type` is drawn as a placeholder you can right-click and remove.
- A widget moved over icons pushes them aside. Dropping an icon on a widget, or a widget on another widget, is refused. **Organize** never moves widgets.

### The Moon phase widget

Needs no configuration. Rise and set times and the disc's orientation use the weather location (`[modules.weather] latitude` and `longitude`, or Settings → Shell → Modules → Weather). With none set, the weather's IP lookup is used. If that fails too, the card asks for a weather location in place of the times.

### The analog clock widget

No configuration and no second hand; it redraws once a minute. Larger cards add minute marks, then numerals. Colours come from the theme: `control_surface` for the dial, `foreground` for marks and hands, `accent` for the centre.

### The stock market widget

Shows the same watchlist as the [stocks bar module](#stock-market) (`[modules.stocks] symbols`), from the same poll. Each row has the ticker, price and today's move. Wider cards add the company name and the day's range. Click a row to open it on Yahoo Finance.

### The news widget

Headlines from all chosen feeds, newest first, with outlet and time. A story carried by two sources is shown once. Click a story to open it in your browser. The refresh button reads the feeds now. Feeds are only read while a news card is on the desktop. Choose outlets under **Settings → Shell → Desktop Grid → News widget**.

```toml
[news]
sources = ["ap", "reuters", "npr", "https://example.com/rss.xml"]
refresh_minutes = 15
```

| Key               | Type             | Default             | Description                                  |
| ----------------- | ---------------- | ------------------- | -------------------------------------------- |
| `sources`         | array of strings | `["ap", "reuters"]` | Short names below, or `http(s)://` RSS/Atom feed URLs |
| `refresh_minutes` | int              | `15`                | Minutes between reads, 5–1440                |

| Short name | Source                                    |
| ---------- | ----------------------------------------- |
| `ap`       | Associated Press (via Google News)        |
| `reuters`  | Reuters (via Google News)                 |
| `npr`      | NPR News                                  |
| `bbc`      | BBC News — World                          |
| `pbs`      | PBS NewsHour                              |

- Any other entry is ignored. An empty list shows no news, and the card offers to choose sources.
- AP and Reuters publish no RSS, so they are read through Google News; links go through Google's redirect.
- If a source fails, its last stories stay and the error is shown under them; click it to retry.

## Lock Screen

`[lock]` configures the lock screen, opened from **Lock** in the power menu (or by the power button with `[power] key_action = "lock"`). The compositor hides every other surface while locked and blanks any monitor without a lock surface.

```toml
[lock]
background = "/home/user/wallpapers/lock.jpg"
fit = "fill"
show_username = true
blur_sigma = 18.0
```

| Key             | Type    | Default           | Description                                              |
| --------------- | ------- | ----------------- | -------------------------------------------------------- |
| `background`    | string  | shipped wallpaper | Absolute path to an image or video                       |
| `fit`           | string  | `"fill"`          | Same values as [`[background]`](#background)             |
| `show_username` | boolean | `true`            | Show your name above the unlock button                   |
| `blur_sigma`    | number  | `18.0`            | Wallpaper blur while the password field shows, 0–100; `0` is none |

- One wallpaper, no rotation. Images as for `[background]`, plus MP4, MKV, WebM, MOV, AVI and M4V videos, which loop silently.
- If `background` is unset or missing, the shipped `lock-wallpaper.jpg` is used, then a plain dark fill.
- Press Unlock, Enter or any key to show the password field; a typed character goes into it. Escape once leaves the field, twice hides it.

**Requirements**

- `libgtk-session-lock0`. Without it Lock does nothing (the reason is only logged).
- A compositor with `ext-session-lock-v1` (Mir and Miracle have it).
- Passwords are checked with PAM. Run `sudo make install-pam` to install the `moonswing` service; without it the `login` service is used, so attempts are logged as `login`.

## Calendar

`[calendar]` configures the Calendar tab (click the clock): a month grid beside the local time and your world clocks. It shows events only once a Google or CalDAV account is signed in under Settings › Accounts and its calendars are switched on under Settings › Shell › Calendar.

```toml
[calendar]
week_start = "monday"

[[calendar.world_clocks]]
zone = "Europe/London"

[[calendar.world_clocks]]
zone = "Asia/Tokyo"
label = "HQ"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `week_start` | string | `"sunday"` | First day of the week: `"sunday"` or `"monday"` |

### Events on the calendar

- **Month**, **Week** and **Day** switch the view (shown only while events are). **+N more** in a day cell opens that day.
- Click an event for its details and buttons: **Join** (Meet, Zoom, Teams), **Open in Google Calendar**, and one per link in the description.
- A calendar that can't be read shows its reason and **Retry** above the grid; the others stay on screen.

### CalDAV calendars

Sign in to one or more CalDAV servers under Settings › Accounts (as for the [Todo](#todo) task list sync), then switch calendars on under Settings › Shell › Calendar.

```toml
[caldav]
calendars = ["https://dav.example.com/dav/calendars/me/personal/"]
show_in_calendar = true
refresh_minutes = 5
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `calendars` | array of strings | `[]` | Calendar URLs to show, as Settings writes them; one list for every server |
| `show_in_calendar` | bool | `true` | Show these calendars' events on the Calendar tab |
| `refresh_minutes` | int | `5` | Re-read interval while the tab is open (1–60); nothing is fetched while it is closed |

If the server doesn't expand recurring events, the shell handles simple daily, weekly, monthly and yearly rules; other rules show only the first occurrence.

### World Clocks

One row per `[[calendar.world_clocks]]` entry. The tab edits these for you: **+** adds, **✕** removes, drag to reorder.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `zone` | string | — | IANA time zone, e.g. `Europe/London`. Required; an entry without one is ignored |
| `label` | string | the zone's city | Row name |

An unknown zone shows "Unknown time zone" and can still be removed.

## Google Account

Sign in to one or more Google accounts under Settings › **Accounts** to show their events on the Calendar tab and, optionally, today's meetings on the todo board.

### Signing in

1. Press **Sign in with Google**. Google's consent page opens in your browser.
2. Google warns that the app is unverified. Choose **Advanced**, then **Go to Moonswing (unsafe)**.
3. Allow the one permission asked for: read-only access to your calendars (`calendar.readonly`).

- Nothing to set up: the shell uses Moonswing's own Google app. Data goes straight from Google to your machine ([privacy policy](https://miracle-wm-org.github.io/moonswing/privacy/)).
- Until the app is verified, Google caps it at 100 users; a sign-in error about the user cap means that limit is reached.
- **Add account** adds another account. **Sign out** revokes that account's grant at Google and deletes it.
- Sign-ins are stored in `~/.local/state/moonswing/google-account.json` (mode 0600), not `config.toml`.
- A sign-in from an earlier build's own OAuth client is dropped with a notice; sign in again.

### `[google]`

```toml
[google]
calendars = ["primary", "team@group.calendar.google.com"]
show_in_calendar = true
todo_sync = true
refresh_minutes = 5
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `calendars` | array of strings | `["primary"]` | Calendar ids to read; `primary` means every account's main calendar |
| `show_in_calendar` | bool | `true` | Show the events on the Calendar tab |
| `todo_sync` | bool | `false` | Put today's timed events on the todo board |
| `refresh_minutes` | int | `5` | Re-read interval while anything shows the events (1–60) |

One list covers every account; Settings › Shell › Calendar has a switch per calendar. Switching off one account's main calendar replaces `primary` with the other accounts' addresses.

### Meetings on the todo board

With `todo_sync = true`, each timed event today becomes a card with its time, its join link and a link to the event. The card moves itself: **Todo** before the meeting, **In Progress** during it, **Finished** after it.

- A card you move, edit or delete stays that way; the sync still updates a moved card's time and link.
- A meeting that leaves today's calendar (cancelled, declined, moved) sends its card to **Abandoned**.
- All-day events never become cards. A meeting on two accounts makes one card.

## Code Dashboard

The overview's **Code** tab lists what is waiting on you across GitHub and GitLab: review requests, your open pull and merge requests, issues assigned to you, your inbox, and what you merged recently. It reads the GitHub and GitLab accounts linked under Settings › **Accounts**, and only while the tab is showing.

```toml
[code]
review_stale_days = 2
stale_days = 7
issue_stale_days = 14
shipped_days = 7
refresh_minutes = 5
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `review_stale_days` | int | `2` | Days before a review request is stale (1–365) |
| `stale_days` | int | `7` | Days without activity before your own open change is stale (1–365) |
| `issue_stale_days` | int | `14` | Days without activity before an assigned issue is stale (1–365) |
| `shipped_days` | int | `7` | How far back **Shipped** reaches (1–90) |
| `refresh_minutes` | int | `5` | Re-read interval while the tab is showing (1–120) |

Settings › Shell › **Code Dashboard** edits these; the sliders button on the tab opens it.

### What the tab shows

- **Tiles** at the top count each list and the stale items; click one to filter, again to clear.
- **Review requests**, longest-waiting first; **Your changes**, those needing action (*Conflicts*, *Changes requested*, *Checks failing*) first; **Assigned issues**, stale first.
- **Inbox**: GitHub notifications and GitLab to-dos. The tick marks one read or done; the double tick marks all.
- **Shipped**: your merges within `shipped_days`.
- Rows open in your browser. With both forges linked, an account chip filters to one.
- Staleness counts from the last push, comment or review; the age turns amber at half the threshold.

### GitLab

GitLab (gitlab.com or a self-managed instance) is linked with a personal access token:

1. Under Settings › **Accounts**, enter the instance (default `gitlab.com`).
2. Press **Create a token**. Your instance's token page opens with the name *Moonswing* and the `read_api` scope filled in.
3. Pick an expiry, create the token, paste it in and press **Connect**. The shell checks the token before saving it.

- The instance, token and user name are stored in `~/.local/state/moonswing/gitlab-account` (mode 0600), never in `config.toml`.
- **Sign out** deletes that file; the key button beside it opens the token page, where you revoke the token.
- An expired or revoked token signs the account out, with the reason on the card.
- Marking to-dos done needs the `api` scope; with `read_api` the tab says so.

### Private GitHub repositories

The GitHub sign-in asks only for `notifications` by default, which leaves out private repositories. Add `repo` to `scopes` under `[modules.github]` and sign in again (see [GitHub](#github)).

## Notifications

`[notifications]` stores the notification bell's **silence** switch. The shell writes it when you use *Silence notifications* in the bell's right-click menu or the switch in the notification panel. It survives a restart.

```toml
[notifications]
silenced = false
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `silenced` | bool | `false` | Silence notifications |

While silenced, notifications still arrive and collect in the panel, but the bell doesn't shake, the chime doesn't play and the floating card doesn't appear. The bell shows a crossed-out icon. The chime itself is set under `[modules.notifications]`.

## On-Screen Indicator

`[osd]` configures the indicator shown above the bottom of every monitor when the volume, microphone volume or screen brightness changes, and the sound a volume change makes. The shell only watches these values; your existing key bindings still change them. Brightness needs a backlight under `/sys/class/backlight`.

```toml
[osd]
enabled = true
hide_delay_ms = 1500
margin = 96
volume_sound = "pop"
volume_sound_volume = 0.6
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Show the indicator (restart to apply) |
| `hide_delay_ms` | int | `1500` | How long it stays up after the last change, in ms (min 100; restart to apply) |
| `margin` | int | `96` | Distance from the bottom of the screen, in pixels (applies the next time it appears) |
| `volume_sound` | string | `"pop"` | Sound when the output volume changes or is unmuted |
| `volume_sound_volume` | float | `0.6` | Sound volume, 0–1 |

`volume_sound` accepts:

- a built-in sound: `pop`, `tick` or `blip`;
- a sound-theme name from your XDG `sounds/` directories, e.g. `audio-volume-change`;
- a path to an audio file (`~/` is expanded);
- `none`, `off` or `silent`.

The sound plays at the new level, even with `enabled = false`; muting is silent. Sound keys apply live, but if the indicator and the sound were both off at start-up, restart to turn either on. Settings › Shell › Volume & Sound previews the sound and reports one it can't find.

## Screen Sharing

`[screenshare]` configures the shell's xdg-desktop-portal ScreenCast backend. When an application asks to share your screen (a browser, a video call, OBS), the shell shows a picker with live previews of every monitor and window. Nothing is shared until you pick a source and press Share; Escape or a click outside denies the request. Frames go to the application as a PipeWire stream.

```toml
[screenshare]
enabled = true
preview_fps = 10
max_fps = 0
cursor = "app"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Serve ScreenCast; set `false` to leave it to another backend such as `xdg-desktop-portal-wlr` (restart to apply) |
| `preview_fps` | int | `10` | Frame rate of the picker's previews (1–60) |
| `max_fps` | int | `0` | Cap on the shared stream's frame rate; `0` follows the monitor's refresh rate (restart to apply) |
| `cursor` | string | `"app"` | Pointer in the stream: `"app"`, `"always"` or `"never"`; see [The pointer](#the-pointer) |

### The pointer

Applications ask for the pointer to be hidden, painted into the frames, or sent as metadata for the application to draw itself. Chrome, Chromium and Electron apps always ask for metadata.

- `"app"` gives each application what it asked for.
- `"always"` paints the pointer into every frame. Use it for a recorder that hides the pointer and can't draw its own (for example Recordly; turn off its own pointer to avoid seeing two).
- `"never"` keeps the pointer out.

`cursor` is read each time sharing starts. Metadata needs compositor support (`ext-image-copy-capture-v1` cursor sessions, which miracle-wm has); without it those applications share with no pointer.

### Requirements

- A compositor with `ext-image-copy-capture-v1` (miracle-wm built against MirAL 5.6 or newer). Without it the feature turns itself off and logs why.
- PipeWire 1.0 or newer.
- The portal files. `make install` (or `make install-portal`) writes:
  - `~/.local/share/xdg-desktop-portal/portals/moonswing.portal`
  - `~/.config/xdg-desktop-portal/mir-portals.conf`, only if it doesn't exist; otherwise it prints the lines to add

  Then run `systemctl --user restart xdg-desktop-portal` once.
- **The snap does this for you**, system-wide on install and per user on first run, and restarts xdg-desktop-portal. `snap remove` removes them but leaves the per-user `*-portals.conf`. With `enabled = false` the snap registers nothing.

Existing files are never edited. If one of your `~/.config/xdg-desktop-portal/*-portals.conf` sends ScreenCast elsewhere, it wins; the snap logs which file. To use the shell, set:

```ini
[preferred]
org.freedesktop.impl.portal.ScreenCast=moonswing
```

The shell must be running for screen sharing to work; sharing never starts it.

## Input Capture

`[input_capture]` configures the shell's xdg-desktop-portal InputCapture backend. It lets keyboard-and-mouse sharing apps such as [DeskFlow](https://github.com/deskflow/deskflow) or Input Leap share this computer's keyboard and mouse with other computers. The first time an application asks, the shell names it and waits for **Allow**; Deny, Escape or a click outside refuses.

Once allowed, the application sets barriers on your screen edges. Push the pointer through one and your input goes to the application until it hands it back.

**Super+Shift+Escape always takes your keyboard and mouse back** and stops that application capturing until it asks again.

```toml
[input_capture]
enabled = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Serve InputCapture (restart to apply) |

### Requirements

- **libeis** (`libeis1` on Debian and Ubuntu 24.04+; the snap includes it).
- A compositor with `wlr-layer-shell`, `relative-pointer` and `pointer-constraints`. The shell logs any that are missing.
- The same portal files as [Screen Sharing](#screen-sharing). If you keep your own `*-portals.conf`, add under `[preferred]`:

  ```ini
  org.freedesktop.impl.portal.InputCapture=moonswing
  ```

  The snap adds this line to confs it wrote itself, not to yours. `[screenshare] enabled = false` also stops the snap registering input capture.

### How it behaves

- While barriers are armed, a one-pixel strip along each armed edge takes clicks meant for what's under it.
- Barriers must be on outer screen edges; edges between two of your monitors are refused.
- Plugging or unplugging a monitor ends a capture, and the application must set its barriers again.
- Locking the screen ends a capture.

## Full Example

```toml
theme = "dracula"

[panels.top]
height = 32
padding_horizontal = 8
anchor = "top"
layer = "top"

[panels.top.layout]
left   = ["workspaces"]
center = ["clock"]
right  = ["screenshot", "sound_control", "brightness", "system_tray", "battery", "network", "weather", "system"]

[panels.bottom]
height = 32
padding_horizontal = 0
anchor = "bottom"
layer = "top"

[panels.bottom.layout]
left   = ["clipboard"]
center = ["dock"]
right  = ["media_player", "notifications", "launcher"]

[modules.weather]
unit = "celsius"
refresh_minutes = 30

[modules.battery]
poll_seconds = 30

[modules.clock]
show_date = true
show_seconds = false
hour_format = "12"
timer_sound = "ding"
timer_volume = 0.7

[modules.media_player]
max_text_width = 200.0

[modules.dock]
apps = ["firefox", "org.gnome.Nautilus", "org.gnome.Ptyxis"]
icon_size = 24

[shortcuts]
open_settings = "super+s"
open_launcher = "super+d"
screenshot_area = "print"
record_screen = "super+print"
open_emoji = ""                  # disabled

[power]
key_action = "menu"
inhibit_logind = true

[polkit]
enabled = true

[screenshare]
enabled = true
preview_fps = 10
max_fps = 0
cursor = "app"

[background]
fit = "fill"
interval_minutes = 15
transition = "fade"

[[background.entries]]
theme = true                     # the active theme's wallpaper
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

[lock]
show_username = true
```
