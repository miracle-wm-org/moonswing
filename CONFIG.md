# Moonswing Configuration

Moonswing is configured via a TOML file located at:

```
~/.config/moonswing/config.toml
```

If `$XDG_CONFIG_HOME` is set, the config file is read from `$XDG_CONFIG_HOME/moonswing/config.toml` instead.

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
- `"scratchpad"` - Shows or hides the window manager's scratchpad (requires Miracle WM)
- `"todo"` - The todo board, with a count of what is due today

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
timer_sound = "ding"
timer_volume = 0.7
```

| Key            | Type   | Default  | Description                                           |
| -------------- | ------ | -------- | ----------------------------------------------------- |
| `show_date`    | bool   | `true`   | Whether to show the date alongside time               |
| `timer_sound`  | string | `"ding"` | What rings when a countdown reaches zero — see below. |
| `timer_volume` | float  | `0.7`    | How loud it rings, from 0 to 1. Clamped.              |

#### When a timer is up

The shell's timers live behind the clock: the readout appears beside the time
while one runs, the popup under it pauses and stops them, and the calendar
overlay's **Timers & stopwatches** section is where one is started. So the keys
that decide what a finished countdown sounds like are `[modules.clock]` keys.

A countdown reaching zero does two things, and it does both every time:

1. **It rings.** `timer_sound` is the alarm, and it is what reaches somebody who
   has walked away from the screen — which is most of the point of setting a
   timer.
2. **It posts a notification.** *Timer finished*, with the length that ran out,
   and no timeout on it: it stays on the notification panel until you dismiss
   it. A sound that has already played tells somebody who missed it nothing, so
   the notification is what is still there when they come back.

The notification deliberately does **not** also play the [notification
chime](#notifications), whatever that is set to — the timer has already made its
own noise, and answering one event with two sounds a frame apart is not an
announcement, it is a collision. Setting `timer_sound = "none"` means a finished
timer is silent and notified, not silent and chimed.

`timer_sound` takes four kinds of answer, tried in this order:

- **One of the shipped alarms** — `ding`, `ding-dong`, `alarm` or `gong`. These
  are not files: the shell synthesises them from a handful of numbers and writes
  the result into `~/.cache/moonswing/sounds/` the first time one is
  wanted, which is what lets them work identically under `flutter run`, a `make
  install` and the snap. It is also what makes them shippable — a recorded
  kitchen timer is somebody's sample and somebody's licence, and these are
  arithmetic under this project's own GPL-3.0. `ding` is the default, one clear
  strike left to ring; `ding-dong` is two notes falling, like a doorbell;
  `alarm` is two bursts of three quick tones for somebody in the next room; and
  `gong` is one low strike with a long tail.
- **`none`** (or `off`, or `silent`) — a finished timer notifies without a
  sound.
- **A path** — anything with a `/` in it, `~` included. Any format mpv can open.
- **A name from the system's sound theme** — anything else, looked for under the
  XDG sound directories exactly as [the notification chime](#notifications) is.
  `timer_sound = "complete"` finds
  `/usr/share/sounds/freedesktop/stereo/complete.oga`.

A name that resolves to nothing is *not* silence: the calendar overlay's timers
section says so and names what it could not find. The notification arrives
either way, which is why it needs saying.

Several countdowns set to the same minute ring **once**, not once each — the
alarm is longer than a chime and three of them over each other is a noise. Each
one still posts its own notification, so nothing about *which* timers finished
is lost.

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
show_policy_toggle = true
```

| Key                  | Type | Default | Description                                                           |
| -------------------- | ---- | ------- | --------------------------------------------------------------------- |
| `show_app_icons`     | bool | `true`  | Show the icons of the applications open on each workspace             |
| `icon_size`          | int  | `14`    | Icon size in pixels (8–64)                                            |
| `max_icons`          | int  | `4`     | Icons one workspace shows before the rest collapse into a `+N` (1–16) |
| `show_policy_toggle` | bool | `true`  | Put the tiling/floating switch in a workspace's right-click menu      |

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

**Right-clicking a workspace button opens a menu** for that workspace — not the
focused one, whichever button was clicked. It has two things on it.

With `show_policy_toggle` on, the first two rows are the workspace's window
placement: *Tile new windows* and *Float new windows*, with the one it is
currently in marked. Choosing the other sends Miracle
`workspace <n> policy tile|float`, which changes where the *next* window opens —
whatever is already on the workspace stays where it is. Like the urgency flash it
costs no extra round-trip: Miracle reports the policy on the `GET_WORKSPACES`
entry the button is already built from, so the menu opens already knowing which
row to mark. A Miracle too old to know the command answers with a parse error,
and the mark visibly stays where it was rather than reporting a policy nothing
took.

*Move to output…* is the second page of the same menu, and lists every other
display Miracle reports — by connector name, with the make and model beside it
where Miracle knows them. On a single-monitor session the row is greyed rather
than hidden. Miracle's own `move workspace to output` acts on the *focused*
workspace and takes no selector, so moving one that is not focused focuses it,
moves it and puts the focus back where it was; every hop carries
`--no-auto-back-and-forth`, or a compositor with that option set would read the
hop back as "go back" and land somewhere else. The list of displays is read once
per connection and refreshed on Miracle's `output` event — never on a timer — so
the menu answers out of memory rather than on a round-trip.

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

### GitHub

The GitHub mark, the number of unread notifications beside it, and the inbox
behind a click: what is waiting for you across every repository you watch, with
the reason each thread arrived. Clicking one opens it in your browser and marks
it read, the way clicking it on github.com does; the tick beside a row marks it
read without opening it, and the double tick in the header marks the whole list.

```toml
[modules.github]
refresh_seconds = 60
show_count = true
participating_only = false
include_read = false
mark_read_on_open = true
```

| Key                  | Type   | Default | Description                                                                                        |
| -------------------- | ------ | ------- | -------------------------------------------------------------------------------------------------- |
| `refresh_seconds`    | int    | `60`    | How often the list is re-read (60–3600). GitHub enforces a floor of a minute and may ask for longer |
| `show_count`         | bool   | `true`  | Show the unread count beside the mark                                                               |
| `participating_only` | bool   | `false` | Only threads you are mentioned in, assigned to or asked to review                                   |
| `include_read`       | bool   | `false` | Keep threads in the list after they are marked read                                                 |
| `mark_read_on_open`  | bool   | `true`  | Mark a notification read as it opens                                                                |
| `client_id`          | string | the GitHub CLI's | The OAuth app the sign-in runs against — see below                                        |
| `scopes`             | string | `"notifications"` | What the sign-in asks for — see below                                                     |

**This module is in the default bottom panel, but adding it to an existing
config is manual** — the default config file is only written when none exists.
Add `"github"` to a panel's layout:

```toml
[panels.bottom.layout]
left = ["github"]
```

#### Signing in

The first click offers a **Sign in with GitHub** button. Pressing it starts the
same *device flow* `gh auth login` uses: the shell asks GitHub for an eight
character code, shows it, and opens github.com/login/device in your browser. You
type the code in there, authorise the app, and the shell takes it from there —
your password is never typed into the shell and never reaches it.

The access token is written to `~/.local/state/moonswing/github-token`
(mode 0600, in a directory created 0700), not into `config.toml`. **Sign out** in
the popup's header deletes it. That signs this machine out; it does not revoke
the authorisation, which is done from
[Settings › Applications](https://github.com/settings/applications) on github.com.

The consent screen says **GitHub CLI**, because `client_id` defaults to that
tool's public client id — a client id is public by construction, and borrowing
one is what lets this work without every user registering an app. To use your
own instead, register an OAuth app (Developer settings › OAuth Apps) with
*Enable Device Flow* ticked, and name it:

```toml
[modules.github]
client_id = "Iv1.0123456789abcdef"
```

`scopes` is what that sign-in asks for. The default, `notifications`, is read
access to the notification list plus the two calls that mark a thread read —
nothing else, not the contents of a single repository. Notifications from
**private** repositories are not included in that; listing them needs `repo`,
which is full read/write access to every repository you can reach:

```toml
[modules.github]
scopes = "notifications repo"
```

Change either key and the saved token no longer matches what is being asked for:
sign out and in again.

#### How current the list is

There is no push channel for notifications — GitHub's API is polled — so the
module polls it the way the API asks to be polled. Each request carries the
previous response's validator, so an unchanged list comes back as a 304 that
costs no rate-limit quota, and GitHub's own `X-Poll-Interval` is honoured
whenever it asks for longer than `refresh_seconds`. Nothing is polled at all
while no panel carries the module: one poll for the machine, however many bars
draw the mark.

Copying the sign-in code needs `wl-copy` (the `wl-clipboard` package), as the
emoji picker does; without it the code can still be typed out by hand, and the
card says so.

### Notifications

A bell that shakes and shows a count when a notification arrives, and opens the
notification panel on click — a full-height surface that sweeps in from the right
edge over everything else on screen, and back out the same way when dismissed,
listing what has arrived with each notification's actions, a **mark everything
read** button and a **Clear all**. The shell is the desktop's notification
daemon, so this is where notifications from every application land.

```toml
[modules.notifications]
sound = "chime"
sound_volume = 0.7
```

| Key            | Type   | Default   | What it does                                        |
| -------------- | ------ | --------- | --------------------------------------------------- |
| `sound`        | string | `"chime"` | What plays when a notification arrives — see below. |
| `sound_volume` | float  | `0.7`     | How loud it plays, from 0 to 1. Clamped.            |

`sound` takes four kinds of answer, tried in this order:

- **One of the shipped sounds** — `chime`, `ping`, `glass`, `bell` or `knock`.
  These are not files: the shell synthesises them from a handful of numbers and
  writes the result into `~/.cache/moonswing/sounds/` the first time one is
  wanted, which is what lets them work identically under `flutter run`, a `make
  install` and the snap. `chime` is the default.
- **`none`** (or `off`, or `silent`) — notifications arrive without a sound.
- **A path** — anything with a `/` in it, `~` included. Any format mpv can open.
- **A name from the system's sound theme** — anything else. Looked for under the
  XDG sound directories (`~/.local/share/sounds`, `/usr/share/sounds`, and
  whatever `XDG_DATA_DIRS` names), both directly and in the
  `<theme>/<profile>/` layout the `sound-theme-freedesktop` package installs.
  `sound = "message"` finds `/usr/share/sounds/freedesktop/stereo/message.oga`.

A name that resolves to nothing is *not* silence: the notification panel's
**Notification sound** row says so, names the key, and previews whatever is
configured when you click it.

Two things the chime deliberately does not do. It does not play while
notifications are silenced — silencing is about interruption, and a sound is the
most interrupting thing the shell does. And a burst of notifications arriving
together plays once rather than once each, which is why the count on the bell is
what says how many there were.

**The chime belongs to this module**, so it plays only while a `notifications`
module is in one of your panels. With the module in no panel there is nothing
holding it open, and the panel's sound row says that too.

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

#### Read, and dismissed

The panel's two clearing buttons are not the same act. The **✓✓** button marks
everything read: nothing is removed, the messages stay on the list to be read
again, and what stops is the shell *asking* — the bell's count, the floating
card in the corner of every output, and the chime. **Clear all** empties the
list.

Opening the panel does not mark anything read. Reading a notification is
something you do, not something a window being mapped does for you.

### Sound Control

No configurable settings.

### System Monitor

Drives both the panel module (CPU, memory, and temperature, with a popup) and the **System** tab in the overlay, which adds usage graphs, swap, load average, network throughput, disk usage, and a sortable process table you can kill from. The two share one sampler, so these settings apply to both.

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

| Key                   | Type   | Default     | Description                                                                                              |
| --------------------- | ------ | ----------- | -------------------------------------------------------------------------------------------------------- |
| `poll_seconds`        | int    | `1`         | How often stats are re-read (1–60)                                                                        |
| `temp_unit`           | string | `"celsius"` | `"celsius"` or `"fahrenheit"`                                                                             |
| `history_samples`     | int    | `120`       | How many samples the graphs keep (10–600). At the default cadence, 120 is two minutes                     |
| `cpu_percent_mode`    | string | `"machine"` | `"machine"`: 0–100% of the whole machine, so the process rows sum to the total. `"core"`: `top`-style, where 100% is one saturated core |
| `show_kernel_threads` | bool   | `false`     | Show kernel threads in the process table                                                                  |
| `confirm_kill`        | bool   | `true`      | Ask before quitting a process. A *force* quit always confirms regardless                                  |
| `kill_grace_seconds`  | int    | `5`         | How long a process gets to honour the request to quit before the row offers to force it (1–60)            |
| `disk_poll_seconds`   | int    | `30`        | How often filesystem usage is re-read (5–600). Separate because it shells out to `df`                     |

Nothing is read until something needs it: the shell only samples `/proc` while the panel module is on a panel or the System tab is open, and the per-process scan runs only while that tab is actually the visible one.

Two processes can never be killed from here, whatever the config says: the shell itself, and `init`.

### Screenshot

The camera in the bar: click it, choose an area, a window or a screen, and the
PNG is on the disk and on the clipboard. The same settings apply to the
`screenshot_area` shortcut, which takes the shot without the module being in any
panel.

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

| Key                 | Type   | Default                  | What it does                                                             |
| ------------------- | ------ | ------------------------ | ------------------------------------------------------------------------ |
| `directory`         | string | `~/Pictures/Screenshots` | Where the PNG is written. `~` and `$HOME` are expanded.                  |
| `filename_prefix`   | string | `"Screenshot"`           | What each file is named before the date and time.                        |
| `copy_to_clipboard` | bool   | `true`                   | Also put the shot on the clipboard, via `wl-copy`.                       |
| `delay_seconds`     | int    | `0`                      | A pause before the shutter, for getting a menu on screen first (0–60).   |
| `show_cursor`       | bool   | `false`                  | Paint the pointer into the frame.                                        |
| `shutter_sound`     | string | `"shutter"`              | What plays once the file has been written — see below.                   |
| `shutter_volume`    | float  | `0.6`                    | How loud it plays, from 0 to 1. Clamped.                                 |

#### The shutter

The sound plays when the screenshot has been **saved**, not when you choose what
to capture — so it follows `delay_seconds`, and it is the thing that tells you
the file exists. A capture that failed makes no sound, because nothing was
photographed.

`shutter_sound` takes four kinds of answer, tried in this order:

- **One of the shipped shutters** — `shutter`, `snap`, `clack` or `tick`. These
  are not files: the shell synthesises them from a handful of numbers and writes
  the result into `~/.cache/moonswing/sounds/` the first time one is
  wanted, which is what lets them work identically under `flutter run`, a `make
  install` and the snap. It is also what makes them shippable — a camera click
  recording is almost always somebody's licensed sample, and these are
  arithmetic under this project's own GPL-3.0, with no third party in them.
  `shutter` is the default: a reflex camera, mirror up and mirror down. `snap`
  is one bright click, `clack` a heavier mechanism with the body ringing under
  it, and `tick` a small dry tick for somebody who wants the confirmation
  without the theatre.
- **`none`** (or `off`, or `silent`) — screenshots are saved without a sound.
- **A path** — anything with a `/` in it, `~` included. Any format mpv can open.
- **A name from the system's sound theme** — anything else, looked for under the
  XDG sound directories exactly as [the notification chime](#notifications) is.
  `shutter_sound = "camera-shutter"` finds
  `/usr/share/sounds/freedesktop/stereo/camera-shutter.oga`.

A name that resolves to nothing is *not* silence: the screenshot menu says so
and names what it could not find. The file is written either way, which is why
it needs saying — a shutter that has quietly stopped working looks exactly like
one you turned off.

There is deliberately no shutter for a **recording**. A recording announces
itself by the readout in the bar for as long as it runs, and a camera click at
the end of one would be describing a photograph nobody took.

### Scratchpad

The note in the bar is the window manager's scratchpad: a place to stash a
window off every workspace and call it back over whatever you are doing. A
click shows what is on the scratchpad, centred on the screen you are on, or
hides it again. Hovering it names the two [shortcuts](#shortcuts) that go with
it — `toggle_scratchpad`, which does what the click does, and
`move_to_scratchpad`, which stashes the window you are in. That half has no
button, because clicking the bar is not the window you meant to stash.

The module has no settings of its own. It shows no count of what is stashed,
because the window manager does not report one: a stashed window is taken out
of its window tree altogether. Every stashed window is shown and hidden together.

If the shell cannot reach the window manager, the icon dims and its label says
why; the next click tries again.

### Todo

The checklist icon opens the todo board on the screen whose bar you clicked. It
is a board of five columns — **Inbox**, **Todo**, **In Progress**, **Finished**
and **Abandoned** — and a card is moved between them by dragging it. The **+**
at the top of a column adds a card there; clicking a card opens it to edit its
title, details, column, due date and repetition, and to read its history. Every
time a card changes column, the date and time is recorded in that history.

When the shell starts, and again at each midnight, it posts one notification
listing what is due that day, followed by anything still open from an earlier
day. The number beside the icon counts the same things. Finished and abandoned
cards are never counted.

A card can **repeat** every so many days, weeks or months, starting on a day you
choose. On each scheduled day a copy of it is added to the top of **Todo**, due
that day, and the repetition moves to the copy — so the newest copy is the one
to edit or delete to change or stop it. A monthly card started on the 31st
lands on the last day of shorter months and goes back to the 31st after them.
If the shell was not running on a scheduled day, one copy is made when it next
starts, for the most recent day missed.

The search field at the top of the board filters every column down to the
cards that match, and highlights what matched. It looks for any piece of text —
the middle of a word counts, and case does not — in a card's title and details;
with several words, a card has to contain all of them. **Ctrl+F** returns to the
field, and **Escape** clears it before it closes the board.

The board is kept in an SQLite database, `~/.local/share/moonswing/notes.db`
(or under `$XDG_DATA_HOME`), not in `config.toml`, and saved as you go. It needs
the SQLite library, which nearly every system already has (`libsqlite3-0` on
Debian and Ubuntu, `sqlite-libs` on Fedora). A board saved by an older version
of the shell as `todo.json` is imported the first time, and the file is renamed
to `todo.json.imported` rather than deleted. If the board cannot be read, it
says why and refuses to save anything over it until it can. The module has no
settings of its own.

## Shortcuts

The `[shortcuts]` section binds the shell's global keyboard shortcuts. These are registered with the compositor (Mir's `ext-input-trigger` protocols), so they fire no matter which window has focus.

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

| Key                    | Type   | Default              | Description                                    |
| ---------------------- | ------ | -------------------- | ---------------------------------------------- |
| `open_settings`        | string | `"super+s"`          | Opens (and closes) the settings overlay        |
| `open_launcher`        | string | `"super+d"`          | Opens (and closes) the application launcher    |
| `open_emoji`           | string | `"ctrl+shift+e"`     | Opens (and closes) the [emoji picker](#emoji-picker) |
| `open_notifications`   | string | `"super+n"`          | Opens (and closes) the [notification panel](#notifications) |
| `open_power_menu`      | string | `"shift+super+e"`    | Opens (and closes) the [power menu](#power-button) — shut down, restart, suspend, lock or log out |
| `switch_windows`       | string | `"alt+tab"`          | Opens the [window switcher](#the-window-switcher) and moves forward through it |
| `switch_windows_back`  | string | `"alt+shift+tab"`    | The same switcher, moving backwards |
| `screenshot_area`      | string | `"print"`            | Drag out an area and screenshot it — the screenshot module's own **Select an area** |
| `record_screen`        | string | `"super+print"`      | Starts recording the screen you are on; press it again to stop |
| `toggle_scratchpad`    | string | `"super+z"`          | Shows what is on the window manager's [scratchpad](#scratchpad), or hides it — the scratchpad module's own click |
| `move_to_scratchpad`   | string | `"shift+super+z"`    | Moves the focused window to the scratchpad |
| `power_button`         | string | `"poweroff"`         | The machine's own power button — what it *does* is [`[power]`](#power-button) |

`record_screen` records the whole of the output holding the focused workspace, and needs no aim: nothing is put on screen first, so the recording opens on the desktop as it already is. On a shell that is not connected to the window manager — and so cannot tell which screen that is — it falls back to asking you to click the screen to record, which is what the recorder module's own **Select a screen** does.

### The window switcher

`switch_windows` is the only shortcut here that is *held* rather than pressed. The first press puts an overlay on every screen showing an icon for each open window, five to a row; each further press of Tab moves the highlight, and letting go of Alt switches to whatever it is on. The full title of the highlighted window is written under the grid, which is what tells two windows of the same application apart. Escape, or a click on the backdrop, closes it without switching; a click on an icon switches to that window.

The list is ordered most-recently-used first, so the very first press lands on the window you were in before this one — tap and release to go back and forth between two windows. That ordering comes from the window manager, so a shell that is not connected to it offers the compositor's own order instead; everything else works the same.

Rebinding is the usual thing with one constraint: **keep a modifier in it**. What ends the gesture is the modifier coming back up, so a binding with none — `switch_windows = "f13"` — would leave the switcher on screen with nothing to release. Both keys are read independently, so you can bind them to different modifiers, or set either to `""` to turn that direction off.

If the window that is picked is on another workspace, the shell switches to that workspace first and focuses the window second. Both go to the window manager as one request, so nothing can land in between.

**Changing these requires restarting the shell.** Shortcuts are registered once at start-up; unlike the theme or panel layout they do not reload live.

### Changing one without editing the file

The keyboard icon on the bar opens the shortcut sheet, and every one of the above is listed on it under **Shell**, alongside every binding the window manager has configured. Click one and press the combination you want:

- **Esc** stops listening and changes nothing;
- **Backspace** clears the shortcut, the same as writing `""` below;
- the arrow beside a row you have changed puts it back on its default.

Only the shell's own shortcuts can be changed from there. The window manager's bindings are on the same sheet but read-only — they are miracle's configuration, and they are edited under **Settings › Window Manager › Key Bindings**.

What you press is written back into `config.toml` as the text you would have typed yourself, so the file stays readable and hand-editable. Two things the sheet says that the file cannot: it refuses a combination another of the shell's own shortcuts is already on (the second registration would silently never happen), and it warns — without refusing — when the window manager already uses that combination for something. And because registration latches at start-up, an edited row says so until the shell is restarted.

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

## Emoji Picker

`Ctrl+Shift+E` opens a centred picker over whatever is on screen. Type to search, move with the arrow keys, and press **Enter** to copy the highlighted emoji and close. **Escape** — or a click on the backdrop — leaves without copying.

The search is fuzzy and runs across every dimension an emoji has, so all four of these find 🍕:

```
pizza      →  its name
food       →  its category
italian    →  one of its keywords
🍕          →  the character itself
```

Fuzzy means the letters need only appear *in order*: `gfws` finds "grinning face with sweat", `thmbs` finds "thumbs up". Spaces are ordinary characters here — the copy key is Enter, not Space — so a query may be several words, and those words need only appear in order too: `face joy` finds "face with tears of joy".

A literal match always beats a scattered one, and the dimensions are weighted: the name first, then the keywords, then the category. So typing `cat` puts the cat face above the emoji merely filed under a *category*.

Copying goes through `wl-copy`, from the **wl-clipboard** package. Wayland has no clipboard a client can write to without a seat, and the shell's surfaces are layer-shell ones, so there is no in-process route; if `wl-copy` is missing the picker says so in a notification rather than failing quietly.

Rebind or disable it under [`[shortcuts]`](#shortcuts):

```toml
[shortcuts]
open_emoji = "super+period"
```

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

`key_action` is about the *physical* key alone. The panel's power icon and the [`open_power_menu`](#shortcuts) shortcut (`Super+Shift+E`) always open the power menu, whatever this is set to — including `"none"`, which leaves the key to logind without leaving you with no way to shut down from the shell.

### Why `inhibit_logind` exists

systemd-logind watches the power button directly, and `HandlePowerKey` in `logind.conf` is `poweroff` on a stock system. It does not care that a compositor also delivered the key to the shell — so a shell that only listened would draw its power menu onto a machine that was already going down.

While the shell is handling the key it therefore takes logind's `handle-power-key` inhibitor lock, in `block` mode, which stops logind acting on presses for as long as the shell holds it. The lock is released the moment the shell exits — including if it crashes — so it can never leave a machine that will not power off.

Two things it deliberately does **not** claim: `handle-power-key-long-press` (holding the button down keeps doing whatever logind is configured to do, which is the "get me out of here" gesture), and the key on a compositor that never delivered it. The shell takes the lock only once the compositor has confirmed the shortcut registration, so on a compositor without Mir's `ext-input-trigger` protocols — or where another client already owns the key — the button keeps working exactly as it did before.

Turn `inhibit_logind` off if your `logind.conf` already says `HandlePowerKey=ignore`; otherwise, with it off, logind's shutdown and the shell's dialog race.

### If the button does nothing

- Check that the compositor is delivering it: the shell logs `input-trigger: "moonswing.power-button" owned` on start-up when it has the key, and says so when another client owns it instead.
- Some keyboards' power keys emit a keysym this table's `poweroff` does not match. Bind the physical key instead, which is layout- and keysym-independent:

  ```toml
  [shortcuts]
  power_button = "code:116"   # evdev KEY_POWER
  ```

- A laptop lid or a "sleep" key is a different key entirely (`sleep`, `code:142`); this section is only about the power button.

## Authentication Prompts

The `[polkit]` section decides whether the shell answers polkit's authentication requests — the "Authentication required" dialog you get when something asks for administrator rights.

```toml
[polkit]
enabled = true
max_attempts = 3
```

| Key            | Type    | Default | Description                                                    |
| -------------- | ------- | ------- | -------------------------------------------------------------- |
| `enabled`      | boolean | `true`  | Register as this session's polkit authentication agent          |
| `max_attempts` | integer | `3`     | How many times the password may be refused before the dialog gives up (clamped to 1–5) |

### What this is for

polkit never asks anybody anything by itself. When an application requests a privileged operation — changing the system keyboard layout, mounting a disk, installing an update — polkitd looks for an *authentication agent* registered for your session and asks it to get the password. With no agent registered there is nothing to ask, so every one of those requests is refused immediately, which usually surfaces as a setting that silently refuses to change.

Most desktops ship one (`polkit-gnome`, `mate-polkit`, `lxpolkit`). miracle-wm does not, which is why the shell is one.

The prompt is a dialog in the middle of the screen, in your theme: what is being asked, which account is answering, and a field for the password. Escape, a click outside it, or Cancel all *refuse* the request — dismissing is denying, not deferring.

### Turning it off

The shell yields automatically if it finds an agent already registered when it starts: that session already has working prompts, and two agents fighting over the registration is how one of them silently stops prompting. `enabled = false` is for the other ordering — an agent that starts *after* the shell, which would otherwise find the registration taken.

With `enabled = false` and no other agent running, nothing on the desktop can ask for administrator rights.

### If prompts do not appear

- The shell logs `polkit: registered as the authentication agent for session <id>` on start-up, and says so when another agent has the registration instead.
- The password is checked by `polkit-agent-helper-1`, a small setuid program that ships with polkit itself. If it is missing the dialog says so rather than failing silently; install polkit (`polkitd` on Debian and Ubuntu, `polkit` on Fedora, Arch and openSUSE).
- Registration needs a logind session. If `echo $XDG_SESSION_ID` prints nothing and `loginctl` does not know about your session, polkit has nothing to register an agent *for*.

## Theme

Themes live in their own files, one per theme, under `~/.config/moonswing/themes/`. `config.toml` picks one by name — the file's basename without `.toml`:

```toml
theme = "dracula"
```

Five themes ship with the shell and are written into that directory the first time it starts:

| Name       | Looks like                                                        |
| ---------- | ----------------------------------------------------------------- |
| `glassy`   | Cool translucent surfaces that let the wallpaper through. The default. |
| `forest`   | Pine and moss over a near-black green, floating on a lit sage rim. |
| `dracula`  | The canonical [Dracula](https://draculatheme.com) palette.         |
| `midnight` | Indigo over deep water, one type size up, and lit: its cards glow rather than casting a shadow. |
| `carbon`   | Machined graphite. Flat, square, unlifted — and every bar menu grows out of the bar on a flared join. |

If `theme` is absent, names a theme that does not exist, or names a file that will not parse, the shell falls back to `glassy` rather than starting unstyled. A single bad value inside a theme file costs only that key.

The **Appearance** page in Settings → Shell is the easy way in: it lists every theme with a preview of its colors, switches on click with no restart, and offers **New theme…**. The five shipped themes are read-only there — editing one offers to duplicate it first.

Because the shell owns those five files, it rewrites any of them that differs from what it ships every time it starts, so a fix to a shipped palette reaches you on the next launch. Editing `dracula.toml` by hand will not stick; duplicate it and edit the copy. Your own theme files are never touched.

### Writing a theme file

A theme file is a flat table — no section header. Every key is optional.

```toml
# ~/.config/moonswing/themes/gruvbox.toml
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

popup_animation      = "slide"
popup_animation_duration = 140

overlay_animation    = "scale"
overlay_animation_duration = 160
overlay_animation_exit_ratio = 1.0
overlay_animation_curve = "ease_out"
```

Colors are hex strings in `#RRGGBB` (opaque) or `#AARRGGBB` (with alpha, where `AA` is the alpha channel). `"#33FFFFFF"` is white at ~20% opacity. Alpha is what makes a translucent theme translucent: panel and popup surfaces composite against the desktop behind them.

| Key                    | Default       | Description                                                                 |
| ---------------------- | ------------- | --------------------------------------------------------------------------- |
| `name`                 | the filename  | Display name shown in the settings picker                                   |
| `font`                 | `Ubuntu Sans` | Font family used for all text across panels and popups. Any fontconfig family name; the settings picker lists the ones installed (via `fc-list`), and falls back to a free-typed field where there is no fontconfig |
| `font_size`            | `13.0`        | Size of the shell's body text, in logical pixels, and with it the whole type scale — labels, captions and headings keep their proportions either side of it. Clamped to 6–32. See the note below |
| `blur`                 | `24.0`        | Blur applied behind the settings and launcher overlays (see the note below) |
| `accent`               | `#853953`     | Focused workspace button, slider fill, selection highlights, chart series (see the note below) |
| `foreground`           | `#F3F4F4`     | Primary text and icon color in the panels                                   |
| `surface_hover`        | `#853953`     | Button background when hovered                                              |
| `surface_pressed`      | `#612D53`     | Button background when pressed; the mid stop of the panel gradient          |
| `workspace_background` | `#2C2C2C`     | Unfocused workspace button; the dark end of the panel gradient              |
| `popup_background`     | `#2C2C2C`     | Background of popups, flyouts, menus, the OSD card and the overlay panel    |
| `popup_foreground`     | `#F3F4F4`     | Text and icons inside popups                                                |
| `control_surface`      | `#39393D`     | Cards, inputs and tiles inside popups and the settings pages                |
| `slider_track`         | `#612D53`     | The unfilled portion of sliders and usage bars                              |
| `muted`                | `#C4A8B2`     | Secondary, de-emphasised text: menu headers, timestamps, units, greyed rows |
| `divider`              | `#33F3F4F4`   | Separator lines, and the resting fill of subtle list rows (supports alpha)  |
| `notification_badge`   | `#F2B441`     | What an unread notification is announced in (see the note below)           |
| `notification_badge_foreground` | `#2C1218` | Text and glyphs drawn on `notification_badge`                           |
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
| `popup_animation`      | `slide`       | How a popup arrives, and — reversed — how it leaves (see below)             |
| `popup_animation_duration` | `140`     | How long that entrance runs, in milliseconds; the exit takes four fifths of it |
| `overlay_animation`    | `scale`       | How a full-screen overlay arrives, and — reversed — how it leaves (see below) |
| `overlay_animation_duration` | `160`   | How long *that* entrance runs, in milliseconds                             |
| `overlay_animation_exit_ratio` | `1.0` | What fraction of the entrance the overlay's exit takes                     |
| `overlay_animation_curve` | `ease_out` | The easing the overlay's animation is paced on                             |
| `scrim`                | `#882C2C2C`   | The wash drawn over the screen behind a full-screen overlay                 |

Note that `divider` is used both as a hairline *and* as a background fill for quiet rows, so it wants enough alpha to read as a surface.

**`accent` is a fill, and the shell derives its own reading colour from it.** The accent is picked to be *filled* — a primary button, the focused workspace, the travelled half of a slider — which means it has to be dark enough to carry white. A colour dark enough for that is rarely light enough to be read as a *label* on a dark card: the shell's own `#853953` holds white at 7.8:1 and then lands on its own popup at 1.8:1. So anything writing in the accent — a checked menu row, the current tab, today's date, a section heading in the settings pages — is drawn in the accent moved along its own lightness ramp until it clears 4.5:1 against `popup_background`, keeping its hue and saturation. There is no key for this and nothing to set: an accent that already reads as text is used exactly as written, and one that does not is lifted only as far as it has to be. Fills, rims and washes are never touched, so the colour you chose is still the colour that gets filled.


`notification_badge` is deliberately not `accent`. The accent is the bar's ordinary "this one is active" — it is on the focused workspace, on every hovered button and on half the controls in the settings panel — and the floating card that plants itself in the corner of every output would read as more of the same furniture wearing it. This is the one colour in the shell that is allowed to be louder than the rest of the palette, so every shipped theme spells it as a hue that theme does not otherwise use. It is worn by the floating card, the bell's unread count and the dot on an unread message, so those three cannot disagree about what "unread" looks like.

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

Two things to know before attaching a theme. A theme with a **translucent `popup_background`** should keep a gap: at zero the popup's fill and the bar's composite separately against the wallpaper, so the join shows a step in tone that nothing here can remove, and a flare only makes that step wider — which is why `glassy` sets `popup_gap = 8` to match its own `panel_margin` rather than attaching. And a bar with `panel_border_width` above zero draws its rim on the inner edge too — the edge the menus come out of. The compositor places a popup *below* the bar rather than over it, so the card cannot paint that hairline out; the **bar** leaves it out instead, across exactly the stretch the open menu covers. `carbon` is the shipped example: a 1px rim in the same colour and width as its popups', so the outline runs along the bar, breaks off where a menu is open, goes round the card and comes back.

Hover tooltips take the edge anchor but never attach: a label that comes and goes with the pointer reads as a floating card, not as part of the furniture. Menus anchored to the *pointer* — the desktop's context menu, the app-directory's category flyouts — have no panel edge to sit off and are unaffected by either key.

Sensible defaults are shipped rather than zero — `8.0` with a 1px rim — because that is the shape the shell's menus have always drawn. A theme that says nothing about popups gets that, including a theme file written before these keys existed.

The five `popup_shadow_*` keys are a CSS box-shadow, spelled out: a color, a blur radius, a spread, and an offset on each axis. There is one shadow per theme rather than the stack CSS allows.

**A shadow makes a popup's window bigger.** A popup is its own compositor surface, sized to its content, and a shadow paints *outside* the card — so the shell grows the surface by the shadow's reach (`blur + spread`, shifted by the offset, on each side independently) and then repositions the popup by that same amount, so the card lands exactly where it would have without one. Two consequences worth knowing: a click landing in the shadow's margin hits the popup rather than passing through to what is underneath, and a very large blur on a popup near a screen edge gives the compositor more to slide back on-screen. Setting `popup_shadow_color`'s alpha to `0` removes the margin along with the shadow, restoring the exact geometry of a shell with no shadow at all — which is what `carbon` does.

Nothing says the shadow has to read as one. Give it a colour off the palette rather than a black, leave both offsets at `0` so it is not displaced from the card, and take `popup_shadow_spread` above zero so the falloff starts outside the card's edge, and the same key paints a symmetrical bloom around the card instead of weight beneath it. That is `midnight`, and the geometry follows it: with no displacement the window grows by `blur + spread` on all four sides equally, and on a bar popup the joined side is still clamped to `popup_gap`, so the glow fills the gap between card and bar and stops at the panel.

A bar popup never paints its shadow over the bar: on the joined edge the margin is clamped to `popup_gap`, so at a small gap the shadow fills it and stops, and at `0` the surface is flush and the shadow is cut exactly at the join. A gap of `popup_shadow_blur + popup_shadow_spread` or more leaves the shadow untouched.

Popup *sizes* are not themable. Each module fixes its own width, and some of them fix it deliberately: the sound popup pins its width because a popup that resizes after it has been placed walks away from the button that opened it.

### About `popup_animation`

`popup_animation` is how a popup arrives. Whichever effect you pick is also how it leaves, played backwards — there is no second key for the exit, and there cannot be one: the way out is the way in reversed, always, which is what makes a card that unrolled out of the bar roll back into it rather than blinking away.

| Value    | What it does                                                              |
| -------- | ------------------------------------------------------------------------- |
| `none`   | No animation. The card is simply there, and simply gone                    |
| `fade`   | Opacity alone                                                             |
| `slide`  | A short travel out of the bar the popup belongs to, under a fade — the default |
| `scale`  | Grows into place from the card's own centre, under a fade                  |
| `grow`   | Unrolls out of the bar, growing from the edge the two share                |
| `flip`   | Swings open about that same edge, as though hinged there                   |
| `spin`   | Turns a few degrees as it scales into place, under a fade                  |

`slide`, `grow` and `flip` take their direction from the bar the popup was opened from, so a bottom bar's menus rise and a top bar's drop. A menu anchored to the *pointer* — the desktop's context menu, an app-directory category flyout — has no bar to travel out of and is treated as hanging below its anchor, which is where the compositor puts it.

`popup_animation_duration` is how long the entrance runs, in milliseconds, and it defaults to 140. The exit is four fifths of whatever you set: an entrance is paced to be followed, while a dismissal is you saying you are done with the card, and a fraction rather than a second key is what stops the two drifting into an exit longer than the entrance it reverses. It is clamped to 0–2000, and `none` is the off switch rather than a duration of `0` — at `none` nothing is wrapped and no animation controller is created at all, where `0` is the effect played instantly.

**The dock ignores this key.** Its hover labels and its unpin menu always open with `none`, whatever the theme says: the dock is a strip the pointer sweeps along, opening and abandoning a surface at every button on the way past, and a card that animated at each of them reads as the shell twitching rather than answering.

Themes written before this key existed get `slide`.

### About the overlay animation

The four `overlay_animation*` keys are `popup_animation`'s counterpart one layer up: how the **full-screen overlays** arrive. That is the settings panel, the launcher, the emoji picker, the power menu, the keybind cheat sheet, the authentication prompt and the screen-share picker — everything that dims the screen and puts a card in the middle of it. Until these keys existed they all did exactly one thing, at exactly one pace.

They are separate from the popup keys on purpose. A menu is furniture you are already reaching past, and an overlay is a surface you asked for; a theme that wants a snappy bar and a stately settings panel has to be able to say both.

**`overlay_animation`** is the shape:

| Value    | What it does                                                                 |
| -------- | ---------------------------------------------------------------------------- |
| `none`   | No animation. The overlay is simply there, and simply gone                    |
| `fade`   | Opacity alone — the scrim washes in and the card fades up in place            |
| `scale`  | The card grows a little into place from its own centre, under a fade — the default |
| `zoom`   | The card settles back to size from slightly larger, as though coming towards you |
| `rise`   | The card lifts into place from below, under a fade                           |
| `drop`   | The card comes down into place from above, under a fade                       |
| `unfold` | The card unfolds vertically from its own middle, keeping its width            |
| `flip`   | The card tilts open about its horizontal middle, as though hinged there       |
| `swing`  | The card swings open about its vertical middle, like a door                   |
| `spin`   | The card turns a few degrees as it scales into place, under a fade            |

Every value but `none` fades as well as moves, and that is not decoration: an overlay is a card centred on a scrim that covers the whole screen, so an effect that only moved would slide a solid card in over a wash that was already there.

**`overlay_animation_curve`** is the pacing, and the two multiply out — a `rise` on an `elastic` and a `flip` on a `linear` are both sentences these keys can say:

| Value         | What it does                                                          |
| ------------- | --------------------------------------------------------------------- |
| `linear`      | A constant rate, with no acceleration                                 |
| `ease_in`     | Starts slowly and accelerates into place                              |
| `ease_out`    | Starts quickly and settles — the shell's standard entrance, and the default |
| `ease_in_out` | Eased at both ends                                                    |
| `emphasized`  | A sharp departure and a soft landing, weighted towards the end        |
| `overshoot`   | Goes a little past where it is heading, then settles back             |
| `bounce`      | Lands, bounces, and lands again                                       |
| `elastic`     | Springs past and oscillates before settling                           |

The last three deliberately travel past the resting state and come back, which is the whole point of having them; the card's *opacity* is held inside its normal range while they do, so an overshoot is a movement rather than a flicker. `elastic` in particular wants a longer duration than the default — at 160 ms a spring reads as a stutter.

**`overlay_animation_duration`** is how long the entrance runs, in milliseconds, clamped to 0–4000. A wider ceiling than a popup's, for the same reason these are separate keys at all. `0` is the animation played instantly; `overlay_animation = "none"` is the off switch, and it is a real one — no animation controller is built, nothing is layered over the card, and the window is destroyed on the frame it is dismissed.

**`overlay_animation_exit_ratio`** is how the exit relates to the entrance, and it is the second timing knob rather than a second duration. The way out is always the way in reversed — the same shape, so a card that swung open swings shut — and this says only how long it takes: `0.75` leaves in three quarters of the time it arrived in, `1.0` (the default) takes exactly as long, and the ceiling of `2.0` is there because an overlay that dissolves more slowly than it appeared is a legitimate choice. Because it is a ratio, lengthening the entrance lengthens the exit with it; the two cannot drift apart. Read backwards, an `overshoot` entrance becomes an anticipation dip on the way out, which is the pair those curves are drawn to make.

Two notes on what is *not* animated. The **scrim never moves** — it is the size of your display, so anything transforming or layering it would cost a full-screen composite every frame, and it arrives by its own alpha instead. And the **settings panel arrives a half again more slowly** than the other overlays, as it always has, because it is a workspace rather than a card you are chasing: that is a proportion of whatever you set here, not a duration of its own, so it still moves when you move `overlay_animation_duration`.

The **notification panel keeps its own entrance**, and these keys do not reach it. It is a full-height surface butted against the screen edge rather than a card in the middle of one, so it slides out of that edge and is thrown back into it; a centre-pivoted scale there opens a transparent strip along the screen edge that reads as the panel having come loose.

Themes written before these keys existed get `scale` at 160 ms on `ease_out`, which is exactly what every overlay played before there was a choice.

### About `font_size`

`font_size` is the size of the shell's *body* text — the tier most of the shell is set in — and every other size follows it. A caption stays a caption and a heading stays a heading: the whole scale is multiplied through by `font_size / 13`, so `font_size = 16` makes everything about a quarter larger and `font_size = 10` makes everything smaller, in the panels and in every popup, menu, overlay and desktop widget they open. `13.0` is the shipped value, so a theme file that does not spell the key renders exactly as it always did; `midnight` is the one shipped theme that moves it, at `14.0`.

Two things it deliberately does not change. **Panel thickness** is `[panels.<name>] height` in `config.toml`, not a theme key — a bar left at its default height crops a much larger font, and the fix is to raise `height` alongside. **Icons** keep the size they are drawn at: a tray icon or a weather glyph is a picture, not type, and their sizes are `[modules.*]` options where they are configurable at all.

Sizes are in logical pixels and clamped to 6–32. The settings editor's **Font size** field is the same key, live: the shell re-lays itself as you type, with no restart.

### About `blur`

`blur` softens what sits behind the settings and launcher panels — that is, the `scrim` — and nothing else. It cannot frost the desktop: a shell surface is transparent and the compositor owns everything under it, and Mir exposes no blur protocol for a client to ask for one. A theme that wants to look like glass does it with alpha, as `glassy` does. Set `blur = 0` to skip the filter entirely.

### Migrating from an inline `[theme]` table

Older versions kept the palette in a `[theme]` table inside `config.toml`. That table is now ignored — `theme` is a name, not a table. To keep a palette you had customized, copy the contents of your old `[theme]` table into `~/.config/moonswing/themes/mine.toml` (dropping the `[theme]` header line), delete the table from `config.toml`, and set `theme = "mine"`. An un-migrated `[theme]` table is harmless: it costs you the theme, not the rest of your config.

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

Six types ship:

| `type` | Name | What it draws |
| ------ | ---- | ------------- |
| `media_player` | Media player | What is playing over MPRIS: art, title, transport, and a progress bar as the card grows |
| `weather` | Weather | The current conditions and a forecast strip, over a sky animated to match |
| `moon_phase` | Moon phase | Tonight's Moon drawn at its actual phase, with the times it rises and sets and what the phase means for tides, night light and eclipses |
| `fortune` | Fortune | A line from `fortune(6)` over a lamp, with a button that asks for another |
| `tux` | Tux | A penguin with something nice to say each day |
| `analog_clock` | Analog clock | The time on a dial, with an hour hand and a minute hand and no second hand |

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

### The analog clock widget

No configuration, and **no second hand** — deliberately. A hand that sweeps
seconds is a repaint every second, on every monitor, for as long as the card is
on screen; this one wakes when the minute changes and is idle in between, so a
clock on the desktop costs nothing to leave there. The hour hand still moves
continuously between the numerals, so half past six looks like half past six.

The face buys its detail from the size you give it: at one cell it draws the
twelve hour marks, at two it adds the sixty minute marks, and larger still it
sets the hour numerals inside them. It is drawn in your theme — the dial takes
`control_surface`, the marks and hands `foreground`, and the pivot `accent` —
so it changes with everything else when you change themes.

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

Unlike `[background]`, this is a single wallpaper rather than a rotating list — but it accepts the same image and video formats, and videos loop silently. If `background` is unset or the file is missing, the shipped default (`$PREFIX/share/moonswing/lock-wallpaper.jpg`) is used, falling back to a plain dark fill.

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

## Notifications

The `[notifications]` section holds the state of the notification bell's **silence** switch. The shell writes this key itself — right-click the bell, or use the switch at the top of the notification panel — so it is documented because the file is yours to edit, not because you have to.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `silenced` | boolean | `false` | Whether notifications are silenced. |

Silencing is about interruption, never about delivery. The shell keeps acting as the notification daemon and every notification still arrives and stacks up in the panel; what stops is the shell asking for your attention — the bell no longer shakes, the chime does not play, and the floating card that plants itself in the corner of every monitor does not appear. The bell wears a crossed-out glyph while the switch is on, so the state is never invisible.

The sound itself is configured in `[modules.notifications]`, not here: this key is a decision about the machine, and that one is an option of the module that plays it.

It is a file key rather than state that dies with the process on purpose: a shell that quietly started interrupting you again after a restart would be the one failure a "do not disturb" switch may not have.

```toml
[notifications]
silenced = false
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
[polkit]
enabled = true
max_attempts = 3

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
  - `~/.local/share/xdg-desktop-portal/portals/moonswing.portal`
  - `~/.config/xdg-desktop-portal/mir-portals.conf` (only written if absent, so an existing preference is never overwritten)

  then run `systemctl --user restart xdg-desktop-portal` once.

  **The snap does all of this for you.** Its install hook writes `/usr/share/xdg-desktop-portal/portals/moonswing.portal` and `/usr/share/xdg-desktop-portal/{miracle-wm,mir}-portals.conf`; the launcher writes the same pair under `~/.local/share` and `~/.config` on first run, and restarts xdg-desktop-portal itself. `snap remove` deletes both sets again. Nothing is manual.

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
timer_sound = "ding"
timer_volume = 0.7

[modules.media_player]
max_text_width = 200.0

[modules.dock]
apps = ["firefox", "org.gnome.Nautilus", "kitty"]
icon_size = 24

[shortcuts]
open_settings = "super+s"
open_launcher = "super+d"
open_notifications = "super+n"
screenshot_area = "print"
record_screen = "super+print"
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
