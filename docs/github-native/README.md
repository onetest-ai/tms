# OneTest → GitHub-Native Mapping

This section maps every OneTest functionality onto **GitHub primitives**, for the planned
re-platform to a **git-native architecture with no backend services**. It builds directly on the
[data model](../data-model/) and [functionality](../functionalities/) docs.

It encodes the target mental model:

> - **Organization** = the OneTest workspace; we create **repositories** for test-case management
>   within it.
> - **Test runs** = a *function* that creates **tasks for specific repositories** and surfaces
>   them through **GitHub Projects** to the testing team.
> - **Reports** = a *function* that analyzes data and prepares **Markdown/HTML**, with **charts in
>   Projects**.
> - **Automated tests** = **reports in GitHub Actions**, analyzed by *functions* to create
>   summaries.

Here "function" means a **GitHub Action / reusable workflow / `gh` CLI script** (optionally
calling Claude). There is no always-on server — everything is files, git, Issues, Projects, and
event-triggered Actions. The catalog of these functions is in [functions.md](functions.md).

## Contents

- [Repository topology](00-repo-topology.md) — **start here**: no co-location; dedicated
  test-management repos vs target/app repos, cross-repo flows, auth
- [Core mapping principles](#core-mapping-principles)
- [Primitive mapping](#primitive-mapping) — GitHub primitive ⇄ OneTest concept
- [Master feature-to-feature table](#master-feature-to-feature-table)
- Per-domain detail:
  - [01 — Test Case Management](01-test-case-management.md)
  - [02 — Test Execution Management](02-test-execution-management.md)
  - [03 — Automated Test Results](03-automated-test-results.md)
  - [04 — Correlations & Reporting](04-correlations-and-reporting.md)
- [05 — Test Run UX (agents + MCP)](05-test-run-ux.md) — how runs feel to use in Copilot/Claude/VS Code
- [`onetest-gh` MCP tool spec](onetest-gh-mcp-spec.md) — the buildable contract (tool schemas + GitHub API mapping)
- [Parity with OneTest](parity-with-onetest.md) — capability-by-capability audit (TCM + Execution)
- [Functions catalog](functions.md)
- [Open decisions & trade-offs](#open-decisions--trade-offs)

## Core mapping principles

0. **No co-location — two repo classes.** Test cases live in **dedicated test-management repos**
   (source, QA-owned, own standards); the apps they test are **separate target repos**. This is
   the foundational decision — see [Repository topology](00-repo-topology.md).
1. **Tenant = Organization; Product = test-management Repository.** A OneTest `product` becomes one
   **TM repo** of test assets inside the org. The org replaces the `membership` tenant root; the TM
   repo replaces `product_id` scoping. The system under test is a separate repo, referenced as
   metadata (`targets[]`). (Identity moves from Clerk to **GitHub accounts/teams**.)
2. **Authored content = files in git.** A test case is a Markdown file with YAML front-matter.
   **Versioning, diff, history, approval** come for free from git + Pull Requests — replacing
   `test_case_versions`, the audit log, and the approval workflow.
3. **Work items = Issues; boards = Projects.** A test **execution** is an **Issue** (a task); a
   test **run** is a **GitHub Project** (v2) view that gathers those issues, possibly across
   repos, and shows them to the testing team. Sub-issues model run → executions.
4. **Behaviour = Actions ("functions").** Anything OneTest did in a backend service (allocate an
   ID, create a run, parse results, compute coverage, render a report) becomes an event- or
   dispatch-triggered Action. State lives in git/Issues/Projects, not a database.
5. **Reports = generated artifacts + Project insights.** Functions emit Markdown/HTML to
   `reports/` and **GitHub Pages**; trend/coverage charts use **Projects Insights** plus generated
   chart images/embeds.
6. **Automated results = CI output, parsed.** GitHub Actions run the tests; a parsing function
   turns JUnit/results artifacts into **job summaries**, result files, and **correlations** back
   to test-case files — replacing the `receiver` service and its ReportPortal API.
7. **Config replaces enums.** The per-product/workspace allow-lists become version-controlled
   config files (`.onetest/`), validated by a CI check on PRs.

## Primitive mapping

| GitHub primitive | OneTest concept it replaces | Notes |
| --- | --- | --- |
| **Organization** | Workspace / `membership` tenant root | Holds product repos, teams, org Projects |
| **Repository** | `product` (project/tenant scope) | One repo per product; `product_id` ⇒ repo |
| **Repo files (MD + YAML front-matter)** | `test_cases` + `test_case_versions` content | One file per test case |
| **Directories** | `test_folders` (static tree) | Folder = directory |
| **Git commits / history** | `test_case_versions`, `test_audit_events` | Version lineage, audit, immutability |
| **Git tags** | version pins, `builds` | Immutable references |
| **Pull Requests + reviews** | version `approval_status`, change review | `approved/rejected` = PR review states |
| **Commit message (conventional)** | `change_reason`, `change_category`, `author` | e.g. `fix:`/`feat:`/`refactor:`/`chore:` |
| **Issues** | `test_executions` (a task), defects | One issue per execution; defects = linked issues |
| **Sub-issues / task lists** | run → executions hierarchy | Parent run-issue → child execution-issues |
| **Issue labels** | tags, status, priority, category, failure_reason | Mirrored from front-matter when executed |
| **Issue assignees** | execution `assigned_to`, `owner` | |
| **GitHub Projects (v2)** | `test_runs` board, dashboards | Run surface + custom fields + Insights charts |
| **Project custom fields** | execution status/step results, custom fields | `not_run/passed/failed/...` as a single-select field |
| **Project iterations** | `sprints` / run cadence | |
| **Milestones** | `releases` / `sprints` | Group issues by release |
| **GitHub Releases** | `releases`, `builds` (assets) | Release notes + build artifacts |
| **GitHub Environments / Deployments** | `environments`, `deployments` | Deployment targets + history |
| **GitHub Actions / reusable workflows** | every backend "function" | create-run, parse-results, coverage, reports |
| **Actions artifacts** | execution evidence, automated logs, `import_export_jobs` | Screenshots, JUnit XML, logs |
| **Actions job summary (`$GITHUB_STEP_SUMMARY`)** | inline automated-result summary | Markdown rendered on the run page |
| **GitHub Pages** | shared/public reports, dashboards | Hosted HTML reports |
| **Git LFS / Releases assets** | `artifacts` service (large blobs) | Binary attachments |
| **Org/repo roles + Teams** | `product_members.role`, `platform_admins` | `owner→admin`, `member→write`; teams = QA team |
| **GitHub accounts** | Clerk users / `user_profiles` | `clerk_user_id` ⇒ GitHub login |
| **CODEOWNERS** | folder/test ownership | Auto-review routing by area |
| **Code search / `gh search` / front-matter index** | OQL search | Keep OQL syntax over a generated index |
| **Repo/org secrets & variables** | `product_llm_configs`, API keys | LLM creds, tokens |
| **OIDC / fine-grained PATs / `GITHUB_TOKEN`** | `product_api_keys`, Clerk API keys | CI auth for ingest |
| **MCP server over the repo + Claude Code** | AI assistant, MCP tool servers | AI reads/writes files, Issues, Projects |

## Master feature-to-feature table

| # | OneTest feature | GitHub-native realization | Function(s) |
| --- | --- | --- | --- |
| 1 | Create test case (manual) | Add a Markdown+front-matter file via PR | `validate-test-case`, `allocate-id` |
| 1 | Create test case (AI) | Claude (Action/Claude Code) opens a PR adding files | `ai-generate-test` |
| 1 | Import (XLSX/CSV/ZIP) | Importer Action converts → files in a PR | `import-test-cases` |
| 1 | Versioning / history / diff | Git commits, `git log`, PR diff | (native) |
| 1 | Approval (`pending/approved/rejected`) | PR review (request changes / approve) | (native) + branch protection |
| 1 | Folders / suites | Directory tree | (native) |
| 1 | Dynamic suites (OQL) | Saved query file, materialized on demand | `oql-search` |
| 1 | Tags | Front-matter `tags[]` (+ labels when executed) | `validate-test-case` |
| 1 | Custom fields / field allow-lists | `.onetest/fields.yml` config, CI-validated | `validate-test-case` |
| 1 | Saved queries | Query files / Project saved views | `oql-search` |
| 1 | Attachments | Files in `assets/` (LFS) or issue uploads | (native) |
| 1 | Export | Exporter Action → XLSX/ZIP artifact | `export-test-cases` |
| 2 | Create test run | Function creates execution **Issues** + adds to a **Project** | `create-run` |
| 2 | Add tests to run (ids/bulk/OQL) | `create-run` inputs: file globs, folders, OQL | `create-run`, `oql-search` |
| 2 | Run lifecycle (start/complete/abort) | Project status field + run parent-issue state | `create-run`, `complete-run` |
| 2 | Record manual result | Update the execution Issue (Project status field, checklist, comment) | (native UI) + `sync-execution` |
| 2 | Step results | Issue body task-list / checklist | (native) |
| 2 | Failure reason / defect links | Label + linked Issue references | (native) |
| 2 | Evidence (screenshots) | Drag-drop into Issue, or commit to `assets/` | (native) |
| 2 | Personal queue (`/me/executions`) | Project view filtered by assignee | (native) |
| 2 | AI-agent execution | Claude Code `/qa-onetest` via MCP over repo + Issues | `ai-run` (Claude Code) |
| 2 | Re-run | Reopen / new child Issue | `create-run` |
| 2 | Shared public report | GitHub Pages report | `generate-report` |
| 3 | Automated framework results | CI runs tests → artifacts → parsed | `parse-automated-results` |
| 3 | ReportPortal/JUnit ingest | Upload artifact + parsing Action (RP-compat shim optional) | `parse-automated-results` |
| 3 | Launch → items → logs | Workflow run → parsed result file → Actions logs/artifacts | `parse-automated-results` |
| 3 | Result summaries | `$GITHUB_STEP_SUMMARY` + committed results file | `parse-automated-results` |
| 3 | Item → test-case mapping | `code_ref` ⇄ `automation_test_id` match → correlation file | `correlate-results` |
| 4 | OQL search | OQL over a generated front-matter index | `build-index`, `oql-search` |
| 4 | Automation coverage | Function compares refs vs CI code_refs → report | `automation-coverage` |
| 4 | Dashboards / trends | Projects Insights + generated report/charts | `generate-report` |
| 4 | Per-run analytics | Report computed from the run's Issues | `generate-report` |
| 4 | Per-case execution history | Aggregated from Issues + correlation file | `generate-report` |
| 4 | Traceability (req/defect) | Front-matter `requirements[]` + linked Issues | `correlate-results` |
| F | Releases / sprints / builds | Releases, Milestones, iterations, tags | (native) |
| F | Environments / deployments | GitHub Environments + Deployments | (native) |
| F | Members / roles | Org/repo roles + Teams | (native) |
| F | LLM config / API keys | Secrets/variables; OIDC/PAT for CI | (native) |

## Open decisions & trade-offs

These are the genuine design forks; defaults chosen are noted, all are reversible.

1. **Repo topology — DECIDED: no co-location.** Dedicated test-management repos (source) vs
   separate target/app repos. One TM repo per product. See
   [Repository topology](00-repo-topology.md).
1b. **Where execution Issues live — DEFAULT: the target/app repo** (matches "tasks for specific
   repositories for testing"; native target numbering; dev visibility). **Alternative:** a
   centralized `tm-<product>-runs`/TM repo with target as a field — one `create-run` toggle. See
   [topology](00-repo-topology.md#where-each-thing-lives).
2. **Execution = Issue (default) vs Project draft item.** Issues give comments, assignees,
   cross-links, sub-issues, and history; draft items are lighter but can't be assigned/cross-
   referenced well. **Default: Issues**, added to a Project.
3. **Test-case ID scheme — DECIDED: `<SOURCE_KEY>-<number>`, source-project based.** The ID is
   `project + number`, where `project` = the **source** repo that owns the case (not the target
   under test) — identity must stay stable when a case is retargeted, and a case has one author but
   may test many systems. `SOURCE_KEY` is an immutable key in `.onetest/config.yml` (unique per
   repo ⇒ globally unique IDs); `<number>` is `max+1` allocated locally by
   [`allocate-id`](functions.md#allocate-id) with Actions `concurrency` (replacing the DB lock).
   Target is front-matter `targets[]` (routing only); execution Issues additionally carry the
   target repo's native issue number. Full rationale in
   [01 — Identifier scheme](01-test-case-management.md#identifier-scheme--source_key-number-decided).
4. **OQL backing store.** Keep `onetest-oql` syntax and retarget its executor to a generated
   `index.json` (built by `build-index` on push) — vs mapping to GitHub code search (limited
   operators). **Default: keep OQL over a generated index.**
5. **Status duplication.** Test-case lifecycle (`draft/ready/deprecated`) lives in front-matter;
   execution status lives in the Project field. Keep them separate (they always were) and sync
   only when an execution closes. **Default: front-matter is source of truth for cases; Project
   field for executions.**
6. **ReportPortal compatibility.** Customers' CI may post to the RP v2 API today. A pure
   git-native model drops that endpoint; offer a thin **RP-compat receiver Action** (or a small
   webhook-to-`repository_dispatch` shim) if drop-in compatibility must be preserved.
