#!/usr/bin/env bash
# build-index — scan tests/ front-matter into index.json (backs oql-search & coverage).
# Usage: scripts/build-index.sh [--dir tests] [--out index.json] [--commit]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="tests"; OUT="index.json"; COMMIT=0
while [ $# -gt 0 ]; do case "$1" in
  --dir) DIR="$2"; shift 2;; --out) OUT="$2"; shift 2;; --commit) COMMIT=1; shift;;
  *) echo "unknown option: $1" >&2; exit 2;;
esac; done
python3 "$HERE/_index.py" --dir "$DIR" --out "$OUT"
echo "✓ wrote $OUT"
python3 "$HERE/_vault.py" --dir "$DIR" --index "$OUT"
if [ "$COMMIT" -eq 1 ]; then
  git add "$OUT" "$DIR" && git commit -q -m "index: rebuild + vault" && git push -q origin HEAD && echo "✓ committed"
fi
