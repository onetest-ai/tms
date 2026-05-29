#!/usr/bin/env bash
# Create/ensure the org Project (v2) "QA Runs" with the TMS field schema.
# Requires the `project` scope:  gh auth refresh -h github.com -s project,read:project
# Usage: scripts/bootstrap-project.sh [org] [title]
set -euo pipefail
ORG="${1:-onetest-ai}"; TITLE="${2:-QA Runs}"
echo "Ensuring Project '$TITLE' in org: $ORG"

num="$(gh project list --owner "$ORG" --format json -q ".projects[] | select(.title==\"$TITLE\") | .number" 2>/dev/null | head -1 || true)"
if [ -z "${num:-}" ]; then
  num="$(gh project create --owner "$ORG" --title "$TITLE" --format json -q .number)"
  echo "  ✓ created project #$num"
else
  echo "  • exists: project #$num"
fi

field() { gh project field-create "$num" --owner "$ORG" --name "$1" --data-type "$2" ${3:+--single-select-options "$3"} >/dev/null 2>&1 \
            && echo "  ✓ field: $1" || echo "  • field exists/skipped: $1"; }

field "Result"        SINGLE_SELECT "Not run,In progress,Passed,Failed,Blocked,Skipped"
field "Run"           TEXT
field "Case"          TEXT
field "Priority"      SINGLE_SELECT "critical,high,medium,low"
field "Size"          SINGLE_SELECT "S,M,L"
field "Failure reason" SINGLE_SELECT "bug_in_app,test_data_issue,environment_issue,test_needs_update,blocked_by_other,other"
# "Target" options are populated from .onetest/config.yml default_targets at run time.

echo "Project #$num ready. Write this number into .onetest/config.yml (project.number) and .onetest/project.yml."
