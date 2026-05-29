# 2 — Test Execution Management

**What it is:** planning and running test cases, and recording per-step results and evidence.
Implemented by the `test-management` service (runs/executions REST + MCP) and the `core` UI;
AI-agent execution is driven by `qa-agent` / `octobots` through MCP.

→ Data model: [data-model/03-test-execution.md](../data-model/03-test-execution.md).

## Core concepts

- A **test run** is a test cycle: a scoped set of executions in a context (environment / build /
  release / sprint). Its scope is **frozen** at start (`scope_snapshot`).
- A **test execution** is one test case's run within a run — the central record. It carries
  status, per-step results, notes, evidence, failure classification, defect links, and timing.
- Three actors write executions through the **same data model**: humans (UI), AI agents (MCP),
  and — separately — automated frameworks (which post to `receiver`, not here; see
  [Automated Results](03-automated-test-results-management.md)).

## Lifecycles (state machines)

**Run:** `draft`/`planned` → **start** (freezes scope) → `in_progress` → **complete** →
`completed`, or **abort** → `aborted`. **copy** clones a completed run for re-execution.

**Execution:** `not_run` → **start** → `in_progress` → **complete(status)** → `passed` /
`failed` / `blocked` / `skipped`. **rerun(reason)** creates a child execution. Executions are
only executable while the parent run is `in_progress`. **Defect links remain editable after
completion** (supports fail → file ticket → link).

**Step:** `pending` (UI transient) → `passed` / `failed` / `skipped` / `blocked`. UI fail-cascade:
failing step N auto-passes steps `<N`, fails N, blocks `>N`.

## Capabilities

### Building & running a run
- Create a run with name, environment, optional build/release/sprint.
- Add test cases by **id list**, **bulk** (deduped), or **from an OQL query**
  (`/runs/{id}/add-from-oql`).
- Start (freeze scope) → execute → complete (generates analytics) or abort.

### Recording a manual execution (UI ExecutionPanel)
- Step-by-step **Pass / Fail / Skip / Blocked**, with per-step actual result + notes.
- Per-step **screenshot/evidence upload** (to `artifacts`, presigned URLs).
- On failure: a dialog captures **failure reason** (`bug_in_app / test_data_issue /
  environment_issue / test_needs_update / blocked_by_other / other`), failure details, steps to
  reproduce, and **defect links** (Jira/GitHub/ADO URLs).
- "Complete Execution" → run summary.
- Personal queue via `/me/executions` (per-execution `assigned_to`).

### AI-agent execution (the git-native-relevant model)
The `qa-agent` repo ships a `/qa-onetest` skill for **Claude Code** that drives runs via the
`test-management` MCP server (`https://tms.onetest.ai/mcp/test-management`, Bearer API key,
`X-Project-Id`). Setup: install Claude Code → `npx github:onetest-ai/qa-agent init` → connect via
browser (or hand-edit `.mcp.json`).

`/qa-onetest` commands:
- `run` — create + start + execute + complete a full run.
- `pull tests` — fetch cases for local browser execution.
- `push findings` — convert QA audit findings into OneTest test cases (auto-maps priority +
  category).
- `status` — show execution queue and active runs.

During `run`, for each case the agent: navigates to the target URL in **real Chrome via Chrome
DevTools Protocol**, executes each step, captures **before/after screenshots**, checks the
browser console for errors, validates actual vs expected, then calls `record_test_result` /
`record_exploratory_result`. **Exploratory findings** (issues outside existing cases) are
recorded alongside planned results. **Parallel execution** runs non-conflicting tests on separate
Chrome instances / CDP ports.

`octobots` is the team-scale version: autonomous Claude Code instances (incl. a QA role, "Sage")
coordinated via SQLite + GitHub issues + git worktrees. `Octo` is the underlying multi-provider
agent CLI engine; `mcp-host` brokers STDIO MCP servers. None of these introduce new execution
tables — they all write through the same MCP/REST execution model.

### Evidence & defects
- Manual evidence = `test_attachments` rows (`entity_type='execution'`, optional `step_number`)
  pointing into `artifacts`.
- Defects = `defect_links[]` on the execution (editable post-completion).

### Per-run analytics & sharing
- `GET /runs/{id}/analytics` → counts, pass/completion rates, durations, failures-by-reason,
  per-folder stats, failed-test summaries (see [Correlations & Reporting](04-correlations-and-reporting.md)).
- **Shared public reports** — tokenized, expiring, revocable links (`/runs/{id}/share`,
  `/reports/share/{token}`).

## Interfaces

- **REST** (`/api/v1`): runs (`/products/{id}/runs`, `/runs/{id}` + `start|complete|abort|copy`,
  `add-tests|add-tests-bulk|add-from-oql`, `analytics`, `share`); executions
  (`/runs/{id}/executions`, `/executions/{id}` + `start|complete|rerun`, `assign|steps|defects`,
  `/me/executions`); execution attachments + presigned URLs.
- **MCP** (`/mcp/runs`): `create_run`, `start_run`, `complete_run`, `abort_run`,
  `add_tests_to_run`, `add_tests_from_oql`, `record_test_result`, `record_exploratory_result`,
  `get_my_execution_queue`, `list_runs`, plus analytics tools (`get_run_analytics`,
  `get_run_items`, `get_run_item_details`, `get_run_item_logs`).

## Re-platforming notes

- An execution is a result record bound to (run, test case, executed version). In git-native
  form it's a result file referencing a case file + version.
- `scope_snapshot` freezing matters — a run pins which cases (and via execution
  `test_case_version_id`, which versions) it covered.
- The actor (human / AI agent / framework) only differs in **who writes**; preserve one result
  schema. Note automated-framework results live in a separate domain
  ([03](03-automated-test-results-management.md)) and are unified only at reporting time.
- `failure_reason` is a per-product extendable allow-list, like the test-case field values.
