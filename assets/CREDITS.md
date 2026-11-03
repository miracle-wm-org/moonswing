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

Installed to `$PREFIX/share/moonswing/wallpaper.jpg` by `make install`. It is
the default theme's own wallpaper (`wallpaper = "wallpaper.jpg"` in Glassy),
which the default `[background]` section of `config.toml` shows through its
`theme = true` entry.

## The shipped themes' wallpapers

Each shipped theme names a desktop wallpaper of its own (`wallpaper` in the theme file), which
is what the **Theme default** tile in Settings › Background shows while that theme is active.
Glassy, the default theme, names `wallpaper.jpg` above, and Classic 95 names `wallpaper-classic95.jpg`
below; the other five are photographs and
artwork from the [Ubuntu wallpaper contests](https://launchpad.net/ubuntu-wallpapers), taken
from Ubuntu 24.04's `ubuntu-wallpapers-<release>` packages, whose
`/usr/share/doc/<package>/copyright` gives each file's author and licence.

| File | Theme | Work | Author | Licence | Package |
| --- | --- | --- | --- | --- | --- |
| `wallpaper-forest.jpg` | Forest | *Forest* | Moritz Reisinger | [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/) | `ubuntu-wallpapers-zesty` |
| `wallpaper-autumn.jpg` | Autumn | *Way* | Kacper Ślusarczyk | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) | `ubuntu-wallpapers-impish` |
| `wallpaper-dracula.jpg` | Dracula | *Flow* | Emanuele Santoro | [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/) | `ubuntu-wallpapers-lunar` |
| `wallpaper-midnight.jpg` | Midnight | *Milky Way* | Paulo José Oliveira Amaro | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) | `ubuntu-wallpapers-impish` |
| `wallpaper-carbon.jpg` | Carbon | *Optical Fibers in Dark* | Elena Stravoravdi | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) | `ubuntu-wallpapers-jammy` |

- **Changes:** each is cover-cropped to 3840×2160 and re-encoded as JPEG (the originals are
  3840 wide and 2160 to 2560 tall; `Flow` was a PNG). Nothing else is altered.
- **License:** each file keeps its original's licence, as the licence requires of an
  adaptation — a resized copy of a CC BY-SA work is CC BY-SA under the same version. The
  shell does not use them in a way that brings its own code under that licence: they are
  separate files, installed beside the binary and opened at run time.
- **Source:** the files of the same names (`Forest_by_Moritz_Reisinger.jpg`,
  `Way_by_Kacper_Ślusarczyk.jpg`, `Flow_by_Emanuele_Santoro.png`,
  `Milky_Way_by_Paulo_José_Oliveira_Amaro.jpg`,
  `Optical_Fibers_in_Dark_by_Elena_Stravoravdi.jpg`) under `/usr/share/backgrounds` in the
  packages named above.

Installed to `$PREFIX/share/moonswing/` by `make install` and staged by the snap; a theme
names one by its bare file name and `lib/theme/theme_wallpaper.dart` finds it there.

## `wallpaper-classic95.jpg`

Classic 95's desktop: one solid colour, RGB 0/128/128 — the teal of the sixteen-colour system
palette that a mid-nineties PC desktop showed when no picture was chosen. There is no picture in
it, only the colour.

- **Credit:** original work for this repository.
- **License:** GPL-3.0, the same as the shell. A flat field of one colour carries no expression
  of anybody's to license.
- **Source:** generated with Pillow, and reproduced by
  `python3 -c "from PIL import Image; Image.new('RGB', (3840, 2160), (0, 128, 128)).save('assets/wallpaper-classic95.jpg', quality=95, subsampling=0, optimize=True)"`.
  JPEG's colour conversion rounds the blue channel to 129, which no eye can tell apart.

Installed and staged with the other `wallpaper-*.jpg` files above.

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
