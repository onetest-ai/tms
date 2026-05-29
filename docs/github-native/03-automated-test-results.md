# GitHub-Native: Automated Test Results

Maps [Functionality 03](../functionalities/03-automated-test-results-management.md) and
[Data model 04](../data-model/04-automated-results.md) onto GitHub.

**Principle (your model):** *automated tests are just reports produced in GitHub Actions, analyzed
by functions to create summaries.* The entire `receiver` service (ReportPortal API, launches,
items, logs, ingestion jobs, API keys) collapses into **CI artifacts + a parsing function**.

## Entity mapping

| OneTest (`receiver`) | GitHub-native |
| --- | --- |
| `launches` (one automated run) | a **workflow run** (the CI job that ran the tests) |
| `launches.statistics` | computed by the parser; written to the run's results file + job summary |
| `receiver_test_items` (suite/test/step tree) | parsed entries from the JUnit/results artifact |
| `receiver_test_item_logs` + attachments | **Actions logs** + uploaded **artifacts** (screenshots, traces) |
| `receiver_ingestion_jobs` | the parsing workflow run itself |
| `product_api_keys` (RP auth, scopes) | `GITHUB_TOKEN` / OIDC / fine-grained PAT; scopes = token perms |
| ReportPortal v2 endpoints | **artifact upload** + parser (optional RP-compat shim, see below) |
| `code_ref` (item) | parsed test node id (kept verbatim) |
| `test_case_id` / `mapping_confidence` / `mapped_by` | a correlation record (see [Reporting](04-correlations-and-reporting.md)) |
| launch → release/sprint/build/environment auto-link | derived from the workflow context (ref/tag/Release/Environment) |

## The flow

```
push / PR / schedule
   └─> test workflow (pytest, playwright, junit, ...) runs the suite
         └─> produces results.xml / report.json  ──upload-artifact──┐
                                                                      ▼
        parse-automated-results (function, on workflow_run completed)
            ├─ parse JUnit/JSON → normalized result entries (code_ref, status, duration, logs)
            ├─ write reports/automated/<run>.json + a Markdown summary
            ├─ emit $GITHUB_STEP_SUMMARY (rendered on the run page)
            ├─ (optional) comment pass/fail summary on the PR
            └─ trigger correlate-results
```

### 1. Run the tests (native CI)
Each product repo (or the app repo) has normal test workflows. They write a machine-readable
report and upload it:

```yaml
- run: pytest --junitxml=results.xml
  continue-on-error: true
- uses: actions/upload-artifact@v4
  if: always()
  with: { name: junit, path: results.xml }
```

### 2. Parse into a summary (the "function")
[`parse-automated-results`](functions.md#parse-automated-results) triggers on `workflow_run:
completed` (or is called as a reusable workflow at the end of the test job). It:
- Downloads the results artifact, parses JUnit/JSON (reuse the existing `receiver` JUnit parser
  logic).
- Builds the launch-equivalent record: totals/passed/failed/skipped, per-test `code_ref`, status,
  duration, failure message/stacktrace.
- Writes `reports/automated/<workflow-run-id>.json` (the durable "launch") and a Markdown summary.
- Writes the **job summary** via `$GITHUB_STEP_SUMMARY` (the inline "report in Actions" you
  described) and optionally **comments on the PR**.
- Hands off to [`correlate-results`](functions.md#correlate-results) for test-case mapping.

### Cross-repo flow (no co-location)

Because test cases live in the **TM repo** and CI runs in the **target/app repo**
([topology](00-repo-topology.md)), results must cross the boundary:

```
target/app repo                                  TM repo
─────────────                                    ───────
test workflow → results.xml
   └─ parse-automated-results (here: has artifacts)
        ├─ $GITHUB_STEP_SUMMARY (report in Actions)
        └─ repository_dispatch ─────────────────▶ correlate-results (here: has automation_test_id)
                                                      ├─ reports/correlation.json
                                                      ├─ automation-coverage
                                                      └─ generate-report
```

- **Parse in the target repo** (it owns the artifacts) → emit the job summary there.
- **Dispatch normalized results to the TM repo** via `repository_dispatch` (needs the GitHub App /
  org token from [topology auth](00-repo-topology.md#auth-for-cross-repo-work)).
- **Correlate, compute coverage, and report in the TM repo** — it has the `automation_test_id`
  refs and is where reports live. This keeps the QA domain authoritative for correlation/coverage.

### 3. Context auto-link (native)
The OneTest receiver guessed release/sprint/build/environment from the membership service. Here
it's free from CI context: the **git ref/tag** → build/release, the deployed **GitHub
Environment** → environment, the triggering **Release** → release. No network calls, no swallowed
errors.

## Replacing the ReportPortal API

Two strategies:

1. **Native (default):** drop the always-on RP endpoint; CI uploads artifacts and the parser runs
   in Actions. Simpler, fully git-native, but requires each pipeline to upload an artifact rather
   than POST live to an API.
2. **RP-compat shim (optional):** if customers must keep posting to a ReportPortal v2 URL with no
   CI changes, provide a thin endpoint (a small serverless function or a webhook) that converts RP
   calls into a `repository_dispatch` carrying the payload, which `parse-automated-results` then
   ingests. This preserves the external contract documented in
   [03 — Automated Results](../functionalities/03-automated-test-results-management.md) without a
   full backend.

## Viewing results

| OneTest | GitHub-native |
| --- | --- |
| Automated runs in Test Runs (All/Automated/Manual) | a **Project view** filtered by source, fed by result files / status-check Issues; or the Actions runs list |
| Pass/fail/skip breakdown with % | the job summary + the generated report |
| Drill-down item tree | the report (Markdown/HTML) + Actions logs |
| Logs & screenshots | Actions logs + artifacts |
| Per-test/total duration | parsed into the report |

## Metering

The `onetest-otel` per-call coin metering disappears (it billed API usage). GitHub already meters
**Actions minutes**; if usage accounting is still wanted, a function can tally runs into a report.

## What disappears

- The `receiver` Postgres service and all five tables → CI artifacts + `reports/automated/*` files.
- `product_api_keys` → GitHub tokens/OIDC.
- Ingestion jobs → the parsing workflow.
- Live RP ingestion → artifact-driven parsing (or an optional shim).

Correlation of these results back to test cases is covered in
[04 — Correlations & Reporting](04-correlations-and-reporting.md).
