# GitHub-Native: Correlations & Reporting

Maps [Functionality 04](../functionalities/04-correlations-and-reporting.md),
[OQL](../functionalities/oql-query-language.md), and the
[traceability map](../data-model/relationships.md) onto GitHub.

**Principle (your model):** *reports = a function that analyzes data and prepares Markdown/HTML,
and Projects carry the charts.* Plus the OneTest correlation engine (`automation_test_id ⇄
code_ref`) runs as a function over files + CI results.

## Search — OQL over a generated index

OQL is a self-contained library; keep its syntax and retarget its executor.

| OneTest | GitHub-native |
| --- | --- |
| `POST /search/.../test-cases` (OQL → SQL) | [`oql-search`](functions.md#oql-search) (OQL → query over `index.json`) |
| product-aware schema (field allow-lists) | index built from front-matter + `.onetest/fields.yml` |
| user-field resolution (email/name → id) | resolve to **GitHub logins** |
| dynamic suites / add-from-OQL / saved queries | same OQL engine, invoked by `create-run` and suites |
| natural-language → OQL (AI) | unchanged — Claude emits OQL, executed by `oql-search` |

[`build-index`](functions.md#build-index) runs on push to `main`: it scans every test-case file's
front-matter into `index.json` (committed or cached as an artifact). `oql-search` queries that
index. (Alternative: GitHub **code search** for simple cases, but it lacks OQL's operators —
keeping the index preserves full fidelity.)

## The correlation engine — `automation_test_id ⇄ code_ref`

This single mechanism (the heart of [Reporting](../functionalities/04-correlations-and-reporting.md))
becomes [`correlate-results`](functions.md#correlate-results):

1. Read each test case's `automation_test_id[]` (front-matter) → normalize to `file:Class.method`.
2. Read parsed automated results (`reports/automated/*.json` from
   [Automated Results](03-automated-test-results.md)) → normalize each `code_ref` the same way.
3. Match (any ref matches = linked) → write a **correlation file** `reports/correlation.json`
   `{ test_case_id, code_ref, status, workflow_run, confidence, mapped_by }`.
4. Optionally back-annotate the test-case file or the execution Issue with the latest automated
   result.

This preserves the exact normalization rules (pytest `::` ↔ `:`, multi-ref, etc.) — reuse the
`_normalize_ref` logic from `test-management`.

## Reports — functions that emit Markdown/HTML

[`generate-report`](functions.md#generate-report) is the "reporting function." Triggered on
`complete-run`, on schedule, or on dispatch. It reads Issues (executions), the Project, result
files, and the correlation file, then writes:

| OneTest report | GitHub-native output |
| --- | --- |
| Per-run analytics (`/runs/{id}/analytics`) | `reports/runs/<run>.md` + `.html`: counts, pass_rate, completion, durations, failures-by-reason, per-folder, failed-tests |
| Run dashboard / summary / trends | `reports/dashboard.html` (history from prior report files) + **Projects Insights** charts |
| Per-case execution history | section per case, merging Issue results + correlation entries |
| Shared public report | published to **GitHub Pages** (a public URL replaces `shared_reports` tokens; access controlled by repo/Pages visibility) |
| Test-case stats | counts by `status` + unassigned, from the index |

> **Reconcile on the way:** pick **one** `pass_rate` denominator (OneTest had two) and **one**
> priority scheme (`p0–p3` vs `p1–p4`) — see
> [overview discrepancies](../overview.md#documented-discrepancies-authoritative-source-wins).

### Charts in Projects (your "charts in projects")
- **GitHub Projects Insights** gives native charts: status breakdown, burn-up/down by iteration,
  field distributions (Result, Priority, Category) — no code needed. Configure saved charts on the
  run/quality Project.
- For charts beyond Insights (trend lines, coverage gauges), `generate-report` renders images
  (e.g. SVG/`mermaid`) into the Pages report and embeds them; Project READMEs can link to them.

## Automation coverage — `automation-coverage` function

The coverage correlation ([the engine](../functionalities/04-correlations-and-reporting.md#automation-coverage--the-correlation-engine))
becomes [`automation-coverage`](functions.md#automation-coverage) (scheduled/dispatch):

- Inputs: the index (`execution_type`, `automation_test_id`, priority, category) + the correlation
  file (which refs actually ran in CI).
- Outputs the same metrics — `marked_automated`, `linked_to_results`, `no_automation_ref`,
  `automation_gap` (+ %), `coverage_by_priority`, `coverage_by_category` — as
  `reports/coverage.md`/`.html` with the green/orange/red gap bar, published to Pages and surfaced
  on the quality Project.

## Traceability

| Link | GitHub-native |
| --- | --- |
| test case ⇄ requirement | front-matter `requirements[]` (e.g. `US-123`); if requirements are GitHub Issues, link them; coverage by requirement computed by a function |
| test case ⇄ automated result | `automation_test_id ⇄ code_ref` via `correlate-results` |
| test case ⇄ manual/AI result | execution **Issue** references the test-case file + commit (the executed version) |
| run ⇄ release/build/env | Project iteration + **Milestone**/**Release** + Environment field |
| execution ⇄ defect | linked bug **Issues** |
| test case ⇄ bug (known issue) | front-matter `known_issues[]` → Issue refs |

"Which version was executed" (OneTest pinned `test_case_version_id`) → the execution Issue records
the **commit SHA** of the test-case file at run-creation time.

## What disappears / changes

- The reporting/search SQL in `test-management` → `oql-search`, `generate-report`,
  `automation-coverage`, `correlate-results` functions over files + Issues + CI artifacts.
- Live dashboards → generated Pages reports + Projects Insights (refreshed by scheduled
  functions).
- Stored audit/history → git history + Issue/PR timelines.
- The two pass_rate definitions and dual priority scheme → reconcile to one each.
