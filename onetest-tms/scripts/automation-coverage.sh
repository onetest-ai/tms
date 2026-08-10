#!/usr/bin/env bash
# automation-coverage — compute coverage from index.json (+ reports/correlation.json).
# Usage: scripts/automation-coverage.sh [--commit]
set -euo pipefail
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"   # Windows: keep Python stdout UTF-8
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="reports/coverage.md"; COMMIT=0
while [ $# -gt 0 ]; do case "$1" in
  --out) OUT="$2"; shift 2;; --commit) COMMIT=1; shift;;
  *) echo "unknown option: $1" >&2; exit 2;;
esac; done
[ -f index.json ] || python3 "$HERE/_index.py" --dir tests --out index.json
mkdir -p "$(dirname "$OUT")"
python3 "$HERE/_coverage.py" --index index.json --correlation reports/correlation.json --out "$OUT"
echo "✓ wrote $OUT"
if [ "$COMMIT" -eq 1 ]; then
  git add "$OUT" && git commit -q -m "coverage: rebuild" && git push -q origin HEAD && echo "✓ committed"
fi
