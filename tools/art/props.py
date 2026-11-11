"""Builds the harbour props as SVGs (stdlib only): one file per kind in assets/props/, same style as the animals
(thick ink outline, flat colours, one highlight). A hider who becomes a prop is drawn with exactly the same file,
so a disguise is pixel-identical to the real thing.

Every SVG is 200 x 200 with the prop's foot point at (100, 150): the view places it at the prop's position.
Usage: python -I tools/art/props.py
"""
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "props")
INK = "#2B3A4A"
S = 'stroke="%s" stroke-width="7" stroke-linejoin="round" stroke-linecap="round"' % INK


def shadow() -> str:
    return '<ellipse cx="100" cy="150" rx="46" ry="12" fill="#000" opacity="0.18"/>'


PROPS = {
    "barrel": [
        f'<rect x="64" y="62" width="72" height="86" rx="18" fill="#B5703A" {S}/>',
        f'<path d="M64 84 H136 M64 126 H136" fill="none" {S}/>',
        '<rect x="76" y="70" width="10" height="70" rx="5" fill="#D9925A"/>',
    ],
    "crate": [
        f'<rect x="58" y="66" width="84" height="82" rx="6" fill="#D6A55E" {S}/>',
        f'<path d="M58 66 L142 148 M142 66 L58 148" fill="none" {S}/>',
        '<rect x="64" y="72" width="16" height="8" rx="3" fill="#F0C987"/>',
    ],
    "buoy": [
        f'<path d="M100 60 L100 80" fill="none" {S}/>',
        f'<circle cx="100" cy="60" r="8" fill="#FFD23F" {S}/>',
        f'<ellipse cx="100" cy="116" rx="40" ry="36" fill="#E8503A" {S}/>',
        f'<path d="M62 112 Q100 128 138 112" fill="none" stroke="#FFFFFF" stroke-width="12"/>',
        '<circle cx="84" cy="98" r="7" fill="#FF9B8A"/>',
    ],
    "net": [
        f'<path d="M52 140 Q60 92 100 86 Q140 92 148 140 Z" fill="#7FA88C" {S}/>',
        f'<path d="M66 128 L134 128 M72 112 L128 112 M100 88 L100 140 M80 92 L72 140 M120 92 L128 140" fill="none" stroke="{INK}" stroke-width="3.5"/>',
        f'<circle cx="60" cy="140" r="6" fill="#FFD23F" {S}/>',
    ],
    "anchor": [
        f'<circle cx="100" cy="66" r="12" fill="none" {S}/>',
        f'<path d="M100 78 L100 140 M80 96 H120 M64 118 Q70 146 100 146 Q130 146 136 118" fill="none" stroke="{INK}" stroke-width="16" stroke-linecap="round"/>',
        '<path d="M100 78 L100 140 M80 96 H120 M64 118 Q70 146 100 146 Q130 146 136 118" fill="none" stroke="#8A97A6" stroke-width="7" stroke-linecap="round"/>',
    ],
    "pot": [
        f'<path d="M60 146 L60 100 Q100 62 140 100 L140 146 Z" fill="#C7955C" {S}/>',
        f'<path d="M60 120 H140 M80 82 L80 146 M100 76 L100 146 M120 82 L120 146" fill="none" stroke="{INK}" stroke-width="3.5"/>',
        f'<ellipse cx="100" cy="116" rx="12" ry="10" fill="#2B3A4A"/>',
    ],
    "rope": [
        f'<ellipse cx="100" cy="124" rx="44" ry="26" fill="#E2C28A" {S}/>',
        f'<ellipse cx="100" cy="118" rx="28" ry="15" fill="none" stroke="{INK}" stroke-width="4"/>',
        f'<ellipse cx="100" cy="114" rx="12" ry="6" fill="#B8955C" stroke="{INK}" stroke-width="4"/>',
        f'<path d="M140 132 Q156 140 150 150" fill="none" {S}/>',
    ],
    "bollard": [
        f'<rect x="78" y="82" width="44" height="66" rx="10" fill="#3D4A5A" {S}/>',
        f'<ellipse cx="100" cy="82" rx="30" ry="12" fill="#55657A" {S}/>',
        '<rect x="86" y="96" width="8" height="40" rx="4" fill="#6E8198"/>',
    ],
}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for kind, parts in PROPS.items():
        svg = '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 200 200">' + shadow() + "".join(parts) + "</svg>\n"
        with open(os.path.join(OUT, f"{kind}.svg"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(svg)
    print("wrote", len(PROPS), "props to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
