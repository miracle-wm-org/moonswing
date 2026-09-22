#!/usr/bin/env python3
"""Draws the project's artwork: assets/moonswing-mark.svg and moonswing-banner.svg.

Both are one drawing — a silhouette of someone on a swing in front of a full
moon — emitted twice: cropped to the moon for the favicon and site logo, and
set on a night sky for the README and the website hero. The figure is authored
here rather than in the SVGs because the banner's placement is *derived* from
the mark's, so the two cannot drift into being two different drawings the way
two hand-edited files would. Change the geometry below and re-run:

    python3 tool/moonswing_sprite.py

Two things the shapes below are trying to buy, both of which a silhouette
loses easily and cannot get back with colour, because it has only one:

  * **A neck.** A head drawn as wide as the shoulders it sits on is a blob at
    any size. The torso is a taper rather than a stroke so it can be widest at
    the shoulder, and the head is narrower than that with a thin neck between.
  * **A pose that is not horizontal.** The first attempt reclined the figure
    until it was wider than it was tall, and it read as someone lying down.
    The torso is near-upright, the thighs run forward and the shins hang below
    the seat, so the outline is an upright mass with one clear horizontal.

The placement is computed, not hand-tuned: `_fit` measures the drawing and
centres it, so moving a joint cannot quietly push the figure off the disc.
"""

import math
import os

# ---------------------------------------------------------------------------
# Palette. One ink and no shading: past favicon size a silhouette is carried
# entirely by its outline, and anything else is detail only the banner keeps.
# ---------------------------------------------------------------------------

INK = '#151926'  # the silhouette: near-black, blued so it sits in a night scene
MOON_LIT = '#F7F2E4'  # the moon's centre
MOON_RIM = '#E4D9BD'  # its limb, warmer and a shade darker
MARIA_FILL = '#D6CAAC'  # the maria, at low opacity over the disc

SKY = ('#31456B', '#1B2338', '#120E18')  # banner sky, zenith -> horizon
STAR = '#E8EEFA'

# ---------------------------------------------------------------------------
# The swing, in its own space: the pivot is the origin and y runs downward, so
# the swing hangs straight down and LEAN tilts it. Everything named below is a
# joint; the W_* values are limb thicknesses, not outlines.
# ---------------------------------------------------------------------------

LEAN = -14  # degrees; negative swings the seat forward, the way the figure faces

ROPE_X = 4.0  # half the rope spacing — where they meet the seat. Wide
#               enough that the back rope clears the head: run closer and
#               it grazes the skull, and a silhouette reads that as a bite
#               taken out of the head rather than as a rope behind it.
ROPE_TOP = -34.0  # drawn well past the pivot so the ropes leave both frames
SEAT_Y = 26.0  # the top face of the seat
SEAT_HALF = 4.4
SEAT_H = 1.1

# Seated in profile, facing the direction of travel. The near arm reaches up
# to the front rope and the far one is behind the body, so only one is drawn:
# a second arm in a silhouette reads as a second limb, never as depth.
#
# The torso is only slightly off the seat's perpendicular, because the lean
# supplies the rest: swing space is upright, so a torso drawn straight up from
# the hip already arrives in the world leaning back by LEAN. Drawing the
# recline here as well is what tipped an early pass flat onto its back.
# The thigh lies *along* the plank rather than lifting off it, and the kick is
# all in the shin. A thigh that leaves the hip at a shallow angle opens a long
# thin wedge of moon between it and the plank, and at silhouette scale that
# reads as a crack in the drawing rather than as daylight under a raised leg —
# there is no angle small enough to be invisible and none large enough to look
# deliberate. Overlapping the plank has neither problem, and it is what sitting
# on a swing actually looks like.
# The kick is in the shin, and it goes *down*: straightening the leg forward
# and up merges thigh, shin and plank into one long sweep, and the swing stops
# being a swing. A bent knee with the shin falling away from the plank is what
# keeps the seat legible as a seat.
HIP = (0.2, 25.3)
KNEE = (5.8, 25.0)
ANKLE = (9.6, 27.4)
TOE = (10.9, 27.2)
SHOULDER = (-0.5, 17.5)
HEAD = (-0.6, 12.85)
HEAD_RX, HEAD_RY = 1.8, 2.15  # a head is taller than it is deep, in profile
#                               as much as head-on, and a circle at this size
#                               reads as a ball on a stick. The oval is slight
#                               on purpose: swing space is upright, so it
#                               arrives in the world tipped back by LEAN, and
#                               a stronger one would read as a tilted head.
ELBOW = (2.3, 14.8)
HAND = (ROPE_X, 11.0)  # on the rope, not near it, and high enough up it that
#                        the arm clears the torso — gripping at shoulder height
#                        drew an arm that merged into the chest and vanished.

W_HIP, W_SHOULDER = 3.0, 4.4  # the torso taper: widest where the arms hang
#                               off, and wider than the head — a head as broad
#                               as the shoulders under it is a blob at any size
W_NECK = 2.05  # wide: the head and the shoulder are both discs, and a thin
#                neck between them leaves a notch at each side that no amount
#                of outward rounding can reach, a corner being concave there
W_UPPER_ARM, W_ELBOW, W_WRIST = 1.45, 1.25, 0.95
W_THIGH, W_KNEE, W_ANKLE = 2.4, 1.9, 1.3
W_FOOT = 1.2
W_ROPE = 0.5

# How far every corner in the drawing is rounded off. Each filled shape is
# built this much smaller and then stroked back out to size with a round join,
# so the silhouette keeps its dimensions and loses its corners: the quadrilateral
# limbs stop meeting the torso, each other and the seat at points. It is one
# number for the whole figure on purpose — a silhouette whose knee is rounder
# than its shoulder reads as two drawings.
SOFTEN = 0.7

# ---------------------------------------------------------------------------
# Framing. The mark is the moon, full-bleed in a 32x32 box. The banner states
# its own moon and derives the swing from the mark's, so the banner is the
# mark's drawing at the banner's scale and nothing else.
# ---------------------------------------------------------------------------

MARK_N = 32
MARK_MOON = (16.0, 16.0, 15.5)  # cx, cy, r
MARK_SPAN = 18.0  # the body's longer side, against a 31-wide disc
MARK_CENTRE = (16.7, 18.0)  # low of the disc's centre: the ropes want the top

BANNER_W, BANNER_H = 960, 420  # website/scripts/sync.mjs rasterises the card at 2x
BANNER_MOON = (470.0, 196.0, 152.0)

# Fractions of the moon's radius: offset from its centre, then radius. Most sit
# behind the figure at any scale; the ones that do not are what stop the disc
# reading as a hole punched in the sky.
MARIA = ((-0.40, -0.32, 0.22), (0.20, -0.48, 0.14), (0.44, 0.16, 0.21),
         (-0.16, 0.46, 0.17), (-0.56, 0.20, 0.12), (0.10, -0.10, 0.11))

# x, y, r, opacity. Fixed rather than random so the artwork diffs, and kept
# clear of the moon and its halo.
STARS = ((72, 64, 1.5, .55), (148, 132, 1.0, .35), (96, 226, 1.8, .45),
         (196, 58, 1.1, .40), (38, 158, 1.2, .30), (128, 318, 1.4, .40),
         (222, 246, 1.0, .30), (58, 300, 1.6, .50), (176, 372, 1.1, .30),
         (246, 152, 1.3, .35), (758, 78, 1.7, .55), (836, 148, 1.2, .38),
         (692, 210, 1.4, .42), (902, 244, 1.0, .30), (788, 320, 1.5, .45),
         (716, 372, 1.1, .30), (874, 62, 1.3, .40), (930, 330, 1.2, .35),
         (664, 128, 1.0, .30), (820, 396, 1.0, .28))


def _n(v):
    """A number, without the trailing zeroes that make the SVGs diff noisily."""
    return f'{v:.4g}'


def _rotate(p):
    """A point in swing space, leaned."""
    a = math.radians(LEAN)
    return (p[0] * math.cos(a) - p[1] * math.sin(a),
            p[0] * math.sin(a) + p[1] * math.cos(a))


def _fit(span, centre):
    """Scale and pivot that put the leaned body at `centre`, `span` across.

    Measured from the drawing itself so a moved joint re-centres the figure
    instead of silently pushing it off the disc. The ropes are left out on
    purpose: they run off the top of both frames by design, and measuring them
    would shrink the figure to nothing.
    """
    # Each entry is a point and how far the drawing reaches around it — one
    # number, or a pair for the head, which is the only thing here that is not
    # round. Expanding the rotated centre along the world axes is a shade off
    # for an oval (the oval leans too), and over-estimates, which is the safe
    # direction for something deciding how much room to leave.
    blobs = [(HEAD, (HEAD_RX, HEAD_RY)), (HIP, W_HIP / 2),
             (SHOULDER, W_SHOULDER / 2), (KNEE, W_KNEE / 2),
             (ANKLE, W_ANKLE / 2), (TOE, W_FOOT / 2), (ELBOW, W_ELBOW / 2),
             (HAND, W_WRIST / 2),
             ((-SEAT_HALF, SEAT_Y + SEAT_H), 0), ((SEAT_HALF, SEAT_Y), 0)]

    xs, ys = [], []
    for point, reach in blobs:
        rx, ry = reach if isinstance(reach, tuple) else (reach, reach)
        x, y = _rotate(point)
        xs += [x - rx, x + rx]
        ys += [y - ry, y + ry]
    lo = (min(xs), min(ys))
    hi = (max(xs), max(ys))

    scale = span / max(hi[0] - lo[0], hi[1] - lo[1])
    mid = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2)
    return scale, (centre[0] - mid[0] * scale, centre[1] - mid[1] * scale)


def _banner_placement():
    """The banner's scale and pivot, as the mark's seen at the banner's size.

    This is the whole reason the banner is not its own drawing: the ratio of
    the two moons is the only number it gets, so a change to the figure or to
    either moon moves both files and neither can be adjusted on its own.
    """
    scale, pivot = _fit(MARK_SPAN, MARK_CENTRE)
    k = BANNER_MOON[2] / MARK_MOON[2]
    return scale * k, (BANNER_MOON[0] + (pivot[0] - MARK_MOON[0]) * k,
                       BANNER_MOON[1] + (pivot[1] - MARK_MOON[1]) * k)


# ---------------------------------------------------------------------------
# Shapes
# ---------------------------------------------------------------------------


def _stroke(a, b, width, indent):
    """A limb of one thickness: a round-capped stroke is its own union."""
    return (f'{indent}<path d="M{_n(a[0])} {_n(a[1])}L{_n(b[0])} {_n(b[1])}" '
            f'stroke-width="{_n(width)}"/>')


def _disc(p, width, indent):
    """A rounded joint, or any disc: the head, the fist, a knee.

    Two tapers meeting at an angle leave a notch on the outside of it — a
    quadrilateral has a corner where a stroke would have a cap. A disc the
    width of the limb fills it, which is what `stroke-linejoin` does for the
    limbs that are strokes.
    """
    r = max(width / 2 - SOFTEN / 2, 0.02)
    return (f'{indent}<circle cx="{_n(p[0])}" cy="{_n(p[1])}" r="{_n(r)}" '
            f'stroke-width="{_n(SOFTEN)}"/>')


def _oval(p, rx, ry, indent):
    """The head. Softened exactly as the discs are, so it sits in the same
    silhouette: built inward by half of SOFTEN, then stroked back out."""
    return (f'{indent}<ellipse cx="{_n(p[0])}" cy="{_n(p[1])}" '
            f'rx="{_n(max(rx - SOFTEN / 2, 0.02))}" '
            f'ry="{_n(max(ry - SOFTEN / 2, 0.02))}" '
            f'stroke-width="{_n(SOFTEN)}"/>')


def _taper(a, b, wa, wb, indent):
    """A limb that changes thickness, as a quadrilateral.

    A stroke cannot taper, and the torso has to: see the module docstring.
    Drawn *and* stroked so the corners round over the same way the stroked
    limbs' caps do — see SOFTEN.
    """
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    nx, ny = -dy / length, dx / length
    ha, hb = max(wa - SOFTEN, 0) / 2, max(wb - SOFTEN, 0) / 2
    pts = [(a[0] + nx * ha, a[1] + ny * ha), (b[0] + nx * hb, b[1] + ny * hb),
           (b[0] - nx * hb, b[1] - ny * hb), (a[0] - nx * ha, a[1] - ny * ha)]
    d = 'M' + 'L'.join(f'{_n(x)} {_n(y)}' for x, y in pts) + 'Z'
    return f'{indent}<path d="{d}" stroke-width="{_n(SOFTEN)}"/>'


def _seat(indent):
    """The plank, softened the same way and by the same amount as the body."""
    h = SOFTEN / 2
    return (f'{indent}<rect x="{_n(-SEAT_HALF + h)}" y="{_n(SEAT_Y + h)}" '
            f'width="{_n(2 * SEAT_HALF - SOFTEN)}" '
            f'height="{_n(max(SEAT_H - SOFTEN, 0.02))}" '
            f'rx="{_n(max(SEAT_H / 2 - h, 0.02))}" '
            f'stroke-width="{_n(SOFTEN)}"/>')


def moon(cx, cy, r, ident, indent):
    """The full moon: the lit disc, then its maria."""
    out = [f'{indent}<circle cx="{_n(cx)}" cy="{_n(cy)}" r="{_n(r)}" '
           f'fill="url(#{ident})"/>']
    out += [f'{indent}<circle cx="{_n(cx + dx * r)}" cy="{_n(cy + dy * r)}" '
            f'r="{_n(dr * r)}" fill="{MARIA_FILL}" opacity=".32"/>'
            for dx, dy, dr in MARIA]
    return '\n'.join(out)


def moon_gradient(ident, indent):
    return (f'{indent}<radialGradient id="{ident}" cx="38%" cy="34%" r="72%">\n'
            f'{indent}  <stop offset="0" stop-color="{MOON_LIT}"/>\n'
            f'{indent}  <stop offset="1" stop-color="{MOON_RIM}"/>\n'
            f'{indent}</radialGradient>')


def swing(i):
    """The silhouette, in swing space, back to front.

    Order matters only where the ink meets itself — it is one colour, so the
    drawing is the union of these shapes and nothing here can occlude anything
    above it. It is written back to front anyway, because that is the order
    the pose is easiest to read in.
    """
    out = [f'{i}<!-- the swing itself -->']
    out += [_stroke((x, ROPE_TOP), (x, SEAT_Y), W_ROPE, i)
            for x in (-ROPE_X, ROPE_X)]
    out.append(_seat(i))

    out.append(f'{i}<!-- leg: thigh forward, shin hanging past the seat -->')
    out.append(_taper(HIP, KNEE, W_THIGH, W_KNEE, i))
    out.append(_disc(KNEE, W_KNEE, i))
    out.append(_taper(KNEE, ANKLE, W_KNEE, W_ANKLE, i))
    out.append(_disc(ANKLE, W_ANKLE, i))
    out.append(_stroke(ANKLE, TOE, W_FOOT, i))

    out.append(f'{i}<!-- torso, neck, head -->')
    out.append(_taper(HIP, SHOULDER, W_HIP, W_SHOULDER, i))
    out.append(_disc(HIP, W_HIP, i))
    out.append(_disc(SHOULDER, W_SHOULDER, i))
    out.append(_stroke(SHOULDER, HEAD, W_NECK, i))
    out.append(_oval(HEAD, HEAD_RX, HEAD_RY, i))

    out.append(f'{i}<!-- the near arm, up to the front rope -->')
    out.append(_taper(SHOULDER, ELBOW, W_UPPER_ARM, W_ELBOW, i))
    out.append(_disc(ELBOW, W_ELBOW, i))
    out.append(_taper(ELBOW, HAND, W_ELBOW, W_WRIST, i))
    out.append(_disc(HAND, W_WRIST * 1.6, i))  # the fist closed on the rope
    return '\n'.join(out)


def figure_group(pivot, scale, indent):
    """The swing, placed. Read the transform right to left, as SVG applies it:
    the drawing leans about its own pivot first, so LEAN is an angle of the
    swing and not of the frame."""
    transform = (f'translate({_n(pivot[0])} {_n(pivot[1])}) '
                 f'scale({_n(scale)}) rotate({_n(LEAN)})')
    return (f'{indent}<g transform="{transform}" fill="{INK}" stroke="{INK}"\n'
            f'{indent}   stroke-linecap="round" stroke-linejoin="round">\n'
            f'{swing(indent + "  ")}\n'
            f'{indent}</g>')


def legend():
    """The joints, as a comment, so a diff of the artwork is readable."""
    joints = (('hip', HIP), ('knee', KNEE), ('ankle', ANKLE), ('toe', TOE),
              ('shoulder', SHOULDER), ('elbow', ELBOW), ('hand', HAND),
              ('head', HEAD))
    body = '  '.join(f'{k} {_n(v[0])},{_n(v[1])}' for k, v in joints)
    return ('  <!-- Generated by tool/moonswing_sprite.py — edit there, not here.\n'
            f'    lean {_n(LEAN)}deg   ropes +-{_n(ROPE_X)}   seat y{_n(SEAT_Y)}\n'
            f'    {body}\n'
            '  -->')


def mark():
    """The swing on the moon, cropped to it: the favicon and the site logo.

    The disc is the moon rather than a plate the drawing stands on, so the
    ropes have nowhere to go but off its top edge — which is what the clip is
    for. They leave the frame the way they would leave a photograph, and the
    mark needs no branch, no sky and no second colour to say what it is.
    """
    cx, cy, r = MARK_MOON
    scale, pivot = _fit(MARK_SPAN, MARK_CENTRE)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {MARK_N} {MARK_N}" \
width="{MARK_N}" height="{MARK_N}"
     role="img" aria-label="A silhouette of someone on a swing in front of a full moon">
{legend()}
  <defs>
{moon_gradient('ms-moon-m', '    ')}
    <clipPath id="ms-disc">
      <circle cx="{_n(cx)}" cy="{_n(cy)}" r="{_n(r)}"/>
    </clipPath>
  </defs>

{moon(cx, cy, r, 'ms-moon-m', '  ')}
  <g clip-path="url(#ms-disc)">
{figure_group(pivot, scale, '    ')}
  </g>
</svg>
'''


def banner():
    """The same drawing on a night sky, for README.md and the website hero.

    No scene beyond the sky. The banner used to draw a mock desktop behind the
    character — a panel, two windows, a starfield — and that was a screenshot
    the shell had not earned, dating itself every time the real thing changed.
    The stars are the one thing kept from it, because a sky this wide is
    otherwise a gradient with a hole in it, and a star dates never.

    The 960x420 box is load-bearing: website/scripts/sync.mjs rasterises the
    social card at exactly 2x it.
    """
    scale, pivot = _banner_placement()
    cx, cy, r = BANNER_MOON
    stars = '\n'.join(
        f'  <circle cx="{_n(x)}" cy="{_n(y)}" r="{_n(rad)}" fill="{STAR}" '
        f'opacity="{_n(op)}"/>' for x, y, rad, op in STARS)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {BANNER_W} {BANNER_H}" \
width="{BANNER_W}" height="{BANNER_H}"
     role="img" aria-label="A silhouette of someone on a swing in front of a full moon">
{legend()}
  <defs>
    <linearGradient id="ms-sky" x1="0" y1="0" x2=".25" y2="1">
      <stop offset="0" stop-color="{SKY[0]}"/>
      <stop offset="55%" stop-color="{SKY[1]}"/>
      <stop offset="1" stop-color="{SKY[2]}"/>
    </linearGradient>
    <radialGradient id="ms-halo" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="{MOON_LIT}" stop-opacity=".26"/>
      <stop offset="55%" stop-color="{MOON_LIT}" stop-opacity=".07"/>
      <stop offset="1" stop-color="{MOON_LIT}" stop-opacity="0"/>
    </radialGradient>
{moon_gradient('ms-moon-b', '    ')}
  </defs>

  <rect width="{BANNER_W}" height="{BANNER_H}" fill="url(#ms-sky)"/>
{stars}

  <!-- the halo first: it is the moon's light falling on the sky, so it sits
       under the disc and over the stars it would wash out -->
  <circle cx="{_n(cx)}" cy="{_n(cy)}" r="{_n(r * 2.1)}" fill="url(#ms-halo)"/>
{moon(cx, cy, r, 'ms-moon-b', '  ')}

{figure_group(pivot, scale, '  ')}
</svg>
'''


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for name, svg in (('moonswing-mark.svg', mark()),
                      ('moonswing-banner.svg', banner())):
        path = os.path.join(root, 'assets', name)
        with open(path, 'w') as f:
            f.write(svg)
        print(f'wrote {path}')


if __name__ == '__main__':
    main()
