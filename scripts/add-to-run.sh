#!/usr/bin/env bash
# add-to-run — add cases to an existing run (spec §I add_to_run).
# Usage:
#   scripts/add-to-run.sh --run RUN-2026-05-29-001 --folder tests/checkout
#   scripts/add-to-run.sh --run RUN-... --oql "tags CONTAINS 'smoke'" --target onetest-ai/app-web
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/_run_lib.sh"; TC="$HERE/_tc.py"
RUN=""; FOLDER=""; GLOB=""; TAG=""; OQL=""; ENVN=""; TARGET_OVERRIDE=""; ASSIGNEES=""
ORG="onetest-ai"; PN=""; DRY=0; declare -a FILES=()
while [ $# -gt 0 ]; do case "$1" in
  --run) RUN="$2"; shift 2;; --folder) FOLDER="$2"; shift 2;; --glob) GLOB="$2"; shift 2;;
  --tag) TAG="$2"; shift 2;; --oql) OQL="$2"; shift 2;; --env) ENVN="$2"; shift 2;;
  --target) TARGET_OVERRIDE="$2"; shift 2;; --assignees) ASSIGNEES="$2"; shift 2;;
  --project) PN="$2"; shift 2;; --org) ORG="$2"; shift 2;; --dry-run) DRY=1; shift;;
  -*) echo "unknown option: $1" >&2; exit 2;; *) FILES+=("$1"); shift;;
esac; done
[ -n "$RUN" ] || { echo "--run RUN-ID is required" >&2; exit 2; }
RUN_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

# ---- scope ----------------------------------------------------------------
declare -a CAND=()
[ ${#FILES[@]} -gt 0 ] && CAND+=("${FILES[@]}")
[ -n "$FOLDER" ] && while IFS= read -r f; do CAND+=("$f"); done < <(find "$FOLDER" -type f -name '*.md' ! -name 'README.md' | sort)
[ -n "$GLOB" ] && while IFS= read -r f; do CAND+=("$f"); done < <(bash -c "shopt -s globstar nullglob; for x in $GLOB; do echo \$x; done" | sort)
if [ -n "$OQL" ]; then
  [ -f index.json ] || python3 "$HERE/_index.py" --dir tests --out index.json
  while IFS= read -r f; do CAND+=("$f"); done < <(python3 "$HERE/_oql.py" --query "$OQL" --index index.json)
fi
[ ${#CAND[@]} -gt 0 ] || { echo "no scope — use --folder/--glob/--oql/files" >&2; exit 2; }
declare -a SELECTED=()
for f in "${CAND[@]}"; do
  [ -f "$f" ] || continue
  IFS=$'\t' read -r ID _ _ _ _ TAGS < <(python3 "$TC" --tsv "$f"); [ -n "$ID" ] || continue
  if [ -n "$TAG" ]; then case ",$TAGS," in *",$TAG,"*) ;; *) continue;; esac; fi
  SELECTED+=("$f")
done
[ ${#SELECTED[@]} -gt 0 ] || { echo "scope matched no test cases" >&2; exit 1; }

# ---- locate the run issue -------------------------------------------------
RUN_NUM="$(gh issue list --repo "$RUN_REPO" --label kind:run --state all --search "$RUN in:title" \
            --json number,title -q ".[] | select(.title|startswith(\"$RUN\")) | .number" | head -1)"
[ -n "$RUN_NUM" ] || { echo "run issue for $RUN not found" >&2; exit 1; }
[ -n "$ENVN" ] || ENVN="$(gh issue view "$RUN_NUM" --repo "$RUN_REPO" --json body -q '.body' | sed -n 's/.*\*\*Environment:\*\* *//p' | head -1)"

echo "Add ${#SELECTED[@]} case(s) to $RUN (issue #$RUN_NUM), env=$ENVN, target=${TARGET_OVERRIDE:-<case>}"
[ "$DRY" -eq 1 ] && { for f in "${SELECTED[@]}"; do echo "  + $f"; done; echo "(dry-run)"; exit 0; }

ot_project_setup "$ORG" "$PN"
gh issue reopen "$RUN_NUM" --repo "$RUN_REPO" >/dev/null 2>&1 || true
gh issue edit "$RUN_NUM" --repo "$RUN_REPO" --remove-label run:completed --add-label run:in-progress >/dev/null 2>&1 || true

declare -a AS=(); [ -n "$ASSIGNEES" ] && IFS=',' read -ra AS <<<"$ASSIGNEES"
APPEND="$(mktemp)"; i=0
for f in "${SELECTED[@]}"; do
  AS_ONE=""; [ ${#AS[@]} -gt 0 ] && AS_ONE="${AS[$((i % ${#AS[@]}))]}"
  OUT="$(ot_create_execution "$RUN_REPO" "$RUN_NUM" "$RUN" "$ENVN" "$f" "$TARGET_OVERRIDE" "$AS_ONE" "$TC")"
  ID="${OUT%%|*}"; REST="${OUT#*|}"; REF="${REST%%|*}"; URL="${REST#*|}"
  echo "  ✓ $ID → $REF"; echo "- [ ] $ID ($URL)" >> "$APPEND"; i=$((i + 1))
done
# append to run body
BODY="$(mktemp)"; gh issue view "$RUN_NUM" --repo "$RUN_REPO" --json body -q '.body' > "$BODY"
{ echo; echo "### Added $(date +%Y-%m-%d)"; cat "$APPEND"; } >> "$BODY"
gh issue edit "$RUN_NUM" --repo "$RUN_REPO" --body-file "$BODY" >/dev/null
echo "✓ added ${#SELECTED[@]} to $RUN"
