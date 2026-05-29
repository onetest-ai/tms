#!/usr/bin/env bash
# Apply TMS repo labels (mirrors .onetest/labels.yml). Idempotent (--force upserts).
# Usage: scripts/apply-labels.sh [owner/repo]   (default: current repo)
set -euo pipefail
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
echo "Applying labels to $REPO"

create() { gh label create "$1" --color "$2" --description "$3" --force --repo "$REPO" >/dev/null && echo "  ✓ $1"; }

# kind (fallback for Issue Types)
create "kind:run"        8957e5 "A test run cycle (parent issue)"
create "kind:execution"  2da44e "One test case executed in a run"
create "kind:defect"     d73a4a "A bug found during testing"
create "kind:finding"    fb8500 "Exploratory finding"
# run status
create "run:planned"     c5def5 "Run created, not started"
create "run:in-progress" 0969da "Run executing"
create "run:completed"   1a7f37 "Run finished"
create "run:aborted"     6e7781 "Run cancelled"
# execution result
create "result:not-run"  eeeeee "Not yet executed"
create "result:passed"   1a7f37 "Passed"
create "result:failed"   d73a4a "Failed"
create "result:blocked"  bf8700 "Blocked"
create "result:skipped"  8c959f "Skipped"
# priority
create "priority:critical" b60205 "Blocks release"
create "priority:high"     d93f0b "Major feature"
create "priority:medium"   fbca04 "Standard"
create "priority:low"      0e8a16 "Cosmetic / edge"
# failure reason
create "fail:bug-in-app"        d73a4a "Product defect"
create "fail:test-data"         e99695 "Test data issue"
create "fail:environment"       fef2c0 "Environment issue"
create "fail:test-needs-update" c2e0c6 "Test out of date"
create "fail:blocked-by-other"  d4c5f9 "Blocked by another test"
create "fail:other"             ededed "Other"
# misc
create "onetest"        5319e7 "Managed by OneTest TMS automation"
create "defect-linked"  5319e7 "Execution has a linked defect"
create "exploratory"    fb8500 "From exploratory testing"
echo "Done."
