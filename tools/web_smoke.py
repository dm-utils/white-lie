"""Web smoke test: the exported web build must load and keep running in a real (headless) Chromium.

Checks:
  1. the engine starts (the loader finishes) and frames keep coming,
  2. the start screen opens the menu, Play starts a session,
  3. the debug entry ?scene=hide&seed=N plays: walking and disguising change the picture,
  4. settings and the report overlay (F8) open, the Dutch screens render,
  5. no page errors were thrown.

Usage: python -I tools/web_smoke.py build/web [screenshot_dir]
"""
import functools
import hashlib
import http.server
import os
import re
import socketserver
import sys
import threading

from playwright.sync_api import sync_playwright


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args) -> None:
        pass


def serve(directory: str) -> tuple[socketserver.TCPServer, int]:
    handler = functools.partial(QuietHandler, directory=directory)
    httpd = socketserver.TCPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, httpd.server_address[1]


def canvas_hash(page) -> str:
    return hashlib.sha256(page.screenshot()).hexdigest()


def online_check(browser, port: int, shots) -> list:
    """Two windows click Online in the menu, land in one session through the dev relay, and must agree on every
    settled tick (desync check). Waits for 3 common checks, at most 75 s (slow runner)."""
    failures = []
    logs = {0: [], 1: []}
    pages = []
    for i in range(2):
        pg = browser.new_context(viewport={"width": 960, "height": 540}).new_page()
        pg.on("console", lambda m, i=i: logs[i].append(m.text))
        pg.goto(f"http://127.0.0.1:{port}/index.html?scene=menu&lang=nl")
        pg.wait_for_selector("#loader.done", state="attached", timeout=60000)
        pages.append(pg)
    pages[0].wait_for_timeout(1500)
    for pg in pages:
        pg.mouse.click(480, 358)  # "Online spelen", under Play
    pages[0].wait_for_timeout(12000)
    pages[0].keyboard.down("KeyD")
    rx = re.compile(r"online settled tick (\d+) hash (-?\d+) seat (\d+)")

    def settled():
        return [{int(m.group(1)): (int(m.group(2)), int(m.group(3))) for line in logs[i] for m in [rx.search(line)] if m} for i in range(2)]

    for _ in range(25):
        pages[0].wait_for_timeout(3000)
        got = settled()
        if len(set(got[0]) & set(got[1])) >= 3:
            break
    if shots:
        pages[1].screenshot(path=f"{shots}/web-online-session.png")
    got = settled()
    common = sorted(set(got[0]) & set(got[1]))
    seats = {v[1] for g in got for v in g.values()}
    print(f"online: settled ticks {len(got[0])} / {len(got[1])}, common {len(common)}, seats {sorted(seats)}")
    if len(seats) < 2:
        failures.append("online: the two windows did not end up in the same session")
    elif not common:
        failures.append("online: no settled ticks in common")
    elif any(got[0][t][0] != got[1][t][0] for t in common):
        failures.append("online: the two windows disagree (desync)")
    for pg in pages:
        pg.context.close()
    return failures


def main() -> int:
    build = sys.argv[1]
    shots = sys.argv[2] if len(sys.argv) > 2 else None
    httpd, port = serve(build)
    errors: list[str] = []
    failures: list[str] = []
    base = f"http://127.0.0.1:{port}/index.html"

    def shot(page, name):
        if shots:
            page.screenshot(path=f"{shots}/{name}.png")

    with sync_playwright() as p:
        # SMOKE_CHANNEL=chrome uses the installed Chrome (local); CI uses Playwright's own Chromium.
        browser = p.chromium.launch(channel=os.environ.get("SMOKE_CHANNEL") or None,
                                    args=["--mute-audio", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.on("pageerror", lambda e: errors.append(str(e)))

        def load(url, what):
            page.goto(url)
            try:
                page.wait_for_selector("#loader.done", state="attached", timeout=60000)
            except Exception:
                failures.append(f"{what}: engine did not start within 60 s")

        load(base, "boot")
        page.wait_for_timeout(1500)
        shot(page, "web-boot")
        hashes = set()
        for _ in range(4):
            hashes.add(canvas_hash(page))
            page.wait_for_timeout(400)
        if len(hashes) < 2:
            failures.append("canvas did not change for 1.6 s: frames are not coming")

        page.mouse.click(640, 360)  # start screen -> menu
        page.wait_for_timeout(1200)
        shot(page, "web-menu")
        before = canvas_hash(page)
        page.mouse.click(640, 393)  # Play, the big orange button (under the character button)
        page.wait_for_timeout(2500)
        if canvas_hash(page) == before:
            failures.append("Play did not start a session")

        # a session through the debug entry: walk, disguise, then the seek phase starts
        load(f"{base}?scene=hide&seed=5", "hide")
        page.wait_for_timeout(2500)
        shot(page, "web-hide-start")
        hashes = set()
        page.keyboard.down("KeyD")
        for _ in range(5):
            hashes.add(canvas_hash(page))
            page.wait_for_timeout(300)
        page.keyboard.up("KeyD")
        page.keyboard.press("Space")
        page.wait_for_timeout(1500)
        shot(page, "web-hide-disguised")
        if len(hashes) < 3:
            failures.append("hide: the picture barely changed while walking")
        page.wait_for_timeout(18000)
        shot(page, "web-hide-seek")

        load(f"{base}?scene=settings", "settings")
        page.wait_for_timeout(2000)
        shot(page, "web-settings")
        top = {"x": 0, "y": 0, "width": 1280, "height": 420}
        before = hashlib.sha256(page.screenshot(clip=top)).hexdigest()
        page.keyboard.press("F8")
        page.wait_for_timeout(1200)
        shot(page, "web-report")
        if hashlib.sha256(page.screenshot(clip=top)).hexdigest() == before:
            failures.append("F8 did not open the report overlay")

        # Dutch: texts are ~30 % longer, the layouts must still fit (checked by eye in the contact sheet)
        for scene, extra, name in [("menu", "&lang=nl", "web-menu-nl"), ("settings", "&lang=nl", "web-settings-nl"),
                                   ("settings", "&lang=nl&dialog=privacy", "web-privacy-nl"),
                                   ("hide", "&lang=nl&seed=9", "web-hide-nl"), ("online", "&lang=nl", "web-online-nl")]:
            load(f"{base}?scene={scene}{extra}", name)
            page.wait_for_timeout(2500)
            shot(page, name)
        failures.extend(online_check(browser, port, shots))
        browser.close()
    httpd.shutdown()

    for e in errors:
        failures.append("page error: " + e)
    for f in failures:
        print("FAIL:", f)
    print("web smoke:", "OK" if not failures else f"{len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
