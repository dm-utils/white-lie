"""Art and size budgets as a CI check (styleguide section 10). Fails when something grows past its budget.

  island tile set   every image in assets/island/        <= 2048 x 2048
  animal            all parts of one animal or look       <= 1024 x 1024 in area (parts at their import scale)
  shaders           .gdshader files + inline shader code  <= 3 (water, glint, hit flash)
  web download      what a player downloads at the start  <= 30 MB (the .br file when CI made one)

Usage: python -I tools/check_budgets.py [build/web]
"""
import glob
import os
import re
import struct
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
ISLAND_MAX = 2048
ANIMAL_AREA_MAX = 1024 * 1024
SHADERS_MAX = 3
WEB_MAX_MB = 30.0


def png_size(path: str) -> tuple:
    with open(path, "rb") as fh:
        head = fh.read(24)
    return struct.unpack(">II", head[16:24])


def svg_size(path: str) -> tuple:
    text = open(path, encoding="utf-8").read(400)
    w = re.search(r'\bwidth="([\d.]+)"', text)
    h = re.search(r'\bheight="([\d.]+)"', text)
    return float(w.group(1)), float(h.group(1))


def import_scale(path: str) -> float:
    imp = path + ".import"
    if os.path.exists(imp):
        m = re.search(r"^svg/scale=([\d.]+)", open(imp, encoding="utf-8").read(), re.M)
        if m:
            return float(m.group(1))
    return 1.0


def main() -> None:
    rows, failures = [], []

    def check(what: str, value: float, limit: float, unit: str = "") -> None:
        ok = value <= limit
        rows.append(f"| {what} | {value:g}{unit} | {limit:g}{unit} | {'ok' if ok else 'OVER'} |")
        if not ok:
            failures.append(f"{what}: {value:g}{unit} > {limit:g}{unit}")

    for png in sorted(glob.glob(os.path.join(ROOT, "assets", "island", "*.png"))):
        w, h = png_size(png)
        check(f"island {os.path.basename(png)} (longest side)", max(w, h), ISLAND_MAX, " px")

    for folder in sorted(glob.glob(os.path.join(ROOT, "assets", "animals", "*")) +
                         glob.glob(os.path.join(ROOT, "assets", "looks", "*"))):
        area = 0.0
        for svg in glob.glob(os.path.join(folder, "*.svg")):
            w, h = svg_size(svg)
            s = import_scale(svg)
            area += w * s * h * s
        name = os.path.relpath(folder, os.path.join(ROOT, "assets")).replace(os.sep, "/")
        check(f"{name} (parts, as a square)", round(area ** 0.5), ANIMAL_AREA_MAX ** 0.5, " px")

    shaders = glob.glob(os.path.join(ROOT, "**", "*.gdshader"), recursive=True)
    inline = 0
    for ext in ("tscn", "tres", "gd"):
        for f in glob.glob(os.path.join(ROOT, "**", f"*.{ext}"), recursive=True):
            if os.sep + "build" + os.sep in f or os.sep + "." in f or f.endswith("check_budgets.py"):
                continue
            inline += len(re.findall(r'"shader_type |\bshader_type (canvas_item|spatial|particles)\b',
                                     open(f, encoding="utf-8", errors="ignore").read()))
    shaders = [s for s in shaders if os.sep + "build" + os.sep not in s and os.sep + ".godot" + os.sep not in s]
    check("shaders", len(shaders) + inline, SHADERS_MAX)

    if len(sys.argv) > 1:
        web = sys.argv[1]
        total = 0
        for f in os.listdir(web):
            p = os.path.join(web, f)
            if f.endswith(".br") or not os.path.isfile(p):
                continue
            total += os.path.getsize(p + ".br") if os.path.exists(p + ".br") else os.path.getsize(p)
        check("web download", round(total / 1e6, 1), WEB_MAX_MB, " MB")

    print("| Budget | Now | Max | |\n|---|---|---|---|\n" + "\n".join(rows))
    if failures:
        sys.exit("over budget:\n  " + "\n  ".join(failures))


if __name__ == "__main__":
    main()
