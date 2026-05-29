# 3 — Automated Test Results Management

**What it is:** ingesting automated test results from any CI/CD pipeline so they appear alongside
manual and AI-driven runs in one unified dashboard. Implemented by the `receiver` service
(ReportPortal-v2-compatible API + JUnit import).

→ Data model: [data-model/04-automated-results.md](../data-model/04-automated-results.md).

## Core concepts

- A **launch** = one automated run (the ReportPortal term). It contains a **tree of test items**
  (`SUITE → TEST → STEP`, plus setup/teardown items), each with **logs** and attachments.
- Each test item carries a **`code_ref`** (fully-qualified test name, e.g.
  `test_login.py:TestLogin.test_valid_login`) — the key that links it to an authored test case.
- Launches are tenant-scoped by `product_id` and optionally tied to release/sprint/build/
  environment (auto-resolved).
- Ingestion is authenticated with a **product API key** (`product_api_keys`, prefixed
  `octo_…`/legacy `rp_…`), scoped (e.g. `autotests:write`).

## Three ways to report results

### Method 1 — ReportPortal agents (drop-in, no code changes)
Point any existing ReportPortal v2 agent at OneTest:
```
RP_ENDPOINT = https://tms.onetest.ai/api/receiver
RP_PROJECT  = <product-uuid>
RP_API_KEY  = <api-key>
```
Supported agents: pytest (`pytest-reportportal`), JUnit 5 (`agent-java-junit5`), TestNG
(`agent-java-testng`), Cypress (`agent-js-cypress`), Playwright (`agent-js-playwright`), Robot
Framework. Preserves the full **Launch → Suite → Test → Step → Log** hierarchy, including
`code_ref`, status, duration, logs, stack traces, and screenshots.

### Method 2 — JUnit XML import
For frameworks without an RP agent:
```
POST https://tms.onetest.ai/api/v1/products/{product_uuid}/import/junit
  Authorization: Bearer {api_key}   -F file=@results.xml   (10 MB limit)
```
Creates a single launch with cases as **flat items** (no suite hierarchy). Parser maps
`failure`/`error` → `failed`, `skipped` → `skipped`, else `passed`; captures messages,
stacktrace, system-out/err; sets `code_ref = "{classname}.{name}"`. Tracked as a
`receiver_ingestion_jobs` job (async worker, progress every 50 items). `nunit_xml` /
`realtime_batch` job types exist as enums but only JUnit has a processor.

### Method 3 — MCP / agent
The `/qa-onetest run` agent path records full runs through MCP (this is really execution-side —
see [Execution Management](02-test-execution-management.md)).

## The ReportPortal-compatible ingestion API

Prefix `/api/v2/{product_uuid}` (the product UUID is the "project"), product-API-key auth:

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/launch` | POST | Start a launch (`name, uuid?, mode, attributes[], startTime`, optional `release_id/sprint_id/build_id/environment_id/build_version`) → `{id, number}` |
| `/launch/{uuid}/finish` | PUT | Finish: compute stats, derive status, schedule a (delayed) metering event |
| `/item` | POST | Start a root item (`name, type, codeRef, parameters[], attributes[], launchUuid, startTime`) |
| `/item/{parent_uuid}` | POST | Start a child item (nested) |
| `/item/{uuid}` | PUT | Finish item (status, `issue.comment` → `failure_message`, computes `duration_ms`) |
| `/log` and `/log/entry` | POST | Add log(s); supports JSON and multipart batch (pytest-reportportal style); base64/binary attachments uploaded to `artifacts`, matched to logs by filename |

Timestamps accept epoch-ms (int/float/string) or ISO-8601. Native (session-auth) endpoints under
`/products/{product_id}` let the UI list/read launches, items, and logs; `PUT
/launches/{id}/finish` force-completes a stuck launch; `DELETE /launches/{id}` cascades + deletes
artifacts; `GET /logs/{id}/attachment/url` returns a presigned download URL.

## Linking launches to context (auto-link)

On launch start, `receiver/services/auto_link.py` resolves run context: explicit IDs are used if
provided, else it best-effort calls `membership` for the **active release → active sprint →
build (find-or-create by `build_version`) → default environment**. All failures are swallowed —
a launch never fails because auto-link failed.

## Linking items to authored test cases

- Items arrive **unmapped** (`test_case_id IS NULL`); the agent-sent `testCaseId`/`code_ref` are
  stored, with `code_ref` indexed and unmapped items queryable.
- Linking writes back `test_case_id`, `mapped_by` (`auto`/`manual`/`ai`), `mapped_at`,
  `mapping_confidence` via `link_to_test_case`.
- **The actual matching engine lives in `test-management`**, not `receiver` — it normalizes
  `code_ref` ⇄ `automation_test_id` (`file:Class.method`). See
  [Correlations & Reporting](04-correlations-and-reporting.md).

## Viewing automated results

Automated runs appear in **Test Runs**, filterable by source (**All / Automated / Manual**). Each
shows pass/fail/skip breakdown with %, the drill-down item tree (suites/tests/steps), logs &
screenshots, and per-test/total duration. The reporting layer normalizes launch and item statuses
into the manual-run vocabulary so both show side-by-side.

## Cost / metering

Each ingestion API call costs **1 coin** from the weekly budget (browser UI is free). On launch
finish and JUnit completion, the receiver emits `onetest-otel` metering spans
(`test_ingestion` / `junit_import`); stated intent is 1 coin per run + 1 coin per 100 tests.

## Re-platforming notes

- A launch is an automated-run artifact; the item tree + logs map to a nested result document
  with attachment pointers.
- Keep `code_ref` as the durable automation identity; correlation to cases stays computed.
- ReportPortal v2 compatibility is a real external contract — any git-native ingest must keep
  accepting it (or provide a shim) to avoid breaking customers' CI configs.
- Statistics are denormalized on the launch — recompute on write in any new model.
