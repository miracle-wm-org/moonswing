# Configuration Overview

Graceful Shell is configured via a single [TOML](https://toml.io/) file.

## File Location

The config file is read from:

```
~/.config/graceful-shell/config.toml
```

If the `XDG_CONFIG_HOME` environment variable is set, the path is:

```
$XDG_CONFIG_HOME/graceful-shell/config.toml
```

## Creating or Editing the Config

On first launch with no config file, Graceful Shell writes a default `config.toml` and starts with the default layout. You can then edit that file to customize behavior.

To open the config in your editor:

```sh
$EDITOR ~/.config/graceful-shell/config.toml
```

Restart Graceful Shell after saving changes:

```sh
# If running as a systemd user service:
systemctl --user restart graceful-shell

# Or kill and relaunch manually:
pkill graceful-shell && graceful-shell &
```

## Fallback Behavior

- If the config file is **missing**, a default file is written automatically on startup.
- If the config file contains **parse errors**, all settings fall back to built-in defaults silently.
- All individual settings are optional — omitting any key uses its documented default.

## Config File Structure

A config file has four top-level sections:

```toml
[panels.<name>]          # One section per panel (repeat for multiple panels)
[panels.<name>.layout]   # Module layout for that panel

[modules.<name>]         # Per-module settings (global, shared across panels)

[theme]                  # Color palette and font

[background]             # Wallpaper / video background
[[background.entries]]   # One or more media entries
```

See each section's page for full details:

- [Panels & Layout](panels.md)
- [Modules](modules.md)
- [Theme](theme.md)
- [Background](background.md)
- [Full Example](example.md)
