#!/usr/bin/env bash
# oql-search — run an OQL query over index.json (builds the index if missing).
# Usage: scripts/oql-search.sh "tags CONTAINS 'smoke' AND priority IN (critical, high)" [--ids|--json] [--rebuild]
set -euo pipefail
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"   # Windows: keep Python stdout UTF-8
HERE="$(cd "$(dirname "$0")" && pwd)"
QUERY=""; MODE=""; REBUILD=0
while [ $# -gt 0 ]; do case "$1" in
  --ids) MODE="--ids"; shift;; --json) MODE="--json"; shift;; --rebuild) REBUILD=1; shift;;
  -*) echo "unknown option: $1" >&2; exit 2;;
  *) QUERY="$1"; shift;;
esac; done
[ -n "$QUERY" ] || { echo "usage: oql-search.sh \"<OQL>\" [--ids|--json]" >&2; exit 2; }
{ [ "$REBUILD" -eq 1 ] || [ ! -f index.json ]; } && python3 "$HERE/_index.py" --dir tests --out index.json
python3 "$HERE/_oql.py" --query "$QUERY" --index index.json $MODE
