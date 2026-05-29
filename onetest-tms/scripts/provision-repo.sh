#!/usr/bin/env bash
# provision-repo — stand up a new product TM repo from the template in one command:
# create-from-template → set source_key/name/targets → labels → issue types → project.
#
# Usage:
#   provision-repo.sh --repo onetest-ai/tm-shop --key SHOP --name "Shop" --targets onetest-ai/app-web
# Options:
#   --repo OWNER/NAME   new TM repo to create (required)
#   --key  SOURCE_KEY   ID prefix for cases, e.g. SHOP (required)
#   --name NAME         human name (default: the repo name)
#   --targets a,b       default target repos (comma-separated; optional)
#   --template OWNER/NAME  template repo (default: onetest-ai/tms)
#   --public            create public (default: private)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=""; KEY=""; NAME=""; TARGETS=""; TEMPLATE="onetest-ai/tms"; VIS="--private"
while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="$2"; shift 2;; --key) KEY="$2"; shift 2;; --name) NAME="$2"; shift 2;;
  --targets) TARGETS="$2"; shift 2;; --template) TEMPLATE="$2"; shift 2;; --public) VIS="--public"; shift;;
  *) echo "unknown option: $1" >&2; exit 2;;
esac; done
[ -n "$REPO" ] && [ -n "$KEY" ] || { echo "--repo and --key are required" >&2; exit 2; }
ORG="${REPO%%/*}"; NAME="${NAME:-${REPO##*/}}"

echo "▶ Creating $REPO from $TEMPLATE"
gh repo create "$REPO" $VIS --template "$TEMPLATE" --description "OneTest TMS — $NAME" 2>&1 | tail -1 || \
  echo "  (repo may already exist — continuing)"

# Wait for template content to populate
for i in 1 2 3 4 5; do gh api "repos/$REPO/contents/.onetest/config.yml" >/dev/null 2>&1 && break; sleep 2; done

echo "▶ Configuring .onetest/config.yml"
WT="$(mktemp -d)"; trap 'rm -rf "$WT"' EXIT
gh repo clone "$REPO" "$WT/repo" -- -q
( cd "$WT/repo"
  sed -i.bak "s#^source_key:.*#source_key: $KEY#" .onetest/config.yml
  sed -i.bak "s#^name:.*#name: $NAME#" .onetest/config.yml
  if [ -n "$TARGETS" ]; then
    list="$(echo "$TARGETS" | sed 's/,/, /g')"
    sed -i.bak "s#^default_targets:.*#default_targets: [$list]#" .onetest/config.yml
  fi
  rm -f .onetest/config.yml.bak
  if ! git diff --quiet; then
    git add .onetest/config.yml
    git commit -q -m "config: source_key=$KEY, name=$NAME"
    git push -q origin HEAD
    echo "  ✓ committed config"
  fi )

echo "▶ Applying labels"
"$HERE/apply-labels.sh" "$REPO" >/dev/null && echo "  ✓ labels applied"
echo "▶ Ensuring org issue types ($ORG)"
"$HERE/apply-issue-types.sh" "$ORG" 2>&1 | sed 's/^/  /' || echo "  ⚠ need admin:org scope (skipped)"
echo "▶ Ensuring QA Runs project ($ORG)"
"$HERE/bootstrap-project.sh" "$ORG" "QA Runs" 2>&1 | tail -1 | sed 's/^/  /' || echo "  ⚠ need project scope (skipped)"

echo
echo "✓ $REPO provisioned. Next:"
echo "  • author cases under tests/ (PR)"
echo "  • run:  create_run({ repo: \"$REPO\", name: \"Smoke\", folder: \"tests\", env: \"staging\" })"
