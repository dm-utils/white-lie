"""Builds the island detail atlas from code (stdlib only): one PNG, one row of seamless 128 px tiles.

The island shader (view/island.gdshader) paints the ground and water colours itself from data/palette.json
("world"); the atlas only adds detail on top, so every tile is a white/alpha overlay or a small sprite:

  slot 0  sand    speckles and tiny shells          (alpha overlay, tiles seamlessly)
  slot 1  wet     ripple lines left by the water    (alpha overlay, tiles seamlessly)
  slot 2  waves   crescent wave marks for deep water (alpha overlay, tiles seamlessly; colour-blind cue)
  slot 3  grass   a dune-grass tuft                 (coloured sprite with outline, placed per tile)

Change a number, run the script, get the atlas. Deterministic: same numbers, same bytes (CI checks this).
Output:  assets/island/atlas.png
Usage:   python -I tools/art/tiles.py            (write the atlas)
         python -I tools/art/tiles.py --check    (CI: fail if the committed atlas differs from what the script makes;
                                                  compares pixels, not bytes, because zlib output differs per platform)
"""
import json
import math
import os
import random
import struct
import sys
import zlib

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
PALETTE = json.load(open(os.path.join(ROOT, "data", "palette.json"), encoding="utf-8"))
TILE = 128
SLOTS = ["sand", "wet", "waves", "grass"]
OUT = os.path.join(ROOT, "assets", "island", "atlas.png")


def hex_rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class Canvas:
    """A premultiplied-free RGBA float canvas for one tile; 'over' blending; optional wrap-around drawing."""

    def __init__(self, wrap: bool):
        self.wrap = wrap
        self.px = [[0.0, 0.0, 0.0, 0.0] for _ in range(TILE * TILE)]

    def put(self, x: int, y: int, rgb: tuple, a: float) -> None:
        if self.wrap:
            x %= TILE
            y %= TILE
        elif not (0 <= x < TILE and 0 <= y < TILE):
            return
        if a <= 0.0:
            return
        p = self.px[y * TILE + x]
        out_a = a + p[3] * (1.0 - a)
        for i in range(3):
            p[i] = (rgb[i] * a + p[i] * p[3] * (1.0 - a)) / out_a
        p[3] = out_a

    def disc(self, cx: float, cy: float, r: float, rgb: tuple, a: float) -> None:
        """Anti-aliased filled circle."""
        for y in range(math.floor(cy - r - 1), math.ceil(cy + r + 2)):
            for x in range(math.floor(cx - r - 1), math.ceil(cx + r + 2)):
                d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                cover = min(1.0, max(0.0, r + 0.5 - d))
                self.put(x, y, rgb, a * cover)

    def stroke(self, pts: list, width: float, rgb: tuple, a: float) -> None:
        """Anti-aliased polyline with round joints (distance to each segment, max coverage per pixel)."""
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        hw = width / 2.0
        cover = {}
        for y in range(math.floor(min(ys) - hw - 1), math.ceil(max(ys) + hw + 2)):
            for x in range(math.floor(min(xs) - hw - 1), math.ceil(max(xs) + hw + 2)):
                px, py = x + 0.5, y + 0.5
                best = 1e9
                for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                    vx, vy = bx - ax, by - ay
                    t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy or 1.0)))
                    best = min(best, math.hypot(px - ax - t * vx, py - ay - t * vy))
                c = min(1.0, max(0.0, hw + 0.5 - best))
                if c > 0.0:
                    cover[(x, y)] = c
        for (x, y), c in cover.items():
            self.put(x, y, rgb, a * c)


WHITE = (255, 255, 255)
DARK = (0, 0, 0)


def sand(rng: random.Random) -> Canvas:
    c = Canvas(wrap=True)
    for _ in range(70):  # fine grain: dark and light specks
        light = rng.random() < 0.45
        c.disc(rng.uniform(0, TILE), rng.uniform(0, TILE), rng.uniform(0.8, 1.7), WHITE if light else DARK,
               0.30 if light else 0.16)
    for _ in range(3):  # a few tiny shells (styleguide: details, no photo textures)
        x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
        c.disc(x, y, 3.2, DARK, 0.22)
        c.disc(x - 0.6, y - 0.8, 2.4, WHITE, 0.75)
    return c


def wet(rng: random.Random) -> Canvas:
    c = Canvas(wrap=True)
    for row in range(5):  # ripples: gentle sine lines, periodic in x so the tile repeats
        y0 = row * TILE / 5 + rng.uniform(-4, 4)
        phase = rng.uniform(0, math.tau)
        pts = [(x, y0 + 3.0 * math.sin(phase + x / TILE * math.tau * 2)) for x in range(0, TILE + 1, 4)]
        c.stroke(pts, 2.2, DARK, 0.14)
        c.stroke([(x, y + 2.5) for x, y in pts], 1.4, WHITE, 0.18)
    return c


def waves(rng: random.Random) -> Canvas:
    c = Canvas(wrap=True)
    # staggered crescents: the deep-water pattern that tells deep from shallow without colour
    for row in range(4):
        for col in range(3):
            cx = col * TILE / 3 + (TILE / 6 if row % 2 else 0) + rng.uniform(-5, 5)
            cy = row * TILE / 4 + rng.uniform(-3, 3)
            pts = [(cx + 14 * math.cos(a), cy + 7 * math.sin(a)) for a in
                   [math.pi * (1.1 + 0.8 * i / 10) for i in range(11)]]
            c.stroke(pts, 3.0, WHITE, 0.55)
    return c


def grass(rng: random.Random) -> Canvas:
    c = Canvas(wrap=False)
    green = hex_rgb(PALETTE["world"]["grass"])
    dark = hex_rgb(PALETTE["world"]["grass_shade"])
    outline = hex_rgb(PALETTE["outline"])
    blades = []
    for i in range(7):
        base_x = 64 + (i - 3) * 7 + rng.uniform(-2, 2)
        lean = (i - 3) * 7 + rng.uniform(-5, 5)
        height = rng.uniform(48, 76)
        blades.append([(base_x, 108), (base_x + lean * 0.4, 108 - height * 0.55), (base_x + lean, 108 - height)])
    for b in blades:  # outline pass first, then colour, so the tuft reads as one shape
        c.stroke(b, 9.0, outline, 1.0)
    for i, b in enumerate(blades):
        c.stroke(b, 4.5, dark if i % 3 == 0 else green, 1.0)
    return c


BUILDERS = {"sand": sand, "wet": wet, "waves": waves, "grass": grass}


def png(width: int, height: int, rows: list) -> bytes:
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def read_png(path: str) -> tuple:
    """Decodes the PNGs this script writes (8-bit RGBA, filter 0); returns (width, height, rows)."""
    data = open(path, "rb").read()
    pos, idat, width, height = 8, b"", 0, 0
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            width, height = struct.unpack(">II", body[:8])
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    raw = zlib.decompress(idat)
    stride = width * 4 + 1
    return width, height, [list(raw[y * stride + 1:(y + 1) * stride]) for y in range(height)]


def render() -> tuple:
    tiles = [BUILDERS[name](random.Random(1000 + i)) for i, name in enumerate(SLOTS)]
    width = TILE * len(SLOTS)
    rows = []
    for y in range(TILE):
        row = []
        for t in tiles:
            for x in range(TILE):
                p = t.px[y * TILE + x]
                row += [round(p[0]), round(p[1]), round(p[2]), round(p[3] * 255)]
        rows.append(row)
    return width, TILE, rows


def main() -> None:
    width, height, rows = render()
    if "--check" in sys.argv:
        w, h, old = read_png(OUT)
        worst = max((abs(a - b) for r1, r2 in zip(rows, old) for a, b in zip(r1, r2)), default=0)
        if (w, h) != (width, height) or worst > 1:
            sys.exit(f"atlas.png is out of date (size {w}x{h}, max pixel difference {worst}): run tools/art/tiles.py")
        print(f"atlas: up to date ({width} x {height})")
        return
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as fh:
        fh.write(png(width, height, rows))
    print(f"atlas: {width} x {height}, slots {', '.join(SLOTS)}")


if __name__ == "__main__":
    main()
