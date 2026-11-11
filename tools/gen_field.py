"""Generates the Strandbal field (data/islands/strand.json): a beach pitch with two goals.

Heights 0..9 per tile, as in gen_island.py. The pitch is high along its long centre line and slopes down to both
side lines, so the rising tide floods the sides first and the field gets narrower (phase 14). Along its length the
pitch is flat, so neither half is better. Behind each goal line a dry goal box; around everything open sea.
Extra keys for the ball mode: field [x0, y0, x1, y1] (tiles, x1/y1 exclusive), goal [y0, y1] (the mouth, tiles,
y1 exclusive) and team_spawns [[left team x3], [right team x3]].
Usage: python -I tools/gen_field.py
"""
import json
import os

W, H = 44, 26
X0, Y0, X1, Y1 = 4, 3, 40, 23  # the pitch: 36 x 20 tiles
MOUTH = (9, 17)  # 8 tiles wide, centred
CY = (Y0 + Y1) / 2  # 13.0


def height(x: int, y: int) -> int:
    inside = X0 <= x < X1 and Y0 <= y < Y1
    box = (X0 - 3 <= x < X0 or X1 <= x < X1 + 3) and MOUTH[0] - 1 <= y < MOUTH[1] + 1
    d = abs(y + 0.5 - CY)
    if inside or box:
        return max(2, min(9, round(9 - d * 0.72)))
    # a strip of shallow sand around the pitch, then sea
    near = X0 - 2 <= x < X1 + 2 and Y0 - 1 <= y < Y1 + 1
    return 1 if near else 0


def generate() -> dict:
    heights = [height(x, y) for y in range(H) for x in range(W)]
    left = [[X0 + 6, 9], [X0 + 10, 13], [X0 + 6, 17]]
    right = [[X1 - 1 - (x - X0), y] for x, y in left]
    spawns = left + right
    snack_spots = [[x, y] for y in range(Y0 + 1, Y1 - 1) for x in range(X0 + 2, X1 - 2)
                   if (x - X0) % 6 == 3 and (y - Y0) % 4 == 2 and abs(x + 0.5 - (X0 + X1) / 2) > 4]
    return {"name": "strand", "width": W, "height": H, "heights": heights, "spawns": spawns,
            "snack_spots": snack_spots, "seed": 0, "field": [X0, Y0, X1, Y1], "goal": list(MOUTH),
            "team_spawns": [left, right]}


def main() -> None:
    path = os.path.join(os.path.dirname(__file__), "..", "data", "islands", "strand.json")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(generate(), fh, separators=(",", ":"))
        fh.write("\n")
    print("wrote", os.path.normpath(path))


if __name__ == "__main__":
    main()
