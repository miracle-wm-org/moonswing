#!/usr/bin/env python3
"""Draws the project's artwork: assets/moonswing-mark.svg and moonswing-banner.svg.

Both are one scene — someone with long hair on a swing hung from a branch, in
front of a full moon, a tree at the left and a hill below — seen through two
windows: a square cropped close on the moon for the favicon and site logo, and
a wide one for the README and the website hero. The scene is authored once, in
its own coordinates (a 1080x1350 poster, the moon at its heart), and each file
is that scene under a different `viewBox`. Nothing is placed per file, so the
two cannot drift into being two different drawings the way two hand-edited
files would. Change the geometry below and re-run:

    python3 tool/moonswing_sprite.py

The things that have to reach the frame's edges — the sky, the trunk, the hill
— are built from the frame they are drawn for, since the banner sees far more
of the world to either side than the poster the scene was drawn on.
"""

import os

# ---------------------------------------------------------------------------
# Palette. One ink for everything that is not sky or moon: the tree, the swing
# and the figure are a single silhouette, and past favicon size a silhouette
# is carried entirely by its outline.
# ---------------------------------------------------------------------------

INK = '#0A0C1A'
MOON = '#F7ECCB'  # the moon's body; its glow is the same colour, fading
MOON_LIT = '#FFFDF2'  # the bright spot the face gradient starts from
MOON_RIM = '#E3CF98'  # the limb, warmer and darker
MARIA_FILL = '#C9B37C'
CRATER_FILL = '#CDB67F'
CRATER_FLOOR = '#B89F66'
CRATER_RIM = '#FFFAF0'
SKY = ('#2A3566', '#141A3D', '#070A1C')  # around the moon -> the corners
STAR = '#FDF7E0'

# ---------------------------------------------------------------------------
# The scene, in its own units. y runs downward.
# ---------------------------------------------------------------------------

MOON_C = (560.0, 640.0)
MOON_R = 380.0
GLOW_R = 560.0

# Low-contrast seas, as (cx, cy, rx, ry), clipped to the disc.
MARIA = ((420, 470, 120, 90), (690, 780, 150, 110), (760, 500, 80, 120),
         (400, 820, 90, 60))

# Craters: (cx, cy, r, rim) — the larger ones get a darker floor and a lit
# upper rim, which is what makes them read as dents rather than spots.
CRATERS = ((470, 420, 46, True), (700, 560, 64, True), (380, 680, 34, False),
           (600, 880, 52, True), (820, 760, 28, False), (560, 330, 22, False),
           (300, 560, 18, False), (520, 600, 14, False), (760, 380, 16, False),
           (470, 960, 20, False), (880, 600, 12, False), (640, 700, 10, False),
           (340, 780, 11, False), (720, 960, 15, False))

# x, y, r. Fixed rather than random so the artwork diffs. The poster's own
# stars sit inside 0..1080; the rest fill the banner's wings either side.
STARS = ((90, 70, 2), (210, 130, 1.4), (330, 60, 2.4), (610, 90, 1.6),
         (760, 50, 2), (880, 140, 2.6), (1010, 80, 1.5), (960, 260, 1.8),
         (1040, 380, 2.2), (1000, 560, 1.4), (1050, 720, 2), (990, 880, 1.6),
         (150, 340, 1.6), (60, 480, 2.2), (120, 700, 1.4), (70, 900, 2),
         (180, 1010, 1.5), (930, 1040, 1.8), (700, 150, 1.2), (480, 40, 1.4),
         (1060, 200, 1.3),
         (-547, 264, 4), (-341, 449, 2.7), (-482, 704, 4.9), (-210, 248, 3),
         (-640, 519, 3.3), (-395, 954, 3.8), (-140, 759, 2.7), (-585, 905, 4.3),
         (-265, 1101, 3), (-75, 503, 3.5), (1318, 302, 4.6), (1530, 492, 3.3),
         (1137, 660, 3.8), (1708, 753, 2.7), (1398, 959, 4.1), (1203, 1100, 3),
         (1632, 258, 3.5), (1784, 986, 3.3), (1061, 437, 2.7), (1475, 1167, 2.7))

# Four-pointed glints: (x, y, arm).
SPARKLES = ((904, 206, 16), (113, 599, 12), (-300, 360, 14), (1560, 620, 13))

BRANCH = ('M 20 150 C 180 150 330 180 470 196 C 620 212 760 222 900 246 '
          'C 780 238 620 232 470 222 C 330 212 170 200 40 212 Z')
# Twigs off the branch, as (path, width).
TWIGS = (('M 720 222 C 760 200 790 180 830 176', 7),
         ('M 260 180 C 280 150 300 130 330 120', 6),
         ('M 610 214 C 640 240 660 262 700 270', 5),
         ('M 830 236 C 860 250 880 270 900 290', 5))
# Leaves: (cx, cy, rx, ry, angle).
LEAVES = ((836, 172, 18, 8, -20), (812, 184, 15, 7, 30), (336, 116, 18, 8, -25),
          (310, 130, 14, 6, 35), (706, 272, 17, 7, 15), (682, 258, 13, 6, 50),
          (904, 296, 16, 7, 50), (900, 246, 16, 7, 10), (120, 150, 22, 9, -30),
          (160, 176, 18, 8, 20))

# The swing and its rider, drawn hanging straight down from the branch and then
# swung forward about the point the ropes are tied at.
SWING_PIVOT = (470, 210)
SWING_ANGLE = -20
SWING = '''\
<line x1="440" y1="206" x2="440" y2="782" stroke-width="4" fill="none"/>
<line x1="500" y1="206" x2="500" y2="782" stroke-width="4" fill="none"/>
<rect x="392" y="776" width="150" height="14" rx="3" stroke="none"/>
<!-- legs, out along the seat -->
<path stroke="none" d="M 452 752 C 482 750 512 752 536 758 C 556 764 574 772 592 778 C 604 780 616 786 622 794 C 624 799 620 802 614 802 C 604 802 594 800 584 797 C 566 792 550 786 534 780 C 524 778 516 777 508 777 L 456 777 C 448 772 446 760 452 752 Z"/>
<!-- the far arm -->
<path fill="none" stroke-width="12" d="M 438 642 Q 468 624 494 606"/>
<ellipse cx="498" cy="603" rx="8" ry="10" stroke="none"/>
<!-- body and head -->
<path stroke="none" d="M 428 777 C 418 758 410 724 408 690 C 406 668 408 650 414 638 C 418 630 420 624 418 616 C 404 608 400 588 406 574 C 414 560 434 556 446 566 C 452 572 454 578 454 582 L 462 594 L 456 598 C 458 604 456 610 452 614 C 448 618 444 620 442 622 C 446 628 452 634 460 640 C 470 650 474 670 470 690 C 468 708 470 726 482 744 C 506 744 526 746 544 750 C 564 756 584 762 602 766 C 614 767 626 770 634 777 C 637 782 634 786 628 787 C 616 788 604 786 594 784 C 576 780 560 776 544 772 C 526 774 504 777 480 777 L 428 777 Z"/>
<!-- hair, streaming back -->
<path stroke="none" d="M 448 568 C 438 552 414 546 396 554 C 380 560 370 572 356 576 C 346 580 336 578 326 584 C 336 592 346 594 354 598 C 346 606 338 612 328 618 C 342 626 358 624 370 618 C 380 628 394 630 404 624 C 412 618 416 610 418 604 C 424 590 438 578 448 576 Z"/>
<!-- the near arm, up to the rope -->
<path stroke="none" d="M 430 652 C 452 638 476 626 494 616 C 504 612 512 620 506 630 C 486 642 462 654 444 666 C 436 668 428 660 430 652 Z"/>
<ellipse cx="502" cy="621" rx="9" ry="11" stroke="none"/>'''

# ---------------------------------------------------------------------------
# Framing: each file is a window onto the scene, (x, y, w, h) in scene units.
# ---------------------------------------------------------------------------

MARK_N = 32
MARK_VIEW = (-20.0, 140.0, 1080.0, 1080.0)  # the moon, the branch over it, the
#                                         hill's crest and a sliver of trunk
MARK_RADIUS = 0.2  # of the side: the corner rounding of the icon's tile

BANNER_W, BANNER_H = 960, 420  # website/scripts/sync.mjs rasterises the card at 2x
_BANNER_SCALE = 1140 / BANNER_H  # scene units per banner pixel
BANNER_VIEW = (MOON_C[0] - 480 * _BANNER_SCALE, 90.0,
               BANNER_W * _BANNER_SCALE, 1140.0)

LABEL = ('A silhouette of someone with long hair on a swing hung from a '
         'branch, in front of a full moon')


def _n(v):
    """A number, without the trailing zeroes that make the SVGs diff noisily."""
    return f'{v:.5g}'


def _indent(text, indent):
    return '\n'.join(indent + line for line in text.splitlines())


def _trunk(view):
    """The tree, rising out of the left of the poster. It runs past the top of
    either frame so the branch never grows out of a stump."""
    top = _n(view[1] - 100)
    bottom = _n(view[1] + view[3] + 100)
    return (f'M -150 {bottom} C -90 1100 -60 800 -50 500 C -44 300 -40 150 -36 {top} '
            f'L 52 {top} C 50 0 52 120 60 180 '
            f'C 70 260 64 420 72 600 C 80 820 110 1060 170 {bottom} Z')


def _hill(view):
    """The ground, from one edge of the frame to the other."""
    x0, x1 = view[0] - 10, view[0] + view[2] + 10
    bottom = view[1] + view[3] + 10
    left = (f'M {_n(x0)} {_n(bottom)} L {_n(x0)} 1150 '
            f'C {_n(x0 / 2)} 1140 {_n(x0 / 3)} 1220 0 1210 ' if x0 < 0 else
            f'M {_n(x0)} {_n(bottom)} L {_n(x0)} 1210 ')
    right = (f'C {_n(1080 + (x1 - 1080) / 3)} 1165 {_n(1080 + (x1 - 1080) * 2 / 3)} '
             f'1130 {_n(x1)} 1150 ' if x1 > 1080 else '')
    return (left + 'C 160 1170 300 1190 460 1215 C 640 1245 820 1200 1080 1180 '
            + right + f'L {_n(max(x1, 1080))} {_n(bottom)} Z')


def _sparkle(x, y, a):
    b = a / 3
    return (f'M {_n(x)} {_n(y - a)} L {_n(x + b)} {_n(y - b)} L {_n(x + a)} {_n(y)} '
            f'L {_n(x + b)} {_n(y + b)} L {_n(x)} {_n(y + a)} L {_n(x - b)} {_n(y + b)} '
            f'L {_n(x - a)} {_n(y)} L {_n(x - b)} {_n(y - b)} Z')


def _in(view, x, y, margin):
    return (view[0] - margin <= x <= view[0] + view[2] + margin
            and view[1] - margin <= y <= view[1] + view[3] + margin)


def defs(p):
    """Gradients and clips, their ids prefixed so two files inlined into one
    page cannot resolve each other's."""
    cx, cy = MOON_C
    return f'''\
<radialGradient id="{p}-sky" cx="{_n(cx)}" cy="{_n(cy)}" r="900" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="{SKY[0]}"/>
  <stop offset=".45" stop-color="{SKY[1]}"/>
  <stop offset="1" stop-color="{SKY[2]}"/>
</radialGradient>
<radialGradient id="{p}-glow" cx="{_n(cx)}" cy="{_n(cy)}" r="{_n(GLOW_R)}" gradientUnits="userSpaceOnUse">
  <stop offset=".6" stop-color="{MOON}" stop-opacity=".55"/>
  <stop offset=".75" stop-color="{MOON}" stop-opacity=".16"/>
  <stop offset="1" stop-color="{MOON}" stop-opacity="0"/>
</radialGradient>
<radialGradient id="{p}-face" cx="{_n(cx - 60)}" cy="{_n(cy - 80)}" r="420" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="{MOON_LIT}"/>
  <stop offset=".7" stop-color="{MOON}"/>
  <stop offset="1" stop-color="{MOON_RIM}"/>
</radialGradient>
<clipPath id="{p}-moon">
  <circle cx="{_n(cx)}" cy="{_n(cy)}" r="{_n(MOON_R)}"/>
</clipPath>'''


def scene(view, p):
    """Everything, back to front, for a frame onto `view`."""
    x, y, w, h = view
    cx, cy = MOON_C
    out = [f'<rect x="{_n(x)}" y="{_n(y)}" width="{_n(w)}" height="{_n(h)}" '
           f'fill="url(#{p}-sky)"/>']

    out.append(f'<g fill="{STAR}">')
    out += [f'  <circle cx="{_n(sx)}" cy="{_n(sy)}" r="{_n(r)}"/>'
            for sx, sy, r in STARS if _in(view, sx, sy, r)]
    out += [f'  <path d="{_sparkle(sx, sy, a)}"/>'
            for sx, sy, a in SPARKLES if _in(view, sx, sy, a)]
    out.append('</g>')

    out.append('<!-- the moon: its light on the sky, the disc, then its face -->')
    out.append(f'<circle cx="{_n(cx)}" cy="{_n(cy)}" r="{_n(GLOW_R)}" '
               f'fill="url(#{p}-glow)"/>')
    out.append(f'<circle cx="{_n(cx)}" cy="{_n(cy)}" r="{_n(MOON_R)}" '
               f'fill="url(#{p}-face)"/>')
    out.append(f'<g clip-path="url(#{p}-moon)">')
    out.append(f'  <g fill="{MARIA_FILL}" opacity=".28">')
    out += [f'    <ellipse cx="{mx}" cy="{my}" rx="{rx}" ry="{ry}"/>'
            for mx, my, rx, ry in MARIA]
    out.append('  </g>')
    for kx, ky, r, rim in CRATERS:
        out.append(f'  <circle cx="{kx}" cy="{ky}" r="{r}" fill="{CRATER_FILL}" '
                   f'opacity=".45"/>')
        if rim:
            d = r * 0.12
            out.append(f'  <circle cx="{_n(kx + d)}" cy="{_n(ky + d)}" '
                       f'r="{_n(r * 0.83)}" fill="{CRATER_FLOOR}" opacity=".33"/>')
            out.append(f'  <path d="M {_n(kx - r * 0.83)} {_n(ky - r * 0.43)} '
                       f'A {r} {r} 0 0 1 {_n(kx + r * 0.78)} {_n(ky - r * 0.52)}" '
                       f'stroke="{CRATER_RIM}" stroke-width="{_n(r / 12)}" '
                       f'fill="none" opacity=".5"/>')
    out.append('</g>')

    out.append('<!-- the tree, the ground, and the swing hung from the branch -->')
    out.append(f'<g fill="{INK}" stroke="{INK}" stroke-linecap="round" '
               'stroke-linejoin="round">')
    out.append(f'  <path stroke="none" d="{_trunk(view)}"/>')
    out.append(f'  <path stroke="none" d="{BRANCH}"/>')
    out += [f'  <path fill="none" stroke-width="{sw}" d="{d}"/>' for d, sw in TWIGS]
    out += [f'  <ellipse stroke="none" cx="{lx}" cy="{ly}" rx="{rx}" ry="{ry}" '
            f'transform="rotate({a} {lx} {ly})"/>' for lx, ly, rx, ry, a in LEAVES]
    out.append(f'  <path stroke="none" d="{_hill(view)}"/>')
    px, py = SWING_PIVOT
    out.append(f'  <g transform="rotate({SWING_ANGLE} {px} {py})">')
    out.append(_indent(SWING, '    '))
    out.append('  </g>')
    out.append('</g>')
    return '\n'.join(out)


def _header(view, width, height):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" '
            f'viewBox="{" ".join(_n(v) for v in view)}" '
            f'width="{width}" height="{height}"\n'
            f'     role="img" aria-label="{LABEL}">\n'
            '  <!-- Generated by tool/moonswing_sprite.py — edit there, not here. -->')


def mark():
    """The scene cropped close on the moon, on a rounded tile: the favicon and
    the site logo."""
    x, y, w, h = MARK_VIEW
    r = w * MARK_RADIUS
    return f'''{_header(MARK_VIEW, MARK_N, MARK_N)}
  <defs>
{_indent(defs('ms-m'), '    ')}
    <clipPath id="ms-m-tile">
      <rect x="{_n(x)}" y="{_n(y)}" width="{_n(w)}" height="{_n(h)}" rx="{_n(r)}"/>
    </clipPath>
  </defs>
  <g clip-path="url(#ms-m-tile)">
{_indent(scene(MARK_VIEW, 'ms-m'), '    ')}
  </g>
</svg>
'''


def banner():
    """The same scene, wide, for README.md and the website hero.

    The 960x420 box is load-bearing: website/scripts/sync.mjs rasterises the
    social card at exactly 2x it.
    """
    return f'''{_header(BANNER_VIEW, BANNER_W, BANNER_H)}
  <defs>
{_indent(defs('ms-b'), '    ')}
  </defs>
{_indent(scene(BANNER_VIEW, 'ms-b'), '  ')}
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
