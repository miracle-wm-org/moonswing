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
