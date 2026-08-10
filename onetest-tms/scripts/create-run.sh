#!/usr/bin/env bash
# create-run — gh-CLI implementation of the `create_run` tool (spec §B).
# Resolves a scope of test-case files → creates a "Test Run" parent issue →
# one "Test Execution" issue per case (in its target repo) → links them as
# sub-issues → adds all to the org Project with fields set.
#
# Usage:
#   scripts/create-run.sh --name "Smoke app-web staging" --folder tests/authentication [options]
#   scripts/create-run.sh --name "Login" --glob "tests/**/*.md" --tag smoke --env staging
#   scripts/create-run.sh --name "Ad-hoc" tests/authentication/login/TMS-0001_valid-login.md
#
# Options:
#   --name NAME          run name (required)
#   --folder DIR         select all *.md under DIR (recursive)
#   --glob  PATTERN      select files matching a glob
#   --tag   TAG          keep only cases whose front-matter tags include TAG
#   --env   ENV          environment (default: staging)
#   --target OWNER/REPO  override target repo for all cases (else case front-matter targets[0], else this repo)
#   --assignees a,b,c    round-robin assign executions
#   --project N          org Project number (default: looked up by title "QA Runs")
#   --org ORG            org (default: onetest-ai)
#   --dry-run            print the plan, create nothing
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/_run_lib.sh"
TC="$HERE/_tc.py"; CFG="$HERE/_cfg.py"

# ---- args -----------------------------------------------------------------
NAME=""; FOLDER=""; GLOB=""; TAG=""; OQL=""; ENVIRONMENT="staging"; TARGET_OVERRIDE=""
ASSIGNEES=""; ORG="onetest-ai"; PROJECT_NUMBER=""; DRY=0; declare -a FILES=()
while [ $# -gt 0 ]; do case "$1" in
  --name) NAME="$2"; shift 2;;
  --folder) FOLDER="$2"; shift 2;;
  --glob) GLOB="$2"; shift 2;;
  --tag) TAG="$2"; shift 2;;
  --oql) OQL="$2"; shift 2;;
  --env) ENVIRONMENT="$2"; shift 2;;
  --target) TARGET_OVERRIDE="$2"; shift 2;;
  --assignees) ASSIGNEES="$2"; shift 2;;
  --project) PROJECT_NUMBER="$2"; shift 2;;
  --org) ORG="$2"; shift 2;;
  --dry-run) DRY=1; shift;;
  -*) echo "unknown option: $1" >&2; exit 2;;
  *) FILES+=("$1"); shift;;
esac; done
[ -n "$NAME" ] || { echo "--name is required" >&2; exit 2; }

RUN_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
# jget / winpath / ensure_label / ot_has_type come from _run_lib.sh

# ---- resolve scope --------------------------------------------------------
declare -a CAND=()
[ ${#FILES[@]} -gt 0 ] && CAND+=("${FILES[@]}")
[ -n "$FOLDER" ] && while IFS= read -r f; do CAND+=("$f"); done < <(find "$FOLDER" -type f -name '*.md' ! -name 'README.md' ! -name '_suite.yml' | sort)
[ -n "$GLOB" ] && while IFS= read -r f; do CAND+=("$f"); done < <(bash -c "shopt -s globstar nullglob; for x in $GLOB; do echo \$x; done" | sort)
if [ -n "$OQL" ]; then
  [ -f index.json ] || python3 "$HERE/_index.py" --dir tests --out index.json
  while IFS= read -r f; do CAND+=("$f"); done < <(python3 "$HERE/_oql.py" --query "$OQL" --index index.json)
fi
[ ${#CAND[@]} -gt 0 ] || { echo "no scope given — use --folder, --glob, --oql, or file args" >&2; exit 2; }

declare -a SELECTED=()
for f in "${CAND[@]}"; do
  [ -f "$f" ] || continue
  IFS=$'\t' read -r ID TITLE PRIORITY SIZE TARGETS TAGS < <(python3 "$TC" --tsv "$f")
  [ -n "$ID" ] || continue                                   # skip non-test-case markdown
  if [ -n "$TAG" ]; then case ",$TAGS," in *",$TAG,"*) ;; *) continue;; esac; fi
  SELECTED+=("$f")
done
[ ${#SELECTED[@]} -gt 0 ] || { echo "scope matched no test cases" >&2; exit 1; }

# ---- run id (RUN-<SOURCE_KEY>-YYYY-MM-DD-NNN) -----------------------------
# The source key keeps the run id unique on the shared org Project board, so
# aggregation never mixes runs from different TM repos.
KEY="$(sed -n 's/^source_key:[[:space:]]*\([A-Za-z0-9_-]\{1,\}\).*/\1/p' .onetest/config.yml 2>/dev/null | head -1)"; KEY="${KEY:-RUN}"
TODAY="$(date +%Y-%m-%d)"; PREFIX="RUN-$KEY-$TODAY"
LASTN="$(gh issue list --repo "$RUN_REPO" --label kind:run --search "$PREFIX in:title" --state all --json title \
          -q '[.[].title | capture("'"$PREFIX"'-(?<n>[0-9]+)").n | tonumber] | max // 0' 2>/dev/null || echo 0)"
RUN_ID="$PREFIX-$(printf '%03d' $((LASTN + 1)))"

# ---- plan / dry-run -------------------------------------------------------
echo "Run:        $NAME ($RUN_ID)"
echo "Env:        $ENVIRONMENT     Project: ${PROJECT_NUMBER:-auto}/$ORG     TM repo: $RUN_REPO"
echo "Cases (${#SELECTED[@]}):"
for f in "${SELECTED[@]}"; do
  IFS=$'\t' read -r ID TITLE PRIORITY SIZE TARGETS TAGS < <(python3 "$TC" --tsv "$f")
  TARGET="${TARGET_OVERRIDE:-${TARGETS%%,*}}"; TARGET="${TARGET:-$RUN_REPO}"
  printf '  %-12s %-9s %-3s → %-24s %s\n' "$ID" "$PRIORITY" "$SIZE" "$TARGET" "$TITLE"
done
[ "$DRY" -eq 1 ] && { echo "(dry-run — nothing created)"; exit 0; }

# ---- resolve project + field/option ids -----------------------------------
[ -n "$PROJECT_NUMBER" ] || PROJECT_NUMBER="$(gh project list --owner "$ORG" --format json -q '.projects[] | select(.title=="QA Runs") | .number' | head -1)"
[ -n "$PROJECT_NUMBER" ] || { echo "QA Runs project not found; run scripts/bootstrap-project.sh" >&2; exit 1; }
PROJECT_ID="$(gh project view "$PROJECT_NUMBER" --owner "$ORG" --format json -q .id)"
FL="$(mktemp)"; gh project field-list "$PROJECT_NUMBER" --owner "$ORG" --format json > "$FL"
fid(){ python3 -c "import json,sys;print(next((f['id'] for f in json.load(open(sys.argv[1]))['fields'] if f.get('name')==sys.argv[2]),''))" "$(winpath "$FL")" "$1"; }
opt(){ python3 -c "import json,sys
f=next((f for f in json.load(open(sys.argv[1]))['fields'] if f.get('name')==sys.argv[2]),{})
print(next((o['id'] for o in f.get('options',[]) if o['name']==sys.argv[3]),''))" "$(winpath "$FL")" "$1" "$2"; }
F_RESULT=$(fid Result); O_NOTRUN=$(opt Result "Not run")
F_RUN=$(fid Run); F_CASE=$(fid Case); F_PRIO=$(fid Priority); F_SIZE=$(fid Size)
set_text(){ gh project item-edit --id "$1" --project-id "$PROJECT_ID" --field-id "$2" --text "$3" >/dev/null; }
set_opt(){  [ -n "$3" ] && gh project item-edit --id "$1" --project-id "$PROJECT_ID" --field-id "$2" --single-select-option-id "$3" >/dev/null || true; }
add_item(){ gh project item-add "$PROJECT_NUMBER" --owner "$ORG" --url "$1" --format json -q .id; }

# ---- create the Test Run parent issue -------------------------------------
RUNBODY="$(mktemp)"
{ echo "**Run:** $RUN_ID"; echo "**Environment:** $ENVIRONMENT"; echo "**Scope:** ${#SELECTED[@]} cases"; echo;
  echo "## Executions"; } > "$RUNBODY"
RESP="$(mktemp)"
ensure_label "$RUN_REPO" onetest; ensure_label "$RUN_REPO" kind:run; ensure_label "$RUN_REPO" run:in-progress "0075ca"
declare -a RA=(-X POST "repos/$RUN_REPO/issues" -f title="$RUN_ID — $NAME" -F "body=@$(winpath "$RUNBODY")")
ot_has_type "${RUN_REPO%%/*}" "Test Run" && RA+=(-f type="Test Run")
RA+=(-f "labels[]=kind:run" -f "labels[]=run:in-progress" -f "labels[]=onetest")
gh api "${RA[@]}" > "$RESP"
RUN_NUM=$(jget "$RESP" number); RUN_URL=$(jget "$RESP" html_url)
RUN_ITEM=$(add_item "$RUN_URL"); set_text "$RUN_ITEM" "$F_RUN" "$RUN_ID"
echo "✓ run issue: $RUN_URL"

# ---- per-case execution issues --------------------------------------------
declare -a AS=(); [ -n "$ASSIGNEES" ] && IFS=',' read -ra AS <<<"$ASSIGNEES"
i=0
for f in "${SELECTED[@]}"; do
  IFS=$'\t' read -r ID TITLE PRIORITY SIZE TARGETS TAGS < <(python3 "$TC" --tsv "$f")
  TARGET="${TARGET_OVERRIDE:-${TARGETS%%,*}}"; TARGET="${TARGET:-$RUN_REPO}"
  SRC="https://github.com/$RUN_REPO/blob/main/$f"
  BASE_URL="$(python3 "$CFG" --env "$ENVIRONMENT" 2>/dev/null || true)"
  EB="$(mktemp)"
  { echo "**Test case:** [\`$ID\`]($SRC) · Priority: ${PRIORITY:-—} · Size: ${SIZE:-—}";
    echo "**Run:** $RUN_ID · **Environment:** $ENVIRONMENT${BASE_URL:+ ($BASE_URL)}"; echo;
    if [ -n "$BASE_URL" ]; then python3 "$TC" --exec-body "$f" --base-url "$BASE_URL"; else python3 "$TC" --exec-body "$f"; fi; echo;
    echo "<!-- onetest:run=$RUN_ID case=$ID -->"; } > "$EB"
  ensure_label "$TARGET" onetest; ensure_label "$TARGET" kind:execution; ensure_label "$TARGET" result:not-run
  [ -n "$PRIORITY" ] && ensure_label "$TARGET" "priority:$PRIORITY"
  declare -a A=(-X POST "repos/$TARGET/issues" -f title="$ID — $TITLE" -F "body=@$(winpath "$EB")")
  ot_has_type "${TARGET%%/*}" "Test Execution" && A+=(-f type="Test Execution")
  A+=(-f "labels[]=kind:execution" -f "labels[]=result:not-run" -f "labels[]=onetest")
  [ -n "$PRIORITY" ] && A+=(-f "labels[]=priority:$PRIORITY")
  if [ ${#AS[@]} -gt 0 ]; then A+=(-f "assignees[]=${AS[$((i % ${#AS[@]}))]}"); fi
  ER="$(mktemp)"; gh api "${A[@]}" > "$ER"
  E_NUM=$(jget "$ER" number); E_ID=$(jget "$ER" id); E_URL=$(jget "$ER" html_url)
  # link as sub-issue (same-repo only); else reference in run body
  if [ "$TARGET" = "$RUN_REPO" ]; then
    gh api -X POST "repos/$RUN_REPO/issues/$RUN_NUM/sub_issues" -F sub_issue_id="$E_ID" >/dev/null 2>&1 || true
  fi
  echo "- [ ] $ID — $TITLE ($E_URL)" >> "$RUNBODY"
  # project item + fields
  IT=$(add_item "$E_URL")
  set_opt "$IT" "$F_RESULT" "$O_NOTRUN"
  set_text "$IT" "$F_RUN" "$RUN_ID"
  set_text "$IT" "$F_CASE" "$ID"
  [ -n "$PRIORITY" ] && set_opt "$IT" "$F_PRIO" "$(opt Priority "$PRIORITY")"
  [ -n "$SIZE" ] && set_opt "$IT" "$F_SIZE" "$(opt Size "$SIZE")"
  echo "  ✓ $ID → $TARGET#$E_NUM"
  i=$((i + 1))
done

# ---- finalize run body ----------------------------------------------------
gh issue edit "$RUN_NUM" --repo "$RUN_REPO" --body-file "$RUNBODY" >/dev/null
echo
echo "Done. Run $RUN_ID — ${#SELECTED[@]} executions."
echo "Board:  https://github.com/orgs/$ORG/projects/$PROJECT_NUMBER"
echo "Run:    $RUN_URL"
