"""Tests for tools/i18n_sync.py pull: Final texts land in the CSV, bad placeholders are refused (stdlib only).
Usage: python -I tools/test_i18n_sync.py
"""
import csv
import importlib.util
import os
import shutil
import sys
import tempfile

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("i18n_sync", os.path.join(here, "i18n_sync.py"))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

failures = []


def check(ok: bool, what: str) -> None:
    if not ok:
        failures.append(what)
        print("FAIL:", what)


tmp = tempfile.mkdtemp()
try:
    path = os.path.join(tmp, "strings.csv")
    shutil.copy(sync.CSV_PATH, path)
    sync.CSV_PATH = path
    os.environ.update({"I18N_URL": "https://i18n.test", "I18N_CLIENT_ID": "id", "I18N_CLIENT_SECRET": "secret"})
    sent = []

    def fake_call(method, url, headers, body=None):
        sent.append((method, url, headers, body))
        if url.endswith("/api/sync/final?ns=getij"):
            return {"final": {"nl": {"MENU_PLAY": "SPEEL!", "HUD_LEFT": "nog {aantal}", "NOT_A_KEY": "x"}, "de": {"MENU_PLAY": "SPIELEN"}}}
        return {"strings": 1, "english_changed": 0, "removed": 0}

    sync.call = fake_call
    sync.pull()
    with open(path, encoding="utf-8", newline="") as fh:
        rows = {r[0]: r for r in csv.reader(fh)}
    header = rows["keys"]
    nl = header.index("nl")
    check(rows["MENU_PLAY"][nl] == "SPEEL!", "Final text applied")
    check(rows["HUD_LEFT"][nl] == "nog {count}", "Final text with wrong placeholders refused, code text kept")
    check("de" not in header, "a language the game does not have is ignored")
    check(sent[0][2] == {"CF-Access-Client-Id": "id", "CF-Access-Client-Secret": "secret"}, "service token headers sent")

    sent.clear()
    sync.push()
    body = sent[0][3]
    check(body["ns"] == "getij" and body["langs"] == ["nl"] and any(s["key"] == "MENU_PLAY" and s["code"]["nl"] for s in body["strings"]),
          "push sends English, context and the code's Dutch")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("i18n sync tests:", "OK" if not failures else f"{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
