#!/usr/bin/env bash
# create-defect — open a Defect issue (spec §D create_defect) and link it to an execution.
# Usage:
#   scripts/create-defect.sh --target onetest-ai/app-web --title "500 on valid login" \
#       --severity High --from-execution onetest-ai/tms#2 --body "repro…" --evidence url1,url2
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/_run_lib.sh"
TARGET=""; TITLE=""; SEVERITY="Medium"; FROM=""; BODY=""; EVIDENCE=""
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="$2"; shift 2;; --title) TITLE="$2"; shift 2;; --severity) SEVERITY="$2"; shift 2;;
  --from-execution) FROM="$2"; shift 2;; --body) BODY="$2"; shift 2;; --evidence) EVIDENCE="$2"; shift 2;;
  *) echo "unknown option: $1" >&2; exit 2;;
esac; done
[ -n "$TARGET" ] && [ -n "$TITLE" ] || { echo "--target and --title are required" >&2; exit 2; }

DB="$(mktemp)"
{ echo "**Severity:** $SEVERITY";
  [ -n "$FROM" ] && echo "**Found in execution:** $FROM";
  echo; [ -n "$BODY" ] && { echo "$BODY"; echo; };
  if [ -n "$EVIDENCE" ]; then echo "**Evidence:**"; IFS=',' read -ra EV <<<"$EVIDENCE"; for e in "${EV[@]}"; do echo "- $e"; done; fi
} > "$DB"
DR="$(mktemp)"
ensure_label "$TARGET" onetest; ensure_label "$TARGET" kind:defect "d73a4a"
declare -a DA=(-X POST "repos/$TARGET/issues" -f title="$TITLE" -F "body=@$(winpath "$DB")")
ot_has_type "${TARGET%%/*}" "Defect" && DA+=(-f type="Defect")
DA+=(-f "labels[]=kind:defect" -f "labels[]=onetest")
gh api "${DA[@]}" > "$DR"
D_NUM=$(jget "$DR" number); D_URL=$(jget "$DR" html_url)
echo "✓ defect: $TARGET#$D_NUM ($D_URL)"

if [ -n "$FROM" ]; then
  FREPO="${FROM%%#*}"; FNUM="${FROM##*#}"
  gh issue comment "$FNUM" --repo "$FREPO" --body "Defect filed: $TARGET#$D_NUM — $TITLE" >/dev/null
  gh issue edit "$FNUM" --repo "$FREPO" --add-label defect-linked >/dev/null 2>&1 || true
  echo "✓ linked to execution $FROM"
fi
