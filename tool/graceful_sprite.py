#!/usr/bin/env python3
"""Draws the project's artwork: assets/graceful-mark.svg and graceful-banner.svg.

Both are pixel art of one 32x32 sprite — a character in the graceful outfit,
head-on — so the favicon and the banner are literally the same character. The
sprite is authored here rather than in the SVGs, because a grid of <rect>s is
not something anyone can edit by hand; change `sprite()` or `PALETTE` and
re-run:

    python3 tool/graceful_sprite.py

The palette is the default (pink) graceful recolour from Old School RuneScape,
matched by eye. No RuneScape asset is used — see assets/CREDITS.md.
"""

import os

N = 32  # the sprite grid is 32x32

PALETTE = {
    'o': '#22221f',  # outline
    'k': '#3f3f3d',  # charcoal: the eyes, the chest markings, gloves, boots
    'v': '#8e8a74',  # bone cloth in shadow: the cape, the back of the hood
                     # (darker than the reference, or the cape and the back
                     # leg merge into one pale mass at favicon sizes)
    'c': '#d8d3bd',  # bone cloth, the body of the outfit
    'w': '#ece8d8',  # bone cloth highlight
    'g': '#4fa79b',  # jade: the chest diamond and the waist sash
    'r': '#b03a2b',  # the red diamond, and the panel down the leg
    's': '#c18f66',  # skin, the only part of the wearer left uncovered
}
DISC = '#23262b'  # slate, dark enough for the bone cloth to carry the silhouette


def sprite():
    """The pose, painted back to front: cape, back limbs, torso, head, front."""
    g = [['.'] * N for _ in range(N)]
    dy = 1  # the pose is drawn one row high of the disc's centre

    def put(r, c, s):
        for i, ch in enumerate(s):
            if ch != ' ':
                g[r + dy][c + i] = ch

    # cape, hanging behind: a single pixel down the body, where the arms and
    # gloves cover it, and three where it clears them past the hips. That
    # widening is the whole read — an even strip beside the body is piping.
    put(12, 8, "ovvvvvvvvvvvvvvo")
    put(13, 8, "ovvvvvvvvvvvvvvo")
    put(14, 8, "ovvvvvvvvvvvvvvo")
    put(15, 8, "ovvvvvvvvvvvvvvo")
    put(16, 8, "ovvvvvvvvvvvvvvo")
    put(17, 8, "ovvvvvvvvvvvvvvo")
    put(18, 8, "ovvvvvvvvvvvvvvo")
    put(19, 8, "ovvvvvvvvvvvvvvo")
    put(20, 7, "ovvvvvvvvvvvvvvvvo")
    put(21, 7, "ovvvvvvvvvvvvvvvvo")
    put(22, 7, "ovvvvvvvvvvvvvvvvo")
    put(23, 8, "ovvvvvvvvvvvvvvo")
    put(24, 9, "ovvvvvvvvvvvvo")
    # arms: one pixel of bare skin down each side, into a small round glove.
    # Undrawn on the outside — an arm this thin, outlined, is mostly outline —
    # so the cape sits straight against the skin, and the only line beside it
    # is the torso's own.
    put(14, 10, "s")
    put(15, 10, "s")
    put(16, 10, "s")
    put(17, 10, "s")
    put(18, 9, "kk")
    put(19, 9, "kk")
    put(14, 21, "s")
    put(15, 21, "s")
    put(16, 21, "s")
    put(17, 21, "s")
    put(18, 21, "kk")
    put(19, 21, "kk")
    # torso: the charcoal markings, the jade and red diamonds, the jade sash
    put(12, 9, "occcccccccccco")
    put(13, 10, "occccccccccо".replace("о", "o"))
    put(14, 11, "occcggccco")
    put(15, 11, "ockcccckco")
    put(16, 11, "occcrrccco")
    put(17, 11, "ockcccckco")
    put(18, 11, "oggggggggo")
    put(19, 11, "occcccccco")
    # the tabard, with the red panel down its centre
    put(20, 11, "occcrrccco")
    put(21, 11, "occcrrccco")
    put(22, 11, "occcrrccco")
    # legs, into charcoal boots
    put(23, 11, "occco")
    put(24, 11, "occco")
    put(25, 11, "occco")
    put(26, 11, "okkko")
    put(23, 16, "occco")
    put(24, 16, "occco")
    put(25, 16, "occco")
    put(26, 16, "okkko")
    put(27, 10, "okkkko")
    put(27, 16, "okkkko")
    # The two things that make a cape read from the front: it comes over the
    # shoulders as one band with the strips down the sides, and it hangs
    # behind, showing in the gap between the legs.
    put(12, 9, "vvvvvvvvvvvvvv")
    put(23, 15, "vv")
    put(24, 15, "vv")
    put(25, 15, "vv")
    # hood: a rounded crown, and the opening shows the face —
    # skin, two eyes, and the bone wrap over the mouth below them
    put(4, 13, "occcco")
    put(5, 12, "occcccco")
    put(6, 11, "occcccccco")
    put(7, 11, "occcccccco")
    put(8, 11, "ocskssksco")
    put(9, 11, "occsssscco")
    put(10, 11, "occcccccco")
    put(11, 12, "occcccco")
    return [''.join(row) for row in g]


def rects(rows, indent):
    """One <rect> per run of equal pixels, rather than one per pixel."""
    out = []
    for y, row in enumerate(rows):
        x = 0
        while x < N:
            ch = row[x]
            if ch == '.':
                x += 1
                continue
            w = 1
            while x + w < N and row[x + w] == ch:
                w += 1
            out.append(f'{indent}<rect x="{x}" y="{y}" width="{w}" height="1" '
                       f'fill="{PALETTE[ch]}"/>')
            x += w
    return '\n'.join(out)


def legend(rows):
    """The grid, as a comment, so a diff of the artwork is readable."""
    key = '  '.join(f'{k} {v}' for k, v in PALETTE.items())
    body = '\n'.join('    ' + r for r in rows)
    return f'  <!-- Generated by tool/graceful_sprite.py — edit there, not here.\n' \
           f'    {key}\n\n{body}\n  -->'


def mark(rows):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {N} {N}" width="{N}" height="{N}"
     shape-rendering="crispEdges" role="img" aria-label="Graceful Shell">
{legend(rows)}
  <circle cx="16" cy="16" r="15.5" fill="{DISC}"/>
{rects(rows, '  ')}
</svg>
'''


def banner(rows):
    """The sprite at 6x, vaulting the gap between two windows under a panel."""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 420" width="960" height="420"
     shape-rendering="auto" role="img"
     aria-label="A hooded character in the graceful outfit, standing between two desktop windows under a shell panel">
{legend(rows)}
  <defs>
    <linearGradient id="ga-sky" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#232831"/>
      <stop offset="55%" stop-color="#1a1e25"/>
      <stop offset="1" stop-color="#121519"/>
    </linearGradient>
    <linearGradient id="ga-win" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2c333c" stop-opacity=".95"/>
      <stop offset="1" stop-color="#1b2027" stop-opacity=".95"/>
    </linearGradient>
    <radialGradient id="ga-glow" cx="50%" cy="45%" r="55%">
      <stop offset="0" stop-color="#4fa79b" stop-opacity=".22"/>
      <stop offset="1" stop-color="#4fa79b" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <rect width="960" height="420" fill="url(#ga-sky)"/>
  <rect width="960" height="420" fill="url(#ga-glow)"/>

  <!-- faint starfield -->
  <g fill="#dfe6e4" fill-opacity=".18">
    <circle cx="96" cy="72" r="1.6"/><circle cx="212" cy="46" r="1.1"/><circle cx="330" cy="96" r="1.4"/>
    <circle cx="628" cy="58" r="1.2"/><circle cx="742" cy="104" r="1.7"/><circle cx="884" cy="64" r="1.3"/>
    <circle cx="452" cy="40" r="1"/><circle cx="806" cy="176" r="1.2"/><circle cx="150" cy="168" r="1.1"/>
  </g>

  <!-- the shell's own panel, across the top -->
  <rect x="0" y="0" width="960" height="26" fill="#171b21" fill-opacity=".92"/>
  <g fill="#4fa79b" fill-opacity=".55">
    <rect x="24" y="10" width="26" height="6" rx="3"/>
    <rect x="58" y="10" width="12" height="6" rx="3" fill-opacity=".3"/>
    <rect x="78" y="10" width="12" height="6" rx="3" fill-opacity=".3"/>
    <rect x="432" y="10" width="52" height="6" rx="3" fill-opacity=".4"/>
    <rect x="806" y="10" width="18" height="6" rx="3"/>
    <rect x="832" y="10" width="18" height="6" rx="3"/>
    <rect x="858" y="10" width="42" height="6" rx="3"/>
  </g>
  <rect x="0" y="26" width="960" height="1" fill="#4fa79b" fill-opacity=".22"/>

  <!-- two windows, flanking, sharing the character's baseline -->
  <g>
    <rect x="40" y="200" width="280" height="180" rx="14" fill="url(#ga-win)"
          stroke="#4fa79b" stroke-opacity=".28" stroke-width="1.5"/>
    <rect x="40" y="200" width="280" height="30" rx="14" fill="#4fa79b" fill-opacity=".12"/>
    <rect x="40" y="216" width="280" height="14" fill="#4fa79b" fill-opacity=".12"/>
    <g fill="#7fc7bd" fill-opacity=".5">
      <circle cx="62" cy="215" r="4"/><circle cx="78" cy="215" r="4"/><circle cx="94" cy="215" r="4"/>
    </g>
    <g fill="#dfe6e4" fill-opacity=".13">
      <rect x="64" y="256" width="180" height="9" rx="4.5"/>
      <rect x="64" y="278" width="222" height="9" rx="4.5"/>
      <rect x="64" y="300" width="140" height="9" rx="4.5"/>
      <rect x="64" y="322" width="196" height="9" rx="4.5"/>
    </g>
  </g>
  <g>
    <rect x="640" y="236" width="280" height="144" rx="14" fill="url(#ga-win)"
          stroke="#4fa79b" stroke-opacity=".28" stroke-width="1.5"/>
    <rect x="640" y="236" width="280" height="30" rx="14" fill="#4fa79b" fill-opacity=".12"/>
    <rect x="640" y="252" width="280" height="14" fill="#4fa79b" fill-opacity=".12"/>
    <g fill="#7fc7bd" fill-opacity=".5">
      <circle cx="662" cy="251" r="4"/><circle cx="678" cy="251" r="4"/><circle cx="694" cy="251" r="4"/>
    </g>
    <g fill="#dfe6e4" fill-opacity=".13">
      <rect x="664" y="292" width="200" height="9" rx="4.5"/>
      <rect x="664" y="314" width="150" height="9" rx="4.5"/>
      <rect x="664" y="336" width="184" height="9" rx="4.5"/>
    </g>
  </g>

  <!-- the ground the three of them stand on -->
  <ellipse cx="480" cy="380" rx="180" ry="16" fill="#4fa79b" fill-opacity=".13"/>
  <rect x="0" y="380" width="960" height="1" fill="#4fa79b" fill-opacity=".16"/>

  <!-- the sprite, at 10x so every pixel stays square -->
  <g transform="translate(320 100) scale(10)" shape-rendering="crispEdges">
{rects(rows, '    ')}
  </g>
</svg>
'''


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    rows = sprite()
    for name, svg in (('graceful-mark.svg', mark(rows)),
                      ('graceful-banner.svg', banner(rows))):
        path = os.path.join(root, 'assets', name)
        with open(path, 'w') as f:
            f.write(svg)
        print(f'wrote {path}')


if __name__ == '__main__':
    main()
