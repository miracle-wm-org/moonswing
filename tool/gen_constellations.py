"""Regenerate the figure table in lib/astrology/constellation.dart.

Run offline, by hand, and only when the table needs to change — the shell has
no Python at run time and nothing in the build calls this.

    curl -o /tmp/cl.json https://raw.githubusercontent.com/ofrohn/d3-celestial/master/data/constellations.lines.json
    curl -o /tmp/stars.json https://raw.githubusercontent.com/ofrohn/d3-celestial/master/data/stars.6.json
    python3 tool/gen_constellations.py      # writes /tmp/figures.dart

Both inputs are d3-celestial's (Olaf Frohn, BSD-3-Clause), whose own sources are
the Hipparcos and Yale Bright Star catalogues. The output is the `_figures`
literal, pasted under the hand-written half of constellation.dart.

What it does: takes each zodiac constellation's stick figure, looks up the
catalogued magnitude of the star at every vertex, projects the vertices onto a
tangent plane about the figure's centroid (RA flipped, since it grows eastward
and a sky chart puts east to the left; declination flipped, since north is up
and a canvas grows downward), and scales *both axes by one factor* into the unit
box so nothing is stretched.
"""
import json, math

Z = [("Ari","Aries"),("Tau","Taurus"),("Gem","Gemini"),("Cnc","Cancer"),
     ("Leo","Leo"),("Vir","Virgo"),("Lib","Libra"),("Sco","Scorpius"),
     ("Sgr","Sagittarius"),("Cap","Capricornus"),("Aqr","Aquarius"),
     ("Psc","Pisces")]

lines = {f["id"]: f["geometry"]["coordinates"]
         for f in json.load(open("/tmp/cl.json"))["features"]}
stars = [(f["geometry"]["coordinates"][0], f["geometry"]["coordinates"][1],
          f["properties"]["mag"])
         for f in json.load(open("/tmp/stars.json"))["features"]]

def unwrap(segs):
    """RA is in [-180,180]; a constellation straddling 0h needs one branch."""
    ras = [p[0] for s in segs for p in s]
    if max(ras) - min(ras) > 180:
        return [[[p[0] + 360 if p[0] < 0 else p[0], p[1]] for p in s] for s in segs]
    return [[list(p) for p in s] for s in segs]

def magnitude(ra, dec):
    """The catalogued magnitude of the star at this vertex."""
    best, bestd = None, 1e9
    for sra, sdec, mag in stars:
        d = (ra - sra) ** 2 + (dec - sdec) ** 2
        if d < bestd:
            best, bestd = mag, d
    return best if bestd < 0.02 ** 2 else None

out = []
for code, name in Z:
    segs = unwrap(lines[code])
    pts = [p for s in segs for p in s]
    ra0 = sum(p[0] for p in pts) / len(pts)
    dec0 = sum(p[1] for p in pts) / len(pts)
    k = math.cos(math.radians(dec0))

    def project(p):
        # Small-field tangent plane. RA grows eastward, which is leftward on a
        # sky chart, and declination grows upward, which is -y on a canvas.
        return (-(p[0] - ra0) * k, -(p[1] - dec0))

    proj = [project(p) for p in pts]
    xs, ys = [p[0] for p in proj], [p[1] for p in proj]
    spanx, spany = max(xs) - min(xs), max(ys) - min(ys)
    scale = 1.0 / max(spanx, spany)
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2

    def unit(p):
        x, y = project(p)
        return (round((x - cx) * scale + 0.5, 4), round((y - cy) * scale + 0.5, 4))

    # One index per distinct star, so a vertex shared by two segments is one dot.
    index, order = {}, []
    for p in pts:
        key = (round(p[0], 4), round(p[1], 4))
        if key not in index:
            index[key] = len(order)
            order.append(p)
    stars_out = []
    for p in order:
        x, y = unit(p)
        mag = magnitude(p[0] if p[0] <= 180 else p[0] - 360, p[1])
        stars_out.append((x, y, mag))
    segs_out = []
    for s in segs:
        segs_out.append([index[(round(p[0], 4), round(p[1], 4))] for p in s])

    out.append((code, name, stars_out, segs_out, spanx / spany))

for code, name, st, sg, aspect in out:
    unmatched = sum(1 for s in st if s[2] is None)
    print(f"// {name:<12} {len(st):>2} stars, {len(sg)} segments, "
          f"aspect {aspect:.2f}, unmatched {unmatched}")

NAMES = {"Ari":"Aries","Tau":"Taurus","Gem":"Gemini","Cnc":"Cancer","Leo":"Leo",
         "Vir":"Virgo","Lib":"Libra","Sco":"Scorpius","Sgr":"Sagittarius",
         "Cap":"Capricornus","Aqr":"Aquarius","Psc":"Pisces"}

body = []
for code, name, st, sg, aspect in out:
    body.append(f"  '{code}': Constellation(")
    body.append(f"    code: '{code}',")
    body.append(f"    name: '{NAMES[code]}',")
    body.append("    stars: [")
    for x, y, mag in st:
        body.append(f"      ConstellationStar({x}, {y}, {mag}),")
    body.append("    ],")
    body.append("    lines: [")
    for seg in sg:
        body.append("      [" + ", ".join(str(i) for i in seg) + "],")
    body.append("    ],")
    body.append("  ),")
with open("/tmp/figures.dart", "w") as f:
    f.write("\n".join(body) + "\n")
print("emitted", len(body), "lines")
