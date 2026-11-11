"""Generates an island heightmap as data (data/islands/<name>.json) from a fixed seed.

Heights 0..9 per tile. A tile is underwater when tide level > height (level - height = 1 shallow, >= 2 deep).
Rounded hills, a few tide pools and one high point so the final phase always leaves a small dry hill.
The output is committed; the game never generates islands at run time (content is data).
Usage: python -I tools/gen_island.py cove 1234
"""
import json
import math
import os
import random
import sys

W, H = 40, 30


def generate(seed: int) -> dict:
    rnd = random.Random(seed)
    a, b, c = (rnd.random() * 6 for _ in range(3))
    pools = []
    for _ in range(5):
        ang, d = rnd.random() * 6.28, 0.25 + rnd.random() * 0.4
        pools.append((W / 2 + math.cos(ang) * d * W / 2, H / 2 + math.sin(ang) * d * H / 2, 2 + rnd.random() * 1.5))
    hill = (W / 2 + (rnd.random() - 0.5) * 8, H / 2 + (rnd.random() - 0.5) * 6)
    heights = []
    for y in range(H):
        for x in range(W):
            nx, ny = (x + 0.5) / W * 2 - 1, (y + 0.5) / H * 2 - 1
            d = math.sqrt(nx * nx + ny * ny)
            v = 9.5 * (1 - d) + math.sin(x * 0.45 + a) * math.cos(y * 0.5 + b) * 1.1 + math.sin((x + y) * 0.27 + c) * 0.8
            for px, py, pr in pools:
                dd = math.hypot(x - px, y - py)
                if dd < pr:
                    v -= 2.6 * (1 - dd / pr)
            dh = math.hypot(x - hill[0], y - hill[1])
            if dh < 6:
                v += 3 * (1 - dh / 6)
            heights.append(max(0, min(9, round(v))))
    # exactly one summit area with height 9 guaranteed
    hx, hy = round(hill[0]), round(hill[1])
    for y in range(hy - 1, hy + 2):
        for x in range(hx - 1, hx + 2):
            heights[y * W + x] = 9
    # spawn points: 6 dry spots on a ring, height >= 4
    spawns = []
    for i in range(6):
        ang = i / 6 * math.tau + 0.3
        for r in [x / 100 for x in range(65, 10, -3)]:
            x, y = int(W / 2 + math.cos(ang) * r * W / 2), int(H / 2 + math.sin(ang) * r * H / 2)
            if heights[y * W + x] >= 4:
                spawns.append([x, y])
                break
    snack_spots = [[x, y] for y in range(2, H - 2) for x in range(2, W - 2) if heights[y * W + x] >= 3 and (x * 7 + y * 13) % 11 == 0]
    return {"name": "", "width": W, "height": H, "heights": heights, "spawns": spawns, "snack_spots": snack_spots, "seed": seed}


def main() -> None:
    name, seed = sys.argv[1], int(sys.argv[2])
    island = generate(seed)
    island["name"] = name
    path = os.path.join(os.path.dirname(__file__), "..", "data", "islands", f"{name}.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(island, fh, separators=(",", ":"))
        fh.write("\n")
    print("wrote", os.path.normpath(path), "spawns", len(island["spawns"]), "snack spots", len(island["snack_spots"]))


if __name__ == "__main__":
    main()
