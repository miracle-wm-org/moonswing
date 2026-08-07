# Graceful

The shell of your dreams, built with Flutter.

![Graceful Shell demo](demo.png)

## Dependencies

Install the required system libraries before building:

- `libgtk3`
- `gtk-layer-shell`
- `libasound2-dev`
- `libmpv-dev`

On Ubuntu 26.04:

```sh
sudo apt install libgtk-3-dev libgtk-layer-shell-dev libasound2-dev libmpv-dev
```

The lock screen needs two more libraries at **runtime**. Both are loaded with
`dlopen`, so the shell builds and runs fine without them — only locking is
unavailable:

- `libgtk-session-lock0` — the `ext-session-lock-v1` implementation
- `libpam0g` — password verification (part of the base system, so already installed)

```sh
sudo apt install libgtk-session-lock0
```

Your compositor must also implement `ext-session-lock-v1` (Mir/Miracle does).

Screen sharing needs **PipeWire 1.0+** (already running on any current desktop)
and a compositor implementing `ext-image-copy-capture-v1` — miracle-wm built
against MirAL 5.6 or newer. Both are checked at start-up; without them the
shell runs normally and only screen sharing is unavailable. `make install`
registers the shell as the ScreenCast portal backend; see
[CONFIG.md](CONFIG.md#screen-sharing).

You also need the [Flutter SDK](https://docs.flutter.dev/get-started/install/linux) on the `master` channel:

```sh
flutter channel master
flutter upgrade
```

## Install the nightly snap (amd64)

Prebuilt classic snaps are published for every commit to `main`. Download the
latest `graceful-shell_*.snap` from the [nightly release](https://github.com/miracle-wm-org/graceful-shell/releases/tag/nightly),
then install it:

```sh
sudo snap install ./graceful-shell_*.snap --classic --dangerous
```

`--classic` is required (this shell needs full access to the Wayland compositor);
`--dangerous` allows installing a locally downloaded snap. Once installed, run:

```sh
graceful-shell
```

The snap bundles `libgtk-session-lock` and the wallpapers, so the lock screen and
the wallpaper work out of the box. Two things it cannot install for you:

- **Screen sharing.** The first run drops the ScreenCast portal backend files into
  your XDG directories, but xdg-desktop-portal only reads them at start-up:

  ```sh
  systemctl --user restart xdg-desktop-portal
  ```

- **The PAM service file.** `/etc/pam.d/graceful-shell` needs root, so the lock
  screen falls back to the system `login` service — it still authenticates, it
  just attributes unlock attempts to `login` in the auth logs.

Everything else — PipeWire, PAM, udev, D-Bus, icon themes, the `Ubuntu Sans` font,
and the helper binaries the audio and System panes shell out to (`pw-metadata`,
`speaker-test`, `lspci`) — comes from the host, which is what classic confinement
is for.

To update, download the newest snap and re-run the install command. To remove:

```sh
sudo snap remove graceful-shell
```

## Building and installing

Enable Flutter's experimental windowing API (one-time setup):

```sh
flutter config --enable-windowing
```

Build and install to `~/.local` (default):

```sh
make install
```

Or install to a custom prefix:

```sh
make install PREFIX=/usr/local
```

This copies the binary, libraries, and the default wallpapers to the prefix. Make sure `$PREFIX/bin` is in your `PATH`.

Optionally, install the lock screen's PAM service file (needs root, and writes
to `/etc/pam.d` rather than the prefix):

```sh
sudo make install-pam
```

Without it the lock screen falls back to the system `login` service, which works
but attributes unlock attempts to `login` in the auth logs.

Once built, simply run:

```sh
graceful-shell
```

To uninstall:

```sh
make uninstall
sudo make uninstall-pam   # if you installed the PAM service file
```

## Running in development

```sh
flutter run -d linux
```
