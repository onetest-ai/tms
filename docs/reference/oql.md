# OQL — OneTest Query Language

OQL is the query language used to select test cases for search and for run scope. In OneTest TMS the agent evaluates OQL over the generated `index.json` (built by `build_index`) to resolve queries to concrete cases. You pass OQL to `search_test_cases`, and to `create_run` / `add_to_run` via the `oql` parameter. Dynamic suites (`_suite.yml`) also use it.

You rarely type OQL by hand: describe the selection in natural language and the agent translates it to OQL. This page is the reference for the resulting syntax.

See also: [Test-case format](test-case-format.md) (the searchable fields) · [MCP tools](mcp-tools.md) · [Running test runs](../guides/running-test-runs.md).

## Query structure

```
<filter_expression> [ORDER BY <field> [ASC|DESC]] [LIMIT <n>] [OFFSET <n>]
```

- All clauses are optional. A bare filter is valid; so is `ORDER BY … LIMIT …` with no filter.
- `#` begins a line comment.
- String comparisons are **case-insensitive**.

## Operators

| Category | Operators | Meaning |
| --- | --- | --- |
| Comparison | `=` `!=` `>` `>=` `<` `<=` | Equality / ordering. Numeric when both sides parse as numbers, else case-insensitive string compare. |
| Pattern | `~` (or `~=`) `!~` `^` `$` `LIKE` | `~` contains, `!~` not-contains, `^` starts-with, `$` ends-with, `LIKE` substring (`%` stripped). All case-insensitive. |
| Set | `IN (...)` `NOT IN (...)` | Membership in a value list. |
| Array | `CONTAINS x` `CONTAINS ANY (...)` `CONTAINS ALL (...)` | Element tests against array fields like `tags`, `targets`. |
| Null / empty | `IS NULL` `IS NOT NULL` `IS EMPTY` `IS NOT EMPTY` | Presence test. Empty = missing, `""`, or empty list. (`NULL`/`EMPTY` behave the same here.) |
| Logical | `AND` `OR` `NOT` `( )` | Combine and group conditions. |

> Keywords and operators are case-insensitive; field names should match the front-matter keys.

## Value types

| Type | Form | Example |
| --- | --- | --- |
| String | `"..."` or `'...'` | `"smoke"`, `'happy-path'` |
| Number | `123`, `-123`, `123.45` | `size > 1` |
| Bare identifier | unquoted word | `priority IN (critical, high)` |

List values for `IN` / `CONTAINS ANY` / `CONTAINS ALL` are comma-separated inside parentheses, e.g. `(critical, high)`.

## Logical and grouping

- Combine conditions with `AND` / `OR`; negate with `NOT`.
- Use parentheses to control grouping: `(a OR b) AND c`.

## ORDER BY / LIMIT / OFFSET

| Clause | Effect |
| --- | --- |
| `ORDER BY <field> [ASC\|DESC]` | Sort by one field (default `ASC`); compared case-insensitively as text. |
| `LIMIT <n>` | Return at most `n` results. |
| `OFFSET <n>` | Skip the first `n` results (applied before `LIMIT`). |

## Searchable fields

OQL matches against the test-case front-matter fields indexed into `index.json`:

`id`, `title`, `priority`, `type`, `module`, `status`, `execution_type`, `size`, `targets`, `automation_test_id`, `requirements`, `tags`, plus `path`.

Array fields (`targets`, `automation_test_id`, `requirements`, `tags`) work with `CONTAINS` / `CONTAINS ANY` / `CONTAINS ALL`; scalar fields work with the comparison and pattern operators.

## Example queries

```
# Smoke cases at the top two priorities
tags CONTAINS "smoke" AND priority IN (critical, high)

# Ready automated cases, highest priority first
status = "ready" AND execution_type = "automated" ORDER BY priority

# Authentication module, exclude deprecated
module = "authentication" AND status != "deprecated"

# Cases targeting a specific repo
targets CONTAINS "onetest-ai/app-web"

# Cases that have no automation reference yet
automation_test_id IS EMPTY AND execution_type = "automated"

# Title starts-with, capped and paged
title ^ "Login" ORDER BY id ASC LIMIT 20 OFFSET 20

# Cases covering either of two requirements
requirements CONTAINS ANY (REQ-001, REQ-002)
```

Used via the agent:

```
search_test_cases({ repo: "onetest-ai/tm-shop", query: "tags CONTAINS 'smoke' AND priority IN (critical, high)", ids: true })
create_run({ repo: "onetest-ai/tm-shop", name: "Smoke", oql: "tags CONTAINS 'smoke'", env: "staging" })
```
