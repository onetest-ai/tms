---
name: onetest-tms
description: >-
  Use when you need to manage or run tests in OneTest TMS via the onetest-tms MCP — creating or
  executing a test run, recording pass/fail results, searching test cases, filing defects,
  ingesting CI/JUnit results, or checking automation coverage, where test cases, runs, and reports
  live in GitHub Issues, Projects, and repo files.
license: MIT
version: 0.1.0
metadata:
  homepage: https://github.com/onetest-ai/tms
  provides: consumer-guidance
  mcp_server: onetest-tms
---

# Using OneTest TMS

OneTest TMS is a **git-native test management system**: test cases are Markdown files in a repo,
runs and executions are **GitHub Issues**, status lives on a **GitHub Project**, and reports are
committed Markdown. You operate it through the **`onetest-tms` MCP server**.

This skill teaches you how to *consume* the TMS. You bring your own way to actually run tests (for
example a browser driven via Playwright); the TMS stores the cases and records what happened.

## When to use
Creating or running a test run; recording results; searching tests; filing defects; ingesting
automated (CI/JUnit) results; or checking automation coverage.

## Prerequisites
- The `onetest-tms` MCP server is configured (local stdio), e.g. `.mcp.json`:
  `{ "onetest-tms": { "command": "npx", "args": ["-y", "onetest-gh-mcp"] } }`.
- `gh` is authenticated with access to the target TM repo and the org Project.
- Most tools take an optional **`repo`** (`OWNER/NAME`) — the TM repo to operate on. Omit it to use
  the server's default repo.

## Core workflow — a test run
1. **Find cases** — `search_test_cases({ query: "<OQL>", repo })` (or select by folder in step 2).
2. **Create the run** — `create_run({ name, oql | folder, repo, env, target, assignees })`.
   Creates a *Test Run* issue + one *Test Execution* issue per case, all on the board. Returns the
   run id (`RUN-<KEY>-YYYY-MM-DD-NNN`) and the execution issue refs (e.g. `OWNER/REPO#4`).
3. **Execute** each case with your own engine, capturing evidence (screenshots/logs).
4. **Record results** — `record_result({ execution: "OWNER/REPO#N", result, failure_reason?,
   notes?, evidence?, defect? })`. `result` ∈ `PASS|FAIL|BLOCKED|SKIPPED`. **PASS requires an
   `evidence` reference** and closes the issue.
5. **File defects** for failures — `create_defect({ target, title, severity, from_execution })`
   (or pass `defect` to `record_result`).
6. **Complete** — `complete_run({ run, repo })` → aggregates results, writes
   `reports/RUN-….md`, comments the summary on the run issue, and closes it.

## Other tools
- `get_test_case({ id })` — full case Markdown.
- `build_index({ repo })` — refresh the search index after cases change.
- `add_to_run({ run, oql | folder, repo })` — add cases to an existing run.
- `rerun_execution({ execution, reason })` — re-run a case as a new linked execution.
- `ingest_results({ file })` + `correlate_results({ automated })` — bring in automated JUnit
  results and match them to cases by `code_ref ⇄ automation_test_id`.
- `automation_coverage({ repo })` — coverage report: marked-automated vs linked-to-CI gaps.

## Conventions you must follow
- **IDs:** cases are `<SOURCE_KEY>-NNNN` (immutable, never reused). Runs are
  `RUN-<SOURCE_KEY>-YYYY-MM-DD-NNN` (unique on the shared org board).
- **`repo`:** pass the *product* TM repo (e.g. `onetest-ai/tm-shop`) — never the template repo.
- **`targets`:** executions are created in each case's `targets` repo (or `target`).
- **Evidence before PASS:** never record `PASS` without an `evidence` reference.
- **Don't hand-edit** issue `Result`/labels — always go through `record_result` so the Project
  field and labels stay in sync.
- **Authoring** test cases is done via a **pull request** of Markdown files to the TM repo (see the
  repo's `tests/README.md`), not through an MCP tool.

## OQL quick reference
`field OP value`, joined with `AND`/`OR`/`NOT` and `( )`; optional `ORDER BY f [ASC|DESC]`,
`LIMIT n`, `OFFSET n`. Operators: `= != ~ !~ ^ $ > >= < <=`, `IN (...)`/`NOT IN (...)`,
`CONTAINS [ANY|ALL] (...)`, `IS [NOT] NULL|EMPTY`. Examples:
- `tags CONTAINS "smoke" AND priority IN (critical, high)`
- `status = "ready" AND execution_type = "automated" ORDER BY priority`

## Worked example
```
search_test_cases({ repo: "onetest-ai/tm-shop", query: "tags CONTAINS 'smoke'", ids: true })
create_run({ repo: "onetest-ai/tm-shop", name: "Cart smoke", folder: "tests/cart", env: "staging" })
# → RUN-SHOP-2026-05-29-001, execution onetest-ai/tm-shop#4
record_result({ execution: "onetest-ai/tm-shop#4", result: "PASS",
                evidence: "reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0001.png" })
complete_run({ repo: "onetest-ai/tm-shop", run: "RUN-SHOP-2026-05-29-001" })
```
