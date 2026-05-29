#!/usr/bin/env bash
# ingest-results — parse a JUnit XML report into reports/automated/<name>.json.
# Usage: scripts/ingest-results.sh --file results.xml [--out reports/automated/NAME.json] [--commit]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FILE=""; OUT=""; COMMIT=0
while [ $# -gt 0 ]; do case "$1" in
  --file) FILE="$2"; shift 2;; --out) OUT="$2"; shift 2;; --commit) COMMIT=1; shift;;
  *) echo "unknown option: $1" >&2; exit 2;;
esac; done
[ -n "$FILE" ] || { echo "--file results.xml is required" >&2; exit 2; }
[ -n "$OUT" ] || OUT="reports/automated/$(basename "${FILE%.*}").json"
mkdir -p "$(dirname "$OUT")"
python3 "$HERE/_junit.py" --file "$FILE" --out "$OUT"
echo "✓ wrote $OUT"
if [ "$COMMIT" -eq 1 ]; then
  git add "$OUT" && git commit -q -m "results: ingest $(basename "$OUT")" && git push -q origin HEAD && echo "✓ committed"
fi
