# GitHub-Native: Test Case Management

Maps [Functionality 01](../functionalities/01-test-case-management.md) and
[Data model 02](../data-model/02-test-case-management.md) onto GitHub.

**Principle:** a test case is a **file in a repo**; everything OneTest layered on top
(versioning, history, diff, approval) becomes **git + Pull Requests**.

## Repository layout (per product)

```
<product-repo>/
├── .onetest/
│   ├── config.yml            # product metadata (was products row): name, type, prefix
│   ├── fields.yml            # status/execution_type/test_category allow-lists (was *_field_values)
│   ├── custom-fields.yml     # custom_field_definitions
│   └── queries/              # saved queries + dynamic-suite OQL (one file each)
├── tests/                    # the folder tree == test_folders
│   ├── authentication/
│   │   ├── login/
│   │   │   ├── TC-0001-valid-login.md
│   │   │   └── TC-0002-invalid-password.md
│   │   └── _suite.yml        # optional folder metadata (description, dynamic OQL)
│   └── checkout/...
├── assets/                   # attachments (Git LFS): screenshots, test data
├── reports/                  # generated reports (see Reporting)
└── .github/workflows/        # the "functions"
```

Org-level defaults (shared `fields.yml`, reusable workflows, issue/PR templates) live in the
org's special **`.github` repository**.

## Test case = Markdown + YAML front-matter

One file per test case. The front-matter carries the structured fields; the body carries steps.

```markdown
---
id: LOGIN-0042                    # <SOURCE_KEY>-<number> — identity from the OWNING repo (see ID scheme)
title: Verify valid login redirects to dashboard
status: ready                     # config-driven (fields.yml)
execution_type: automated         # config-driven
test_category: functional         # config-driven
priority: p1
component: authentication
owner: alice                      # GitHub login (was clerk_user_id)
targets: [app-web, app-api]       # routing metadata: project(s)/repo(s) under test (NOT identity)
tags: [smoke, login, regression]
requirements: [US-123]            # traceability
dependencies: [LOGIN-0005]
known_issues: [BUG-42]
automation_test_id:               # the CI correlation key (one per line)
  - tests/e2e/login.spec.ts:Login.valid
parameters: { }
custom_fields: { jira_ticket: PROJ-99 }
# moved_from: AUTH-0042           # optional alias if the case ever moves source repos
---

## Preconditions
- User account exists and is active.

## Steps
1. **Action:** Navigate to `/login`.
   **Expected:** Login form is visible.
2. **Action:** Enter valid credentials and submit.
   **Expected:** Redirected to `/dashboard`.

## Pass/Fail criteria
Dashboard loads within 2s and shows the user's name.
```

> **Front-matter schema is reconciled with the shipping
> [`web-qa` bundle](https://github.com/arozumenko/sdlc-skills/tree/main/bundles/web-qa).** web-qa
> already uses `priority: critical|high|medium|low`, `type`, `module`, `size: S|M|L`. The merged
> schema (web-qa fields + the OneTest fields coverage needs, e.g. `execution_type` /
> `automation_test_id`) and the priority-scheme decision are in
> [05 — Test Run UX › Artifact reconciliation](05-test-run-ux.md#artifact-reconciliation-web-qa--github-native).

| OneTest field | Lands as |
| --- | --- |
| `test_cases.identifier` | front-matter `id` = `<SOURCE_KEY>-<number>` + filename prefix |
| `priority` | front-matter `priority: critical/high/medium/low` (web-qa scheme) |
| `test_category` | front-matter `type` (web-qa) |
| `component` | front-matter `module` (web-qa) |
| _(new)_ agent-execution cost | front-matter `size: S/M/L` (web-qa `test-sizer`) |
| _(new)_ system(s) under test | front-matter `targets[]` — routing metadata, not identity |
| `test_case_versions.title/description/steps/...` | front-matter + body |
| `status / execution_type / test_category / priority / component` | front-matter |
| `owner` | front-matter (GitHub login) |
| `tags` (m:n `test_tags`) | front-matter `tags[]` |
| `requirements / dependencies / known_issues` | front-matter arrays |
| `automation_test_id` | front-matter `automation_test_id[]` |
| `custom_fields` | front-matter `custom_fields{}` |
| `parameter_sets` | front-matter `parameters` or a sibling `TC-0001.params.yml` |

## Versioning, history, diff, approval — all native git

| OneTest | GitHub-native |
| --- | --- |
| `test_case_versions` (immutable, numbered) | git commits on the file; history is immutable |
| `version_number` / `parent_version_id` | commit sequence / parent commit |
| `change_reason` / `change_category` | commit message (Conventional Commits: `feat/fix/refactor/chore`) |
| `author` | git commit author (GitHub identity) |
| version **diff** (`/diff?v1=&v2=`) | `git diff` / PR "Files changed" |
| `approval_status` (`pending/approved/rejected`) | PR review: open = pending, **Approve** = approved, **Request changes** = rejected |
| `test_audit_events` (activity timeline) | `git log` + PR timeline + Issues timeline |
| "every content change creates a new version" | every edit is a commit (ideally via PR) |

**Branch protection** on `main` enforces the approval gate: a merged change == an approved
version. `CODEOWNERS` routes reviews by folder (feature-team ownership).

## Folders, tags, custom fields, queries

- **Folders/suites** → directories under `tests/`. Move = `git mv`. Folder metadata (description)
  → optional `_suite.yml`. Recursive counts → computed by a function or shown in the README.
- **Dynamic suites (OQL)** → `_suite.yml` with `dynamic: true, oql: "tags CONTAINS 'smoke'"`;
  membership materialized on demand by [`oql-search`](functions.md#oql-search) (e.g. when building a
  run), not stored.
- **Tags** → front-matter `tags[]`. When a case is *executed*, the tag is mirrored onto the
  execution **Issue** as a label. Tag metadata (color/category) optional in `.onetest/tags.yml`.
- **Custom fields** → defined in `.onetest/custom-fields.yml`, values in front-matter
  `custom_fields`. Validated by CI.
- **Field allow-lists** (`status/execution_type/test_category`) → `.onetest/fields.yml` (product)
  layered over org defaults in `.github`. The [`validate-test-case`](functions.md#validate-test-case)
  check rejects values outside the allow-list — the git-native replacement for the HTTP 422.
- **Saved queries** → `.onetest/queries/*.oql`; also expressible as **Project saved views**.

## Identifier scheme — `<SOURCE_KEY>-<number>` (decided)

**The ID is `project + number`, where `project` is the SOURCE project — the repo that owns
(authors/stores) the test case — not the target project it tests.** Identity must be stable and
globally resolvable; a case is authored in exactly one place but may test many, and retargeting
must never rename it.

- **`SOURCE_KEY`** — a short, **immutable** key for the owning test-management project, set once in
  `.onetest/config.yml` (e.g. `LOGIN`, `CHECKOUT`). Decoupled from the repo *name* so a repo
  rename never breaks IDs. Unique per source repo ⇒ `<SOURCE_KEY>-<number>` is **globally unique
  across the org**, so org-level run boards aggregating Issues from many repos never collide.
- **`<number>`** — zero-padded, allocated `max+1` **within the source repo** by
  [`allocate-id`](functions.md#allocate-id) (Action with `concurrency: id-allocation` to serialize,
  replacing the old Postgres advisory lock). Local allocation = no cross-repo coordination.
- **Target is metadata, not identity** — `targets[]` in front-matter lists the project(s)/repo(s)
  under test. [`create-run`](02-test-execution-management.md#creating-a-run--the-create-run-function)
  reads it to route execution Issues into the right repos; each execution Issue then gets the
  **target repo's native issue number** for free (e.g. `app-web#318`). So you get two numbers:
  source-based **identity** (`LOGIN-0042`) + target-based **execution number** (`app-web#318`).

### Why source beats target
| Criterion | Source-based (chosen) | Target-based (rejected) |
| --- | --- | --- |
| Stability under retargeting | ID never changes | ID changes when SUT changes → breaks refs |
| One author, many targets | 1:1 with the case | 1:many — no single key |
| Allocation | local `max+1`, race-free | needs cross-repo coordination |
| Uniqueness / aggregation | globally unique via prefix | collides or needs a registry |
| Migration from OneTest | matches `identifier` (owning product) | diverges |

- **Edge case:** moving a case between source repos changes its ID (effectively delete+recreate) —
  keep a `moved_from:` alias in front-matter for traceability.
- **Note:** if test cases are *co-located* in the app repo (source == target), the distinction
  collapses and either reading yields the same key.
- **Alternatives** (no allocation lock): ULID IDs (`LOGIN-01H...`) or path-as-identity — trade
  human-friendliness for simplicity. Default keeps `<SOURCE_KEY>-<number>`.

## Authoring workflows

1. **Manual** — create the file on a branch → open PR → `validate-test-case` runs →
   `allocate-id` stamps the ID → review/approve → merge. (A small web form or `gh` script can
   scaffold the file.)
2. **AI generation** — [`ai-generate-test`](functions.md#ai-generate-test): describe the test
   (issue comment, dispatch, or Claude Code) → Claude writes the file(s) → opens a PR. The
   interactive-form UX becomes "review the PR diff."
3. **Import** — [`import-test-cases`](functions.md#import-test-cases): upload XLSX/CSV/ZIP as a
   workflow input → converts to files → opens a PR. (Reuse the existing Markdown/TOON serializers
   from `test-management/formats/`.)

## Export

[`export-test-cases`](functions.md#export-test-cases) renders selected/filtered/all files to XLSX
or ZIP and uploads as an **Actions artifact** (or attaches to a Release). The ZIP format already
matches OneTest's per-case Markdown + `manifest.json`.

## What disappears

- `product_id` scoping → the repo boundary.
- The versions table, audit table, and approval columns → git + PRs.
- ID advisory lock → Actions `concurrency`.
- 422 field validation → a required CI check.

See [Execution](02-test-execution-management.md) for how these files become runnable tasks.
