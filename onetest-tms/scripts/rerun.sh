#!/usr/bin/env bash
# rerun — re-run one execution: open a fresh execution issue linked to the original.
# Usage: scripts/rerun.sh --execution onetest-ai/tms#2 --reason "flaky — staging redeploy"
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/_run_lib.sh"
EXEC=""; REASON=""; ORG="onetest-ai"; PN=""
while [ $# -gt 0 ]; do case "$1" in
  --execution) EXEC="$2"; shift 2;; --reason) REASON="$2"; shift 2;;
  --project) PN="$2"; shift 2;; --org) ORG="$2"; shift 2;;
  *) echo "unknown option: $1" >&2; exit 2;;
esac; done
[ -n "$EXEC" ] || { echo "--execution OWNER/REPO#NUM is required" >&2; exit 2; }
EREPO="${EXEC%%#*}"; ENUM="${EXEC##*#}"
RUN_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

# original issue: title, body (for marker), labels (priority)
O="$(mktemp)"; gh issue view "$ENUM" --repo "$EREPO" --json title,body,labels > "$O"
TITLE="$(jget "$O" title)"
BODY="$(jget "$O" body)"
RUN_ID="$(printf '%s' "$BODY" | sed -n 's/.*onetest:run=\([^ ]*\).*/\1/p' | head -1)"
CASE_ID="$(printf '%s' "$BODY" | sed -n 's/.*case=\([^ ]*\).*-->.*/\1/p' | head -1)"
PRIORITY="$(python3 -c "import json,sys;print(next((l['name'].split(':')[1] for l in json.load(open(sys.argv[1]))['labels'] if l['name'].startswith('priority:')),''))" "$(winpath "$O")")"
[ -n "$RUN_ID" ] || { echo "could not read run id from $EXEC body marker" >&2; exit 1; }

# new execution issue (re-run)
NB="$(mktemp)"
{ echo "**Re-run of** $EXEC — reason: ${REASON:-n/a}"; echo;
  printf '%s\n' "$BODY"; } > "$NB"
ensure_label "$EREPO" onetest; ensure_label "$EREPO" kind:execution; ensure_label "$EREPO" result:not-run
[ -n "$PRIORITY" ] && ensure_label "$EREPO" "priority:$PRIORITY"
A=(-X POST "repos/$EREPO/issues" -f title="$TITLE (re-run)" -F "body=@$(winpath "$NB")")
ot_has_type "${EREPO%%/*}" "Test Execution" && A+=(-f type="Test Execution")
A+=(-f "labels[]=kind:execution" -f "labels[]=result:not-run" -f "labels[]=onetest")
[ -n "$PRIORITY" ] && A+=(-f "labels[]=priority:$PRIORITY")
NR="$(mktemp)"; gh api "${A[@]}" > "$NR"
N_NUM=$(jget "$NR" number); N_ID=$(jget "$NR" id); N_URL=$(jget "$NR" html_url)

# link to run (sub-issue if same repo) + board
RUN_NUM="$(gh issue list --repo "$RUN_REPO" --label kind:run --state all --search "$RUN_ID in:title" \
            --json number,title -q ".[] | select(.title|startswith(\"$RUN_ID\")) | .number" | head -1)"
[ -n "$RUN_NUM" ] && [ "$EREPO" = "$RUN_REPO" ] && gh api -X POST "repos/$RUN_REPO/issues/$RUN_NUM/sub_issues" -F sub_issue_id="$N_ID" >/dev/null 2>&1 || true
ot_project_setup "$ORG" "$PN"
IT=$(ot_add_item "$N_URL")
ot_set_opt "$IT" "$(ot_fid Result)" "$(ot_opt Result 'Not run')"
ot_set_text "$IT" "$(ot_fid Run)" "$RUN_ID"
[ -n "$CASE_ID" ] && ot_set_text "$IT" "$(ot_fid Case)" "$CASE_ID"
[ -n "$PRIORITY" ] && ot_set_opt "$IT" "$(ot_fid Priority)" "$(ot_opt Priority "$PRIORITY")"

gh issue comment "$ENUM" --repo "$EREPO" --body "Re-run as $EREPO#$N_NUM — reason: ${REASON:-n/a}" >/dev/null
echo "✓ re-ran $EXEC → $EREPO#$N_NUM ($N_URL)"
