# Graceful Shell

The shell of your dreams, built with Flutter.

## Documentation

Full documentation is available at **[miracle-wm-org.github.io/graceful-shell](https://miracle-wm-org.github.io/graceful-shell/)**, including:

- [Installation](https://miracle-wm-org.github.io/graceful-shell/installation/)
- [Configuration](https://miracle-wm-org.github.io/graceful-shell/configuration/)
- [Panels & Layout](https://miracle-wm-org.github.io/graceful-shell/configuration/panels/)
- [Modules](https://miracle-wm-org.github.io/graceful-shell/configuration/modules/)
- [Theme](https://miracle-wm-org.github.io/graceful-shell/configuration/theme/)
- [Background](https://miracle-wm-org.github.io/graceful-shell/configuration/background/)

To build the docs locally:

```sh
pip install mkdocs-material
mkdocs serve
```

## Quick Start

```sh
# Install dependencies (Debian/Ubuntu)
sudo apt install libgtk-3-dev libgtk-layer-shell-dev libasound2-dev libmpv-dev

# Build and install
flutter config --enable-windowing
make install

# Run
graceful-shell
```

Configuration is written to `~/.config/graceful-shell/config.toml` on first launch.
