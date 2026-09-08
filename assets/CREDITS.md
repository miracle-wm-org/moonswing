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

## `graceful-mark.svg`, `graceful-banner.svg`

The project mark (favicon, site logo) and the banner at the top of `README.md` and of the
website: pixel art of a hooded character in the outfit, head-on, standing between two
windows under a shell panel.

- **Credit:** original work for this repository.
- **License:** GPL-3.0, the same as the shell — these are part of it, not aggregated with it.
- **Source:** `tool/graceful_sprite.py`, which writes both files from one 32×32 sprite, so the
  favicon and the banner are literally the same character. **Edit the script, not the SVGs** —
  a grid of `<rect>`s is not hand-editable. The banner draws that sprite at 10×, an integer
  scale, so every pixel stays square.

The palette is the *graceful outfit* from Old School RuneScape, the agility set this project
takes its name from: bone cloth, charcoal gloves and boots, the jade sash and chest diamond,
the red diamond, and the charcoal band across the eyes. Read off an equipped-outfit render
and listed as `PALETTE` in that script; the cape is a shade darker than the reference, or it
and the trailing leg merge into one pale mass at favicon sizes.

**No RuneScape asset is used, or could be:** the wiki's images are Jagex's own game art,
published under a non-commercial licence that neither a GPL-3.0 repository nor a public
website can honour. Every pixel here is placed by hand.

Neither file is installed by `make install`; they are repository and website artwork only.
`website/scripts/sync.mjs` copies them into the site and rasterises the favicon fallback and
the social card from them.
