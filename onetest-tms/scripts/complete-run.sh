#!/usr/bin/env bash
# complete-run — aggregate a run, write the report, close it (spec §B complete_run).
# Reads the QA Runs board, renders a web-qa-format report to reports/<RUN>.md,
# comments the summary on the run issue, labels it run:completed, and closes it.
#
# Usage:
#   scripts/complete-run.sh --run RUN-2026-05-29-001 [--suite "Smoke (demo)"] [--env staging]
# Options:
#   --run RUN-ID         (required)
#   --suite NAME         report title (default: run issue title)
#   --env URL/NAME       environment (default: from run issue body)
#   --project N --org ORG
#   --no-commit          write the report but don't git commit/push it
#   --no-close           leave the run issue open
#   --force              complete even if executions are unresolved (Not run / In progress)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/_run_lib.sh"
RUN=""; SUITE=""; ENVN=""; ORG="onetest-ai"; PN=""; NOCOMMIT=0; NOCLOSE=0; FORCE=0
while [ $# -gt 0 ]; do case "$1" in
  --run) RUN="$2"; shift 2;; --suite) SUITE="$2"; shift 2;; --env) ENVN="$2"; shift 2;;
  --project) PN="$2"; shift 2;; --org) ORG="$2"; shift 2;;
  --no-commit) NOCOMMIT=1; shift;; --no-close) NOCLOSE=1; shift;; --force) FORCE=1; shift;;
  *) echo "unknown option: $1" >&2; exit 2;;
esac; done
[ -n "$RUN" ] || { echo "--run RUN-ID is required" >&2; exit 2; }
RUN_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
[ -n "$PN" ] || PN="$(gh project list --owner "$ORG" --format json -q '.projects[] | select(.title=="QA Runs") | .number' | head -1)"

# ---- find the run issue ---------------------------------------------------
RUN_NUM="$(gh issue list --repo "$RUN_REPO" --label kind:run --state all --search "$RUN in:title" \
            --json number,title -q ".[] | select(.title | startswith(\"$RUN\")) | .number" | head -1)"
[ -n "$RUN_NUM" ] || { echo "run issue for $RUN not found in $RUN_REPO" >&2; exit 1; }
[ -n "$SUITE" ] || SUITE="$(gh issue view "$RUN_NUM" --repo "$RUN_REPO" --json title -q '.title' | sed "s/^$RUN — //")"
[ -n "$ENVN" ] || ENVN="$(gh issue view "$RUN_NUM" --repo "$RUN_REPO" --json body -q '.body' | sed -n 's/.*\*\*Environment:\*\* *//p' | head -1)"

# ---- gather board items + guard for unresolved ----------------------------
ITEMS="$(mktemp)"; gh project item-list "$PN" --owner "$ORG" --format json --limit 500 > "$ITEMS"
UNRESOLVED="$(python3 -c "import json,sys
d=json.load(open(sys.argv[1])); run=sys.argv[2]
print(sum(1 for i in d.get('items',[]) if i.get('run')==run and i.get('case') and i.get('result') in (None,'','Not run','In progress')))" "$(winpath "$ITEMS")" "$RUN")"
if [ "$UNRESOLVED" -gt 0 ] && [ "$FORCE" -eq 0 ]; then
  echo "$UNRESOLVED execution(s) still Not run / In progress. Use --force to complete anyway." >&2; exit 3
fi

# ---- render report --------------------------------------------------------
mkdir -p reports
OUT="reports/$RUN.md"
SUMMARY="$(python3 "$HERE/_report.py" --run "$RUN" --env "$ENVN" --suite "$SUITE" --date "$(date +%Y-%m-%d)" --out "$OUT" < "$ITEMS")"
echo "✓ report: $OUT"
echo "  $SUMMARY"

# ---- commit the report ----------------------------------------------------
if [ "$NOCOMMIT" -eq 0 ]; then
  git add "$OUT" && git commit -q -m "report: $RUN" && git push -q origin HEAD && echo "✓ committed report"
fi

# ---- comment + close the run ---------------------------------------------
CB="$(mktemp)"
{ echo "## Run complete — $RUN"; echo; echo "$SUMMARY"; echo;
  echo "Report: \`$OUT\`"; echo "Board: https://github.com/orgs/$ORG/projects/$PN"; } > "$CB"
gh issue comment "$RUN_NUM" --repo "$RUN_REPO" --body-file "$CB" >/dev/null
gh issue edit "$RUN_NUM" --repo "$RUN_REPO" --remove-label run:in-progress --add-label run:completed >/dev/null 2>&1 || true
[ "$NOCLOSE" -eq 0 ] && gh issue close "$RUN_NUM" --repo "$RUN_REPO" --reason completed >/dev/null || true
echo "✓ run $RUN completed (issue #$RUN_NUM)"
