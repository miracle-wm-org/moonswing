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
    'd': '#6b6757',  # the cape's own shadow, where it passes close behind the
                     # body: the strip beside the torso, the inside edge of the
                     # flare past the hips, and the gap between the legs
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
    #
    # The shoulders are round, not cut square. The top edge steps in twice on
    # its way up to the hood (cols 8 -> 9 -> 10, and its mirror), which at this
    # size is how a curve is spelled; a flat top row the full width of the cape
    # reads as a signboard held up behind the character rather than cloth
    # falling off a pair of shoulders.
    #
    # And where the cape passes close behind the body it is 'd' rather than
    # 'v': the strip beside the torso, the inside edge of the flare past the
    # hips, and the gap between the legs. That is the shadow the body casts on
    # to it, and it is also what stops the near edge of the cape and the tabard
    # reading as one flat cut-out.
    put(11, 10, "ov")
    put(11, 20, "vo")
    put(12, 9, "ovvvvvvvvvvvvo")
    put(13, 8, "odvvvvvvvvvvvvdo")
    put(14, 8, "odvvvvvvvvvvvvdo")
    put(15, 8, "odvvvvvvvvvvvvdo")
    put(16, 8, "odvvvvvvvvvvvvdo")
    put(17, 8, "odvvvvvvvvvvvvdo")
    put(18, 8, "odvvvvvvvvvvvvdo")
    put(19, 8, "odvvvvvvvvvvvvdo")
    put(20, 7, "ovvdvvvvvvvvvvdvvo")
    put(21, 7, "ovvdvvvvvvvvvvdvvo")
    put(22, 7, "ovvdvvvvvvvvvvdvvo")
    put(23, 8, "ovdvvvvvvvvvvdvo")
    put(24, 9, "odvvvvvvvvvvdo")
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
    # behind, showing in the gap between the legs. The band keeps the rounded
    # corners the cape was drawn with, so it runs col 10..21 and not the full
    # width, and it darkens where the hood hangs over it.
    put(12, 10, "vvddddddddvv")
    put(23, 15, "dd")
    put(24, 15, "dd")
    put(25, 15, "dd")
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
    """The sprite at 12x on a plain gradient — no scene, no chrome.

    The banner used to draw a little desktop behind the character: a panel, two
    windows, a starfield. It was a screenshot the shell had not earned, and it
    dated every time the real thing changed. A gradient dates never, and it
    leaves the character as the only thing in the frame. The 960x420 box is
    load-bearing all the same: website/scripts/sync.mjs rasterises the social
    card at exactly 2x it.
    """
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 420" width="960" height="420"
     shape-rendering="auto" role="img"
     aria-label="A hooded character in the graceful outfit, head-on, on a gradient background">
{legend(rows)}
  <defs>
    <linearGradient id="ga-bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#3c6f66"/>
      <stop offset="50%" stop-color="#27333d"/>
      <stop offset="1" stop-color="#15181d"/>
    </linearGradient>
    <radialGradient id="ga-lift" cx="50%" cy="52%" r="60%">
      <stop offset="0" stop-color="#e8f2ef" stop-opacity=".10"/>
      <stop offset="1" stop-color="#e8f2ef" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <rect width="960" height="420" fill="url(#ga-bg)"/>
  <rect width="960" height="420" fill="url(#ga-lift)"/>

  <!-- the sprite, at 12x so every pixel stays square, centred on its own
       drawn extent (cols 7..24, rows 4..28) rather than on the 32x32 grid -->
  <g transform="translate(288 12) scale(12)" shape-rendering="crispEdges">
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
