# 4 — Correlations & Reporting

**What it is:** searching and analysing test data, correlating authored test cases with automated
CI/CD results and requirements, and computing dashboards, trends, and automation-coverage gaps.
Implemented entirely in the `test-management` service (`api/search.py`, `api/reporting.py`,
`db/repository.py`, `db/unified_run_repository.py`) using the `onetest-oql` query library.

→ Data model & full traceability map: [data-model/relationships.md](../data-model/relationships.md).
→ Query language: [OQL](oql-query-language.md).

## The correlation model (the core of this functionality)

OneTest unifies three result worlds — **manual**, **AI-agent**, and **automated framework** —
around one authored test case. The load-bearing keys:

| Correlation | Key | Mechanism |
| --- | --- | --- |
| **Test case ⇄ automated result** | `automation_test_id` (case version) ⇄ `code_ref` (receiver item) | string match, both normalized to `file:Class.method`; plus optional direct `receiver_test_items.test_case_id` value-link with confidence/provenance |
| Test case ⇄ manual/AI result | `test_executions.test_case_id` + `test_case_version_id` | FK-by-value; pins the executed version |
| Test case ⇄ requirement | `test_case_versions.requirements[]` (free-string IDs e.g. `US-123`) | OQL `requirement` field |
| Test case ⇄ test case | `test_case_versions.dependencies[]` | run-order dependencies |
| Run ⇄ release/build/sprint/env | UUID refs on `test_runs` / `launches` | cross-service ref |
| Execution ⇄ defect | `test_executions.defect_links[]` (URLs) | counted in analytics |

### `automation_test_id` ⇄ `code_ref` normalization
Both normalize to `file:Class.method`. pytest nodeid `file.py::Class::method` →
`file.py:Class.method`. `automation_test_id` may hold **multiple** refs (one per line); a match
on **any** counts. Done in `_normalize_automation_test_id` (write) / `_normalize_ref` (compare).
This reconciles pytest-reportportal STEP items (`file:Class.method`) with raw pytest nodeids.

## Automation Coverage — the correlation engine

`GET /api/v1/products/{product_id}/test-cases/automation-coverage` (5-min per-product cache;
`?no_cache=true` to bypass). Answers: *"are the tests we marked 'automated' actually running in
CI/CD?"* Surfaced under **Analytics** in the UI.

Metrics (`AutomationCoverageStats`):
- `total_test_cases`, `execution_type_distribution {manual, automated}`.
- `marked_automated` — cases with `execution_type='automated'`.
- `linked_to_results` — automated cases with CI/CD evidence, matched two ways: (a) direct FK
  `receiver_test_items.test_case_id`; (b) `code_ref` ≈ latest version's `automation_test_id`.
- `no_automation_ref` — automated cases with empty `automation_test_id` and no link.
- `automation_gap` — has `automation_test_id` but **no** matching CI/CD evidence;
  `automation_gap_percentage = gap / marked_automated × 100`.
- `coverage_by_priority`, `coverage_by_category` — per-bucket `{total, automated, gap_percentage}`.

UI gap-analysis bar (three segments):
- **Green — Linked to CI/CD:** ref matched a `code_ref`. No action.
- **Orange — No test ref set:** automated but no `automation_test_id`. Action: set the field.
- **Red — Has ref, no CI/CD match:** the real gaps (test renamed/deleted/disabled/format
  mismatch). Action: fix the id or revert to manual.

Setting a ref: UI (Execution Type = Automated → Automation Test ID), `PUT /test-cases/{id}` with
`{execution_type, automation_test_id}`, or automatically from CI/CD via `code_ref`.

## Reporting & analytics

### Run dashboard (`/api/v1/reporting/...`)
Common filters: `product_id` + optional `release_id, sprint_id, build_id, environment_id,
date_from, date_to, status, has_failures, min_pass_rate`.
- `GET /reporting/dashboard` — per-run aggregated stats (one grouped subquery, no N+1):
  `total_executions, passed, failed, blocked, skipped, not_run`, plus
  **pass_rate = passed/(passed+failed+blocked+skipped)×100** and **progress = (total−not_run)/
  total×100**. Sortable, paginated.
- `GET /reporting/summary` — `total_runs`, `in_progress`, `with_failures` (failed>0),
  `high_pass_rate` (≥80).
- `GET /reporting/trends` — completed runs over time (ordered by `actual_end`): per point
  counts + percentages (`pass_pct, fail_pct, blocked_pct, skip_pct`).

### Per-run analytics (`GET /api/v1/runs/{id}/analytics`)
Counts by status; **pass_rate = passed/(passed+failed)×100** *(note: different denominator than
the dashboard)*; completion_rate; total/average/estimated-remaining duration; defect metrics
(`total_defects_linked`, `unique_defect_count`); **failures_by_reason** (grouped over the 6
failure reasons); **stats_by_folder**; **failed_tests** list.

### Unified manual + automated analytics
`UnifiedRunRepository` abstracts manual `test_runs` and automated `launches` behind one interface
(`_detect_source` checks runs then launches). It normalizes launch statuses
(`passed/failed→completed`, `stopped/interrupted/cancelled→aborted`) and item statuses
(`interrupted/stopped→blocked`, `cancelled→skipped`), and reads automated analytics from the
denormalized `launches.statistics` plus failed-item detail.

### Per-test-case execution history (`GET /test-cases/{id}/execution-history`)
Merges manual executions (excluding not_run/in_progress) with automated results matched by
normalized `automation_test_id` ⇄ `code_ref`, sorted by date; automated results from the same
launch are aggregated into one entry.

### Other surfaces
- **Test-case stats** — counts by status + unassigned (not in any folder).
- **Shared public reports** — tokenized expiring links with counts/pass-rate/per-folder stats +
  optional AI summary.
- **Activity timeline** — audit-event history per case.

### Searching (OQL)
OQL powers test-case and test-run search, dynamic suites, "add tests to run from query", saved
queries, and is the **translation target for the AI's natural-language search**. Full reference:
[OQL](oql-query-language.md).

## Traceability summary

```
requirement (US-123)  ◀── test_case_versions.requirements[]
       │
   test_case ──┬── automation_test_id ⇄ code_ref ──▶ automated launches (receiver)
               ├── test_executions ──▶ test_runs ──▶ release / build / env
               └── defect_links / known_issues ──▶ Jira / GitHub / ADO
```

## Re-platforming notes

- Correlation is **computed, not stored** — in git-native form, scan result files and match on
  normalized `code_ref`. Keep `automation_test_id` ⇄ `code_ref` as the contract.
- Reconcile the **two pass_rate denominators** and the **priority enum** before re-implementing.
- The docs' OQL field reference lists ~15 non-existent fields; the real schema is the
  `onetest-oql` `EntitySchema`s — see [OQL](oql-query-language.md).
- Most reporting is aggregation over executions/launches; trends rely on `actual_end` and launch
  `statistics`. Keep those timestamps/aggregates available in the new store.
