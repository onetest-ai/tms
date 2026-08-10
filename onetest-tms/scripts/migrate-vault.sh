#!/usr/bin/env bash
# migrate-vault — repair a corpus for the Obsidian vault, then build the vault.
# Usage: migrate-vault.sh --dir tests [--apply] [--default-repo OWNER/REPO]
set -euo pipefail
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"   # Windows: keep Python stdout UTF-8
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="tests"; APPLY=""; REPO=""
while [ $# -gt 0 ]; do case "$1" in
  --dir) DIR="$2"; shift 2;; --apply) APPLY="--apply"; shift;;
  --default-repo) REPO="$2"; shift 2;; *) echo "unknown: $1" >&2; exit 2;;
esac; done
python3 "$HERE/_migrate.py" --dir "$DIR" $APPLY
if [ -n "$APPLY" ]; then
  python3 "$HERE/_index.py" --dir "$DIR" --out index.json
  python3 "$HERE/_vault.py" --dir "$DIR" --index index.json ${REPO:+--default-repo "$REPO"}
  echo "✓ migrated + vault built"
else
  echo "(dry-run — re-run with --apply to write, then build-index)"
fi
