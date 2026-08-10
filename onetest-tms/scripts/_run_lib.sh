# Shared helpers for run scripts (source this; bash 3.2 safe — no associative arrays).
# Provides: winpath, ensure_label, ot_has_type, jget, ot_project_setup,
#           ot_fid, ot_opt, ot_add_item, ot_set_text, ot_set_opt, ot_create_execution.

# Windows/Git Bash compatibility ------------------------------------------------
# Native-Windows Python cannot open MSYS paths like '/tmp/tmp.xxxx'. Convert any
# temp-file path to a Windows path before passing it to Python (argv, never a
# string literal — a backslash path in a `-c` literal triggers a \U unicode
# error). On macOS/Linux `cygpath` is absent, so this is an identity function.
winpath(){ cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }
# Force UTF-8 on every Python subprocess (Windows stdout defaults to cp1252 and
# crashes on chars like ≥ → □ in test-case bodies). Exported into the sourcing shell.
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"

# Create a label if it doesn't exist, so issue creation doesn't 422 on an unknown
# label. Idempotent; safe to call before every issue create. $1=repo $2=name [$3=color]
ensure_label(){ gh label create "$2" --repo "$1" ${3:+--color "$3"} >/dev/null 2>&1 || true; }

# True if org $1 has an issue type named $2. Issue types are ORG-scoped
# (GET /orgs/{org}/issue-types); sending `-f type=NAME` for a name the org
# doesn't define — or on a user/org without the feature — 422s the whole create.
# The org's type list is fetched once and memoized (pipe-joined) per org.
ot_has_type(){ local org="$1" name="$2" v="OT_ITYPES_$(printf '%s' "$1" | tr -c '[:alnum:]' '_')" names
  if ! eval "[ \"\${$v+s}\" = s ]"; then
    names="|$(gh api "orgs/$org/issue-types" --jq '.[].name' 2>/dev/null | tr '\n' '|')" || true
    eval "$v=\"\$names\""
  fi
  eval "case \"\${$v}\" in *\"|\$name|\"*) return 0;; *) return 1;; esac"; }

jget(){ python3 -c "import json,sys;d=json.load(open(sys.argv[1]));v=d.get(sys.argv[2]);print('' if v is None else v)" "$(winpath "$1")" "$2"; }

ot_project_setup(){ # $1=ORG [$2=PN]
  OT_ORG="$1"; OT_PN="${2:-}"
  [ -n "$OT_PN" ] || OT_PN="$(gh project list --owner "$OT_ORG" --format json -q '.projects[]|select(.title=="QA Runs")|.number' | head -1)"
  [ -n "$OT_PN" ] || { echo "QA Runs project not found (run scripts/bootstrap-project.sh)" >&2; return 1; }
  OT_PID="$(gh project view "$OT_PN" --owner "$OT_ORG" --format json -q .id)"
  OT_FL="$(mktemp)"; gh project field-list "$OT_PN" --owner "$OT_ORG" --format json > "$OT_FL"
}
ot_fid(){ python3 -c "import json,sys;print(next((f['id'] for f in json.load(open(sys.argv[1]))['fields'] if f.get('name')==sys.argv[2]),''))" "$(winpath "$OT_FL")" "$1"; }
ot_opt(){ python3 -c "import json,sys
f=next((f for f in json.load(open(sys.argv[1]))['fields'] if f.get('name')==sys.argv[2]),{})
print(next((o['id'] for o in f.get('options',[]) if o['name']==sys.argv[3]),''))" "$(winpath "$OT_FL")" "$1" "$2"; }
ot_add_item(){ gh project item-add "$OT_PN" --owner "$OT_ORG" --url "$1" --format json -q .id; }
ot_set_text(){ gh project item-edit --id "$1" --project-id "$OT_PID" --field-id "$2" --text "$3" >/dev/null; }
ot_set_opt(){ [ -n "$3" ] && gh project item-edit --id "$1" --project-id "$OT_PID" --field-id "$2" --single-select-option-id "$3" >/dev/null || true; }

# Create one execution issue from a test-case file and put it on the board.
# Args: RUN_REPO RUN_NUM RUN_ID ENV CASE_FILE TARGET_OVERRIDE ASSIGNEE TC_HELPER
# Echoes: "<ID>|<TARGET#NUM>|<URL>"
ot_create_execution(){
  local RUN_REPO="$1" RUN_NUM="$2" RUN_ID="$3" ENVIRONMENT="$4" f="$5" TARGET_OVERRIDE="$6" ASSIGNEE="$7" TC="$8"
  local CFG="$(dirname "$TC")/_cfg.py"
  local ID TITLE PRIORITY SIZE TARGETS TAGS TARGET SRC EB ER E_NUM E_ID E_URL IT BASE_URL
  IFS=$'\t' read -r ID TITLE PRIORITY SIZE TARGETS TAGS < <(python3 "$TC" --tsv "$f")
  TARGET="${TARGET_OVERRIDE:-${TARGETS%%,*}}"; TARGET="${TARGET:-$RUN_REPO}"
  SRC="https://github.com/$RUN_REPO/blob/main/$f"
  BASE_URL="$(python3 "$CFG" --env "$ENVIRONMENT" 2>/dev/null || true)"
  EB="$(mktemp)"
  { echo "**Test case:** [\`$ID\`]($SRC) · Priority: ${PRIORITY:-—} · Size: ${SIZE:-—}"
    echo "**Run:** $RUN_ID · **Environment:** $ENVIRONMENT${BASE_URL:+ ($BASE_URL)}"; echo
    if [ -n "$BASE_URL" ]; then python3 "$TC" --exec-body "$f" --base-url "$BASE_URL"; else python3 "$TC" --exec-body "$f"; fi; echo
    echo "<!-- onetest:run=$RUN_ID case=$ID -->"; } > "$EB"
  ensure_label "$TARGET" onetest; ensure_label "$TARGET" kind:execution; ensure_label "$TARGET" result:not-run
  [ -n "$PRIORITY" ] && ensure_label "$TARGET" "priority:$PRIORITY"
  local A=(-X POST "repos/$TARGET/issues" -f title="$ID — $TITLE" -F "body=@$(winpath "$EB")")
  ot_has_type "${TARGET%%/*}" "Test Execution" && A+=(-f type="Test Execution")
  A+=(-f "labels[]=kind:execution" -f "labels[]=result:not-run" -f "labels[]=onetest")
  [ -n "$PRIORITY" ] && A+=(-f "labels[]=priority:$PRIORITY")
  [ -n "$ASSIGNEE" ] && A+=(-f "assignees[]=$ASSIGNEE")
  ER="$(mktemp)"; gh api "${A[@]}" > "$ER"
  E_NUM=$(jget "$ER" number); E_ID=$(jget "$ER" id); E_URL=$(jget "$ER" html_url)
  [ "$TARGET" = "$RUN_REPO" ] && gh api -X POST "repos/$RUN_REPO/issues/$RUN_NUM/sub_issues" -F sub_issue_id="$E_ID" >/dev/null 2>&1 || true
  IT=$(ot_add_item "$E_URL")
  ot_set_opt "$IT" "$(ot_fid Result)" "$(ot_opt Result 'Not run')"
  ot_set_text "$IT" "$(ot_fid Run)" "$RUN_ID"
  ot_set_text "$IT" "$(ot_fid Case)" "$ID"
  [ -n "$PRIORITY" ] && ot_set_opt "$IT" "$(ot_fid Priority)" "$(ot_opt Priority "$PRIORITY")"
  [ -n "$SIZE" ] && ot_set_opt "$IT" "$(ot_fid Size)" "$(ot_opt Size "$SIZE")"
  echo "$ID|$TARGET#$E_NUM|$E_URL"
}
