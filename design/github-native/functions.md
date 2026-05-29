# GitHub-Native: Functions Catalog

In the git-native model there is **no backend service** — every behaviour OneTest implemented in
FastAPI becomes a **"function"**: a GitHub Action / reusable workflow / `gh` CLI script
(optionally calling Claude). State lives in **git, Issues, and Projects**; functions only react to
events or dispatches and read/write that state.

Implementation options for a function (pick per case):
- **GitHub Action** — `workflow_dispatch`, `repository_dispatch`, `workflow_run`, `schedule`,
  `issues`, `pull_request`, `push` triggers.
- **Reusable/composite workflow** — shared across product repos from the org `.github` repo.
- **`gh` CLI / Octokit script** — invoked locally or inside an Action.
- **Claude Code / MCP** — for AI generation and agent execution.

## Packaging: one npx binary (stdio MCP + CLI)

Per the [Test Run UX](05-test-run-ux.md), the functions ship as **one npx package** with the
heavy logic **in code** (not in agent prompts), exposed two ways:

- **stdio MCP server** — `npx -y @onetest/tms` — so Claude Code / Copilot / VS Code agents call
  the functions as tools interactively (assisted mode).
- **CLI** — the same binary with subcommands (`onetest-tms create-run …`, `… parse-results …`) —
  invoked inside GitHub Actions for autonomous/CI runs.

Both entry points call the *same* code: OQL→scope resolution, GitHub API orchestration (create N
Issues, set Project fields), `code_ref ⇄ automation_test_id` matching, coverage math, report
rendering. The agent supplies judgment; the package supplies determinism. This is what makes a run
behave identically in chat and in CI.

Auth: `GITHUB_TOKEN` (scoped per workflow), org **fine-grained PAT** or **OIDC** for cross-repo /
Project writes. LLM creds live in **org/repo secrets** (replacing `product_llm_configs`).

## Catalog

| Function | Trigger | Reads | Writes | Replaces |
| --- | --- | --- | --- | --- |
| [`allocate-id`](#allocate-id) | PR / dispatch | existing `id:` front-matter | the new file's `id` | advisory-lock identifier allocation |
| [`validate-test-case`](#validate-test-case) | `pull_request` | changed test files, `.onetest/fields.yml` | check status | repository-layer 422 validation |
| [`build-index`](#build-index) | `push` to main | all test-case front-matter | `index.json` | the SQL table/indexes for search |
| [`oql-search`](#oql-search) | called by others / dispatch | `index.json` | matched file list | `api/search.py` OQL executor |
| [`ai-generate-test`](#ai-generate-test) | issue comment / dispatch / Claude Code | prompt, repo context, `prompt_templates` | PR adding test files | AI test generation |
| [`import-test-cases`](#import-test-cases) | dispatch (file input) | XLSX/CSV/ZIP | PR adding files | import jobs |
| [`export-test-cases`](#export-test-cases) | dispatch | files (scope/OQL) | XLSX/ZIP artifact | export jobs |
| [`create-run`](#create-run) | dispatch | scope (OQL/folders/ids), repos | Issues + Project items + run-Issue | `POST /runs` + add-tests |
| [`complete-run`](#complete-run) | dispatch / all-issues-closed | run Issues + Project | report, closes run-Issue | `complete_run` + analytics |
| [`sync-execution`](#sync-execution) | `issues`/`projects_v2_item` edited | execution Issue/Project field | `reports/runs/<run>/results.json` | execution writes |
| [`ai-run`](#ai-run) | schedule / dispatch | test files, target app | Issue/Project results, evidence | `/qa-onetest run` |
| [`parse-automated-results`](#parse-automated-results) | `workflow_run` completed | CI results artifact | `reports/automated/*.json`, job summary, PR comment | `receiver` ingestion |
| [`correlate-results`](#correlate-results) | after parse / schedule | front-matter refs + automated results | `reports/correlation.json` | `code_ref ⇄ automation_test_id` matching |
| [`automation-coverage`](#automation-coverage) | schedule / dispatch | index + correlation | `reports/coverage.*` | automation-coverage endpoint |
| [`generate-report`](#generate-report) | `complete-run` / schedule | Issues, results, correlation | `reports/**`, GitHub Pages | dashboards/trends/analytics |

---

## allocate-id
Serializes ID allocation without a DB lock. Runs with `concurrency: { group: id-allocation,
cancel-in-progress: false }`. Allocates `<SOURCE_KEY>-<number>` — `SOURCE_KEY` is the **source
repo's** immutable key from `.onetest/config.yml`; it scans existing `id:` values for that prefix,
computes `max+1`, writes it into the new/changed file, and commits to the PR branch. ID identity is
**source-based**; the target under test is separate front-matter (`targets[]`). *Alternatives:*
ULID IDs or path-as-identity need no serialization. (Maps to: identifier advisory lock; see
[ID scheme](01-test-case-management.md#identifier-scheme--source_key-number-decided).)

## validate-test-case
A required PR check. Validates each changed test file: required front-matter present; `status`,
`execution_type`, `test_category` ∈ allow-lists (`.onetest/fields.yml` ⊕ org defaults); `priority`
in scheme; tags/custom-fields well-formed; `automation_test_id` shape. Fails the check (with the
allowed values) instead of returning HTTP 422. (Maps to: repository-layer field validation +
`product_field_values`/`workspace_field_values`.)

## build-index
On push to `main`, parse every test-case file's front-matter into a single `index.json` (id,
title, status, type, category, priority, component, owner, tags, requirements,
automation_test_id, path, last-commit). Commit it or store as a cached artifact. Feeds all search
and reporting. (Maps to: DB indexes/full-text used by search.)

## oql-search
A small CLI wrapping the existing **`onetest-oql`** library, with its executor retargeted from
SQLAlchemy to `index.json`. Input: an OQL string (+ product context for field allow-lists);
output: matching file paths/ids (JSON). Used by `create-run`, dynamic suites, saved queries, and
AI natural-language search. (Maps to: `api/search.py`.)

## ai-generate-test
Claude (via Action or Claude Code) takes a natural-language request + repo context (existing tags,
`.onetest/` config, prompt templates) and writes one or more test-case files, then opens a **PR**.
Review = the PR diff (the interactive-form replacement). (Maps to: AI test generation.)

## import-test-cases / export-test-cases
Import: convert an uploaded XLSX/CSV/ZIP into files (reuse `test-management/formats/` Markdown/TOON
serializers) and open a PR. Export: render selected/filtered/all files to XLSX/ZIP as an Actions
artifact (or Release asset). (Maps to: `import_export_jobs`.)

## create-run
**The run-creation function** (see [Execution](02-test-execution-management.md#creating-a-run--the-create-run-function)).
Resolves scope (OQL/folders/globs/ids) → creates one execution **Issue** per case in the right
repo(s) → adds them to a **Project** with fields set → creates a parent run-Issue with sub-issues
→ assigns testers → outputs the Project URL. (Maps to: `POST /runs`, add-tests, add-from-oql,
scope_snapshot.)

## complete-run
Marks a run done: verifies/aggregates execution Issue results, invokes `generate-report`, closes
the run-Issue, sets the Project/labels to `completed` (or `aborted`). (Maps to: `complete_run`,
`abort_run`.)

## sync-execution
Optional. On execution Issue / Project field change, append the result to a durable
`reports/runs/<run>/results.json` so reporting and per-case history don't have to re-scan the
Projects API. (Maps to: execution result persistence.)

## ai-run
The autonomous executor: Claude Code with browser (CDP) + GitHub MCP. Reads test-case files,
executes steps, captures before/after screenshots (artifacts), writes results to the execution
Issues/Project, files exploratory findings as Issues. Schedulable; parallelized via matrix. (Maps
to: `qa-agent` `/qa-onetest run`, `octobots`.)

## parse-automated-results
On `workflow_run: completed`, download the CI results artifact (JUnit/JSON), parse (reuse the
`receiver` JUnit parser), compute totals, write `reports/automated/<run-id>.json`, emit
`$GITHUB_STEP_SUMMARY`, optionally comment on the PR, then trigger `correlate-results`. (Maps to:
the entire `receiver` ingestion path.)

## correlate-results
Match normalized `automation_test_id` (front-matter) ⇄ `code_ref` (parsed results) → write
`reports/correlation.json` with status/confidence/provenance; optionally back-annotate cases or
execution Issues. Reuse `_normalize_ref`. (Maps to: `link_to_test_case`, coverage matching.)

## automation-coverage
Compute coverage metrics from the index + correlation file → `reports/coverage.md`/`.html` (gap
bar, by priority/category), publish to Pages, surface on the quality Project. (Maps to:
`get_automation_coverage_stats`.)

## generate-report
The reporting function: read Issues/Project/results/correlation → render per-run analytics, the
dashboard, trends, and per-case history as Markdown/HTML in `reports/**`, publish to **GitHub
Pages**, and rely on **Projects Insights** for native charts (plus embedded SVG/mermaid for the
rest). (Maps to: `api/reporting.py`, shared reports.)

---

## Where each "function" runs

```
events ─────────────────────────────────────────────────────────────────────
push:main         → build-index
pull_request      → validate-test-case  (+ allocate-id on test-add PRs)
workflow_dispatch → create-run, complete-run, import/export, ai-generate-test,
                    ai-run, automation-coverage, generate-report
workflow_run done → parse-automated-results → correlate-results → generate-report
issues / project  → sync-execution
schedule (cron)   → automation-coverage, generate-report, ai-run
```

All reusable functions live in the org **`.github`** repo and are referenced by product repos, so
behaviour is defined once and inherited — the git-native analogue of a shared backend.
