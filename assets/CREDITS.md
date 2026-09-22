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

Default desktop wallpaper: the full moon, the whole near side, on a field of
stars.

- **Subject:** A render, not a photograph. The Moon's near side is projected
  onto a sphere from the Clementine UVVIS basemap mosaic, a map of the whole
  lunar surface, and set on a generated starfield. No single photograph shows
  both: a camera exposed for the full moon records no stars.
- **Credit:** Lunar map: NASA/SDIO, courtesy of the
  [USGS Astrogeology Research Program](https://astrogeology.usgs.gov), from the
  Clementine mission (1994). The render and starfield are original work for this
  repository.
- **License:** The Clementine basemap is a US Government work in the public
  domain. The render adds nothing that restricts it, so this file is also in
  the public domain. Crediting NASA and the USGS does not imply that either
  endorses this project.
- **Source:** The map is the copy KDE Marble ships as
  `maps/moon/clementine/clementine.jpg` (Ubuntu 24.04 `marble-qt-data`).
  `tool/moon_wallpaper.py` renders the wallpaper from it. **Edit the script, not
  the JPEG.** Its starfield comes from a fixed seed, so a re-run reproduces
  the file. The script also fills the gaps the mosaic left in its coverage and
  evens out the streaked polar rows, which otherwise show as black specks and
  stripes on the disc.

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
