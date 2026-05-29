# GitHub-Native: Repository Topology

This is the foundational decision the rest of the mapping hangs off. **No co-location:** test
cases live in **dedicated test-management repositories** with their own standards — separate from
the application/system code they test.

## Two classes of repository

| Class | Holds | Owned by | OneTest analogue |
| --- | --- | --- | --- |
| **Test-management repo (SOURCE)** | test-case files, `.onetest/` config, functions, reports | QA / test team | a `product`'s test assets + `product_id` scope |
| **Target / app repo (UNDER TEST)** | application/service code + its CI | dev teams | the "system under test" (`product_type` webapp/api/mobile) |

Plus two org-level pieces:
- **Org `.github` repo** — shared reusable functions, issue/PR templates, org-default
  `fields.yml`. Behaviour defined once, inherited by all TM repos (the git-native "shared
  backend").
- **Org Projects (v2)** — the testing-team boards that aggregate execution Issues across repos.

```
 Organization
 ├── .github                      (shared functions, templates, org defaults)
 ├── tm-login        ─┐
 ├── tm-checkout      ├─ TEST-MANAGEMENT repos (SOURCE): cases + config + functions + reports
 ├── tm-payments     ─┘            SOURCE_KEY lives here → IDs like LOGIN-0042
 │
 ├── app-web         ─┐
 ├── app-api         ├─ TARGET / APP repos (UNDER TEST): code + CI; receive execution tasks,
 ├── mobile-ios      ─┘            emit automated results
 │
 └── (org Projects)               testing-team run/quality boards, aggregating across repos
```

## Cardinality

- A TM repo **1—\*** target repos: one test suite can exercise several apps/services (front-matter
  `targets[]`).
- A target repo **\*—\*** TM repos: an app can be covered by multiple suites.
- `product_id` scoping ⇒ the **TM repo boundary**. The "system under test" is no longer the scope
  key — it's metadata (`targets[]`).

## What "own standards" means in a TM repo

Because TM repos are dedicated, they enforce the OneTest content standard without touching dev
repos:

- **Front-matter schema** for every test case (the [01](01-test-case-management.md) fields).
- **`.onetest/fields.yml`** allow-lists (status/execution_type/test_category), layered over org
  defaults; enforced by the required [`validate-test-case`](functions.md#validate-test-case) check.
- **Naming conventions** — `SOURCE_KEY` prefix, file naming, folder layout under `tests/`.
- **Branch protection** on `main` = the approval gate (a merge == an approved version).
- **CODEOWNERS** = the QA/feature owners; routes reviews.
- **Conventional commits** carry `change_reason`/`change_category`.

Target/app repos are **not** required to adopt any of this. Their only contracts with the platform
are: (1) accept execution-task Issues, and (2) emit automated results in a parseable form using the
`code_ref` ⇄ `automation_test_id` convention. Everything else stays in the QA domain.

## Where each thing lives

| Thing | Repo |
| --- | --- |
| Test-case files, versions (git history), config, saved queries, dynamic suites | TM repo |
| `SOURCE_KEY` + ID allocation (`<SOURCE_KEY>-<number>`) | TM repo |
| **Execution task Issues** ("tasks for specific repositories for testing") | **target/app repo** (default) — gets the target repo's native issue number; aggregated to the testing team via an **org Project** |
| Parent run-Issue + run report | TM repo |
| Automated test CI + result artifacts | target/app repo |
| Correlation + coverage + dashboards/reports | TM repo |
| Reusable functions, templates, org-default fields | org `.github` repo |
| Run/quality boards | org Project |

> **Why execution Issues default to the target repo:** it matches your framing ("tasks for
> specific repositories for testing"), gives each task the target's native issue number
> (`app-web#318`) next to the code it exercises, and lets dev teams see test status in context. The
> **test-case ID stays source-based** (`LOGIN-0042`) and appears in the Issue title/body — identity
> from the TM repo, execution number from the target. See
> [ID scheme](01-test-case-management.md#identifier-scheme--source_key-number-decided).
>
> **Alternative (centralized QA):** if you'd rather not create Issues in dev repos, point
> `create-run` at a dedicated `tm-<product>-runs` (or the TM repo itself) and record the target as
> a Project field/label. Trade native target numbering + dev visibility for a cleaner separation.
> One toggle in `create-run`; everything else is unchanged.

## Cross-repo flows (the only things that cross a boundary)

Because cases (TM repo) and execution/CI (target repos) are separate, two flows cross repos:

1. **Run creation (write):** `create-run` runs in the TM repo, reads `targets[]`, and **creates
   Issues in the target repos**, then adds them to an org Project.
2. **Automated results (read-back):** the target repo's CI produces results; they are routed back
   to the TM repo for correlation. Recommended:
   `parse-automated-results` runs in the **target** repo (it has the artifacts), emits the job
   summary there, and **`repository_dispatch`es** the normalized results to the **TM** repo;
   `correlate-results` + `automation-coverage` + `generate-report` run in the **TM** repo (it has
   `automation_test_id` and is where reports live). See
   [03 — Automated Results](03-automated-test-results.md#cross-repo-flow-no-colocation).

### Auth for cross-repo work
Cross-repo writes (Issues into target repos) and dispatches (results into the TM repo) exceed the
default per-repo `GITHUB_TOKEN`. Use a **GitHub App installed org-wide** (or an org fine-grained
PAT) with: `issues:write` + `projects:write` on target repos, `contents:write` +
`repository_dispatch` on TM repos. Store as an org secret; this is the git-native replacement for
`product_api_keys` / Clerk service auth.

## Migration note

A OneTest `product` splits into **(TM repo = test assets + scope)** and **(target repo(s) = system
under test)** that were implicitly the same entity before. The `automation_test_id` ⇄ `code_ref`
correlation is exactly what re-joins them across the new repo boundary.
