# OQL — OneTest Query Language

A JQL-inspired query DSL for searching and filtering tests, runs, and release entities.
Implemented as the standalone `onetest-oql` library (lexer → parser → AST → validator →
executor + entity schemas; only dependency `sqlalchemy>=2.0`) and mounted into
`test-management`'s search endpoints.

> **Authoritative fields = the `EntitySchema` definitions in
> `onetest-oql/src/onetest/oql/schemas/__init__.py`.** The published docs `field-reference` lists
> ~15 fields that do not exist (`last_run`, `pass_rate`, `flaky`, `execution_count`,
> `avg_duration`, `environment`, `automation_status`, `test_type`, `folder_path`, `reviewer`,
> `team`, `defect_links`, …) — treat those as marketing/aspirational.

## Where OQL is used

Test-case search, test-run search, **dynamic suites** (`test_folders.oql_query`), **add tests to
a run from a query**, **saved queries**, and as the **translation target for the AI's
natural-language search**.

## Query structure

```
<filter_expression> [ORDER BY <field> [ASC|DESC] (, <field> [ASC|DESC])*] [LIMIT <n>] [OFFSET <n>]
```
All clauses optional (a bare `ORDER BY … LIMIT …` is legal; `OFFSET` requires `LIMIT`). `#`
begins a line comment.

## Literals

- **String** `"..."`/`'...'` (escapes `\n \t \r \\ \" \'`)
- **Number** `123`, `-123`, `123.45`
- **Boolean** `true`/`false`
- **Date** `YYYY-MM-DD`; **Datetime** `YYYY-MM-DDTHH:MM:SS[Z|±HH:MM]`
- **Relative date** `[+-]\d+[dwmy]` — `-7d`, `-2w`, `-1m`, `-1y`, `+30d`. **Months use lowercase
  `m`** (docs' `-3M` would not tokenize). `m`=30 days, `y`=365 days (approx).
- Field names are **case-sensitive**; keywords/operators are case-insensitive.

## Operators

| Category | Operators |
| --- | --- |
| Comparison | `=` `!=` `>` `>=` `<` `<=` |
| Pattern (case-insensitive) | `~`/`~=` contains, `!~` not-contains, `^` starts-with, `$` ends-with, `LIKE` (raw), `MATCHES` (Postgres regex) |
| Set | `IN (...)`, `NOT IN (...)` |
| Array | `CONTAINS x`, `CONTAINS ANY (...)`, `CONTAINS ALL (...)` |
| Null/empty | `IS NULL`, `IS NOT NULL`, `IS EMPTY`, `IS NOT EMPTY` |
| Range | `BETWEEN a AND b` |
| Logical | `AND`, `OR`, `NOT`, `( )` |

Precedence (high→low): `()` > `NOT` > comparison > `AND` > `OR`.
An unquoted identifier on the right-hand side is a **field reference** (column-vs-column compare).
Dotted paths (`custom_fields.jira_ticket`) resolve via attribute access, falling back to JSONB
subscript.

The UI query builder exposes a deliberately narrower per-type operator set
(`LIKE`/`MATCHES`/`IS EMPTY` are parser-only).

## Functions

Implemented & validated: `currentUser()`, `now()`, `today()`, `startOfWeek()`/`endOfWeek()`,
`startOfMonth()`/`endOfMonth()`, `startOfYear()`/`endOfYear()`, `empty()`/`null()`.
**Documented but not implemented:** `startOfQuarter()`/`endOfQuarter()`, `currentUserEmail()`
(registered but raises). Custom functions can be injected programmatically.

## Validation

Unknown field → error listing available fields. Operator/type compatibility enforced (string ops
need string/uuid; ordering & `BETWEEN` need number/date/datetime; `CONTAINS` needs array). Enum
validation is **case-insensitive and normalizes to lowercase** in place.

## Searchable fields by entity (authoritative)

Field types: `string, number, boolean, date, datetime, enum, array, uuid`.

### `test_cases`
| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid | |
| `identifier` | string | e.g. `TC-0058` |
| `execution_type` | enum | per-product: default `manual, automated` |
| `test_category` | enum | per-product: default `functional, performance, security, accessibility, exploratory` |
| `status` | enum | per-product: default `draft, ready, deprecated` |
| `created_by`, `owner` | string | user fields (resolved from email/name → clerk id) |
| `created_at`, `updated_at`, `archived_at` | datetime | |
| `title`, `description`, `preconditions`, `expected_result`, `pass_fail_criteria` | string | **from latest version (join)** |
| `priority` | enum | `p1, p2, p3, p4` *(mismatch with Pydantic `p0–p3`)* |
| `component` | string | from latest version |
| `tags` | array(string) | via `test_case_tags`↔`test_tags` |
| `requirement` | string | singular; JSONB-array-element semantics over version `requirements` |

> The three per-product enums (`status`, `execution_type`, `test_category`) are fed from
> `product_field_values` ∪ `workspace_field_values` so OQL accepts custom values (e.g.
> `status = "ready_for_automation"`) and rejects disabled ones.

### `test_runs`
`id, name, description, run_type(manual|automated), status(planned|in_progress|completed|aborted),
assigned_to, planned_start, planned_end, actual_start, actual_end, created_at, updated_at,
created_by`.

### `releases`
`id, name, description, scope, status(planned|active|released), start_date, end_date, created_at,
updated_at, created_by, sprint_count, build_count`.

### `environments`
`id, name, description, endpoint_url, type(development|staging|production), created_at, updated_at,
deployment_count`.

### `builds`
`id, version, git_sha, scope, status(pending|active|archived), created_at, updated_at,
release(name), sprint(name), deployed_to(array)`.

### `sprints`
`id, number, name, scope, status(planned|active|completed), start_date, end_date, created_at,
release(name)`.

> The public `/search/schema` endpoint only exposes `test_cases` and `test_runs`; the release
> entities exist as join targets.

## How OQL compiles (service integration)

- `POST /search/products/{id}/test-cases` — parse → validate against the **product-aware** schema
  → resolve user fields → execute. Version fields / `tags` / `requirement` trigger a join to the
  latest `TestCaseVersion` (subquery `max(version_number)`). `tags` rewrites to a junction
  subquery (any via `IN`; all via `GROUP BY … HAVING count(distinct)=N`). `requirement` rewrites
  to a Postgres `EXISTS(jsonb_array_elements_text(...))`. Always scoped by `product_id`.
- `POST /search/products/{id}/test-runs` — OQL on `TestRun` directly.
- `POST /search/validate` — parse + validate only.
- `GET /search/schema` — drives the UI query builder.
- `/search/.../global` — simple `%text%` ILIKE mode (LIKE metacharacters escaped).
- **User-field resolution** (`oql_user_resolver.py`): `owner`/`created_by`/`assigned_to` values
  that aren't already clerk ids are resolved against `user_profiles` by email/full-name/partial
  and rewritten to clerk id(s), expanding to `IN (...)` on multiple matches.

## Example queries

```
status = "ready" AND priority IN (p1, p2)
tags CONTAINS "smoke" AND execution_type = "automated"
component ~ "checkout" ORDER BY updated_at DESC LIMIT 50
owner = currentUser() AND updated_at > -30d
requirement = "US-123"
status = "draft" AND created_at BETWEEN 2024-01-01 AND 2024-03-31
```

## Re-platforming notes

- OQL is a clean, self-contained library (no DB beyond SQLAlchemy expression building) — it can be
  retargeted to a git-native index without changing its surface syntax.
- The per-product enum awareness is the only product-coupled part: it needs the field-value config
  to validate custom values.
- Drop or implement the documented-but-missing functions/fields to remove the doc/code drift.
