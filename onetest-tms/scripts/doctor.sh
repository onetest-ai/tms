#!/usr/bin/env bash
# doctor — preflight checks for operating OneTest TMS. Read-only.
# Usage: doctor.sh [--repo OWNER/NAME] [--org ORG]
set -uo pipefail
ORG="onetest-ai"; REPO=""
while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="$2"; shift 2;; --org) ORG="$2"; shift 2;;
  *) echo "unknown option: $1" >&2; exit 2;;
esac; done
ok(){ echo "  ✓ $1"; }
no(){ echo "  ✗ $1"; }

echo "OneTest TMS doctor — org: $ORG${REPO:+, repo: $REPO}"

echo "Authentication"
if gh auth status >/dev/null 2>&1; then ok "gh authenticated"; else no "gh not authenticated — run: gh auth login"; fi
SCOPES="$(gh api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^X-Oauth-Scopes: //p')"
echo "  scopes: ${SCOPES:-<none>}"
case "$SCOPES" in *repo*) ok "repo scope";; *) no "missing 'repo' scope";; esac
case "$SCOPES" in *admin:org*) ok "admin:org (issue types)";; *) no "no admin:org — issue-type creation unavailable (gh auth refresh -s admin:org)";; esac
case "$SCOPES" in *project*) ok "project (board)";; *) no "no project scope — board ops unavailable (gh auth refresh -s project)";; esac

echo "Org Project"
if gh project list --owner "$ORG" --format json -q '.projects[]|select(.title=="QA Runs")|.number' 2>/dev/null | grep -q .; then
  ok "'QA Runs' project exists"; else no "'QA Runs' project missing — run scripts/bootstrap-project.sh"; fi

echo "Issue types"
TYPES="$(gh api "orgs/$ORG/issue-types" -q '.[].name' 2>/dev/null || true)"
for t in "Test Run" "Test Execution" "Defect" "Exploratory Finding"; do
  grep -qxF "$t" <<<"$TYPES" && ok "type: $t" || no "missing issue type: $t — run scripts/apply-issue-types.sh"
done

if [ -n "$REPO" ]; then
  echo "Repo: $REPO"
  gh api "repos/$REPO" >/dev/null 2>&1 && ok "repo reachable" || no "repo not reachable"
  gh api "repos/$REPO/contents/.onetest/config.yml" >/dev/null 2>&1 && ok ".onetest/config.yml present" || no ".onetest/config.yml missing"
  gh api "repos/$REPO/contents/.onetest/fields.yml" >/dev/null 2>&1 && ok ".onetest/fields.yml present" || no ".onetest/fields.yml missing"
  if gh label list --repo "$REPO" 2>/dev/null | grep -q '^kind:run'; then ok "labels applied"; else no "labels missing — run scripts/apply-labels.sh $REPO"; fi
fi

echo "Done."
