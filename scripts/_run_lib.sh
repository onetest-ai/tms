# Shared helpers for run scripts (source this; bash 3.2 safe — no associative arrays).
# Provides: jget, ot_project_setup, ot_fid, ot_opt, ot_add_item, ot_set_text,
#           ot_set_opt, ot_create_execution.

jget(){ python3 -c "import json,sys;d=json.load(open(sys.argv[1]));v=d.get(sys.argv[2]);print('' if v is None else v)" "$1" "$2"; }

ot_project_setup(){ # $1=ORG [$2=PN]
  OT_ORG="$1"; OT_PN="${2:-}"
  [ -n "$OT_PN" ] || OT_PN="$(gh project list --owner "$OT_ORG" --format json -q '.projects[]|select(.title=="QA Runs")|.number' | head -1)"
  [ -n "$OT_PN" ] || { echo "QA Runs project not found (run scripts/bootstrap-project.sh)" >&2; return 1; }
  OT_PID="$(gh project view "$OT_PN" --owner "$OT_ORG" --format json -q .id)"
  OT_FL="$(mktemp)"; gh project field-list "$OT_PN" --owner "$OT_ORG" --format json > "$OT_FL"
}
ot_fid(){ python3 -c "import json,sys;print(next((f['id'] for f in json.load(open('$OT_FL'))['fields'] if f.get('name')==sys.argv[1]),''))" "$1"; }
ot_opt(){ python3 -c "import json,sys
f=next((f for f in json.load(open('$OT_FL'))['fields'] if f.get('name')==sys.argv[1]),{})
print(next((o['id'] for o in f.get('options',[]) if o['name']==sys.argv[2]),''))" "$1" "$2"; }
ot_add_item(){ gh project item-add "$OT_PN" --owner "$OT_ORG" --url "$1" --format json -q .id; }
ot_set_text(){ gh project item-edit --id "$1" --project-id "$OT_PID" --field-id "$2" --text "$3" >/dev/null; }
ot_set_opt(){ [ -n "$3" ] && gh project item-edit --id "$1" --project-id "$OT_PID" --field-id "$2" --single-select-option-id "$3" >/dev/null || true; }

# Create one execution issue from a test-case file and put it on the board.
# Args: RUN_REPO RUN_NUM RUN_ID ENV CASE_FILE TARGET_OVERRIDE ASSIGNEE TC_HELPER
# Echoes: "<ID>|<TARGET#NUM>|<URL>"
ot_create_execution(){
  local RUN_REPO="$1" RUN_NUM="$2" RUN_ID="$3" ENVIRONMENT="$4" f="$5" TARGET_OVERRIDE="$6" ASSIGNEE="$7" TC="$8"
  local ID TITLE PRIORITY SIZE TARGETS TAGS TARGET SRC EB ER E_NUM E_ID E_URL IT
  IFS=$'\t' read -r ID TITLE PRIORITY SIZE TARGETS TAGS < <(python3 "$TC" --tsv "$f")
  TARGET="${TARGET_OVERRIDE:-${TARGETS%%,*}}"; TARGET="${TARGET:-$RUN_REPO}"
  SRC="https://github.com/$RUN_REPO/blob/main/$f"
  EB="$(mktemp)"
  { echo "**Test case:** [\`$ID\`]($SRC) · Priority: ${PRIORITY:-—} · Size: ${SIZE:-—}"
    echo "**Run:** $RUN_ID · **Environment:** $ENVIRONMENT"; echo
    echo "### Steps"; python3 "$TC" --steps "$f"; echo
    echo "<!-- onetest:run=$RUN_ID case=$ID -->"; } > "$EB"
  local A=(-X POST "repos/$TARGET/issues" -f title="$ID — $TITLE" -F "body=@$EB" -f type="Test Execution"
           -f "labels[]=kind:execution" -f "labels[]=result:not-run" -f "labels[]=onetest")
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
