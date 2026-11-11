"""Generates the harbour map (data/maps/haven.json) from a fixed seed: tile kinds, props in small groups, spawns.

Tile kinds: 0 sea (wall), 1 shallow water, 2 sand, 3 dock (wood), 4 quay (stone), 5 building (wall).
Props stand where their kind fits (data/props.json "on"); every prop kind appears in several groups, so a hider
always has look-alikes to stand next to. The output is committed; the game never generates maps at run time.
Usage: python -I tools/gen_haven.py
"""
import json
import os
import random

W, H = 40, 26
SEED = 4711
ROOT = os.path.join(os.path.dirname(__file__), "..")


def tiles() -> list:
    t = [[4] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if y <= 3 or x <= 1 or x >= W - 2:
                t[y][x] = 0
            elif y <= 7:
                t[y][x] = 1
            elif y <= 10:
                t[y][x] = 3 if 4 <= x <= W - 5 else 1
            elif y >= 19:
                t[y][x] = 2
    for px in (8, 18, 28):  # piers out over the water
        for y in range(3, 8):
            for x in (px, px + 1):
                t[y][x] = 3
    for x0, y0, x1, y1 in [(6, 13, 9, 15), (15, 14, 19, 17), (25, 13, 29, 15), (32, 16, 37, 18)]:  # sheds + the office
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                t[y][x] = 5
    for y in range(22, H):  # a tidal pool and the shore at the bottom
        for x in range(2, W - 2):
            if y == H - 1 or (11 <= x <= 15 and y >= 23):
                t[y][x] = 1
    return t


def props(t: list, kinds: dict) -> list:
    rnd = random.Random(SEED)
    out = []

    def free(x, y):
        return all((p[1] - x) ** 2 + (p[2] - y) ** 2 >= 1.4 ** 2 for p in out)

    names = sorted(kinds)
    for _ in range(4):  # rounds over every kind -> groups of 2-4 of each kind, spread over the harbour
        for kind in names:
            allowed = kinds[kind]["on"]
            for _try in range(200):
                cx, cy = rnd.uniform(3, W - 3), rnd.uniform(4, H - 2)
                if t[int(cy)][int(cx)] in allowed:
                    break
            n = rnd.randint(2, 3)
            for _k in range(n * 6):
                if n == 0:
                    break
                x, y = cx + rnd.uniform(-2.2, 2.2), cy + rnd.uniform(-1.6, 1.6)
                if 2 <= x < W - 2 and 2 <= y < H and t[int(y)][int(x)] in allowed and free(x, y):
                    out.append([kind, round(x, 2), round(y, 2)])
                    n -= 1
    return [{"kind": k, "x": int(x * 1000), "y": int(y * 1000)} for k, x, y in out]


def main() -> None:
    kinds = json.load(open(os.path.join(ROOT, "data", "props.json"), encoding="utf-8"))["kinds"]
    t = tiles()
    data = {
        "name": "haven", "width": W, "height": H, "seed": SEED,
        "_kinds": "0 sea (wall), 1 shallow, 2 sand, 3 dock, 4 quay, 5 building (wall)",
        "tiles": [v for row in t for v in row],
        "props": props(t, kinds),
        "hider_spawns": [[12, 12], [21, 12], [12, 19], [24, 19]],
        "seeker_spawns": [[34, 20], [36, 20]],
    }
    path = os.path.join(ROOT, "data", "maps", "haven.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, separators=(",", ":"))
        fh.write("\n")
    print("wrote", os.path.normpath(path), "props", len(data["props"]))
    for row in t:
        print("".join(" ~.=#X"[v] if v else "~" for v in row))


if __name__ == "__main__":
    main()
