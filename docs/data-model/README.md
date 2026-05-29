# Data Model — Conventions & Overview

This folder lists every entity, column, key, enum, and relationship for the four critical
functionalities, plus the foundational/shared entities they reference.

## Files

| File | Domain | Owning service |
| --- | --- | --- |
| [01-foundational.md](01-foundational.md) | Products (tenants), environments, releases, sprints, builds, deployments, members, user profiles, LLM config, admin | `membership` (+ `artifacts`, `gateway`) |
| [02-test-case-management.md](02-test-case-management.md) | Test cases, versions, folders, tags, parameter sets, attachments, custom fields, saved queries, field-value allow-lists, audit | `test-management` |
| [03-test-execution.md](03-test-execution.md) | Test runs, executions, step results, evidence, shared reports | `test-management` |
| [04-automated-results.md](04-automated-results.md) | Launches, test items (tree), logs, ingestion jobs, API keys | `receiver` |
| [relationships.md](relationships.md) | Consolidated cross-domain relationship & traceability map | all |

## Platform-wide conventions

These hold across every table unless noted otherwise.

- **Primary keys** are `UUID`, defaulting to `gen_random_uuid()` (SQL) / `uuid.uuid4()` (ORM).
- **Tenant scope:** almost every table has `product_id UUID NOT NULL` (the tenant). Within
  `membership` these are real FKs to `products(id) ON DELETE CASCADE`; in every other service
  they are **logical references with no FK** (cross-service rule).
- **User references:** `created_by`, `owner`, `assigned_to`, `author`, `uploaded_by`, etc. are
  `VARCHAR(255)` holding a **Clerk `clerk_user_id`** (the JWT `sub`). No FK; resolved against
  `membership.user_profiles` when a human-readable name/email is needed.
- **Timestamps** are `TIMESTAMPTZ`, typically `created_at`/`updated_at` defaulting to `now()`,
  with `updated_at` maintained by triggers or ORM `onupdate`.
- **Free-form JSON** is `JSONB` (Postgres) with a portable `JSONType` decorator for non-Postgres.
- **Object storage:** files are never stored in the DB. Rows carry a `(bucket, object_key)`
  pointer into the `artifacts` service.

## Enum strategy (important)

Most "status-like" columns are stored as `VARCHAR`, **not** native DB enums. Three of them —
`status`, `execution_type`, `test_category` on test cases — are **not even Python enums**: their
allowed values are **config-driven per product** via `product_field_values` (system defaults,
lazy-seeded per product) ∪ `workspace_field_values` (custom, workspace-global), minus disabled
rows. Validation happens at the repository layer (HTTP 422 with the allow-list on a bad value).
Value format is enforced `^[a-z0-9][a-z0-9_]*$`, max 50 chars.

All other enums in these docs are conventional (validated in code), listed per column.

## Stale-schema warning

`test-management/schema.sql` only reflects migrations 001–009; the live model is the ORM
(`src/onetest/test_management/db/models.py`) plus migrations up to **022**. These data-model
files follow the **ORM + latest migrations**, and flag where `schema.sql` disagrees.
