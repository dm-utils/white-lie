"""Builds an index.html contact sheet for a folder of screenshots (stdlib only).

Usage: python -I tools/contact_sheet.py <shots dir> [title]
Commit and date come from the environment (GITHUB_SHA) or git, so the sheet says what it shows.
"""
import datetime
import html
import os
import subprocess
import sys


def commit() -> str:
    sha = os.environ.get("GITHUB_SHA", "")
    if not sha:
        try:
            sha = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
        except Exception:
            sha = "unknown"
    return sha[:7]


def main() -> int:
    folder = sys.argv[1]
    title = sys.argv[2] if len(sys.argv) > 2 else "Getij screenshots"
    shots = sorted(f for f in os.listdir(folder) if f.lower().endswith(".png"))
    when = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    cards = "\n".join(
        f'<figure><a href="{html.escape(f)}"><img src="{html.escape(f)}" alt="{html.escape(f)}"></a>'
        f"<figcaption>{html.escape(f[:-4])}</figcaption></figure>"
        for f in shots
    )
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>
body{{margin:0;padding:16px;font-family:system-ui,sans-serif;background:#f4f6f8;color:#1d2a36}}
h1{{font-size:20px;margin:0 0 4px}} p{{margin:0 0 16px;color:#5b6b78}}
main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:16px}}
figure{{margin:0;background:#fff;border:1px solid #d5dee5;border-radius:10px;overflow:hidden}}
img{{display:block;width:100%;height:auto}} figcaption{{padding:8px 10px;font-weight:600}}
@media (prefers-color-scheme:dark){{body{{background:#0f1720;color:#e6edf3}}figure{{background:#18222d;border-color:#2a3846}}p{{color:#93a4b3}}}}
</style></head><body>
<h1>{html.escape(title)}</h1><p>commit {commit()} · {when} · {len(shots)} screens</p>
<main>{cards}</main>
</body></html>
"""
    with open(os.path.join(folder, "index.html"), "w", encoding="utf-8") as fh:
        fh.write(page)
    print(f"contact sheet: {len(shots)} screens -> {os.path.join(folder, 'index.html')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
