# Installation

## Dependencies

Before building, install the required system libraries:

=== "Debian / Ubuntu"

    ```sh
    sudo apt install libgtk-3-dev libgtk-layer-shell-dev libasound2-dev libmpv-dev
    ```

=== "Arch Linux"

    ```sh
    sudo pacman -S gtk3 gtk-layer-shell alsa-lib mpv
    ```

You also need a working [Flutter](https://flutter.dev/docs/get-started/install/linux) installation.

## Building

Enable Flutter's Linux windowing support and build a release binary:

```sh
flutter config --enable-windowing
make build
```

This runs `flutter build linux --release` and produces a self-contained bundle under `build/linux/x64/release/bundle/`.

## Installing

Install to `~/.local` (the default prefix):

```sh
make install
```

This places the launcher script at `~/.local/bin/graceful-shell` and the application bundle at `~/.local/lib/graceful-shell/`. Make sure `~/.local/bin` is in your `PATH`.

To install to a different prefix:

```sh
make install PREFIX=/usr/local
```

## Uninstalling

```sh
make uninstall
```

## Running

```sh
graceful-shell
```

On first run, if no configuration file exists, a default `config.toml` is written to `~/.config/graceful-shell/config.toml` and the shell starts with that default layout. Edit the file and restart to apply changes.
