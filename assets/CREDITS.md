# Bundled assets

## `lock-wallpaper.jpg`

Default lock-screen wallpaper.

- **Subject:** Barred spiral galaxy NGC 1300
- **Credit:** NASA, ESA, and The Hubble Heritage Team (STScI/AURA)
- **License:** Public domain — NASA/Hubble material is not subject to copyright.
- **Source:** [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Hubble2005-01-barred-spiral-galaxy-NGC1300.jpg)
  (downscaled from the 6637×3787 original)

Installed to `$PREFIX/share/moonswing/lock-wallpaper.jpg` by `make install`
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

Installed to `$PREFIX/share/moonswing/wallpaper.jpg` by `make install` and
referenced by the default `[background]` section of `config.toml`.

## `moonswing-mark.svg`, `moonswing-banner.svg`

The project mark (favicon, site logo) and the banner at the top of `README.md` and of the
website: a silhouette of someone on a swing in front of a full moon — the image the project
is named for. The mark crops it to the moon itself, so the ropes leave the frame over its
top edge; the banner sets the same drawing on a night sky and nothing else. The banner used
to draw a mock desktop behind its subject — a panel, two windows, a starfield — and that was
a screenshot the shell had not earned, dating itself every time the real thing changed. The
stars are all that is kept of it.

- **Credit:** original work for this repository. No third-party reference, asset or trace.
- **License:** GPL-3.0, the same as the shell — these are part of it, not aggregated with it.
- **Source:** `tool/moonswing_sprite.py`, which writes both files. **Edit the script, not the
  SVGs.** The banner's placement is *derived* from the mark's — the scale is the ratio of the
  two moons — so the two cannot drift into being two different drawings, which is the failure
  a pair of hand-edited files invites. The script's own docstring carries the reasoning for
  the pose.

The silhouette is one ink over a warm grey-cream moon: past favicon size a silhouette is
carried entirely by its outline, so a second tone would be detail that only the banner ever
keeps. The figure is built from tapered limbs rather than a traced outline, because the two
things it loses most easily are a neck — a head as wide as the shoulders under it is a blob
at any size — and an upright read, which an early pass lost by reclining the body until it
was wider than it was tall.

Neither file is installed by `make install`; they are repository and website artwork only.
`website/scripts/sync.mjs` copies them into the site and rasterises the favicon fallback and
the social card from them.
