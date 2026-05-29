# Parity with OneTest — Test Case & Test Execution Management

A capability-by-capability audit that the github-native design reaches parity with OneTest's two
core management domains. Each row maps a OneTest capability (from
[Functionality 01](../functionalities/01-test-case-management.md) /
[02](../functionalities/02-test-execution-management.md), grounded in the real REST + MCP surface)
to its github-native realization and the [`onetest-tms` tool](onetest-tms-spec.md) or native
mechanism that delivers it.

**Legend:** ✅ covered · ◑ covered with a deliberate change · ⛔ intentionally dropped (with why).

> Net result: **all of Test Case Management and Test Execution Management is covered.** What
> changes is *mechanism* (DB/REST → files/PRs/Issues/Projects + MCP), not *capability*. The only
> drops are billing/metering and the explicitly out-of-scope pipelines/credpools.

---

## 1. Test Case Management

| OneTest capability | github-native realization | Tool / mechanism | Status |
| --- | --- | --- | --- |
| Create test case (manual) | MD+front-matter file via PR | `create_test_case` / native PR | ✅ |
| Create test case (AI) | Claude writes file(s) → PR | `test-author` + `create_test_case` | ✅ |
| Import (XLSX/CSV/ZIP) | importer → files in a PR | `import_test_cases` | ✅ |
| Export (XLSX/ZIP, scopes) | render files → artifact | `export_test_cases` | ✅ |
| Auto identifier `TC-NNNN` | `SOURCE_KEY-NNNN`, source-repo allocation | `allocate-id` (concurrency) | ◑ source-based ID |
| Versioning (immutable, numbered) | git commits on the file | git / `update_test_case` | ◑ commits = versions |
| Version diff | `git diff` / structured diff | `diff_versions` | ✅ |
| History / activity timeline | git log + Issue/PR timelines | `get_history` | ◑ git history = audit |
| Approval (`pending/approved/rejected`) | PR review + branch protection | native | ◑ PR review |
| Folders / suite tree | directories | `list_folders`/`create_folder`/`move_folder` | ✅ |
| Move test case | `git mv` | `move_test_case` | ✅ |
| Dynamic suites (OQL) | `_suite.yml {dynamic, oql}`, materialized on demand | `search_test_cases` | ✅ |
| Tags (CRUD, auto-create, deprecate) | front-matter `tags[]` (+ labels on execution) | `set_tags` | ◑ files (+labels) |
| Custom fields | `.onetest/custom-fields.yml` + front-matter values | config PR / `validate_test_case` | ◑ config file |
| Field-value allow-lists (status/type/category) | `.onetest/fields.yml` ⊕ org defaults | `list_field_values`, `validate_test_case` | ✅ (422 → CI check) |
| Bulk ops (move/tag/update) | one PR over many files | `bulk_edit` | ✅ |
| Parameter sets (data-driven) | front-matter `parameters` / sibling file | `set_parameters` | ✅ |
| Attachments (case) | committed under `assets/` (LFS) | `attach_evidence` / native | ◑ committed files |
| OQL search | OQL over `index.json` | `search_test_cases`, `build_index` | ✅ |
| Simple contains-search | ILIKE-style over index | `search_test_cases` (mode) | ✅ |
| OQL schema / validate (query builder) | in-code over index | `get_oql_schema`, `validate_oql` | ✅ |
| Field-value autosuggest | distinct values from index | `list_field_values` | ✅ |
| Saved queries | `.onetest/queries/*.oql` / Project views | config / native | ◑ files/views |
| Prompt templates (AI snippets) | `.onetest/` files fed to generation | config | ◑ config file |
| Test-case stats | counts by status + unassigned | `get_test_case_stats` | ✅ |
| Automation coverage | ref ⇄ code_ref correlation | `get_automation_coverage` | ✅ (see [04](04-correlations-and-reporting.md)) |
| Per-case execution history | manual + automated merged | `get_execution_history` | ✅ |
| Audit events | git history + Issue/PR/Project timelines | native | ◑ derived |

---

## 2. Test Execution Management

| OneTest capability | github-native realization | Tool / mechanism | Status |
| --- | --- | --- | --- |
| Create run (cycle, scoped, context) | run-Issue + org Project; execution Issues in target repos | `create_run` | ✅ |
| Add tests (ids / bulk / OQL) | scope at creation or later | `create_run`, `add_to_run` | ✅ |
| Frozen scope (`scope_snapshot`) | the created execution-Issue set | `create_run` | ✅ |
| Run context (env/build/release/sprint) | Project fields + Milestone/Release/Environment | `create_run` inputs | ✅ |
| Run lifecycle (start/complete/abort) | run-Issue labels + Project state | `start_run`/`complete_run`/`abort_run` | ✅ |
| Run CRUD (update/delete) | edit/close run-Issue + Project | `update_run`/`delete_run` | ✅ |
| Copy run (re-run cycle) | clone scope | `copy_run` | ✅ |
| Record manual result | Project `Result` field + Issue comment/checklist | `record_result` | ✅ |
| Step results (pass/fail/skip/blocked) | Issue task-list | `record_step_result` | ✅ |
| Failure reason | Project field / label | `record_result` | ◑ extendable via fields.yml |
| Defect links | linked bug Issues | `create_defect`/`link_defect` | ✅ |
| Evidence (screenshots/logs) | committed + linked (no native issue-upload API) | `attach_evidence` | ◑ committed files |
| Execution assignment | Issue assignee + Project | `assign_execution` | ✅ |
| Personal queue (`/me/executions`) | Project view by assignee | `get_my_queue` | ✅ |
| AI-agent execution | `test-run-lead`/`test-runner` via MCP + Playwright | `web-qa` + MCP tools | ✅ |
| Exploratory results | new Issue + Project item | `record_result` (exploratory) | ✅ |
| Re-run | child execution Issue | `rerun_execution` | ✅ |
| Per-run analytics | computed over Project items | `get_run_analytics` | ✅ |
| Run dashboard / summary / trends | over runs/reports | `get_dashboard`/`get_trends` | ✅ |
| Shared public report | GitHub Pages report (public URL) | `publish_report` | ◑ Pages instead of token |
| Unified manual + automated runs | runs ∪ launches, normalized | `get_dashboard` + correlation | ✅ |
| Execution audit | Issue/Project timelines | native | ◑ derived |

---

## 3. Deliberately changed or dropped

| OneTest | Decision | Why |
| --- | --- | --- |
| Approval columns / status | ◑ → **PR review + branch protection** | git-native approval gate |
| `test_case_versions` / `test_audit_events` tables | ◑ → **git history + timelines** | versioning/audit come free from git |
| `product_field_values`/`workspace_field_values` (422) | ◑ → **`.onetest/fields.yml` + CI check** | config-as-code |
| Two `pass_rate` denominators | ◑ → **one: `passed/total`** | reconciled (matches web-qa report) |
| Four priority schemes (p0–p3 / p1–p4 / P0–P4) | ◑ → **`critical/high/medium/low`** | adopt the shipping web-qa scheme |
| Native issue file-upload for evidence | ◑ → **commit + link** | no official GitHub API for issue uploads |
| Coin metering / usage billing (`onetest-otel`) | ⛔ dropped | GitHub meters Actions minutes; rebuild only if needed |
| LLM config (`product_llm_configs`) | ◑ → **org/repo secrets** | no DB |
| Clerk identity / API keys | ◑ → **GitHub accounts + GitHub App** | native identity |
| **Pipelines, CredPools** | ⛔ out of scope | excluded from this exploration by request |

---

## 4. New capabilities github-native adds (beyond OneTest)

- **`size` (S/M/L)** per case — agent-execution cost (web-qa `test-sizer`); feeds cost estimation
  and reporting.
- **Run Performance Metrics** — tokens / tool_uses / duration per case in the report.
- **Cross-repo runs** — one run can create tasks across multiple target repos, aggregated on an
  org Project.
- **Free, native audit & notifications** — Issue/PR/Project timelines, assignment notifications,
  PR comments.
- **CI-uniform execution** — the same npx package runs runs in chat and in Actions identically.

---

## 5. Coverage summary

| Domain | OneTest capabilities | Covered (✅/◑) | Dropped (⛔) |
| --- | --- | --- | --- |
| Test Case Management | 28 | 28 | 0 |
| Test Execution Management | 22 | 22 | 0 |
| Platform/cross-cutting | — | identity, config, reporting re-homed | metering/billing, pipelines, credpools |

**Conclusion:** the github-native design + `onetest-tms` MCP is **on par with OneTest's Test Case
and Test Execution Management** — every capability is delivered, with mechanism changes that are
git-native wins (versioning, audit, approval, search) and only billing/out-of-scope items dropped.
