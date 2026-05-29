# Authoring test cases

A test case in OneTest TMS is a **Markdown file with YAML front-matter** stored under `tests/` in
your TM repo. The front-matter carries the structured fields (priority, tags, automation links);
the body carries preconditions, steps, and pass/fail criteria. Because cases are files in git, you
get versioning, history, and diff for free, and **a pull request is the approval gate**.

You author cases either by talking to an AI agent (Claude Code / Copilot / VS Code) holding the
`onetest-tms` MCP, by writing the file yourself, or by importing a spreadsheet. Every path ends the
same way: a PR to the TM repo. For the complete field list, see the
[test case format reference](../reference/test-case-format.md). For runs and results, see
[Running test runs](running-test-runs.md).

## Where cases live

```
tests/<suite>/<sub-suite>/<ID>_<slug>.md
e.g. tests/authentication/login/TMS-0001_valid-login.md
```

- The folder tree **is** the suite structure — directories under `tests/` are suites.
- The filename is `<ID>_<slug>.md`, where the ID matches the `id` in front-matter.
- IDs are `<SOURCE_KEY>-NNNN` (the `source_key` from [`.onetest/config.yml`](../reference/configuration.md),
  e.g. `SHOP`, `TMS`). They are **auto-assigned by the `allocate-id` function** — never hand-set,
  never reused.

## The file/PR workflow

Every change to a case — new, edit, move, delete — lands as a pull request:

1. A branch is created and the file is added or changed.
2. The `validate-test-case` check runs on the PR, rejecting front-matter values outside the
   allow-lists in [`.onetest/fields.yml`](../reference/configuration.md).
3. `allocate-id` stamps the next `<SOURCE_KEY>-NNNN` on a new case.
4. A reviewer approves (`CODEOWNERS` routes review by folder). **Approve = approved version;
   Request changes = rejected.**
5. Merge to `main`. The merged commit is the approved version; `build_index` refreshes the search
   index.

Branch protection on `main` enforces the gate — a merged change is an approved version. Every later
edit is another commit, so a case's full version history is its git history.

## Three ways to create a case

### 1. AI generation

Describe the case to your agent in plain language; it writes the file and opens the PR.

```
"Create a test case for adding an item to the cart on app-web,
 priority high, tagged smoke and regression."
```

The agent produces a complete file under the right suite folder and opens a PR. You review the diff
instead of filling in a form. Refine by replying in the conversation or commenting on the PR.

### 2. By hand

Write the file on a branch and open a PR yourself. Put it under the correct suite folder, fill in
the front-matter, and leave the `id` for `allocate-id` to assign (or omit it). The
`validate-test-case` check tells you if any field value is off the allow-list.

### 3. Import

Hand your agent (or a CI dispatch) an XLSX/CSV/ZIP export from another tool. It converts each row
into a case file and opens one PR for the batch. The ZIP format matches OneTest's per-case Markdown
plus `manifest.json`.

## Organizing into suites

- **Create a suite** by creating a folder under `tests/`. Nest folders for sub-suites.
- **Move a case** to another suite with a `git mv` (your agent does this and opens a PR) — the ID
  never changes.
- **Describe a suite** with an optional `_suite.yml` in the folder.

### Dynamic suites (OQL)

A folder can be a **dynamic suite**: its membership is computed from a query instead of being the
files physically inside it. Add a `_suite.yml` with `dynamic: true` and an `oql:` query:

```yaml
# tests/regression/_suite.yml
dynamic: true
oql: "tags CONTAINS 'regression' AND status = 'ready'"
```

Membership is materialized on demand — for example when you build a run scoped to that suite. See
[Searching with OQL](searching-with-oql.md) for the query language.

## Tags

Tags are a front-matter list:

```yaml
tags: [smoke, login, regression]
```

Use them to slice cases for runs and searches (`tags CONTAINS "smoke"`). When a case is executed in
a run, its tags are mirrored onto the execution issue as labels, so you can filter the board by tag
too. Unknown tags are accepted; optional tag metadata (color/category) lives in `.onetest/tags.yml`.

## The `{{base_url}}` convention

Keep cases environment-agnostic. Write URLs with the `{{base_url}}` placeholder rather than a
hard-coded host:

```markdown
1. Navigate to `{{base_url}}/login`  →  Login page loads.
```

At run time the placeholder is substituted with the chosen environment's URL (from the
`environments:` list in [`.onetest/config.yml`](../reference/configuration.md)), so the same case
runs against `staging` or `production` unchanged.

## Editing a case = a new version

To change a case, your agent (or you) edits the file on a branch and opens a new PR. Each merged
edit is a new git commit — the case's version history. To see how a case changed, use the PR's
**Files changed** diff or `git log` on the file. There is no separate "versions" concept: git
history *is* the version history, and the executed version of a case is pinned by the commit SHA
recorded on its execution issue.

## Example case

```markdown
---
id: SHOP-0001
title: Add a product to the cart from the product page
priority: high
type: functional
module: cart
status: ready
execution_type: automated
size: M
targets: [onetest-ai/app-web]
automation_test_id:
  - tests/e2e/cart.spec.ts:Cart.addItem
requirements: [REQ-014]
tags: [smoke, cart, regression]
---

# SHOP-0001: Add a product to the cart from the product page

**Module:** Cart · **Priority:** High · **Type:** Functional / Smoke

## Preconditions
- App is accessible at `{{base_url}}`
- At least one product is in stock

## Steps

| # | Action                                   | Expected Result                       |
|---|------------------------------------------|---------------------------------------|
| 1 | Navigate to `{{base_url}}/products/42`   | Product page loads with "Add to cart" |
| 2 | Click "Add to cart"                      | Cart badge increments to 1            |
| 3 | Open the cart drawer                     | The product is listed with quantity 1 |

## Expected Final State
The cart contains exactly one of the selected product. No error messages.
```

## See also

- [Test case format reference](../reference/test-case-format.md) — every front-matter field.
- [Searching with OQL](searching-with-oql.md) — find and group cases.
- [Automated results](automated-results.md) — link a case to its CI test via `automation_test_id`.
- [Concepts](../getting-started/concepts.md) — cases, suites, runs, and the board.
- [Configuration](../reference/configuration.md) — `source_key`, field allow-lists, environments.
