# Bundled assets

## `lock-wallpaper.jpg`

Default lock-screen wallpaper.

- **Subject:** Barred spiral galaxy NGC 1300
- **Credit:** NASA, ESA, and The Hubble Heritage Team (STScI/AURA)
- **License:** Public domain — NASA/Hubble material is not subject to copyright.
- **Source:** [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Hubble2005-01-barred-spiral-galaxy-NGC1300.jpg)
  (downscaled from the 6637×3787 original)

Installed to `$PREFIX/share/graceful-shell/lock-wallpaper.jpg` by `make install`
and referenced by the default `[lock]` section of `config.toml`.

## `wallpaper.jpg`

Default desktop wallpaper.

- **Subject:** "Pixel Pusher" (dark variant) — a red dot-matrix field
- **Credit:** Jakub Steiner, for the GNOME Project
- **License:** [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/).
  This file is a derivative work and is distributed under the same license; it
  is aggregated with, and not part of, the GPL-3.0 shell itself.
- **Source:** [`gnome-backgrounds`](https://github.com/GNOME/gnome-backgrounds)
  `backgrounds/pixel-pusher-d.jxl` (commit `4b1c8f40`)
- **Changes:** centre-cropped from the 4096×4096 square original to 16:9,
  downscaled to 3840×2160, and re-encoded as JPEG.

Installed to `$PREFIX/share/graceful-shell/wallpaper.jpg` by `make install` and
referenced by the default `[background]` section of `config.toml`.
