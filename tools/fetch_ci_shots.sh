#!/usr/bin/env bash
# Downloads the screenshots of the latest finished CI run on a branch into <dest>/<date>_<commit>/
# and rebuilds <dest>/index.html, a list of every run with a link to its contact sheet.
# Usage: tools/fetch_ci_shots.sh <dest folder> [branch=develop]
set -euo pipefail
dest="${1:?usage: tools/fetch_ci_shots.sh <dest folder> [branch]}"
branch="${2:-develop}"

read -r id sha when < <(gh run list --branch "$branch" --status completed --limit 1 \
  --json databaseId,headSha,createdAt --jq '.[0] | "\(.databaseId) \(.headSha[0:7]) \(.createdAt)"')
stamp="$(echo "$when" | sed -E 's/T([0-9]{2}):([0-9]{2}).*/_\1\2/')_${sha}"
target="$dest/$stamp"
if [ -d "$target" ]; then echo "already have $stamp"; else
  mkdir -p "$target"
  gh run download "$id" -n smoke-shots -D "$target"
  echo "downloaded run $id ($sha) -> $target"
fi

# overview of all runs, newest first
{
  echo '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
  echo '<title>White Lie screenshots</title><style>body{margin:0;padding:16px;font-family:system-ui,sans-serif;background:#f4f6f8;color:#1d2a36}'
  echo 'a{color:#1F6F9F}li{margin:6px 0}@media (prefers-color-scheme:dark){body{background:#0f1720;color:#e6edf3}a{color:#5FD3C9}}</style></head><body>'
  echo '<h1>White Lie screenshots per CI run</h1><ul>'
  for d in $(ls -1 "$dest" | grep -E '^[0-9]{4}-' | sort -r); do
    n=$(ls -1 "$dest/$d" | grep -c '\.png$' || true)
    echo "<li><a href=\"$d/index.html\">$d</a> — $n screens</li>"
  done
  echo '</ul></body></html>'
} > "$dest/index.html"
echo "overview: $dest/index.html"
