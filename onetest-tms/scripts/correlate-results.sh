#!/usr/bin/env bash
# correlate-results — match automated code_ref ⇄ test-case automation_test_id.
# Usage: scripts/correlate-results.sh --automated reports/automated/NAME.json [--commit]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AUTO=""; OUT="reports/correlation.json"; COMMIT=0
while [ $# -gt 0 ]; do case "$1" in
  --automated) AUTO="$2"; shift 2;; --out) OUT="$2"; shift 2;; --commit) COMMIT=1; shift;;
  *) echo "unknown option: $1" >&2; exit 2;;
esac; done
[ -n "$AUTO" ] || { echo "--automated reports/automated/NAME.json is required" >&2; exit 2; }
[ -f index.json ] || python3 "$HERE/_index.py" --dir tests --out index.json
mkdir -p "$(dirname "$OUT")"
python3 "$HERE/_correlate.py" --index index.json --automated "$AUTO" --out "$OUT"
echo "✓ wrote $OUT"
if [ "$COMMIT" -eq 1 ]; then
  git add "$OUT" && git commit -q -m "correlation: rebuild" && git push -q origin HEAD && echo "✓ committed"
fi
