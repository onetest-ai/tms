#!/usr/bin/env bash
# record-result — set one execution's outcome (spec §C record_result).
# Updates the Project Result/Failure-reason fields, mirrors a result:* label,
# comments the detail, and closes the issue on PASS.
#
# Usage:
#   scripts/record-result.sh --execution onetest-ai/tms#2 --result PASS --evidence reports/.../TMS-0001.png
#   scripts/record-result.sh --execution onetest-ai/tms#2 --result FAIL \
#       --failure-reason bug_in_app --notes "Got HTTP 500" --defect onetest-ai/tms#9
#   scripts/record-result.sh --execution onetest-ai/tms#2 --json runner-result.json
#
# Options:
#   --execution OWNER/REPO#NUM   the execution issue (required)
#   --result PASS|FAIL|BLOCKED|SKIPPED
#   --failure-reason R           bug_in_app|test_data_issue|environment_issue|test_needs_update|blocked_by_other|other
#   --notes TEXT                 free-text result note
#   --evidence A,B               screenshot/log links or repo paths
#   --defect OWNER/REPO#NUM      link a defect issue
#   --json FILE                  test-runner JSON (fills result/details/metrics)
#   --force                      allow PASS without evidence
#   --project N / --org ORG
set -euo pipefail
EXEC=""; RESULT=""; FREASON=""; NOTES=""; EVIDENCE=""; DEFECT=""; JSON=""; FORCE=0
ORG="onetest-ai"; PN=""
while [ $# -gt 0 ]; do case "$1" in
  --execution) EXEC="$2"; shift 2;; --result) RESULT="$2"; shift 2;;
  --failure-reason) FREASON="$2"; shift 2;; --notes) NOTES="$2"; shift 2;;
  --evidence) EVIDENCE="$2"; shift 2;; --defect) DEFECT="$2"; shift 2;;
  --json) JSON="$2"; shift 2;; --force) FORCE=1; shift;;
  --project) PN="$2"; shift 2;; --org) ORG="$2"; shift 2;;
  *) echo "unknown option: $1" >&2; exit 2;;
esac; done
[ -n "$EXEC" ] || { echo "--execution OWNER/REPO#NUM is required" >&2; exit 2; }
EREPO="${EXEC%%#*}"; ENUM="${EXEC##*#}"
jget(){ python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get(sys.argv[2],'') if d.get(sys.argv[2]) is not None else '')" "$1" "$2"; }

# ---- ingest runner JSON (flags win over JSON) -----------------------------
if [ -n "$JSON" ]; then
  [ -n "$RESULT" ]  || RESULT="$(jget "$JSON" result)"
  [ -n "$FREASON" ] || FREASON="$(jget "$JSON" failure_reason)"
  JS_SCREEN="$(jget "$JSON" screenshot)"; [ -n "$EVIDENCE" ] || EVIDENCE="$JS_SCREEN"
  JS_DETAILS="$(jget "$JSON" failure_reason)"; JS_NOTES="$(jget "$JSON" notes)"
  [ -n "$NOTES" ] || NOTES="$JS_NOTES"
  JS_DUR="$(jget "$JSON" duration_seconds)"; JS_CONSOLE="$(python3 -c "import json;print('; '.join(json.load(open('$JSON')).get('console_errors',[])))")"
  JS_STEPS="$(jget "$JSON" steps_completed)/$(jget "$JSON" steps_total)"
fi
[ -n "$RESULT" ] || { echo "--result (or --json) is required" >&2; exit 2; }
RESULT="$(echo "$RESULT" | tr '[:lower:]' '[:upper:]')"

# ---- map result → Project option + label ----------------------------------
case "$RESULT" in
  PASS|PASSED)   OPT="Passed";  LABEL="result:passed";;
  FAIL|FAILED)   OPT="Failed";  LABEL="result:failed";;
  BLOCKED)       OPT="Blocked"; LABEL="result:blocked";;
  SKIPPED|SKIP)  OPT="Skipped"; LABEL="result:skipped";;
  *) echo "bad --result: $RESULT" >&2; exit 2;;
esac
# evidence-before-PASS
if [ "$OPT" = "Passed" ] && [ -z "$EVIDENCE" ] && [ "$FORCE" -eq 0 ]; then
  echo "Refusing PASS without --evidence (use --force to override)." >&2; exit 3
fi
fr_label(){ case "$1" in
  bug_in_app) echo "fail:bug-in-app";; test_data_issue) echo "fail:test-data";;
  environment_issue) echo "fail:environment";; test_needs_update) echo "fail:test-needs-update";;
  blocked_by_other) echo "fail:blocked-by-other";; other) echo "fail:other";; *) echo "";;
esac; }

# ---- project field/option ids ---------------------------------------------
[ -n "$PN" ] || PN="$(gh project list --owner "$ORG" --format json -q '.projects[] | select(.title=="QA Runs") | .number' | head -1)"
PID="$(gh project view "$PN" --owner "$ORG" --format json -q .id)"
FL="$(mktemp)"; gh project field-list "$PN" --owner "$ORG" --format json > "$FL"
fid(){ python3 -c "import json;print(next((f['id'] for f in json.load(open('$FL'))['fields'] if f.get('name')==__import__('sys').argv[1]),''))" "$1"; }
opt(){ python3 -c "import json,sys
f=next((f for f in json.load(open('$FL'))['fields'] if f.get('name')==sys.argv[1]),{})
print(next((o['id'] for o in f.get('options',[]) if o['name']==sys.argv[2]),''))" "$1" "$2"; }
EURL="https://github.com/$EREPO/issues/$ENUM"
ITEM="$(gh project item-list "$PN" --owner "$ORG" --format json -q ".items[] | select(.content.url==\"$EURL\") | .id" | head -1)"
[ -n "$ITEM" ] || { echo "execution not found on board: $EURL" >&2; exit 1; }

# ---- set fields -----------------------------------------------------------
gh project item-edit --id "$ITEM" --project-id "$PID" --field-id "$(fid Result)" --single-select-option-id "$(opt Result "$OPT")" >/dev/null
if [ "$OPT" = "Failed" ] && [ -n "$FREASON" ]; then
  FRO="$(opt 'Failure reason' "$FREASON")"
  [ -n "$FRO" ] && gh project item-edit --id "$ITEM" --project-id "$PID" --field-id "$(fid 'Failure reason')" --single-select-option-id "$FRO" >/dev/null || true
fi

# ---- labels ---------------------------------------------------------------
gh issue edit "$ENUM" --repo "$EREPO" \
  --remove-label result:not-run --remove-label result:passed --remove-label result:failed \
  --remove-label result:blocked --remove-label result:skipped >/dev/null 2>&1 || true
gh issue edit "$ENUM" --repo "$EREPO" --add-label "$LABEL" >/dev/null
if [ "$OPT" = "Failed" ] && [ -n "$(fr_label "$FREASON")" ]; then
  gh issue edit "$ENUM" --repo "$EREPO" --add-label "$(fr_label "$FREASON")" >/dev/null || true
fi
[ -n "$DEFECT" ] && gh issue edit "$ENUM" --repo "$EREPO" --add-label defect-linked >/dev/null || true

# ---- comment --------------------------------------------------------------
CB="$(mktemp)"
{ echo "### Result: $OPT";
  [ -n "${JS_STEPS:-}" ] && echo "- Steps: ${JS_STEPS}";
  [ -n "${JS_DUR:-}" ] && echo "- Duration: ${JS_DUR}s";
  [ -n "$FREASON" ] && echo "- Failure reason: \`$FREASON\`";
  [ -n "$NOTES" ] && { echo "- Notes: $NOTES"; };
  [ -n "${JS_CONSOLE:-}" ] && echo "- Console: ${JS_CONSOLE}";
  if [ -n "$EVIDENCE" ]; then echo "- Evidence:"; IFS=',' read -ra EV <<<"$EVIDENCE"; for e in "${EV[@]}"; do echo "  - $e"; done; fi
  [ -n "$DEFECT" ] && echo "- Defect: $DEFECT";
} > "$CB"
gh issue comment "$ENUM" --repo "$EREPO" --body-file "$CB" >/dev/null
[ -n "$DEFECT" ] && gh issue comment "${DEFECT##*#}" --repo "${DEFECT%%#*}" --body "Linked from execution $EXEC" >/dev/null 2>&1 || true

# ---- close on PASS --------------------------------------------------------
[ "$OPT" = "Passed" ] && gh issue close "$ENUM" --repo "$EREPO" --reason completed >/dev/null || true
echo "✓ $EXEC → $OPT"
