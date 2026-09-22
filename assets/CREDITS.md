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
website: someone with long hair on a swing hung from a branch, in front of a full moon — the
image the project is named for — with a tree at the left, a hill below and a starry night sky.
The mark crops the scene close on the moon, on a rounded tile; the banner shows the same scene
wide. The drawing follows a design mocked up for the project in a Claude session.

- **Credit:** original work for this repository. No third-party reference, asset or trace.
- **License:** GPL-3.0, the same as the shell — these are part of it, not aggregated with it.
- **Source:** `tool/moonswing_sprite.py`, which writes both files. **Edit the script, not the
  SVGs.** The scene is authored once, in its own coordinates, and each file is that scene
  under a different `viewBox` — so the two cannot drift into being two different drawings,
  which is the failure a pair of hand-edited files invites.

The tree, swing and figure are one ink: past favicon size a silhouette is carried entirely by
its outline, which is why the figure's streaming hair and outstretched legs are drawn as bold
shapes rather than detail.

Neither file is installed by `make install`; they are repository and website artwork only.
`website/scripts/sync.mjs` copies them into the site and rasterises the favicon fallback and
the social card from them.
