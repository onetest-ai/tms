# Data Model — Test Case Management

Owner: `test-management` service. Sources: `db/models.py` (authoritative), `migrations/001–022`,
`schema.sql` (stale — flagged inline). All entities scoped by `product_id` (logical ref, no FK).

> **Authoritative model = ORM + migrations 010–022.** `schema.sql` reflects only 001–009 and is
> wrong in several places (noted as "schema.sql drift").

## Entity summary

| Entity | Role |
| --- | --- |
| `test_cases` | Stable identity row (the test case) |
| `test_case_versions` | Immutable, numbered content snapshots (versioning) |
| `test_folders` | Folder/suite tree; supports dynamic (OQL-backed) suites |
| `test_case_folders` | M:N test case ↔ folder |
| `test_tags` | Tags/labels (soft-deletable) |
| `test_case_tags` | M:N test case ↔ tag |
| `test_case_credpool_pools` | M:N test case ↔ credential pool (cred pools out of scope) |
| `parameter_sets` | Data-driven parameter sets per test case |
| `test_attachments` | Attachment metadata (files in `artifacts`); polymorphic to case/execution |
| `custom_field_definitions` | Per-product custom field definitions |
| `product_field_values` | Per-product **system** allow-lists for status/execution_type/test_category |
| `workspace_field_values` | Workspace-global **custom** allow-lists for the same three fields |
| `saved_queries` | Saved test-case filters |
| `prompt_templates` | AI instruction snippets (CLAUDE.md-style) for test generation |
| `import_export_jobs` | Bulk import/export job tracking |
| `test_audit_events` | Append-only audit log |

---

## `test_cases` — identity container

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL, indexed. Tenant scope (no FK). |
| `identifier` | VARCHAR(50) | NOT NULL. Human ID e.g. `TC-0058`. Auto-generated (advisory lock + max+1); prefix from config `test_case_prefix`. Never user-set. |
| `status` | VARCHAR(50) | NOT NULL default `draft`. **Config-driven allow-list** (see field-values tables). |
| `execution_type` | VARCHAR(50) | NOT NULL default `manual`. Config-driven (replaced old `test_type` in mig 009b). |
| `test_category` | VARCHAR(50) | NOT NULL default `functional`. Config-driven (added 009b). |
| `created_by` | VARCHAR(255) | NOT NULL (clerk id) |
| `owner` | VARCHAR(255) | nullable |
| `created_at` / `updated_at` | TIMESTAMPTZ | default `now()`; `updated_at` ORM onupdate |
| ~~`archived_at`~~ | TIMESTAMPTZ | **schema.sql only — NOT in ORM. Vestigial.** |

Constraints/indexes: `uq_test_case_identifier UNIQUE(product_id, identifier)`; indexes on
`product_id`, `(product_id, status)`, `execution_type`, `test_category`, `owner`.
The old `test_type` column was dropped (009b); 010 remapped legacy values to
`execution_type ∈ {manual, automated}` and `test_category ∈ {functional, performance, security,
accessibility, exploratory}`.

---

## `test_case_versions` — immutable content snapshot (versioning core)

Content changes create a **new version**; the row is never mutated after insert.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `test_case_id` | UUID | NOT NULL → **`test_cases(id)` CASCADE** |
| `version_number` | INTEGER | NOT NULL |
| `parent_version_id` | UUID | nullable → **`test_case_versions(id)`** (self-ref lineage) |
| `title` | VARCHAR(500) | NOT NULL |
| `description` | TEXT | |
| `preconditions` / `postconditions` | TEXT | |
| `test_data` | TEXT | inputs/datasets/fixtures |
| `steps` | JSONB | NOT NULL default `[]`. Array of step objects (see below) |
| `step_format` | VARCHAR(20) | NOT NULL default `table`. Values: `table`, `gherkin` |
| `expected_result` | TEXT | global expected result |
| `pass_fail_criteria` | TEXT | |
| `gherkin_feature` | TEXT | BDD |
| `charter` | TEXT | exploratory charter |
| `time_box_minutes` | INTEGER | exploratory |
| `parameters` | JSONB | NOT NULL default `{}` (data-driven) |
| `requirements` | JSONB | NOT NULL default `[]` — linked requirement/story IDs (traceability) |
| `dependencies` | JSONB | NOT NULL default `[]` — test IDs that must run first |
| `known_issues` | JSONB | NOT NULL default `[]` (GIN-indexed) — bug-tracker IDs |
| `known_limitations` | TEXT | |
| `priority` | VARCHAR(10) | NOT NULL default `p2`. Enum `Priority`: `p0/p1/p2/p3` *(see priority mismatch note)* |
| `component` | VARCHAR(255) | feature area/module |
| `automation_test_id` | **TEXT** | nullable. **The automation correlation key.** Newline-separated `code_ref` format `file.py:Class.method`. Widened VARCHAR(500)→TEXT in mig 012 |
| `custom_fields` | JSONB | NOT NULL default `{}` (values for `custom_field_definitions`) |
| `change_reason` | TEXT | version metadata |
| `change_category` | VARCHAR(50) | Enum `ChangeCategory`: `bug_fix/enhancement/refactor/cleanup` |
| `author` | VARCHAR(255) | NOT NULL |
| `approval_status` | VARCHAR(50) | default `pending`. Enum `ApprovalStatus`: `pending/approved/rejected` |
| `approved_by` | VARCHAR(255) | nullable |
| `approved_at` | TIMESTAMPTZ | nullable |
| `created_at` | TIMESTAMPTZ | default `now()` (immutable) |

Constraints/indexes: `uq_test_case_version UNIQUE(test_case_id, version_number)`; indexes on
`test_case_id`, `priority`, `component`, GIN on `known_issues`, `(test_case_id, version_number
DESC)` (latest), GIN full-text on `to_tsvector(title + description)`.
**Trigger** `test_case_version_updated` bumps `test_cases.updated_at` on insert/update.
**schema.sql drift:** still shows dropped columns `automation_status` and
`estimated_duration_minutes` (removed in mig 015).

### Embedded `steps[]` object shape
```jsonc
{
  "step_number": 1,
  "action": "Click the Login button",
  "expected_result": "Login form appears",   // nullable
  "data": { "username": "..." },              // nullable
  "attachments": ["<attachment_id>", ...]
}
```

---

## `test_folders` — folder / suite tree (+ dynamic suites)

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL, indexed |
| `parent_id` | UUID | nullable → **`test_folders(id)` CASCADE** (self-ref tree) |
| `name` | VARCHAR(255) | NOT NULL |
| `description` | TEXT | |
| `position` | INTEGER | NOT NULL default 0 (ordering) |
| `is_dynamic` | BOOLEAN | NOT NULL default false |
| `oql_query` | TEXT | nullable — OQL for dynamic suites |
| `created_by` | VARCHAR(255) | NOT NULL |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

Constraints: `uq_folder_product_name UNIQUE(product_id, name)`; partial index on `is_dynamic
WHERE is_dynamic=true`; **CHECK `check_dynamic_suite_has_query`**: `(is_dynamic=false AND
oql_query IS NULL) OR (is_dynamic=true AND oql_query IS NOT NULL)`.
Rules: dynamic suites cannot have children; a folder with children cannot become dynamic;
circular nesting prevented on move; deleting a folder **unlinks** test cases (does not delete
them). Folder counts computed DISTINCT across self + descendants.

## `test_case_folders` — M:N test case ↔ folder

| Column | Type | Notes |
| --- | --- | --- |
| `test_case_id` | UUID | → `test_cases(id)` CASCADE |
| `folder_id` | UUID | → `test_folders(id)` CASCADE |
| `position` | INTEGER | default 0 |
| `added_by` | VARCHAR(255) | NOT NULL |
| `added_at` | TIMESTAMPTZ | default `now()` |

**PK = (test_case_id, folder_id)** — a test case can live in multiple folders.

---

## `test_tags` — tags / labels

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL, indexed |
| `name` | VARCHAR(255) | NOT NULL *(schema.sql says 100 — drift)* |
| `category` | VARCHAR(50) | nullable |
| `color` | VARCHAR(7) | hex `#RRGGBB` (validated); auto-derived from name hash when omitted |
| `description` | TEXT | |
| `metadata` (`metadata_`) | JSONB | default `{}` |
| `created_by` | VARCHAR(255) | NOT NULL |
| `created_at` | TIMESTAMPTZ | default `now()` |
| `deprecated_at` | TIMESTAMPTZ | nullable (soft delete) |

Uniqueness (mig 019): **partial unique `uq_tag_name_active (product_id, name) WHERE deprecated_at
IS NULL`** — deprecated tag names free up for reuse. Tags are soft-deleted (deprecate), and
auto-created on the fly when referenced by name.

## `test_case_tags` — M:N test case ↔ tag

| Column | Type | Notes |
| --- | --- | --- |
| `test_case_id` | UUID | → `test_cases(id)` CASCADE |
| `tag_id` | UUID | → `test_tags(id)` CASCADE |
| `created_by` | VARCHAR(255) | NOT NULL |
| `created_at` | TIMESTAMPTZ | default `now()` |

**PK = (test_case_id, tag_id)**.

## `test_case_credpool_pools` — M:N test case ↔ credential pool *(cred pools out of scope)*
(mig 016) Columns: `test_case_id` → `test_cases(id)` CASCADE; `pool_id` UUID (cross-service, no
FK); `pool_name` VARCHAR(255); `added_by`; `added_at`. **PK = (test_case_id, pool_id)**.

---

## `parameter_sets` — data-driven parameter sets

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `test_case_id` | UUID | NOT NULL → `test_cases(id)` CASCADE |
| `name` | VARCHAR(255) | NOT NULL |
| `description` | TEXT | |
| `schema` | JSONB | NOT NULL default `{}` — param schema (type/required/default/description per key) |
| `data_rows` | JSONB | NOT NULL default `[]` — rows of values |
| `is_active` | BOOLEAN | NOT NULL default true |
| `created_by` | VARCHAR(255) | NOT NULL |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

Mig 011 split the old single `parameters` column into `schema` + `data_rows` and renamed
`is_default`→`is_active`. **schema.sql shows the pre-011 shape (drift).**

## `test_attachments` — attachment metadata (polymorphic)

Files live in `artifacts`; this is metadata + pointer only.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `entity_type` | VARCHAR(50) | NOT NULL — polymorphic: `test_case` or `execution` |
| `entity_id` | UUID | NOT NULL (no FK; polymorphic) |
| `step_number` | INTEGER | nullable — attach to a specific step |
| `bucket_name` | VARCHAR(255) | NOT NULL *(63 in schema.sql — drift)* |
| `object_key` | VARCHAR(1024) | NOT NULL *(500 in schema.sql — drift)* |
| `filename` | VARCHAR(255) | NOT NULL |
| `content_type` | VARCHAR(100) | nullable |
| `size_bytes` | BIGINT | nullable |
| `attachment_type` | VARCHAR(50) | NOT NULL default `general`. Enum `AttachmentType`: `general/screenshot/video/log/har/network_trace/test_data` |
| `description` | TEXT | (schema.sql; not in ORM) |
| `uploaded_by` | VARCHAR(255) | NOT NULL |
| `created_at` | TIMESTAMPTZ | NOT NULL default `now()` |

Index on `(entity_type, entity_id)`. Upload enforces 10 MB max + content-type allowlist.

---

## Configuration & customization entities

### `custom_field_definitions` — per-product custom fields

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL, indexed |
| `field_name` | VARCHAR(100) | NOT NULL, pattern `^[a-z][a-z0-9_]*$` |
| `field_label` | VARCHAR(255) | NOT NULL |
| `field_type` | VARCHAR(50) | NOT NULL. Enum `FieldType`: `text/textarea/select/multiselect/number/date/checkbox` |
| `options` | JSONB | default `[]` — `[{value,label}]` for select/multiselect |
| `default_value` | JSONB | nullable |
| `validation_rules` | JSONB | nullable (min/max length/value, pattern) |
| `is_required` | BOOLEAN | default false |
| `is_visible` | BOOLEAN | NOT NULL default true |
| `display_order` | INTEGER | default 0 |
| `applies_to` | JSONB | default `["test_case"]` |
| `created_by` | VARCHAR(255) | NOT NULL |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

Field **values** are stored in `test_case_versions.custom_fields` (JSONB).
**schema.sql drift:** pre-011 names (`name`, `display_name`, `position`, VARCHAR[] `applies_to`).

### `product_field_values` — per-product **system** allow-lists (mig 020)
| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL (no FK) |
| `field_name` | VARCHAR(50) | NOT NULL, CHECK ∈ `{status, execution_type, test_category}` |
| `value` | VARCHAR(100) | NOT NULL |
| `display_name` | VARCHAR(255) | |
| `sort_order` | INTEGER | default 0 |
| `is_system` | BOOLEAN | default false |
| `is_disabled` | BOOLEAN | default false |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

`UNIQUE(product_id, field_name, value)`. Holds built-in defaults, **lazy-seeded per product** on
first read. After mig 021 only system rows live here.

### `workspace_field_values` — workspace-global **custom** allow-lists (mig 021/022)
Same three `field_name`s; **`UNIQUE(field_name, value)`** (global, not per-product). Custom
values apply to every product. Columns: `id`, `field_name`, `value`, `display_name`,
`sort_order`, `is_disabled`, `created_at`, `updated_at`.

> Together these two tables define what `status`/`execution_type`/`test_category` may contain.
> Defaults: status `draft`, execution_type `manual`, test_category `functional`. Validated at the
> repository layer (HTTP 422 with the allow-list on bad input).

### `saved_queries` — saved test-case filters
`id` PK; `product_id` (indexed); `name`; `description`; `query` JSONB (`QueryDefinition`: tags,
folders, status, execution_type, test_category, search, owner, created_after/before);
`is_public` (default false); `shared_with` JSONB `[]` (user ids); `created_by`; timestamps.
`uq_saved_query_product_name UNIQUE(product_id, name)`. Visibility = owner ∪ public ∪ shared_with.

### `prompt_templates` — AI instruction snippets
`id` PK; `product_id` (indexed); `name`; `description`; `instructions` TEXT NOT NULL;
`is_active` (default true); `created_by`; timestamps. `UNIQUE(product_id, name)`. CLAUDE.md-style
snippets fed to AI test generation.

### `import_export_jobs` — bulk import/export tracking
`id` PK; `product_id` (indexed); `job_type` (`import`/`export`); `format` (enum `FileFormat`=
`excel`; ZIP also supported via endpoints); `status` (`pending/processing/completed/failed`);
progress counters `total_items`/`processed_items`/`successful_items`/`failed_items`;
`result_file_bucket` / `result_file_key`; `error_log` JSONB; `column_mapping` JSONB;
`export_options` JSONB; `created_by`; `started_at`/`completed_at`/`created_at`.

### `test_audit_events` — append-only audit log
`id` PK; `entity_type` VARCHAR(50); `entity_id` UUID; `action` VARCHAR(50); `actor` VARCHAR(255);
`product_id` (nullable); `before_snapshot` / `after_snapshot` / `diff` JSONB; `metadata` JSONB;
`created_at`. Indexes on `(entity_type,entity_id)`, `actor`, `created_at`, `product_id`.
Observed entity types: test_case, test_case_version, folder, tag, custom_field, parameter_set,
attachment, prompt_template, saved_query, product_field_value, test_run, test_execution.
Actions: created/updated/deleted/version_created/tagged/untagged/tags_modified/moved/
test_cases_added/test_case_removed/bulk_updated/started/completed/aborted/rerun_created/
assigned/defect_links_updated/copied. **This is essentially derivable from git history in a
git-native model.**

---

## Relationships (this domain)

```
test_cases 1───* test_case_versions          (CASCADE; latest = max(version_number))
test_case_versions ──self── parent_version_id (version lineage)
test_cases *───* test_folders   via test_case_folders   (a case in many folders)
test_folders ──self── parent_id  (tree; dynamic suites store an OQL query, no junction rows)
test_cases *───* test_tags       via test_case_tags
test_cases *───* credpool pools  via test_case_credpool_pools   (out of scope)
test_cases 1───* parameter_sets  (CASCADE)
test_attachments ──poly── (test_case | execution) via (entity_type, entity_id)
custom_field_definitions  →  values in test_case_versions.custom_fields (JSONB)
product_field_values / workspace_field_values  →  govern status/execution_type/test_category
```

See [relationships.md](relationships.md) for the cross-domain picture (executions, automated
results, traceability).
