# Data Model — Test Execution

Owner: `test-management` service (same DB as Test Case Management). Sources: `db/models.py`,
`migrations/008a, 017, 018`, `schema.sql`, plus field usage verified in the `core` React UI
(`ExecutionPanel.jsx`, `TestRunDetail.jsx`) and the MCP tool surface.

This domain covers **manual and AI-agent execution** of authored test cases. Automated CI/CD
framework results are a separate domain — see [04-automated-results.md](04-automated-results.md).

## Entity summary

| Entity | Role |
| --- | --- |
| `test_runs` | A test cycle/plan: a scoped set of executions in a context (env/build/release) |
| `test_executions` | One test case's execution within a run (the central execution record) |
| `step_results[]` | Per-step results (embedded JSON in an execution) |
| `test_attachments` | Manual evidence (screenshots etc.); shared table, `entity_type='execution'` |
| `shared_reports` | Tokenized public report links for a run |

---

## `test_runs` — test cycle / run

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL, indexed. Tenant scope |
| `name` | VARCHAR(500) | NOT NULL |
| `description` | TEXT | |
| `run_type` | VARCHAR(50) | default `manual`. Enum: `manual / automated / regression / smoke / sanity` (UI/OQL surface a narrower `manual/automated/exploratory`) |
| `status` | VARCHAR(50) | default `planned`. Enum `RunStatus`: `planned / in_progress / completed / aborted` (UI also shows a `draft` pre-state) |
| `environment_id` | UUID | nullable, indexed — cross-service ref → `environments` |
| `build_id` | UUID | nullable, indexed — cross-service ref → `builds` |
| `release_id` | UUID | nullable, indexed — cross-service ref → `releases` |
| `sprint_id` | UUID | nullable, indexed — cross-service ref → `sprints` |
| `scope_snapshot` | JSONB | Frozen scope at start: `{test_case_ids, query_id, folder_ids}` |
| `created_by` | VARCHAR(255) | NOT NULL |
| `assigned_to` | VARCHAR(255) | nullable (run-level assignee) |
| `planned_start` / `planned_end` | TIMESTAMPTZ | |
| `actual_start` / `actual_end` | TIMESTAMPTZ | drive trends/duration |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

The denormalized context names (`environment_name`, `release_name`, `sprint_name`,
`build_version`) are resolved for display in the UI; the run also exposes a computed `statistics`
object `{total, passed, failed, skipped, in_progress}`.
**Lifecycle:** `draft`/`planned` → (start, freezes scope) → `in_progress` → (complete) →
`completed`, or (abort) → `aborted`. `copy` clones a completed run for re-execution.
**Trigger** `update_test_run_timestamp` updates the run when its executions change.

---

## `test_executions` — per-case execution within a run (central)

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `test_run_id` | UUID | NOT NULL → **`test_runs(id)` CASCADE** |
| `test_case_id` | UUID | nullable → **`test_cases(id)` ON DELETE SET NULL** (nullable since mig 017 for exploratory) |
| `test_case_version_id` | UUID | nullable → **`test_case_versions(id)` SET NULL** — pins the exact authored version executed |
| `name` | VARCHAR(500) | nullable (mig 017, for exploratory executions with no case) |
| `parent_execution_id` | UUID | nullable → self (re-runs) |
| `rerun_reason` | TEXT | |
| `status` | VARCHAR(50) | default `not_run`. Enum `ExecutionStatus`: `not_run / in_progress / passed / failed / blocked / skipped` |
| `assigned_to` | VARCHAR(255) | nullable (per-execution assignee; `/me/executions` queue) |
| `executed_by` | VARCHAR(255) | nullable |
| `context_snapshot` | JSONB | |
| `step_results` | JSONB | per-step results (shape below) |
| `parameter_values` | JSONB | resolved data-driven values |
| `notes` | TEXT | |
| `started_at` / `completed_at` | TIMESTAMPTZ | |
| `duration_seconds` | INTEGER | |
| `attachments` | JSONB | embedded evidence refs (also see `test_attachments`) |
| `failure_reason` | VARCHAR(50) | Enum `FailureReason`: `bug_in_app / test_data_issue / environment_issue / test_needs_update / blocked_by_other / other` (config-extendable per product) |
| `failure_details` | TEXT | |
| `steps_to_reproduce` | TEXT | |
| `defect_links` | JSONB | `[{url, id}]` — linked tickets (Jira/GitHub/ADO). GIN-indexed. Editable **after** completion |
| `created_at` | TIMESTAMPTZ | |

Indexes: GIN on `defect_links`; partial indexes on `failure_reason` and `duration`.
**Lifecycle:** `not_run` → (start) → `in_progress` → (complete with status) → `passed / failed /
blocked / skipped`. `rerun(reason)` creates a child execution. Executable only while the parent
run is `in_progress`.

### Embedded `step_results[]` object shape
```jsonc
{
  "step_number": 1,
  "status": "passed",        // passed | failed | skipped | blocked (UI transient: "pending")
  "actual_result": "...",    // nullable
  "comment": "..."           // UI labels this "notes"
}
```
UI fail-cascade rule (`ExecutionPanel.jsx`): failing step N ⇒ steps `<N` auto-`passed`, step N
`failed`, steps `>N` `blocked`.

---

## Evidence — `test_attachments` (execution rows)

The same polymorphic `test_attachments` table from
[Test Case Management](02-test-case-management.md#test_attachments--attachment-metadata-polymorphic)
stores manual execution evidence with `entity_type = 'execution'`, `entity_id = <execution_id>`,
optional `step_number`, `attachment_type` (default `screenshot`), served via presigned URL from
the `artifacts` service.

---

## `shared_reports` — public report links (mig 018)

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `run_id` | UUID | NOT NULL → **`test_runs(id)` CASCADE** |
| `token` | VARCHAR(64) | UNIQUE — public, no-auth access token |
| `created_by` | VARCHAR(255) | |
| `expires_at` | TIMESTAMPTZ | |
| `revoked_at` | TIMESTAMPTZ | |
| `created_at` | TIMESTAMPTZ | |

Served at `GET /reports/share/{token}` (no auth); payload includes counts, pass_rate,
completion_rate, per-folder stats, optional AI summary.

---

## Relationships (this domain)

```
test_runs 1───* test_executions            (CASCADE)
test_executions *───1 test_cases           (SET NULL — execution survives case deletion)
test_executions *───1 test_case_versions   (SET NULL — pins executed version)
test_executions ──self── parent_execution_id (re-runs)
test_runs 1───* shared_reports             (CASCADE)
test_runs → environment / build / release / sprint   (cross-service UUID refs, no FK)
test_executions → step_results[] (embedded), defect_links[] (embedded)
test_attachments ──poly── execution        (entity_type='execution')
```

## Execution actors (same data, different writer)

The execution data model is **identical regardless of who executes**:
- **Manual** — a human records pass/fail per step in the `core` UI ExecutionPanel.
- **AI agent** — `qa-agent` (`/qa-onetest run`) or `octobots` call the same backend via **MCP
  tools** (`record_test_result`, `record_exploratory_result`, `complete_run`, …) using a real
  Chrome browser via Chrome DevTools Protocol, capturing before/after screenshots.
- **Automated frameworks** do **not** write here — they post to the `receiver` service
  (`launches`/`test_items`), surfaced as read-only runs and unified at the reporting layer.

See [02 — Test Execution Management](../functionalities/02-test-execution-management.md) for
behaviour and [relationships.md](relationships.md) for how executions correlate to automated
results.
