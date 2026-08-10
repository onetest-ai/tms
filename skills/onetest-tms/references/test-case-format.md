# Test-case format

A test case is a Markdown file with YAML front-matter, committed to a test-management repo and added
or changed via a pull request. Path: `tests/<suite>/<ID>_<slug>.md` (folders under `tests/` are
suites). Authoring is via git/PR — there is no MCP tool that writes cases.

The TM repo also opens as an **Obsidian vault**: `build-index` generates hub notes
(`_meta/requirements/*.md` and `_index.md` MOCs) so the graph connects cases to their requirements
and suites. See [Obsidian vault](../../../docs/reference/obsidian-vault.md).

## Front-matter fields

| Field | Required | Allowed values / type | Notes |
| --- | --- | --- | --- |
| `id` | yes | `<SOURCE_KEY>-NNNN` (e.g. `SHOP-0001`) | Auto-assigned; never hand-set or reused. |
| `aliases` | yes | `[<ID>]` | Obsidian alias, set to the case `id`, so generated hub notes link the case as `[[<ID>]]`. |
| `title` | yes | string | Short, verb-first ("Add a product to the cart"). |
| `priority` | yes | `critical` \| `high` \| `medium` \| `low` | |
| `type` | yes | `functional` \| `regression` \| `smoke` \| `integration` \| `exploratory` | Allowed set defined in `.onetest/fields.yml`. |
| `module` | yes | string | Feature area (e.g. `cart`, `authentication`). |
| `status` | yes | `draft` \| `ready` \| `deprecated` | |
| `execution_type` | yes | `manual` \| `automated` | Drives automation coverage. |
| `size` | no | `S` \| `M` \| `L` | Agent-execution cost. |
| `targets` | yes | list of `OWNER/REPO` | Repo(s) under test — where execution issues are created. |
| `automation_test_id` | for automated | list of `file:Class.method` | The CI correlation key (matches a result `code_ref`). One per line. |
| `requirements` | no | list of plain refs | Traceability (e.g. `REQ-010` or `OWNER/REPO#N`). **Plain refs — never wikilink them**; the requirement↔case graph edge is a generated proxy note that links back. |
| `automation_url` / `doc_url` | no | list of URLs | Optional external links (automation source, design docs). Clickable in Obsidian's Properties panel; not graph nodes. |
| `tags` | no | list of strings | Free-form labels used for search and run scoping. Nested Obsidian tags via `/` work (e.g. `feat/cart`). |
| `custom_fields` | no | map | Per-repo custom fields (see `.onetest/custom-fields.yml`). |

> Allowed values for `status`, `execution_type`, `priority`, `size`, and `type` are defined in the
> repo's `.onetest/fields.yml` and enforced by a CI check on every PR. Values outside the list are
> rejected.

> **Do not** create or hand-edit `_index.md` or `_meta/requirements/*` — `build-index` generates and
> refreshes those hub notes (they are `id`-less, so the case tooling ignores them).

## Body sections

In order:

1. `## Preconditions` — bullet list of state that must be true before the test.
2. `## Test Data` — optional table of literal values used in the steps.
3. `## Steps` — a table `| # | Action | Expected Result |`, one row per step.
4. `## Expected Final State` — one paragraph describing the end state.
5. `## Teardown` — optional cleanup steps.

## The `{{base_url}}` rule

Write URLs as `{{base_url}}/path`. The placeholder is substituted with the environment's URL when a
run is created, so cases stay environment-agnostic.

## Complete example

```markdown
---
id: SHOP-0001
title: Add a product to the cart from the product page
aliases: [SHOP-0001]
priority: critical
type: functional
module: cart
status: ready
execution_type: manual
size: M
targets: [onetest-ai/tm-shop]
requirements: [SHOP-REQ-001]
tags: [smoke, cart, happy-path]
---

# SHOP-0001: Add a Product to the Cart

## Preconditions
- App is accessible at `{{base_url}}`
- Product "Blue Mug" (SKU `MUG-001`) is in stock

## Test Data

| Field   | Value    |
|---------|----------|
| Product | Blue Mug |
| SKU     | MUG-001  |

## Steps

| # | Action                                      | Expected Result                    |
|---|---------------------------------------------|------------------------------------|
| 1 | Navigate to `{{base_url}}/products/MUG-001` | Product page for "Blue Mug" loads  |
| 2 | Click "Add to cart"                         | Cart badge increments to 1         |
| 3 | Open the cart                               | "Blue Mug" appears with quantity 1 |

## Expected Final State
The cart contains 1 × "Blue Mug"; the cart total reflects one unit.
```

For automated cases, add `automation_test_id` so CI results link back to the case:
```yaml
execution_type: automated
automation_test_id:
  - tests/e2e/cart.spec.ts:Cart.add
```
