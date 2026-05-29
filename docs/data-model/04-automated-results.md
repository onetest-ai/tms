# Data Model — Automated Test Results

Owner: `receiver` service (FastAPI + SQLAlchemy 2.0, Postgres, default port 8008). Sources:
`receiver/schema.sql`, `migrations/001–005`, `src/.../db/models.py` (authoritative),
`db/repository.py`. Metering: `onetest-otel` (emits OTel spans; persists nothing).

The `receiver` ingests automated CI/CD test results via a **ReportPortal-v2-compatible API** and
**JUnit XML import**, storing them as a launch → item-tree → log hierarchy.

> Cross-service refs (`product_id`, `release_id`, `sprint_id`, `build_id`, `environment_id`,
> `test_case_id`) are logical — **no FK**. Only intra-service FKs exist.

## Entity summary

| Entity | Role |
| --- | --- |
| `product_api_keys` | API keys for CI/CD ingestion, MCP agents, API access |
| `launches` | One automated run (= ReportPortal "launch") |
| `receiver_test_items` | Hierarchical items (suite/test/step/setup-teardown); self-referencing tree |
| `receiver_test_item_logs` | Log lines + attachment metadata per item (or launch-level) |
| `receiver_ingestion_jobs` | Async batch import (JUnit) job tracking |

---

## `product_api_keys`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL, indexed. (Originally UNIQUE; dropped mig 003 → multiple keys/product) |
| `name` | VARCHAR(100) | NOT NULL default `Default` (mig 003) |
| `api_key_hash` | VARCHAR(255) | NOT NULL — bcrypt hash |
| `api_key_prefix` | VARCHAR(8) | NOT NULL — first 8 chars for display; new keys `octo_…` (was `rp_…`, mig 004) |
| `allowed_scopes` | TEXT[] | NOT NULL default `['autotests:read','autotests:write']` (mig 004) |
| `retention_days` | INTEGER | NOT NULL default 90 |
| `is_active` | BOOLEAN | NOT NULL default true |
| `expires_at` | TIMESTAMPTZ | nullable (null = never) (mig 004) |
| `last_active_at` | TIMESTAMPTZ | nullable (mig 004) |
| `metadata` (`metadata_`) | JSONB | NOT NULL default `{}` |
| `created_by` | VARCHAR(255) | NOT NULL (clerk id) |
| `created_at` / `updated_at` | TIMESTAMPTZ | NOT NULL default `now()` |

Indexes: `idx_product_api_keys_product_id`; partial `idx_product_api_keys_active WHERE is_active`.
Valid scope strings: `autotests:read/write`, `testcases:read/write`, `testruns:read/write`,
`artifacts:read/write`, `membership:read/write`, `activity:read`.

---

## `launches` — an automated run

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL, indexed (logical ref) |
| `uuid` | VARCHAR(100) | NOT NULL, indexed — client-provided launch UUID |
| `name` | VARCHAR(500) | NOT NULL |
| `description` | TEXT | |
| `mode` | VARCHAR(50) | NOT NULL default `default`. Enum `LaunchMode`: `default / debug / ci` |
| `attributes` | JSONB | NOT NULL default `[]` — `[{key, value, system?}]` |
| `status` | VARCHAR(50) | NOT NULL default `in_progress`, indexed. Enum `LaunchStatus`: `in_progress / passed / failed / stopped / interrupted / cancelled` |
| `statistics` | JSONB | NOT NULL default `{}` — denormalized `{total, passed, failed, skipped, in_progress[, interrupted, cancelled]}` (no `blocked`) |
| `release_id` | UUID | nullable (logical ref, mig 005) |
| `sprint_id` | UUID | nullable (logical ref) |
| `build_id` | UUID | nullable (logical ref) |
| `environment_id` | UUID | nullable (logical ref) |
| `build_version` | VARCHAR(255) | nullable — used for build find-or-create |
| `start_time` | TIMESTAMPTZ | NOT NULL |
| `end_time` | TIMESTAMPTZ | nullable |
| `metadata` (`metadata_`) | JSONB | NOT NULL default `{}` |
| `created_at` / `updated_at` | TIMESTAMPTZ | NOT NULL default `now()` |

Constraints/indexes: `uq_launch_uuid (product_id, uuid)`; indexes on `product_id`,
`(product_id, status)`, `(product_id, start_time DESC)`, `uuid`; partial indexes on
`release_id`/`sprint_id`/`build_id`/`environment_id` (WHERE NOT NULL).
DB function `update_launch_statistics(p_launch_id)` recomputes `statistics` by counting items
where `has_stats=true` (schema.sql counts only `item_type='TEST'`; the app layer counts
`TEST`+`STEP` — a minor divergence).

---

## `receiver_test_items` — hierarchical item tree

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `launch_id` | UUID | NOT NULL → **`launches(id)` CASCADE**, indexed |
| `parent_id` | UUID | nullable → **`receiver_test_items(id)` CASCADE**, indexed (self-ref = hierarchy) |
| `uuid` | VARCHAR(100) | NOT NULL, indexed — client item UUID |
| `name` | VARCHAR(500) | NOT NULL |
| `item_type` | VARCHAR(50) | NOT NULL. Enum `TestItemType`: `SUITE, STORY, TEST, SCENARIO, STEP, BEFORE_CLASS, BEFORE_METHOD, BEFORE_SUITE, BEFORE_TEST, AFTER_CLASS, AFTER_METHOD, AFTER_SUITE, AFTER_TEST` |
| `description` | TEXT | |
| `code_ref` | VARCHAR(1024) | nullable, indexed (partial WHERE NOT NULL). **The correlation key** — e.g. `com.example.TestClass.testMethod` |
| `parameters` | JSONB | NOT NULL default `[]` — `[{key,value}]` |
| `attributes` | JSONB | NOT NULL default `[]` — `[{key,value}]` |
| `status` | VARCHAR(50) | NOT NULL default `in_progress`, indexed. Enum `TestItemStatus`: `in_progress / passed / failed / skipped / interrupted / cancelled` |
| `failure_message` | TEXT | |
| `failure_stacktrace` | TEXT | |
| `start_time` | TIMESTAMPTZ | NOT NULL |
| `end_time` | TIMESTAMPTZ | nullable |
| `duration_ms` | INTEGER | computed on finish |
| `has_stats` | BOOLEAN | NOT NULL default true (false = container not counted in stats) |
| `test_case_id` | UUID | nullable (logical ref → `test_management.test_cases`) — **the authored-case link** |
| `mapping_confidence` | DECIMAL(5,4) | 0.0000–1.0000 |
| `mapped_at` | TIMESTAMPTZ | nullable |
| `mapped_by` | VARCHAR(50) | Enum `MappingSource`: `auto / manual / ai` |
| `metadata` (`metadata_`) | JSONB | NOT NULL default `{}` |
| `created_at` | TIMESTAMPTZ | NOT NULL default `now()` |

Constraints/indexes: `uq_test_item_uuid (launch_id, uuid)`; indexes on launch, parent,
`(launch_id,status)`, uuid, `code_ref` (partial), `idx_test_items_unmapped (launch_id) WHERE
test_case_id IS NULL`, and a **GIN full-text** index on `to_tsvector('english', name)`.

---

## `receiver_test_item_logs` — logs + attachment metadata

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `test_item_id` | UUID | NOT NULL → **`receiver_test_items(id)` CASCADE**, indexed |
| `launch_id` | UUID | nullable → **`launches(id)` CASCADE** (partial idx) — launch-level logs |
| `log_level` | VARCHAR(20) | NOT NULL default `INFO`. Enum `LogLevel`: `TRACE / DEBUG / INFO / WARN / ERROR / FATAL / UNKNOWN` |
| `message` | TEXT | NOT NULL |
| `log_time` | TIMESTAMPTZ | NOT NULL |
| `attachment_bucket` | VARCHAR(255) | nullable — bucket in `artifacts` |
| `attachment_key` | VARCHAR(1024) | nullable — object key (convention `test-runs/{launch_id}/{filename}`) |
| `attachment_content_type` | VARCHAR(100) | nullable |
| `attachment_name` | VARCHAR(255) | nullable |
| `created_at` | TIMESTAMPTZ | NOT NULL default `now()` |

Indexes: `idx_test_item_logs_item`; partial `idx_test_item_logs_launch`; `(test_item_id,
log_level)`. Attachment binaries live in `artifacts`, not the DB.

---

## `receiver_ingestion_jobs` — batch import tracking

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL, indexed (logical ref) |
| `job_type` | VARCHAR(50) | NOT NULL. Enum `JobType`: `junit_xml / nunit_xml / realtime_batch` (only `junit_xml` has a processor) |
| `status` | VARCHAR(50) | NOT NULL default `pending`, indexed. Enum `JobStatus`: `pending / processing / completed / failed / cancelled` |
| `total_items` / `processed_items` / `successful_items` / `failed_items` | INTEGER | NOT NULL default 0 |
| `launch_id` | UUID | nullable → `launches(id)` (no cascade) — the launch this job created |
| `error_log` | JSONB | NOT NULL default `[]` |
| `source_file_bucket` / `source_file_key` | VARCHAR | nullable |
| `created_by` | VARCHAR(255) | NOT NULL |
| `started_at` / `completed_at` | TIMESTAMPTZ | |
| `created_at` | TIMESTAMPTZ | NOT NULL default `now()` |

Indexes: product; partial `idx_ingestion_jobs_status WHERE status IN (pending, processing)`;
`(created_at DESC)`.

---

## Relationships (this domain)

```
launches 1───* receiver_test_items              (CASCADE)
receiver_test_items ──self── parent_id          (SUITE > TEST > STEP tree, CASCADE)
receiver_test_items 1───* receiver_test_item_logs (CASCADE)
launches 1───* receiver_test_item_logs          (nullable launch_id, CASCADE — launch-level logs)
receiver_test_item_logs → artifacts             (attachment_bucket/key pointer, no FK)
receiver_ingestion_jobs → launches              (launch_id, no cascade)

launches → release / sprint / build / environment   (logical refs, no FK)
receiver_test_items.test_case_id → test_management.test_cases   (logical ref, no FK)
receiver_test_items.code_ref  ⇄  test_case_versions.automation_test_id   (the correlation key)
```

Deleting a launch cascades to items, child items, and logs; attachment binaries in `artifacts`
are deleted separately by the delete handler.

## Correlation: automated result → authored test case

Two mechanisms (detail in
[04 — Correlations & Reporting](../functionalities/04-correlations-and-reporting.md)):

1. **Run context** (`services/auto_link.py`): on launch start, explicit `release_id/sprint_id/
   build_id/environment_id` are used if supplied; otherwise the receiver best-effort resolves
   them from `membership` (active release → active sprint → find-or-create build by
   `build_version` → default environment). Failures are swallowed (launch never fails on
   auto-link).
2. **Item → test case:** items start **unmapped** (`test_case_id IS NULL`); `code_ref` is stored
   verbatim. Linking sets `test_case_id`, `mapped_by`, `mapped_at`, `mapping_confidence`.
   **There is no auto-matching engine inside `receiver`** — matching by `code_ref` ⇄
   `automation_test_id` is computed in `test-management` (`get_automation_coverage_stats`) and
   written back via `link_to_test_case`.

## Metering (`onetest-otel`)

The receiver emits OTel metering spans (`record_metering_event`) on launch finish
(`event_type=test_ingestion`) and JUnit import completion (`event_type=junit_import`). `onetest-
otel` persists nothing — spans are routed by an OTel Collector to the (out-of-scope) Metering
Service. Event types: `rest_api_write, mcp_single_action, file_upload, test_ingestion,
junit_import, pipeline_run, ui_operation`. Billing rule: UI/gateway-proxy traffic is free;
api/mcp/agent writes are paid.
