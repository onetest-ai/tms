# OneTest — Platform Overview

## What OneTest is

OneTest is an **AI-powered test management platform** ("build, manage, and execute tests with
AI"). It lets teams author test cases (manually, by AI generation, or by import), organise them,
execute them manually or via AI agents, ingest automated CI/CD results, and report on quality
and automation coverage. The AI assistant is powered by Claude.

The web app runs at `tms.onetest.ai`; documentation at `onetest.ai`.

## Today's architecture (the thing being replaced)

OneTest is currently a **microservice platform**: many independent FastAPI/Starlette services,
each with **its own PostgreSQL schema** (asyncpg + SQLAlchemy 2.0), fronted by a gateway, with
identity delegated to **Clerk** and object storage in an S3-compatible **Artifacts** service.

**Crucial cross-service rule:** there are **no database-level foreign keys across service
boundaries.** Services reference each other's rows by UUID convention only (e.g.
`product_id`, `release_id`, `test_case_id`). This is repeatedly enforced in code and migrations
(e.g. `test-management/migrations/003_remove_cross_service_fks.sql`). Only *intra-service* FKs
exist.

### Repo / service map (in-scope areas in **bold**)

| Repo | Role | In scope? |
| --- | --- | --- |
| `membership` | Tenants (**products**), environments, releases, sprints, builds, deployments, members, LLM config, onboarding | Foundational |
| `onetest-auth` | Shared library: Clerk JWT/API-key verification, ASGI auth middleware, metering hook (no DB) | Foundational |
| `artifacts` | S3-compatible object storage (buckets, credentials); screenshots/logs/attachments live here | Foundational |
| `gateway` | AI-assistant / MCP front door: conversations, integrations catalog, skills, personas, activity | Supporting |
| **`test-management`** | **Test cases, versions, folders, tags, runs, executions, reporting, OQL search, MCP tools** | **1, 2, 4** |
| **`receiver`** | **Automated-result ingestion (ReportPortal v2 compatible, JUnit import): launches, items, logs** | **3** |
| **`onetest-oql`** | **OQL query-language library (lexer/parser/validator/executor + entity schemas)** | **4** |
| `onetest-otel` | Shared OpenTelemetry metering library (emits spans; persists nothing) | Supporting |
| **`core`** | **React 18 + MUI + Redux web UI (test management, execution panel, dashboards)** | **1, 2, 4 (UI)** |
| **`qa-agent`** | **Claude Code QA agent + skills; `/qa-onetest` drives runs via MCP (autonomous execution)** | **2** |
| `octobots` | Autonomous multi-agent dev/QA team (Claude Code instances coordinated via SQLite + GitHub) | 2 (agent runtime) |
| `Octo` | General LangChain/LangGraph multi-provider agent CLI (the engine agents run on) | 2 (agent runtime) |
| `mcp-host` | HTTP proxy that spawns STDIO MCP servers on demand | Supporting |
| `docs` | Public Mintlify documentation (MDX) | Reference |
| `pipeline`, `credpool` | Multi-phase ingestion; credential pools | **OUT OF SCOPE** |
| `membership`/billing, `metering`, `scout`, `sirens`, `octi-tests`, `skills`, `deployment` | Billing, metering store, misc | Out of scope |

## The tenancy & identity model (read this first)

- **There is no `organization`, `account`, `team`, or `project` table.** The single top-level
  tenant entity is **`product`** (`membership.products`). In the UI and URLs, *"project" ==
  product*. Every other table across every service carries `product_id UUID` to isolate data
  per tenant.
- **Users live entirely in Clerk** (external IdP). There is **no `users` table**. Every "who"
  column is `clerk_user_id` / `user_id VARCHAR(255)` (the Clerk `sub`). `membership.user_profiles`
  is a local read-cache of Clerk profile data, keyed by `clerk_user_id`.
- **API keys** are issued/verified by Clerk (session tokens) or by the `receiver` service
  (`product_api_keys`, scoped, prefixed `octo_…`, formerly `rp_…`) for CI/CD ingestion.
- **Roles** are minimal: per-product `product_members.role ∈ {owner, member}`, plus a global
  `platform_admins` table. No granular permission tables, no teams.

## The four critical functionalities at a glance

```
        ┌─────────────────────── product (tenant) ───────────────────────┐
        │                                                                 │
  (1) TEST CASE MGMT          (2) EXECUTION MGMT        (3) AUTOMATED RESULTS
  test_cases                  test_runs                 launches
   └ test_case_versions        └ test_executions         └ receiver_test_items (tree)
   ├ test_folders (tree/OQL)     ├ step_results[]           └ receiver_test_item_logs
   ├ test_tags (m:n)            ├ defect_links[]          product_api_keys
   ├ parameter_sets             └ test_attachments        receiver_ingestion_jobs
   ├ custom_field_definitions
   └ saved_queries
        │                            │                          │
        └──────────────── (4) CORRELATIONS & REPORTING ─────────┘
              OQL search · dashboards · trends · per-run analytics
              automation coverage:  automation_test_id  ⇄  code_ref
              traceability:  test_case ⇄ requirement ⇄ release/build ⇄ defect
```

Each functionality is documented behaviourally in [`functionalities/`](functionalities/) and
structurally in [`data-model/`](data-model/).

## Key facts that survive re-platforming

These are the load-bearing details a git-native design must preserve:

1. **Test case = identity row + immutable numbered versions.** `test_case_versions` already
   models authored content as immutable, numbered, diffable snapshots with author /
   `change_reason` / `change_category` / approval — this maps almost 1:1 onto git commits.
2. **`product_id` scoping == repository/directory boundary.** Everything is tenant-scoped.
3. **Human IDs (`TC-NNNN`) are sequential per product**, currently allocated with a Postgres
   advisory lock — a git-native scheme needs a deterministic replacement.
4. **The single most important correlation key** is `automation_test_id` (on a test-case
   version) ⇄ `code_ref` (on an automated result item), both normalised to `file:Class.method`.
   This unifies the manual and automated worlds. See
   [04 — Correlations & Reporting](functionalities/04-correlations-and-reporting.md).
5. **Allowed values for `status`, `execution_type`, `test_category` are config-driven**, not
   DB/Python enums — sourced from `product_field_values` (system, per-product) ∪
   `workspace_field_values` (custom, workspace-global), minus disabled. Model these as config.
6. **Dynamic folders are stored queries**, not stored membership (`test_folders.oql_query`).
7. **Heavy JSONB** (`steps`, `parameters`, `requirements`, `dependencies`, `known_issues`,
   `custom_fields`, `defect_links`, `step_results`, launch `statistics`) → naturally becomes
   YAML/JSON front-matter or Markdown. The `test-management` repo already ships Markdown/TOON
   serializers (`formats/`) used by ZIP export.
8. **Object storage is referenced by pointer** (`bucket` + `object_key`), never stored inline.

## Documented discrepancies (authoritative source wins)

These came up repeatedly and matter for a faithful re-platform:

- **`test-management/schema.sql` is stale** — it only reflects migrations 001–009. The repo has
  migrations up to **022** and the ORM (`db/models.py`) is current. Trust the ORM + migrations.
  schema.sql wrongly retains `archived_at`, `automation_status`, `estimated_duration_minutes`,
  the old `parameters` column on param sets, pre-011 import/export & custom-field column names,
  narrower varchar widths, and a non-partial tag unique constraint.
- **OQL field reference (docs) lists ~15 fields that do not exist** (`last_run`, `pass_rate`,
  `flaky`, `execution_count`, `avg_duration`, `environment`, `automation_status`, `test_type`,
  `folder_path`, `reviewer`, `team`, `defect_links`, …). The real searchable fields are the
  `EntitySchema` definitions in `onetest-oql`. Docs examples are aspirational/marketing.
- **Priority enum mismatch:** OQL test-case schema = `p1–p4`; the Pydantic `Priority` enum =
  `p0–p3`; UI priority tables show `P0–P4`. Reconcile to one scheme.
- **Relative-date months:** code accepts lowercase `-3m`; docs show `-3M` (would not tokenise).
- `startOfQuarter()/endOfQuarter()` and `currentUserEmail()` are documented but **not
  implemented** in the executor.
- **Two different `pass_rate` denominators** coexist (dashboard includes blocked+skipped in the
  denominator; per-run & automated analytics use `passed/(passed+failed)`).
- **Host inconsistencies** in docs: `tms.onetest.ai/api/...`, `.../api/receiver`,
  `.../api/test-management/api/v1/...`, and `api.onetest.ai/v1/...` all appear.
- Several `docs` pages are marked **"under construction"** (`ui/viewing-results`, all
  `workflows/*`) — treat their feature lists as intent, not shipped behaviour.
