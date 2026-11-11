"""Generates data/sin_table.json: fixed tables so the sim never calls sin/atan at run time.

Angles are 0..4095 (a full turn). sin[i] = round(sin(2*pi*i/4096) * 1024).
atan[r] for r in 0..1024 = round(atan(r/1024) * 4096 / (2*pi)), used by the integer atan2 (first octant).
Run once; the JSON is committed. Same table in GDScript now and in the C++ port later.
Usage: python -I tools/gen_sin_table.py
"""
import json
import math
import os

N = 4096
ONE = 1024
sin = [round(math.sin(2 * math.pi * i / N) * ONE) for i in range(N)]
atan = [round(math.atan(r / ONE) * N / (2 * math.pi)) for r in range(ONE + 1)]
out = {"angles": N, "one": ONE, "sin": sin, "atan": atan}
path = os.path.join(os.path.dirname(__file__), "..", "data", "sin_table.json")
with open(path, "w", encoding="utf-8", newline="\n") as fh:
    json.dump(out, fh, separators=(",", ":"))
    fh.write("\n")
print("wrote", os.path.normpath(path), len(sin), "sin,", len(atan), "atan")
