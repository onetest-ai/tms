#!/usr/bin/env bash
# Create/ensure org Issue Types for TMS (mirrors .onetest/issue-types.yml).
# Requires the admin:org scope:  gh auth refresh -h github.com -s admin:org
# Usage: scripts/apply-issue-types.sh [org]   (default: onetest-ai)
set -euo pipefail
ORG="${1:-onetest-ai}"
echo "Ensuring issue types in org: $ORG"

existing="$(gh api "orgs/$ORG/issue-types" -q '.[].name' 2>/dev/null || true)"

ensure() { # name description color
  if grep -qxF "$1" <<<"$existing"; then echo "  • exists: $1"; return; fi
  gh api --method POST "orgs/$ORG/issue-types" \
    -f name="$1" -f description="$2" -f color="$3" -F is_enabled=true >/dev/null \
    && echo "  ✓ created: $1"
}

ensure "Test Run"            "A test run cycle that aggregates executions"      purple
ensure "Test Execution"      "One test case executed within a run"              green
ensure "Defect"              "A bug found during testing"                       red
ensure "Exploratory Finding" "An unplanned finding outside scripted cases"      orange
echo "Done. (Enable 'type:' in .github/ISSUE_TEMPLATE/*.yml to attach these.)"
