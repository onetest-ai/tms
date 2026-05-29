---
id: TMS-0003
title: Basic product search returns matching results
priority: high
type: functional
module: search
status: ready
execution_type: automated
size: M
targets: [onetest-ai/tms]
automation_test_id:
  - tests/e2e/search.spec.ts:Search.basic
requirements: [REQ-010]
tags: [smoke, search, happy-path]
---

# TMS-0003: Basic Product Search

**Module:** Search · **Priority:** High · **Type:** Functional / Smoke

## Preconditions
- App is accessible at `{{base_url}}`
- Catalog contains a product named "Blue Mug"

## Steps

| # | Action                                          | Expected Result                              |
|---|-------------------------------------------------|----------------------------------------------|
| 1 | Navigate to `{{base_url}}/`                     | Home page loads; search box visible          |
| 2 | Type `Blue Mug` into the search box             | Query text appears in the box                |
| 3 | Press Enter                                     | Results page lists "Blue Mug"                |

## Expected Final State
Results page shows at least one product matching "Blue Mug".
