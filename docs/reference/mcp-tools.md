# MCP tools (`onetest-tms`)

OneTest TMS is operated through the **`onetest-tms` MCP server** (stdio). The agent calls these tools; each maps to a script in the package and reads or writes GitHub Issues, Projects, and repo files. The same operations are available as the `onetest-tms <command>` CLI for CI / autonomous runs.

There are 12 tools, grouped below by purpose.

See also: [Concepts](../getting-started/concepts.md) · [OQL reference](oql.md) · [Test-case format](test-case-format.md) · [Running test runs](../guides/running-test-runs.md) · [Recording results](../guides/recording-results.md).

## The common `repo` parameter

Every tool accepts an optional **`repo`** (`OWNER/NAME`) — the TM repo to operate on. Omit it to use the server's default repo (`OT_REPO_ROOT`, else the package's own repo). Pass the *product* TM repo (e.g. `onetest-ai/tm-shop`), never the template repo. The server checks out the named repo into a workspace and runs the package scripts there, so one server serves any TM repo.

`repo` is omitted from the parameter tables below; it applies to all tools.

---

## Discovery

### `build_index`

Rebuild `index.json` from the `tests/` front-matter. Run it after cases change so search and coverage are current.

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| *(none beyond `repo`)* | | | |

```
build_index({ repo: "onetest-ai/tm-shop" })
```

### `search_test_cases`

Run an [OQL](oql.md) query over the index and return matching file paths (or IDs).

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| `query` | string | yes | OQL query string. |
| `ids` | boolean | no | Return case IDs instead of file paths. |

```
search_test_cases({ query: "tags CONTAINS 'smoke' AND priority IN (critical, high)", ids: true })
```

### `get_test_case`

Return the full Markdown of one case by ID.

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| `id` | string | yes | Case ID, e.g. `TMS-0001`. |

```
get_test_case({ id: "TMS-0001" })
```

---

## Runs

### `create_run`

Create a test run: a run Issue plus one execution Issue per case in the target repos, all added to the org Project board. Provide scope with exactly one of `oql`, `folder`, or `glob`.

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| `name` | string | yes | Human run name. |
| `oql` | string | no | [OQL](oql.md) scope. |
| `folder` | string | no | Folder scope (e.g. `tests/cart`). |
| `glob` | string | no | Glob scope. |
| `env` | string | no | Environment name (from `config.yml` `environments`). |
| `target` | string | no | Override target repo; defaults to each case's `targets`. |
| `assignees` | string | no | Assignee strategy / users. |
| `project` | string | no | Override org Project. |
| `dry_run` | boolean | no | Plan only; write nothing. |

```
create_run({ name: "Cart smoke", folder: "tests/cart", env: "staging" })
```

### `add_to_run`

Add cases to an existing run as new execution Issues and Project items. Provide `oql` or `folder`.

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| `run` | string | yes | Run ID, e.g. `RUN-2026-05-29-001`. |
| `oql` | string | no | [OQL](oql.md) scope. |
| `folder` | string | no | Folder scope. |
| `target` | string | no | Override target repo. |
| `assignees` | string | no | Assignee strategy / users. |
| `dry_run` | boolean | no | Plan only; write nothing. |

```
add_to_run({ run: "RUN-2026-05-29-001", oql: "tags CONTAINS 'regression'" })
```

### `complete_run`

Aggregate a run into `reports/RUN-*.md`, comment the summary on the run Issue, and close it. Refuses if executions are unresolved unless `force`.

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| `run` | string | yes | Run ID. |
| `suite` | string | no | Suite label for the report. |
| `env` | string | no | Environment for the report context. |
| `no_commit` | boolean | no | Build the report but do not commit. |
| `force` | boolean | no | Complete even with unresolved executions. |

```
complete_run({ run: "RUN-2026-05-29-001" })
```

---

## Results

### `record_result`

Record one execution's outcome. Sets the Project **Result** field and labels, comments the details on the execution Issue, and closes it on `PASS`. **`PASS` requires `evidence`.** Do not hand-edit Issue Result/labels — always go through this tool.

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| `execution` | string | yes | Execution ref, e.g. `onetest-ai/app-web#318`. |
| `result` | enum | yes | `PASS`, `FAIL`, `BLOCKED`, or `SKIPPED`. |
| `failure_reason` | string | no | One of `bug_in_app`, `test_data_issue`, `environment_issue`, `test_needs_update`, `blocked_by_other`, `other`. |
| `notes` | string | no | Free-text result notes. |
| `evidence` | string | no | Evidence reference (screenshot/log). Required for `PASS`. |
| `defect` | string | no | Link an existing defect to this execution. |
| `force` | boolean | no | Override guards (e.g. evidence-before-PASS). |

```
record_result({ execution: "onetest-ai/app-web#318", result: "PASS",
                 evidence: "reports/RUN-2026-05-29-001/screenshots/TMS-0001.png" })
```

### `rerun_execution`

Re-run one execution as a new linked execution Issue (Result reset to Not run).

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| `execution` | string | yes | Execution ref to re-run. |
| `reason` | string | no | Why it is being re-run. |

```
rerun_execution({ execution: "onetest-ai/app-web#318", reason: "flaky — staging redeploy" })
```

---

## Defects

### `create_defect`

Open a Defect Issue in a target repo and cross-link it to an execution.

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| `target` | string | yes | Target repo (e.g. `app-web`). |
| `title` | string | yes | Defect title. |
| `severity` | string | no | Severity; defaults from case priority. |
| `from_execution` | string | no | Execution ref the defect was found in. |
| `body` | string | no | Defect body (repro, expected/actual). |
| `evidence` | string | no | Evidence reference. |

```
create_defect({ target: "app-web", title: "500 on valid login (staging)",
                severity: "High", from_execution: "onetest-ai/app-web#318" })
```

---

## Automated results

### `ingest_results`

Parse a JUnit XML report into `reports/automated/*.json`.

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| `file` | string | yes | Path to the JUnit XML report. |

```
ingest_results({ file: "results.xml" })
```

### `correlate_results`

Correlate automated results with cases by `code_ref ⇄ automation_test_id`, writing `reports/correlation.json`.

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| `automated` | string | yes | Path to the ingested automated-results JSON. |

```
correlate_results({ automated: "reports/automated/12345.json" })
```

---

## Coverage

### `automation_coverage`

Compute automation coverage (marked-automated vs linked-to-CI) and write `reports/coverage.md`.

| Parameter | Type | Required | Meaning |
| --- | --- | --- | --- |
| *(none beyond `repo`)* | | | |

```
automation_coverage({ repo: "onetest-ai/tm-shop" })
```
