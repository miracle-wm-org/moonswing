#!/usr/bin/env python3
"""Draws the default desktop wallpaper, assets/wallpaper.jpg: a full moon on stars.

The moon is not a photograph. It is the near side rendered from a public-domain
map: the Clementine UVVIS basemap mosaic (NASA/SDIO, courtesy of the USGS
Astrogeology Research Program), the copy KDE Marble ships at
`maps/moon/clementine/clementine.jpg`, which Debian and Ubuntu package as
`marble-qt-data`. The starfield is generated here. Re-run after a change:

    sudo apt install marble-qt-data   # or pass --map to another copy
    pip install numpy pillow
    python3 tool/moon_wallpaper.py

Rendered rather than photographed because no photograph shows both: a camera
exposed for the full moon records no stars, and one exposed for stars burns the
moon to a white disc. The render keeps both.

The output is deterministic. The stars come from a fixed seed, so a re-run
changes the file only when something below changes.

The moon is flat-lit on purpose. At full phase the Sun is behind the viewer,
and the real disc is nearly as bright at the limb as at the centre. That is
the opposition effect: a full moon looks like a disc rather than a ball. Stronger
limb darkening would draw a gibbous-lit sphere, which is not what a full moon
looks like. The little that is kept is there so the edge does not read as cut
out of paper.
"""

import argparse
import math
import os

import numpy as np
from PIL import Image

WIDTH, HEIGHT = 3840, 2160
SEED = 1969  # the stars; changing it redraws the sky, nothing else

# The moon: centre as a fraction of the frame, radius as a fraction of the
# height. It sits right of centre, because the desktop grid fills from the
# left, and a little high, so a bottom bar does not crowd it.
MOON_CX, MOON_CY, MOON_R = 0.64, 0.46, 0.225

# The disc is a neutral grey with a slight warmth, as the Moon photographs
# under a clear sky. The tint multiplies the albedo channel-wise.
MOON_TINT = np.array([1.00, 0.975, 0.93])
MOON_GAIN = 0.97  # the brightest highland, before tint; below 1 so it never clips flat
LIMB_DARKENING = 0.14  # how much dimmer the limb is than the centre

SKY_TOP = np.array([4, 6, 14]) / 255.0
SKY_BOTTOM = np.array([10, 14, 28]) / 255.0

DEFAULT_MAP = '/usr/share/marble/data/maps/moon/clementine/clementine.jpg'
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'wallpaper.jpg')


def sky():
    """A near-black gradient, a shade bluer toward the bottom of the frame."""
    t = np.linspace(0.0, 1.0, HEIGHT)[:, None, None]
    img = SKY_TOP * (1 - t) + SKY_BOTTOM * t
    return np.broadcast_to(img, (HEIGHT, WIDTH, 3)).copy()


def moon_geometry():
    cx, cy, r = MOON_CX * WIDTH, MOON_CY * HEIGHT, MOON_R * HEIGHT
    ys, xs = np.mgrid[0:HEIGHT, 0:WIDTH].astype(np.float64)
    dist = np.hypot(xs + 0.5 - cx, ys + 0.5 - cy)
    return cx, cy, r, xs, ys, dist


# Star colours, blue-white to orange. Weighted toward white, as the naked-eye
# sky is.
_STAR_TINTS = np.array([
    [0.80, 0.87, 1.00],
    [0.92, 0.95, 1.00],
    [1.00, 1.00, 1.00],
    [1.00, 0.96, 0.88],
    [1.00, 0.88, 0.74],
])
_STAR_WEIGHTS = np.array([0.18, 0.27, 0.30, 0.17, 0.08])


def stars(img, dist, r, rng):
    """Adds the starfield in place.

    The count falls steeply with brightness, as a real field's does: thousands
    at the edge of visibility, a few hundred plain points, and about twenty
    with a halo. Stars near the moon are dimmed, because glare swamps them.
    """
    layers = [
        # count, brightness range, gaussian sigma range (px)
        (5200, (0.08, 0.30), (0.55, 0.75)),
        (700, (0.30, 0.75), (0.70, 1.00)),
        (90, (0.75, 1.00), (0.95, 1.35)),
        (22, (0.95, 1.00), (1.30, 1.80)),
    ]
    for count, (b0, b1), (s0, s1) in layers:
        xs = rng.uniform(0, WIDTH, count)
        ys = rng.uniform(0, HEIGHT, count)
        bright = b0 + (b1 - b0) * rng.power(0.6, count)[::-1]
        sigma = rng.uniform(s0, s1, count)
        tint = _STAR_TINTS[rng.choice(len(_STAR_TINTS), count, p=_STAR_WEIGHTS)]
        for x, y, b, s, c in zip(xs, ys, bright, sigma, tint):
            ix, iy = int(x), int(y)
            # Glare: no stars on or right beside the disc, fading back in
            # over half a radius.
            d = dist[min(iy, HEIGHT - 1), min(ix, WIDTH - 1)]
            glare = np.clip((d - r * 1.08) / (r * 0.55), 0.0, 1.0)
            if glare <= 0.0:
                continue
            k = int(math.ceil(s * 4))
            if b > 0.9 and s > 1.25:
                k = int(math.ceil(s * 9))  # room for the halo
            x0, x1 = max(ix - k, 0), min(ix + k + 1, WIDTH)
            y0, y1 = max(iy - k, 0), min(iy + k + 1, HEIGHT)
            gy, gx = np.mgrid[y0:y1, x0:x1]
            d2 = (gx + 0.5 - x) ** 2 + (gy + 0.5 - y) ** 2
            core = np.exp(-d2 / (2 * s * s))
            if b > 0.9 and s > 1.25:
                core = core + 0.06 * np.exp(-d2 / (2 * (s * 3.2) ** 2))
            img[y0:y1, x0:x1] += (b * glare * core)[..., None] * c


def glow(img, dist, r):
    """A faint halo round the disc: scattered moonlight in the air."""
    outside = np.clip(dist - r, 0.0, None)
    halo = 0.10 * np.exp(-outside / (r * 0.10)) + 0.035 * np.exp(-outside / (r * 0.55))
    img += halo[..., None] * np.array([0.78, 0.82, 0.92])


def _box3(a):
    """The sum of each pixel's 3x3 neighbourhood, wrapping in longitude."""
    p = np.pad(a, ((1, 1), (0, 0)), mode='edge')
    p = np.pad(p, ((0, 0), (1, 1)), mode='wrap')
    h, w = a.shape
    return sum(p[dy:dy + h, dx:dx + w] for dy in range(3) for dx in range(3))


def clean_map(tex):
    """Repairs the two defects the mosaic has, in place of hiding them.

    **Holes.** Clementine left gaps in its coverage. The mosaic stores them as
    black rectangles, which a render shows as black specks strewn across the
    maria. No real surface on the near side is anywhere near that dark, so
    anything that is, plus a pixel of JPEG ringing round it, is filled by
    diffusing its neighbours inward.

    **Poles.** Past about 75 degrees the mosaic is streaked and mostly shadow.
    From the Earth that band is a sliver at the limb, so it is eased toward
    the average of the latitudes just below it rather than drawn as stripes.
    """
    h = tex.shape[0]
    hole = tex < 25.0 / 255.0
    hole = _box3(hole.astype(np.float64)) > 0  # the JPEG ringing round each hole
    known = ~hole
    val = np.where(known, tex, 0.0)
    while not known.all():
        s, c = _box3(val), _box3(known.astype(np.float64))
        grow = ~known & (c > 0)
        val[grow] = s[grow] / c[grow]
        known = known | grow
    for _ in range(4):  # soften the seams the fill leaves; known pixels stay put
        val = np.where(hole, _box3(val) / 9.0, val)

    lat = 90.0 - (np.arange(h) + 0.5) / h * 180.0
    for sign in (1, -1):
        band = (sign * lat > 68) & (sign * lat < 74)
        mean = val[band].mean()
        w_row = np.clip((sign * lat - 74.0) / 8.0, 0.0, 1.0)[:, None]
        val = val * (1 - w_row) + mean * w_row
    return val


def moon(img, cx, cy, r, xs, ys, dist, lunar_map):
    """Composites the near side, orthographically projected, over [img]."""
    tex = clean_map(np.asarray(lunar_map.convert('L'), dtype=np.float64) / 255.0)
    th, tw = tex.shape
    # Stretch the mosaic's range so the maria read against the highlands.
    lo, hi = np.percentile(tex, [0.5, 99.8])
    tex = np.clip((tex - lo) / (hi - lo), 0.0, 1.0) ** 1.15
    # Only the pixels the disc can touch: one pixel of antialiasing past r.
    mask = dist < r + 1.0
    u = (xs[mask] + 0.5 - cx) / r
    v = (cy - (ys[mask] + 0.5)) / r
    rr = np.minimum(np.hypot(u, v), 0.9999)
    scale = np.where(np.hypot(u, v) > 0, rr / np.maximum(np.hypot(u, v), 1e-9), 1.0)
    u, v = u * scale, v * scale
    z = np.sqrt(np.clip(1.0 - u * u - v * v, 0.0, 1.0))
    lat = np.arcsin(np.clip(v, -1.0, 1.0))
    lon = np.arctan2(u, z)  # 0 at the sub-Earth point, east to the right

    # Equirectangular, longitude -180..180 left to right, north up.
    tx = (lon / (2 * math.pi) + 0.5) * tw - 0.5
    ty = (0.5 - lat / math.pi) * th - 0.5
    x0 = np.floor(tx).astype(int)
    y0 = np.floor(ty).astype(int)
    fx, fy = tx - x0, ty - y0
    x0, x1 = x0 % tw, (x0 + 1) % tw
    y0, y1 = np.clip(y0, 0, th - 1), np.clip(y0 + 1, 0, th - 1)
    albedo = (tex[y0, x0] * (1 - fx) * (1 - fy) + tex[y0, x1] * fx * (1 - fy)
              + tex[y1, x0] * (1 - fx) * fy + tex[y1, x1] * fx * fy)

    shade = (1.0 - LIMB_DARKENING) + LIMB_DARKENING * np.sqrt(z)
    lit = MOON_GAIN * (0.26 + 0.78 * albedo) * shade
    colour = lit[:, None] * MOON_TINT

    # Coverage of each edge pixel by the disc, so the limb is antialiased.
    alpha = np.clip(r - dist[mask] + 0.5, 0.0, 1.0)[:, None]
    img[mask] = img[mask] * (1 - alpha) + colour * alpha


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--map', default=DEFAULT_MAP,
                        help='equirectangular lunar albedo map (default: %(default)s)')
    parser.add_argument('--out', default=OUT)
    args = parser.parse_args()

    rng = np.random.default_rng(SEED)
    img = sky()
    cx, cy, r, xs, ys, dist = moon_geometry()
    stars(img, dist, r, rng)
    glow(img, dist, r)
    moon(img, cx, cy, r, xs, ys, dist, Image.open(args.map))

    # Half a level of noise, so the near-black gradient does not band once it
    # is quantised to eight bits.
    img += rng.uniform(-0.5, 0.5, img.shape) / 255.0
    out = Image.fromarray((np.clip(img, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8))
    out.save(args.out, quality=92, progressive=True, optimize=True)
    print(f'wrote {os.path.normpath(args.out)} ({WIDTH}x{HEIGHT})')


if __name__ == '__main__':
    main()
