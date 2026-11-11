"""Builds the White Lie characters as SVGs (stdlib only): one file per character in assets/people/, the same style
as the props (thick ink outline, flat colours, one highlight). The view bobs and tilts them while walking.

Every SVG is 200 x 240 with the feet at (100, 200): the view places that point on the character's position.
Colours come from data/characters.json (shirt) so a character's colour matches its HUD colour.
Usage: python -I tools/art/people.py
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "people")
INK = "#2B3A4A"
SKIN = "#F2C9A0"
S = f'stroke="{INK}" stroke-width="7" stroke-linejoin="round" stroke-linecap="round"'


def darker(hex_color: str, f: float = 0.75) -> str:
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return "#%02X%02X%02X" % (int(r * f), int(g * f), int(b * f))


def body(shirt: str) -> list:
    return [
        '<ellipse cx="100" cy="200" rx="44" ry="11" fill="#000" opacity="0.18"/>',
        f'<rect x="78" y="160" width="18" height="38" rx="8" fill="{INK}"/>',  # legs
        f'<rect x="104" y="160" width="18" height="38" rx="8" fill="{INK}"/>',
        f'<rect x="66" y="104" width="68" height="66" rx="20" fill="{shirt}" {S}/>',  # torso
        f'<rect x="50" y="112" width="20" height="44" rx="10" fill="{shirt}" {S}/>',  # arms
        f'<rect x="130" y="112" width="20" height="44" rx="10" fill="{shirt}" {S}/>',
        f'<circle cx="100" cy="76" r="32" fill="{SKIN}" {S}/>',  # head
        f'<circle cx="90" cy="76" r="4.5" fill="{INK}"/><circle cx="112" cy="76" r="4.5" fill="{INK}"/>',
        f'<path d="M92 92 Q101 99 110 92" fill="none" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>',
        '<circle cx="80" cy="64" r="6" fill="#FFFFFF" opacity="0.5"/>',
    ]


HATS = {
    # captain's cap with a white top and a dark peak
    "skipper": lambda c: [f'<path d="M66 60 Q100 26 134 60 Z" fill="#FFFFFF" {S}/>',
                          f'<rect x="62" y="56" width="76" height="12" rx="6" fill="{darker(c, 0.6)}" {S}/>'],
    # fisher's sou'wester: a wide yellow rain hat
    "fisher": lambda c: [f'<path d="M58 66 Q100 18 142 66 Q100 58 58 66 Z" fill="#FFD23F" {S}/>'],
    # kid: a cap turned backwards in the shirt colour
    "kid": lambda c: [f'<path d="M70 58 Q100 30 130 58 Z" fill="{darker(c)}" {S}/>',
                      f'<rect x="120" y="52" width="26" height="9" rx="4" fill="{darker(c)}" {S}/>'],
}


def main() -> None:
    chars = json.load(open(os.path.join(ROOT, "data", "characters.json"), encoding="utf-8"))["characters"]
    os.makedirs(OUT, exist_ok=True)
    for c in chars:
        shirt = "#" + c["color"]
        parts = body(shirt) + HATS.get(c["id"], lambda _: [])(shirt)
        svg = '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="240" viewBox="0 0 200 240">' + "".join(parts) + "</svg>\n"
        with open(os.path.join(OUT, f"{c['id']}.svg"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(svg)
    print("wrote", len(chars), "characters to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
