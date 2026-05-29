# `onetest-gh` MCP — Tool Specification

The buildable contract for the npx package that bridges the [web-qa agent family](05-test-run-ux.md)
to GitHub. One package, two entry points, **logic in code**:

- **stdio MCP server** — `npx -y onetest-gh-mcp` — tools for Claude Code / Copilot / VS Code agents.
- **CLI** — `onetest-gh <command>` — same code, for GitHub Actions / autonomous runs.

This spec defines tools, input/output schemas, and the GitHub API calls each makes. It implements
the [functions catalog](functions.md) over the [repo topology](00-repo-topology.md) and
[data model](../data-model/).

---

## 1. Runtime & configuration

Node ≥ 20. Config via env (or `.onetest/config.yml` in the TM repo, overridable per tool call):

| Env | Meaning |
| --- | --- |
| `GITHUB_TOKEN` | GitHub **App** installation token (preferred) or fine-grained PAT — see [auth](00-repo-topology.md#auth-for-cross-repo-work) |
| `OT_TM_REPO` | source test-management repo, `org/tm-login` |
| `OT_ORG` | organization login |
| `OT_PROJECT` | org Project number (run/quality board); created by `bootstrap_project` |
| `OT_SOURCE_KEY` | ID prefix for this TM repo (e.g. `LOGIN`); from `.onetest/config.yml` |
| `OT_DEFAULT_TARGETS` | fallback target repos when a case has no `targets[]` |
| `OT_PAGES_PATH` | path/branch the report publisher writes to (e.g. `docs/` or `gh-pages`) |

MCP config (`.mcp.json` / `.vscode/mcp.json`):
```jsonc
{ "mcpServers": { "onetest-gh": {
  "type": "stdio", "command": "npx", "args": ["-y", "onetest-gh-mcp"],
  "env": { "GITHUB_TOKEN": "${OT_GH_APP_TOKEN}", "OT_TM_REPO": "org/tm-login",
           "OT_ORG": "org", "OT_PROJECT": "12", "OT_SOURCE_KEY": "LOGIN" } } } }
```

---

## 2. Resource model & conventions

| Concept | GitHub home | Notes |
| --- | --- | --- |
| Test case | file in **TM repo** `tests/**/TC.md` | identity `OT_SOURCE_KEY-NNNN`; see [01](01-test-case-management.md) |
| Index | `index.json` in TM repo | built by `build_index`; backs OQL search |
| Run | **run-Issue** in TM repo + **org Project** | human id `RUN-YYYY-MM-DD-NNN`; system id = issue number |
| Execution (task) | **Issue in the target repo**, sub-issue of the run-Issue | one per case; added to the Project |
| Execution status | Project single-select **Result** field | `Not run/In progress/Passed/Failed/Blocked/Skipped` |
| Evidence | committed to TM repo `reports/<run>/screenshots/` | linked by raw URL from the Issue (no native issue-upload API) |
| Defect | **Issue in the target repo**, label `defect` | cross-referenced from the execution Issue |
| Report | `reports/RUN-….md` in TM repo + **Pages** | web-qa report format |
| Automated results | `reports/automated/<workflow-run>.json` in TM repo | parsed from CI artifacts |
| Correlation / coverage | `reports/correlation.json`, `reports/coverage.*` in TM repo | computed in code |

### Project v2 field schema (the tools assume / `bootstrap_project` creates)

| Field | Type | Options |
| --- | --- | --- |
| **Result** | single-select | Not run, In progress, Passed, Failed, Blocked, Skipped |
| **Run** | text | `RUN-YYYY-MM-DD-NNN` |
| **Case** | text | source id, `LOGIN-0042` |
| **Target** | single-select | target repo names |
| **Priority** | single-select | critical, high, medium, low |
| **Size** | single-select | S, M, L |
| **Failure reason** | single-select | bug_in_app, test_data_issue, environment_issue, test_needs_update, blocked_by_other, other |
| Assignees, Iteration | built-in | iteration optional (cadence) |

Projects v2 is **GraphQL-only**. The server resolves and **caches** the project node id, field
ids, and option ids on first use.

### Cross-cutting conventions
- **Idempotency:** every execution Issue body carries a marker
  `<!-- onetest:run=RUN-… case=LOGIN-0042 -->`. Mutating tools search for the marker before
  creating, so re-runs don't duplicate. Tools accept an optional `idempotency_key`.
- **Dry-run:** all mutating tools accept `dry_run: bool` → return the planned changes, write
  nothing.
- **Errors:** tools return `{ ok: false, error: { code, message, details? } }`. Codes:
  `NOT_FOUND, VALIDATION, CONFLICT, PERMISSION, RATE_LIMITED, UPSTREAM`.
- **Pagination/rate limits:** handled in-server (auto-paginate, exponential backoff on secondary
  rate limits). Callers never paginate.
- **pass_rate canonical definition:** `passed / total` (matches the web-qa report). This supersedes
  the OneTest dual-denominator ambiguity — one definition platform-wide. `completion = (total −
  not_run) / total`.

---

## 3. Tools

Grouped A–G. Each: signature → input → output → GitHub calls → caller.

### A. Discovery & read

#### `search_test_cases`
Resolve OQL (or folder/glob/ids) to concrete cases. Backs scope selection & dynamic suites.
```jsonc
// input
{ "query": "tags CONTAINS 'smoke' AND priority IN (critical,high)",  // OQL | {folders:[]} | {ids:[]} | {glob:""}
  "tm_repo": "org/tm-login" }                                         // optional override
// output
{ "ok": true, "count": 12,
  "cases": [ { "id":"LOGIN-0042", "path":"tests/auth/login/TC-0042.md",
               "title":"…", "priority":"critical", "size":"M",
               "targets":["app-web"], "execution_type":"automated" } ] }
```
GitHub: `GET contents index.json` (TM repo) → run `onetest-oql` in code. No writes.
Caller: `test-run-lead`, `test-author`.

#### `get_test_case`
```jsonc
{ "id": "LOGIN-0042" }                       // → full front-matter + rendered steps
```
GitHub: `GET /repos/{tm}/contents/{path}`; parse front-matter + body. Caller: `test-runner`, lead.

#### `get_my_queue`
```jsonc
{ "status": ["Not run","In progress"] }      // default
// → execution Issues assigned to the authenticated user, with case id, run, target
```
GitHub: GraphQL `projectV2.items` filtered by `assignees: viewer` + Result; fallback REST
`GET /search/issues?q=assignee:@me label:onetest-execution state:open`. Caller: tester chat.

#### `list_runs`
```jsonc
{ "state": "open", "limit": 20 }             // → run-Issues with summary fields
```
GitHub: `GET /search/issues?q=repo:{tm} label:onetest-run`. Caller: lead, leads.

---

### B. Run lifecycle

#### `create_run`  ← the core function
Resolve scope → create execution Issues in target repos → create run-Issue → add all to the
Project → assign. (Implements [`create-run`](functions.md#create-run).)
```jsonc
// input
{ "name": "Smoke app-web staging",
  "scope": "tags CONTAINS 'smoke' AND priority IN (critical,high)",   // OQL | {ids|folders|glob}
  "targets": ["app-web"],            // optional; default = union of cases' targets[] / OT_DEFAULT_TARGETS
  "environment": "staging",
  "assignees": { "strategy": "round_robin", "users": ["alice","bob"] },  // or {strategy:"codeowners"}
  "run_id": "RUN-2026-05-29-001",    // optional; server allocates if omitted
  "dry_run": false }
// output
{ "ok": true, "run_id": "RUN-2026-05-29-001", "run_issue": "org/tm-login#88",
  "project_item_count": 12, "project_url": "https://github.com/orgs/org/projects/12/views/3",
  "executions": [ { "case":"LOGIN-0042", "issue":"org/app-web#318", "item_id":"PVTI_…" } ] }
```
GitHub, per run:
1. `search_test_cases` (in-code) → case list.
2. Allocate `run_id` (scan TM `reports/RUN-{date}-*`); create **run-Issue** in TM repo:
   `POST /repos/{tm}/issues` (labels `onetest-run`, `run:planned`).
3. For each case → **execution Issue** in its target repo: `POST /repos/{target}/issues`
   (title `LOGIN-0042 — <title>`, body = rendered steps checklist + `{{base_url}}` resolved +
   marker; labels `onetest-execution`, `priority:*`, tags); link as sub-issue
   `POST /repos/{tm}/issues/{run}/sub_issues`.
4. Assign: `POST /repos/{target}/issues/{n}/assignees`.
5. Add to Project + set fields: GraphQL `addProjectV2ItemById`, then
   `updateProjectV2ItemFieldValue` ×N (Result=Not run, Run, Case, Target, Priority, Size).
6. Label run-Issue `run:in_progress` (scope frozen = the created set).

Idempotent via markers. Caller: `test-run-lead`.

#### `start_run` / `abort_run`
```jsonc
{ "run_id": "RUN-2026-05-29-001" }
```
GitHub: `PATCH` run-Issue labels (`run:in_progress` / `run:aborted`); abort closes open execution
Issues with a comment. Caller: lead.

#### `complete_run`
Aggregate, gate, report, close. Refuses if any execution unresolved unless `force`.
```jsonc
{ "run_id":"RUN-2026-05-29-001", "force": false, "publish": true }
// → { ok, analytics:{…}, report_url, run_issue }
```
GitHub: read Project items (GraphQL) → analytics → (if `publish`) call `publish_report` →
comment summary + link on run-Issue → label `run:completed`, close run-Issue. Caller: lead.

---

### C. Execution recording

#### `record_result`  ← consumes the `test-runner` JSON
Writes one execution's outcome. Input is the runner's JSON (web-qa schema) + the execution ref.
```jsonc
// input
{ "execution": "org/app-web#318",          // or {run_id, case_id}
  "result": "FAIL",                         // PASS|FAIL|BLOCKED  → Passed/Failed/Blocked
  "failure_reason": "bug_in_app",
  "failure_details": "Expected /dashboard, got HTTP 500",
  "steps_total": 5, "steps_completed": 4, "failure_step": 4,
  "evidence": ["reports/RUN-2026-05-29-001/screenshots/LOGIN-0042.png"],
  "console_errors": ["TypeError: …"],
  "duration_seconds": 14, "size": "M", "priority": "critical",
  "metrics": { "tokens": 41000, "tool_uses": 22, "duration_ms": 18342 },
  "defects": [] }
// output
{ "ok": true, "execution":"org/app-web#318", "result_field":"Failed" }
```
GitHub:
1. Resolve issue (marker search if `{run_id,case_id}` given).
2. GraphQL `updateProjectV2ItemFieldValue` → Result + Failure reason.
3. `POST /issues/{n}/comments` with the structured result (steps, failure_details, console_errors,
   metrics, evidence links).
4. Tick the step checklist + close the Issue if PASS (`PATCH state=closed`); FAIL/BLOCKED stay open.
**Evidence-before-PASS:** rejects `PASS` with empty `evidence` → `VALIDATION`. Caller: lead (from
runner output) or runner.

#### `record_step_result`
```jsonc
{ "execution":"org/app-web#318", "step":2, "status":"failed", "actual":"500", "note":"" }
```
GitHub: `PATCH` issue body checklist line. Caller: assisted execution.

#### `attach_evidence`
Commit a screenshot/log and return its raw URL.
```jsonc
{ "run_id":"RUN-…", "case_id":"LOGIN-0042", "file_path":"…local.png", "step": 4 }
// → { ok, url: "https://raw.githubusercontent.com/org/tm-login/…/LOGIN-0042.png" }
```
GitHub: `PUT /repos/{tm}/contents/reports/{run}/screenshots/{name}`. Caller: runner/lead.

#### `rerun_execution`
```jsonc
{ "execution":"org/app-web#318", "reason":"flaky — staging redeploy" }
// → { ok, new_execution: "org/app-web#340" }
```
GitHub: create a new execution Issue linked to the original (`POST issues`, cross-ref comment),
add to Project (Result=Not run). Caller: lead, triage.

---

### D. Defects

#### `create_defect`
```jsonc
{ "target":"app-web", "title":"500 on valid login (staging)",
  "body_md":"repro + expected/actual", "evidence":["…png"],
  "severity":"High", "from_execution":"org/app-web#318" }
// → { ok, defect:"org/app-web#319" }
```
GitHub: `POST /repos/{target}/issues` (labels `defect`, `severity:High`); cross-ref comment on the
execution Issue. Severity defaults from case priority (critical/high→High, …). Caller: lead.

#### `link_defect`
```jsonc
{ "execution":"org/app-web#318", "defect":"org/app-web#319" }
```
GitHub: cross-reference comment + `defect-linked` label on the execution Issue. Caller: lead.

---

### E. Reporting & analytics

#### `get_run_analytics`
```jsonc
{ "run_id":"RUN-2026-05-29-001" }
// → { ok, total, passed, failed, blocked, skipped, not_run,
//     pass_rate, completion, by_priority:{…}, by_size:{…},
//     failures_by_reason:{…}, metrics:{tokens_total, avg_tokens_per_case, duration_total} }
```
GitHub: GraphQL Project items (read). Pure compute. Caller: lead, leads, Q&A.

#### `publish_report`
Render the [web-qa report format](https://github.com/arozumenko/sdlc-skills/blob/main/bundles/web-qa/knowledge/test-run-report-format.md)
(MD + HTML) and publish.
```jsonc
{ "run_id":"RUN-2026-05-29-001", "html": true }
// → { ok, md_path:"reports/RUN-2026-05-29-001.md", pages_url:"https://org.github.io/tm-login/RUN-…" }
```
GitHub: `PUT contents reports/RUN-….md` (+ HTML to `OT_PAGES_PATH`); comment link on run-Issue.
Caller: `test-reporter`, `complete_run`.

---

### F. Automated results & correlation (the `receiver` replacement)

#### `ingest_automated_results`
Parse a CI artifact (JUnit/JSON) into the normalized launch record. Runs in the **target** repo's
CI (CLI mode), or against an uploaded artifact.
```jsonc
{ "source": { "junit_path":"results.xml" } ,   // or { artifact:{run_id,name} } | { bucket,key }
  "context": { "target":"app-web", "ref":"refs/tags/v2.1.0", "environment":"staging" },
  "dispatch_to_tm": true }
// → { ok, launch:{ total, passed, failed, skipped, items:[{code_ref,status,duration_ms,...}] },
//     written:"reports/automated/<workflow-run>.json" }
```
GitHub: parse in code (reuse `receiver` JUnit parser); `PUT contents reports/automated/<id>.json`
(TM repo); if `dispatch_to_tm`, `POST /repos/{tm}/dispatches` (`event_type: automated-results`)
to trigger correlation. Emits `$GITHUB_STEP_SUMMARY` in CLI mode. Caller: CI / `parse-automated-results`.

#### `correlate_results`
Match `automation_test_id` (cases) ⇄ `code_ref` (automated items); write correlation.
```jsonc
{ "launch_ref":"reports/automated/<id>.json" }   // or {since:"-7d"} to re-correlate
// → { ok, matched:[{case_id, code_ref, status, confidence}], unmatched_refs:[…], written:"reports/correlation.json" }
```
GitHub: `GET index.json` + the launch json; normalize both to `file:Class.method` (reuse
`_normalize_ref`); `PUT contents reports/correlation.json`. Caller: post-ingest, scheduled.

#### `get_automation_coverage`
```jsonc
{ "targets":["app-web"], "priority":["critical"] }   // filters optional
// → { ok, total_test_cases, marked_automated, linked_to_results, no_automation_ref,
//     automation_gap, automation_gap_percentage, coverage_by_priority:[…], coverage_by_category:[…] }
```
GitHub: read `index.json` + `correlation.json`; compute (mirrors `get_automation_coverage_stats`);
optionally `publish_report` a coverage page. Caller: scheduled, Q&A.

---

### G. Admin / index

#### `bootstrap_project`
Create the org Project with the field schema in §2 (idempotent). Returns ids the server caches.
GitHub: GraphQL `createProjectV2` + `createProjectV2Field` ×N. Caller: one-time setup.

#### `build_index`
Scan TM repo test files → `index.json` (id, title, priority, type, module, size, status,
execution_type, automation_test_id, targets, requirements, tags, path, last_commit_sha).
GitHub: `GET git/trees?recursive=1` + `GET contents` (or local FS in CI); `PUT contents
index.json`. Trigger: `push` to `main` (Action) or on demand. Caller: CI, search cold-start.

---

### H. Authoring & management (test-case parity)

Brings the package to parity with OneTest **Test Case Management**. Every **mutating** tool opens
a **PR to the TM repo** (the approval gate = PR review) unless `commit_direct:true` is allowed by
repo policy. Compact form (name · purpose · GitHub mechanism · caller):

| Tool | Purpose | GitHub mechanism | Caller |
| --- | --- | --- | --- |
| `create_test_case` | allocate `SOURCE_KEY-NNNN`, write `tests/<folder>/<ID>_<slug>.md` (front-matter + steps) | branch + `PUT contents` + `POST pulls`; id via `allocate-id` (concurrency) | `test-author`, chat |
| `update_test_case` | edit a case = **new version** (git commit) | `GET`+`PUT contents` on a branch + `POST pulls` | author, chat |
| `delete_test_case` | remove a case | `DELETE contents`, PR | chat |
| `move_test_case` | move to another folder/suite | rename path (`PUT`+`DELETE contents`), PR | chat |
| `set_tags` | add/remove front-matter `tags[]` (auto-create unknown) | edit front-matter, PR/commit | author, chat |
| `bulk_edit` | move / tag / set-field across many cases | one PR touching N files | chat |
| `validate_test_case` | schema + field-value allow-list check (**the HTTP 422 replacement**), no write | `GET .onetest/fields.yml` (+ org defaults), validate in code | CI (`validate-test-case`), pre-commit |
| `get_history` | a case's versions/audit (author, change_reason, change_category) | `GET commits?path=<file>` | chat, review |
| `diff_versions` | structured diff of a case between two refs | `GET contents@refA/@refB` (or compare), diff in code | chat, review |
| `list_folders` / `create_folder` / `move_folder` | suite tree ops; dynamic suite via `_suite.yml {dynamic, oql}` | tree read / `contents` PR | chat |
| `list_field_values` | merged `status/execution_type/test_category` allow-lists | `GET .onetest/fields.yml` ⊕ org defaults | query builder, validation |
| `get_oql_schema` / `validate_oql` | query-builder schema + parse/validate (parity with `/search/schema`, `/search/validate`) | in-code (`onetest-oql`) over `index.json` | chat, UI |
| `set_parameters` | data-driven parameter set (front-matter `parameters` or sibling `*.params.yml`) | edit/`PUT contents`, PR | author |
| `import_test_cases` / `export_test_cases` | XLSX/CSV/ZIP ⇄ files | import → PR; export → artifact/Release asset | dispatch/CI |
| `get_test_case_stats` | counts by status + unassigned | read `index.json` + folder map | chat, dashboards |

`prompt_templates`, `custom_field_definitions`, and `saved_queries` are **config/files** in
`.onetest/` edited via PR (no dedicated tool needed); `list_field_values` / `get_oql_schema`
expose them read-side.

### I. Execution & reporting additions (execution parity)

Closes the remaining gaps vs OneTest **Test Execution Management**:

| Tool | Purpose | GitHub mechanism | Caller |
| --- | --- | --- | --- |
| `add_to_run` | add cases to an existing run (parity `add-tests` / `add-from-oml`) | resolve scope → new execution Issues + Project items, link as sub-issues | lead |
| `assign_execution` | (re)assign an execution | `POST issues/{n}/assignees` + Project Assignee | lead, tester |
| `update_run` / `delete_run` | run metadata edit / delete | `PATCH`/close run-Issue + Project | lead |
| `copy_run` | clone a completed run for re-execution | re-`create_run` from the original scope snapshot | lead |
| `get_execution_history` | per-case manual + automated results merged (parity `execution-history`) | `GET /search/issues` (executions) + `correlation.json` | chat, case view |
| `get_dashboard` / `get_trends` | cross-run dashboard & trend series (parity `reporting/dashboard|summary|trends`) | read prior `reports/RUN-*.md` front-matter + open run Projects | leads, Q&A |

> **Shared public reports** (OneTest `shared_reports`) = `publish_report` to **GitHub Pages** — the
> Pages URL is the public, no-auth link; revoke = unpublish/remove. No token table needed.

## 4. CLI mapping

Every tool has a CLI subcommand (same inputs as flags/JSON, same outputs as JSON to stdout):
```
onetest-gh create-run   --name "Smoke" --scope "tags CONTAINS 'smoke'" --env staging
onetest-gh record-result --execution org/app-web#318 --json result.json
onetest-gh ingest-automated-results --junit results.xml --target app-web --dispatch-to-tm
onetest-gh correlate-results
onetest-gh coverage --targets app-web
onetest-gh complete-run --run-id RUN-2026-05-29-001 --publish
onetest-gh build-index
```
Used by GitHub Actions for autonomous/CI runs (`ai-run`, `parse-automated-results`).

## 5. GitHub API surface (summary)

- **REST:** issues (create/update/comment/assign/labels), sub-issues, search/issues, contents
  (get/put), repository dispatches, git trees.
- **GraphQL (Projects v2):** `projectV2`, `addProjectV2ItemById`,
  `updateProjectV2ItemFieldValue`, `createProjectV2(Field)`, item/field queries.
- **No official API** for native issue file-uploads → evidence is committed to the TM repo and
  linked (documented limitation).

## 6. Permissions (GitHub App)

| Scope | On | Needed by |
| --- | --- | --- |
| Contents R/W | TM repo | index, evidence, reports, correlation |
| Issues R/W | TM + target repos | run-Issue, execution Issues, defects |
| Projects R/W | org | board items + fields |
| Metadata R | all | resolution |
| `repository_dispatch` | TM repo | automated-results handoff |

## 7. Versioning

This schema is the contract between the web-qa agents and GitHub. Tools are additive; breaking a
schema bumps a `protocolVersion` returned by an `about` tool. Agents should tolerate unknown output
fields.
