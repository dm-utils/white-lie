"""Builds the cutout animals from code: one SVG per part plus a rig file (stdlib only).

Change a number, run the script, get the animal. Part names are stable (game code binds to them):
body, head, eye_l, eye_r, mouth, claw_l, claw_r, limb_fl, limb_fr, limb_bl, limb_br, tail, accessory.
Every part is drawn in the same 200 x 200 animal space, so a part's pivot is simply a point in that space.
Each part's SVG is then cropped to its own bounds (viewBox) and the rig records where that box sits ("box"),
so an eye costs an eye's worth of texture, not a whole canvas (budget: one animal <= 1024 x 1024).
Colours come from data/palette.json; a look (skin) is the same parts with another palette.

Output:  assets/animals/<id>/<part>.svg   and   data/rigs/<id>.json
Usage:   python -I tools/art/animals.py
"""
import json
import math
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
PALETTE = json.load(open(os.path.join(ROOT, "data", "palette.json"), encoding="utf-8"))
SIZE = 200
ORIGIN = (100, 172)  # the animal's feet: where it stands on the ground
STROKE = 7  # thick outline (styleguide: animals pop from the island)


def svg(body: str, box: tuple) -> str:
    x, y, w, h = box
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{x} {y} {w} {h}">'
            f'<g stroke-linejoin="round" stroke-linecap="round">{body}</g></svg>\n')


def _attr(el: str, name: str, default: float = 0.0) -> float:
    m = re.search(rf'\b{name}="(-?[\d.]+)"', el)
    return float(m.group(1)) if m else default


def _path_points(d: str) -> list:
    """Every point a path visits plus its control points (a curve stays inside them); arcs as their radius box."""
    pts, x, y, sx, sy = [], 0.0, 0.0, 0.0, 0.0
    for cmd, args in re.findall(r"([MLQAZmlqaz])([^MLQAZmlqaz]*)", d):
        n = [float(v) for v in re.findall(r"-?[\d.]+", args)]
        if cmd in "Zz":
            x, y = sx, sy
            continue
        step = {"M": 2, "L": 2, "Q": 4, "A": 7}[cmd.upper()]
        rel = cmd.islower()
        for i in range(0, len(n), step):
            a = n[i:i + step]
            if cmd.upper() == "A":
                ex, ey = (x + a[5], y + a[6]) if rel else (a[5], a[6])
                r = max(a[0], a[1])
                pts += [(x - r, y - r), (x + r, y + r), (ex - r, ey - r), (ex + r, ey + r)]
                x, y = ex, ey
                continue
            coords = [(a[j] + (x if rel else 0), a[j + 1] + (y if rel else 0)) for j in range(0, step, 2)]
            pts += coords
            x, y = coords[-1]
            if cmd.upper() == "M" and i == 0:
                sx, sy = x, y
    return pts


def bounds(body: str) -> tuple:
    """Integer box (x, y, w, h) around everything in a part, strokes included, plus a 2-unit margin."""
    lo_x = lo_y = 1e9
    hi_x = hi_y = -1e9
    for el in re.findall(r"<(?:ellipse|circle|path)[^>]*>", body):
        half = _attr(el, "stroke-width") / 2 if "stroke=" in el else 0.0
        if el.startswith("<path"):
            pts = _path_points(re.search(r'\bd="([^"]+)"', el).group(1))
        else:
            cx, cy = _attr(el, "cx"), _attr(el, "cy")
            rx = _attr(el, "r") if el.startswith("<circle") else _attr(el, "rx")
            ry = _attr(el, "r") if el.startswith("<circle") else _attr(el, "ry")
            pts = [(cx - rx, cy - ry), (cx + rx, cy + ry)]
        for px, py in pts:
            lo_x, lo_y = min(lo_x, px - half), min(lo_y, py - half)
            hi_x, hi_y = max(hi_x, px + half), max(hi_y, py + half)
    x0, y0 = math.floor(lo_x) - 2, math.floor(lo_y) - 2
    return x0, y0, math.ceil(hi_x) + 2 - x0, math.ceil(hi_y) + 2 - y0


def eye(x, y, r, look=(2, 1)):
    o, w, p = PALETTE["outline"], PALETTE["eye"], PALETTE["pupil"]
    return (f'<circle cx="{x}" cy="{y}" r="{r}" fill="{w}" stroke="{o}" stroke-width="{STROKE * 0.7:.1f}"/>'
            f'<circle cx="{x + look[0]}" cy="{y + look[1]}" r="{r * 0.48:.1f}" fill="{p}"/>'
            f'<circle cx="{x + look[0] - r * 0.25:.1f}" cy="{y + look[1] - r * 0.25:.1f}" r="{r * 0.14:.1f}" fill="#fff"/>')


def crab(c):
    o = PALETTE["outline"]
    legs = lambda side: "".join(
        f'<path d="M{100 + side * dx} {124 + i * 10} L{100 + side * (dx + 34)} {150 + i * 14}" stroke="{o}" stroke-width="{STROKE}" fill="none"/>'
        for i, dx in enumerate((48, 42)))
    claw = lambda side: (
        f'<path d="M{100 + side * 50} 112 L{100 + side * 66} 86" stroke="{o}" stroke-width="{STROKE}" fill="none"/>'
        f'<path d="M{100 + side * 70} 50 a26 26 0 1 {1 if side > 0 else 0} 0 52 l{-side * 6} -14 a12 12 0 1 {0 if side > 0 else 1} 0 -24 z" '
        f'fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>')
    stalk = lambda x: f'<path d="M{x} 92 L{x} 62" stroke="{o}" stroke-width="{STROKE}" fill="none"/>' + eye(x, 54, 14)
    return {
        "limb_bl": (legs(-1), (54, 128), -2),
        "limb_br": (legs(1), (146, 128), -2),
        "body": (f'<ellipse cx="100" cy="122" rx="64" ry="44" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="100" cy="136" rx="44" ry="18" fill="{c["shade"]}"/>'
                 f'<circle cx="74" cy="106" r="6" fill="{c["accent"]}"/><circle cx="128" cy="102" r="4" fill="{c["accent"]}"/>', (100, 160), 0),
        "eye_l": (stalk(84), (84, 94), 1),
        "eye_r": (stalk(116), (116, 94), 1),
        "mouth": (f'<path d="M88 128 Q100 138 112 128" stroke="{o}" stroke-width="{STROKE * 0.7:.1f}" fill="none"/>', (100, 130), 1),
        "claw_l": (claw(-1), (50, 112), 2),
        "claw_r": (claw(1), (150, 112), 2),
    }


def octopus(c):
    o = PALETTE["outline"]

    def tentacle(x0, bend):
        d = f"M{x0} 118 Q{x0 + bend} 150 {x0 + bend * 0.4:.0f} 176"
        return (f'<path d="{d}" stroke="{o}" stroke-width="{STROKE + 16}" fill="none"/>'
                f'<path d="{d}" stroke="{c["base"]}" stroke-width="16" fill="none"/>')
    return {
        "limb_bl": (tentacle(64, -22), (64, 118), -2),
        "limb_br": (tentacle(136, 22), (136, 118), -2),
        "limb_fl": (tentacle(88, -10), (88, 122), -1),
        "limb_fr": (tentacle(112, 10), (112, 122), -1),
        "body": (f'<ellipse cx="100" cy="86" rx="62" ry="58" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="100" cy="112" rx="44" ry="18" fill="{c["shade"]}"/>'
                 f'<circle cx="72" cy="56" r="8" fill="{c["accent"]}"/><circle cx="126" cy="48" r="5" fill="{c["accent"]}"/>', (100, 140), 0),
        "eye_l": (eye(82, 88, 15), (82, 88), 1),
        "eye_r": (eye(118, 88, 15), (118, 88), 1),
        "mouth": (f'<path d="M90 114 Q100 122 110 114" stroke="{o}" stroke-width="{STROKE * 0.7:.1f}" fill="none"/>', (100, 116), 1),
    }


def gull(c):
    o = PALETTE["outline"]
    leg = lambda x: (f'<path d="M{x} 150 L{x - 2} 172" stroke="{c["legs"]}" stroke-width="{STROKE}" fill="none"/>'
                     f'<path d="M{x - 12} 174 L{x + 8} 174" stroke="{c["legs"]}" stroke-width="{STROKE}" fill="none"/>')
    return {
        "limb_bl": (leg(86), (86, 150), -2),
        "limb_br": (leg(108), (108, 150), -2),
        "tail": (f'<path d="M58 118 L24 104 L32 134 Z" fill="{c["accent"]}" stroke="{o}" stroke-width="{STROKE}"/>', (58, 122), -1),
        "body": (f'<ellipse cx="94" cy="124" rx="54" ry="40" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="96" cy="140" rx="34" ry="14" fill="{c["shade"]}"/>', (94, 162), 0),
        "limb_fl": (f'<path d="M64 112 Q96 92 128 120 Q100 140 64 130 Z" fill="{c["accent"]}" stroke="{o}" stroke-width="{STROKE}"/>', (70, 116), 1),
        "head": (f'<circle cx="132" cy="80" r="32" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>', (124, 108), 2),
        "accessory": (f'<path d="M156 74 L192 84 L156 94 Z" fill="{c["beak"]}" stroke="{o}" stroke-width="{STROKE}"/>', (156, 84), 3),
        "eye_r": (eye(140, 72, 10, (2, 0)), (140, 72), 3),
    }


BUILDERS = {"crab": crab, "octopus": octopus, "gull": gull}
# every part hangs from the body unless listed here (the gull's eye and beak move with its head)
PARENTS = {"gull": {"accessory": "head", "eye_r": "head"}}


def build(animal: str, colours: dict, folder: str) -> list:
    parts = BUILDERS[animal](colours)
    os.makedirs(folder, exist_ok=True)
    rig = []
    for name, (body, pivot, z) in parts.items():
        box = bounds(body)
        with open(os.path.join(folder, f"{name}.svg"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(svg(body, box))
        parent = "" if name == "body" else PARENTS.get(animal, {}).get(name, "body")
        rig.append({"name": name, "pivot": list(pivot), "parent": parent, "z": z, "box": list(box)})
    return rig


def main() -> None:
    for animal in BUILDERS:
        folder = os.path.join(ROOT, "assets", "animals", animal)
        rig = build(animal, PALETTE["animals"][animal], folder)
        with open(os.path.join(ROOT, "data", "rigs", f"{animal}.json"), "w", encoding="utf-8", newline="\n") as fh:
            json.dump({"id": animal, "size": SIZE, "origin": list(ORIGIN), "parts": rig}, fh, indent=2)
            fh.write("\n")
        print(f"{animal}: {len(rig)} parts")
    for look, colours in PALETTE["looks"].items():
        animal = colours["animal"]
        merged = {**PALETTE["animals"][animal], **{k: v for k, v in colours.items() if k != "animal"}}
        build(animal, merged, os.path.join(ROOT, "assets", "looks", look))
        print(f"look {look}: parts recoloured")


if __name__ == "__main__":
    main()
