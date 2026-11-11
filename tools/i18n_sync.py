"""Translation build flow with the St33f i18n site (stdlib only).

  push: send the English source, a context per key (where it appears) and the game's own translations (drafts)
  pull: fetch the reviewers' Final texts and write them into i18n/strings.csv for this build only
        (CI runs it before exporting; the change is not committed). Placeholders are checked again here.

Authentication: a Cloudflare Access service token (CF-Access-Client-Id / CF-Access-Client-Secret).
Without I18N_URL, I18N_CLIENT_ID and I18N_CLIENT_SECRET it prints a notice and exits 0.

Usage: python -I tools/i18n_sync.py push|pull
"""
import csv
import json
import os
import re
import sys
import urllib.request

NS = "getij"
CSV_PATH = os.path.join(os.path.dirname(__file__), "..", "i18n", "strings.csv")
PLACEHOLDER = re.compile(r"\{[a-z_][a-z0-9_]*\}|%[sd]", re.I)

# Where a key shows up, so a reviewer can picture it. More specific prefixes first.
CONTEXT = [
    ("HUD_CONTROLS", "match: control hint, bottom left, one line"),
    ("HUD_", "match HUD, short (big text over the island)"),
    ("MENU_", "main menu"),
    ("RESULT_", "result screen after a match"),
    ("SETTINGS_", "settings screen, section heading or button"),
    ("CONTROLS_", "settings: controls choice"),
    ("ACCOUNT_", "settings: account section"),
    ("SIGNIN_", "settings: sign-in by e-mail code"),
    ("ERROR_", "error line under a form"),
    ("REPORT_", "report-a-problem dialog"),
    ("ANIMAL_", "animal name with nickname"),
    ("REWARD_", "Treasure Path reward name"),
    ("BOOT_", "start screen"),
    ("DROP_", "short text while dropping into a match"),
    ("PATH_", "Treasure Path"),
    ("COMMON_", "button used on many screens"),
]


def context_for(key: str) -> str:
    for prefix, text in CONTEXT:
        if key.startswith(prefix):
            return text
    return ""


def config():
    url, cid, secret = os.environ.get("I18N_URL"), os.environ.get("I18N_CLIENT_ID"), os.environ.get("I18N_CLIENT_SECRET")
    if not (url and cid and secret):
        print("::notice::i18n service token not configured (OWNER_TASKS); skipping translation sync")
        sys.exit(0)
    return url.rstrip("/"), {"CF-Access-Client-Id": cid, "CF-Access-Client-Secret": secret}


def call(method: str, url: str, headers: dict, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={**headers, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.loads(res.read())


def read_csv():
    with open(CSV_PATH, encoding="utf-8", newline="") as fh:
        rows = list(csv.reader(fh))
    return rows[0], rows[1:]


def push() -> None:
    url, headers = config()
    header, body = read_csv()
    langs = [h for h in header[2:] if not h.startswith("_")]
    strings = [{"key": r[0], "en": r[1], "context": context_for(r[0]), "code": {lang: r[header.index(lang)] for lang in langs}} for r in body if r and r[0]]
    res = call("POST", f"{url}/api/sync/source", headers, {"ns": NS, "langs": langs, "strings": strings})
    print(f"i18n push: {res.get('strings')} strings, English changed: {res.get('english_changed')}, removed: {res.get('removed')}")


def pull() -> None:
    url, headers = config()
    final = call("GET", f"{url}/api/sync/final?ns={NS}", headers).get("final", {})
    header, body = read_csv()
    applied = 0
    for lang, texts in final.items():
        if lang not in header:
            continue
        col = header.index(lang)
        for r in body:
            text = texts.get(r[0])
            if text is None:
                continue
            if sorted(PLACEHOLDER.findall(text)) != sorted(PLACEHOLDER.findall(r[1])):
                print(f"::warning::i18n pull: placeholders differ for {r[0]} ({lang}); keeping the code text")
                continue
            r[col] = text
            applied += 1
    with open(CSV_PATH, "w", encoding="utf-8", newline="\n") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(header)
        w.writerows(body)
    print(f"i18n pull: {applied} Final texts applied to this build")


if __name__ == "__main__":
    {"push": push, "pull": pull}[sys.argv[1]]()
