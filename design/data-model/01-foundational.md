# Data Model — Foundational / Shared Entities

Source: `membership/schema.sql` + `migrations/`, `membership/src/onetest/membership/models.py`,
`artifacts/schema.sql` + `migrations/`, `gateway/schema.sql`, `onetest-auth/src/onetest/auth/`.

These entities are owned by the `membership` service (plus `artifacts` for storage) and are
referenced by `product_id` (and `release_id`, `build_id`, `environment_id`, …) from the
in-scope test-management and receiver services — **without cross-service foreign keys**.

> **No org/account/team/project/users tables exist.** The tenant root is `products`; identity
> is external (Clerk). See [overview](../overview.md#the-tenancy--identity-model-read-this-first).

## Tenancy root

### `products` — the tenant ("project")
Owner: `membership`. Every other table scopes to this.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK, `gen_random_uuid()` |
| `name` | VARCHAR(255) | NOT NULL |
| `description` | TEXT | |
| `product_type` | VARCHAR(50) | NOT NULL. Enum `ProductType`: `webapp` (default), `api`, `mobile` |
| `created_by` | VARCHAR(255) | NOT NULL (clerk_user_id) |
| `metadata` | JSONB | NOT NULL default `{}` |
| `integrations` | JSONB | default `{}` (GIN index `idx_products_integrations`) |
| `created_at` / `updated_at` | TIMESTAMPTZ | NOT NULL default `now()` |

## Release hierarchy (execution context targets)

### `environments` — deployment targets per product

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL → `products(id)` CASCADE |
| `name` | VARCHAR(255) | NOT NULL |
| `description` | TEXT | |
| `endpoint_url` | VARCHAR(2048) | NOT NULL |
| `is_default` | BOOLEAN | NOT NULL default false |
| `metadata` | JSONB | NOT NULL default `{}` |
| `created_at` / `updated_at` | TIMESTAMPTZ | default `now()` |

Constraint: partial unique index `uq_environments_default_per_product (product_id) WHERE
is_default = true` — at most one default environment per product.
(OQL also exposes a `type` enum `development/staging/production` for environments.)

### `releases` — per product

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL → `products(id)` CASCADE (indexed) |
| `name` | VARCHAR(255) | NOT NULL |
| `description` / `scope` | TEXT | |
| `start_date` / `end_date` | TIMESTAMPTZ | |
| `status` | VARCHAR(50) | NOT NULL default `planned`. Enum `ReleaseStatus`: `planned`, `active`, `released` |
| `metadata` | JSONB | NOT NULL default `{}` |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

### `sprints` — belong to a release

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `release_id` | UUID | NOT NULL → `releases(id)` CASCADE (indexed) |
| `number` | INTEGER | NOT NULL (`>= 1`) |
| `name` | VARCHAR(255) | nullable |
| `scope` | TEXT | |
| `start_date` / `end_date` | TIMESTAMPTZ | |
| `status` | VARCHAR(50) | NOT NULL default `planned`. Enum `SprintStatus`: `planned`, `active`, `completed` |
| `metadata` | JSONB | NOT NULL default `{}` |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

### `builds` — belong to a sprint OR a release (dual optional FK)

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `sprint_id` | UUID | nullable → `sprints(id)` CASCADE |
| `release_id` | UUID | nullable → `releases(id)` CASCADE |
| `version` | VARCHAR(255) | NOT NULL |
| `git_sha` | VARCHAR(40) | nullable |
| `scope` | TEXT | |
| `status` | VARCHAR(50) | NOT NULL default `pending`. Enum `BuildStatus`: `pending`, `active`, `archived` |
| `metadata` | JSONB | NOT NULL default `{}` |
| `created_at` | TIMESTAMPTZ | (no `updated_at`) |

Supports idempotent **find-or-create by `version`** under a given sprint/release (used by the
receiver auto-link service).

### `deployments` — join build ↔ environment

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `environment_id` | UUID | NOT NULL → `environments(id)` CASCADE |
| `build_id` | UUID | NOT NULL → `builds(id)` CASCADE |
| `deployed_at` | TIMESTAMPTZ | NOT NULL default `now()` |
| `deployed_by` | VARCHAR(255) | NOT NULL (clerk_user_id) |
| `status` | VARCHAR(50) | NOT NULL default `active`. Enum `DeploymentStatus`: `active`, `rolled_back` |
| `metadata` | JSONB | NOT NULL default `{}` |

**Release lineage:** `releases → sprints → builds → deployments → environments`, all under a
product.

## Membership & identity

### `product_members` — user ↔ product membership + role

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL → `products(id)` CASCADE |
| `clerk_user_id` | VARCHAR(255) | NOT NULL |
| `role` | VARCHAR(50) | NOT NULL. Enum `MemberRole`: `owner`, `member` (default `member`) |
| `added_by` | VARCHAR(255) | NOT NULL |
| `metadata` | JSONB | NOT NULL default `{}` |
| `created_at` | TIMESTAMPTZ | default `now()` |

Constraint: `uq_product_member UNIQUE(product_id, clerk_user_id)` — one role per user per product.

### `user_profiles` — Clerk profile cache (PK = clerk id)

| Column | Type | Notes |
| --- | --- | --- |
| `clerk_user_id` | VARCHAR(255) | **PK** |
| `email` | VARCHAR(255) | indexed |
| `first_name` / `last_name` / `display_name` | VARCHAR(255) | |
| `avatar_url` | TEXT | |
| `created_at` / `updated_at` | TIMESTAMPTZ | `updated_at` via trigger |

Used by OQL user-field resolution to translate emails/names → `clerk_user_id`.

### `platform_admins` — global admins

| Column | Type | Notes |
| --- | --- | --- |
| `clerk_user_id` | VARCHAR(255) | **PK** |
| `granted_by` | VARCHAR(255) | NOT NULL |
| `created_at` | TIMESTAMPTZ | default `now()` |

### `product_llm_configs` — per-product BYO LLM (1:1 with product)

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL → `products(id)` CASCADE |
| `provider` | VARCHAR(50) | NOT NULL. Enum `LLMProviderType`: `azure`, `bedrock`, `openai`, `anthropic` |
| `credentials_encrypted` | BYTEA | NOT NULL (never returned; API exposes only `credentials_hint`) |
| `model_high` / `model_default` / `model_low` | VARCHAR(255) | NOT NULL (3-tier model routing) |
| `is_validated` | BOOLEAN | NOT NULL default false |
| `last_validated_at` | TIMESTAMPTZ | |
| `validation_error` | TEXT | |
| `created_by` | VARCHAR(255) | NOT NULL |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

Constraint: `unique_llm_config_per_product UNIQUE(product_id)`.

### Onboarding / legal (informational)
- `access_requests` — gated-onboarding queue: `clerk_user_id`, `email`, `product_name`,
  `product_type`, `use_case`, `status` (`pending`/`approved`/`rejected`), reviewer fields,
  `product_id` (set on approval → `products(id) ON DELETE SET NULL`).
- `eula_acceptances` (migration 008) — `user_id`, `version`, `accepted_at`, `ip_address INET`,
  `user_agent`; `UNIQUE(user_id, version)`.

## Object storage (`artifacts` service)

Screenshots, logs, attachments, skill/persona files live here; other services store only
pointers. Object/file metadata is **not** in Postgres (lives in MinIO/local-FS/S3); only buckets
and credentials are tracked.

### `artifact_buckets`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL (logical ref; indexed) |
| `name` | VARCHAR(63) | NOT NULL — user-facing name (e.g. `screenshots`) |
| `storage_name` | VARCHAR(63) | NOT NULL — physical S3/MinIO bucket (e.g. `p-abc123-screenshots`). UNIQUE pre-migration-005; 005 consolidates many products into one physical bucket + folder prefixes |
| `retention_days` | INTEGER | nullable (null = keep forever; default env 90) |
| `size_limit_bytes` | BIGINT | nullable |
| `is_protected` | BOOLEAN | NOT NULL default false (blocks deletion) |
| `is_consolidated` | BOOLEAN | NOT NULL default false (single-bucket + prefixes) |
| `created_by` | VARCHAR(255) | nullable |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

Constraint: `UNIQUE(product_id, name)`.

### `artifact_credentials` — S3-style access keys (distinct from Clerk API keys)

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | PK |
| `product_id` | UUID | NOT NULL (logical ref) |
| `access_key_id` | VARCHAR(100) | NOT NULL UNIQUE — format `ONETEST{product:8}{random:8}` |
| `secret_access_key_hash` | VARCHAR(255) | NOT NULL (hash; was encrypted BYTEA pre-migration-004) |
| `name` / `description` | VARCHAR(255) / TEXT | |
| `permissions` | JSONB | NOT NULL default `["read","write"]` |
| `is_active` | BOOLEAN | NOT NULL default true |
| `last_used_at` / `expires_at` | TIMESTAMPTZ | (`expires_at` null = never) |
| `created_by` | VARCHAR(255) | nullable (null for auto-created default) |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

One credential auto-provisioned per product on initialization.

## Supporting (gateway) — referenced, not central to the 4 functionalities

The `gateway` service owns the AI-assistant front door. Tables (summarised; full detail not
required for the in-scope domains): `conversations` 1—* `messages` 1—* `message_attachments`
(attachments point into `artifacts`); `integration_catalog` 1—* `integrations` 1—1
`integration_credentials`; `product_skills` 1—* `skill_executions`; `product_personas`;
`user_preferences`; `qa_agent_connections` (registered QA-agent runtimes per product, with
`api_key_id`, `agent_version`, `status`, `last_active_at`); `user_activity` (UI activity feed
used as AI context). Skills/personas are artifact-backed (`artifact_path`, `artifact_etag`).

## `onetest-auth` (shared library, no DB)

Not a service — a library imported by every service. Validates Clerk session JWTs (RS256 against
Clerk JWKS, cached) and opaque `ak_…` API keys (server-side verify at Clerk). Sets `user_id` +
`auth_type ∈ {session, api_key}` per request; extracts `product_id` from the URL path
(`/products/{uuid}`) for metering; meters **API-key write operations only** (POST/PUT/PATCH/
DELETE) — UI/session traffic and reads are free.

**Takeaway for re-platforming:** users and API keys are not platform-owned data. The universal
foreign reference to a user is `clerk_user_id` (the JWT `sub`); the universal tenant key is
`product_id`.
