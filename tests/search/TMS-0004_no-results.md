---
id: TMS-0004
title: Search with no matches shows an empty-state message
priority: medium
type: functional
module: search
status: ready
execution_type: manual
size: S
targets: [onetest-ai/tms]
requirements: [REQ-011]
tags: [search, negative]
---

# TMS-0004: Search With No Matches

**Module:** Search · **Priority:** Medium · **Type:** Functional

## Preconditions
- App is accessible at `{{base_url}}`

## Steps

| # | Action                                          | Expected Result                                   |
|---|-------------------------------------------------|---------------------------------------------------|
| 1 | Navigate to `{{base_url}}/`                     | Home page loads; search box visible               |
| 2 | Search for `zzzznotaproduct`                    | Results page loads                                |
| 3 | Inspect the results area                        | "No results found" empty-state message is shown   |

## Expected Final State
Results page shows the "No results found" empty-state; no product cards are listed.
