# Data Model — Cross-Domain Relationship & Traceability Map

This consolidates how entities relate **across** the four domains and the foundational layer.
Per-domain relationships live in each domain file; this file is the join picture.

## Legend

- `──FK──>` real database foreign key (intra-service).
- `··ref··>` logical reference by UUID, **no FK** (cross-service).
- `⇄` value-based correlation (string match), not a stored FK.

## The whole picture

```
                      membership service                         (foundational)
   products ──FK──> environments
        │   ──FK──> releases ──FK──> sprints ──FK──> builds ──FK──> deployments
        │   ──FK──> product_members      (clerk_user_id ··ref·· Clerk identity)
        │   ──FK──> product_llm_configs
        │
        │ product_id is the tenant key everywhere below (··ref··, no FK)
        ▼
 ┌─────────────────────── test-management service ───────────────────────┐
 │ test_cases ──FK──> test_case_versions (immutable, numbered)           │
 │     │  *──FK──* test_folders (via test_case_folders)                  │
 │     │  *──FK──* test_tags    (via test_case_tags)                     │
 │     │  ──FK──> parameter_sets                                         │
 │     │                                                                 │
 │ test_runs ──FK──> test_executions ··ref··> test_cases (SET NULL)      │
 │     │                    │        ··ref··> test_case_versions         │
 │     │  ··ref··> environment / build / release / sprint (membership)   │
 │     └──FK──> shared_reports                                           │
 │ test_attachments (poly: test_case | execution) ··ref··> artifacts     │
 └───────────────────────────────────────────────────────────────────────┘
                                  ⇅  (no FK)
 ┌───────────────────────────── receiver service ───────────────────────┐
 │ launches ──FK──> receiver_test_items (self-tree) ──FK──> ..._logs     │
 │     │  ··ref··> release / sprint / build / environment (membership)   │
 │ receiver_ingestion_jobs ··ref··> launches                             │
 │ product_api_keys                                                      │
 └───────────────────────────────────────────────────────────────────────┘

 artifacts service:  artifact_buckets, artifact_credentials  (objects referenced by
                     (bucket, object_key) pointers from test_attachments & ..._logs)
```

## The traceability chain (the heart of correlations)

```
requirement (free-string id, e.g. US-123)
     ▲  stored in  test_case_versions.requirements (JSONB array)
     │  queried via OQL `requirement = / ~ / IS NULL`
     │
 test_case ──1:N── test_case_version ──(automation_test_id, newline-separated "file:Class.method")
     │                                          ⇅  normalized match
     │                                  receiver_test_items.code_ref
     │                                  (+ optional direct receiver_test_items.test_case_id link
     │                                     with mapping_confidence / mapped_by / mapped_at)
     │
     ├── manual / AI-agent:  test_executions ──FK──> test_runs ··ref··> environment/build/release/sprint
     │                              └ defect_links[] (URLs to Jira/GitHub/ADO)
     │
     └── automated framework: receiver_test_items ──FK──> launches ··ref··> release/build/env
```

### Matching keys, enumerated

| Relationship | Key(s) | Where stored |
| --- | --- | --- |
| Test case ↔ requirement | free-string requirement IDs | `test_case_versions.requirements` (JSONB[]) |
| Test case ↔ test case (run order) | dependency test IDs | `test_case_versions.dependencies` (JSONB[]) |
| Test case ↔ automated result | (a) direct value-link `receiver_test_items.test_case_id`; (b) **`automation_test_id` ⇄ `code_ref`**, both normalized to `file:Class.method` | versions + receiver items |
| Test case ↔ manual/AI result | `test_executions.test_case_id` + `test_case_version_id` | executions |
| Run ↔ release/build/sprint/env | UUID refs on `test_runs` (manual) / `launches` (automated) | runs / launches |
| Execution ↔ defect | URL list | `test_executions.defect_links` (JSONB[]) |
| Test case ↔ bug (known issue) | bug-tracker IDs | `test_case_versions.known_issues` (JSONB[]) |

### `automation_test_id` ⇄ `code_ref` normalization

Both sides normalize to `file:Class.method`. pytest nodeids `file.py::Class::method` →
`file.py:Class.method`; space-separated refs become newline-separated; `automation_test_id` may
hold **multiple** refs (one per line) and a match on **any** counts as "linked". Implemented in
`_normalize_automation_test_id` (write) and `_normalize_ref` (compare) in
`test-management/db/repository.py`. This reconciles pytest-reportportal STEP items
(`file:Class.method`) with raw pytest nodeids (`file::Class::method`).

## Status / enum vocabularies side-by-side

| Concept | Values | Configurable? |
| --- | --- | --- |
| Test case `status` | `draft, ready, deprecated` (legacy `archived` removed) | **Yes** (product/workspace field values) |
| Test case `execution_type` | `manual, automated` | **Yes** |
| Test case `test_category` | `functional, performance, security, accessibility, exploratory` | **Yes** |
| Test case `priority` | `p0–p3` (Pydantic) / `p1–p4` (OQL) / `P0–P4` (UI) — **inconsistent** | No |
| Version `approval_status` | `pending, approved, rejected` | No |
| Run `status` | `planned, in_progress, completed, aborted` (+ UI `draft`) | No |
| Run `run_type` | `manual, automated, regression, smoke, sanity` | No |
| Execution `status` | `not_run, in_progress, passed, failed, blocked, skipped` | No |
| Step `status` | `passed, failed, skipped, blocked` | No |
| Execution `failure_reason` | `bug_in_app, test_data_issue, environment_issue, test_needs_update, blocked_by_other, other` | Per-product extendable |
| Launch `status` | `in_progress, passed, failed, stopped, interrupted, cancelled` | No |
| Test item `status` | `in_progress, passed, failed, skipped, interrupted, cancelled` | No |

### Status normalization for unified reporting

`test-management/db/unified_run_repository.py` merges manual `test_runs` and automated `launches`
into one analytics view. Launch → run status: `passed/failed → completed`,
`stopped/interrupted/cancelled → aborted`. Item → execution status: `interrupted/stopped →
blocked`, `cancelled → skipped`.

## Notes for a git-native target

- The only true cross-service FKs to preserve are the **release lineage** (membership) and the
  **intra-domain** trees (versions, folders, item tree). Everything else is already
  reference-by-id — natural for files referencing files.
- The `automation_test_id ⇄ code_ref` correlation is computed, not stored — in git-native form
  it can stay computed (scan results, match on normalized ref).
- `test_audit_events` is largely **git history**; it need not be a stored table.
- `product_id` ≈ a repository or top-level directory; `clerk_user_id` stays as the external
  identity reference.
