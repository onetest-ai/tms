# GitHub-Native: Test Execution Management

Maps [Functionality 02](../functionalities/02-test-execution-management.md) and
[Data model 03](../data-model/03-test-execution.md) onto GitHub.

**Principle (your model):** *creating a test run = a function that creates tasks for specific
repositories and surfaces them through GitHub Projects to the testing team.*

- **Test run** → a **GitHub Project (v2)** (the board) + a parent tracking **Issue**.
- **Test execution** → an **Issue** (the task), one per test case in scope, added to the Project.
- **Execution status / step results / evidence** → Project fields + Issue body + attachments.

## Entity mapping

| OneTest | GitHub-native |
| --- | --- |
| `test_runs` (a cycle, scoped, in a context) | a **Project** (v2) + an optional parent run-Issue; context via Project fields (Environment/Build/Release) and/or **Milestone**/iteration |
| `test_runs.scope_snapshot` (frozen) | the set of execution Issues created at run creation = the frozen scope |
| `test_executions` (per-case run) | an **Issue** added to the Project (sub-issue of the run-Issue) |
| `test_executions.status` | Project **single-select field** `Result`: `not_run/in_progress/passed/failed/blocked/skipped` |
| `step_results[]` | task-list checklist in the Issue body |
| `assigned_to` | Issue **assignee** |
| `failure_reason` | Project field or label (`bug_in_app`, `environment_issue`, …) |
| `failure_details` / `steps_to_reproduce` | Issue body sections |
| `defect_links[]` | **linked Issues** (defect = a bug Issue) / cross-repo references |
| evidence (`test_attachments`) | files dropped into the Issue, or committed to `assets/` |
| `duration_seconds` / timestamps | Project fields or derived from Issue events |
| `parent_execution_id` (re-run) | a new child Issue, linked to the original |
| `shared_reports` (public link) | **GitHub Pages** report (see [Reporting](04-correlations-and-reporting.md)) |
| run/execution context (env/build/release/sprint) | Project iteration + Milestone + Project fields, sourced from Releases/Environments |

## Run lifecycle → Project + Issue states

| OneTest run state | GitHub-native |
| --- | --- |
| `draft`/`planned` | Project created, issues created but unassigned; run-Issue open, labeled `run:planned` |
| start (freeze scope) | `create-run` finishes creating issues = scope frozen; label `run:in_progress` |
| `in_progress` | testers work the board |
| `complete` | `complete-run` aggregates results, generates report, closes run-Issue, label `run:completed` |
| `abort` | label `run:aborted`, close run-Issue |
| `copy` (re-run) | `create-run` again with the same scope source |

**Execution state machine** (`not_run → in_progress → passed/failed/blocked/skipped`) maps to the
Project `Result` field; "executable only while the run is in_progress" is a board convention (or
enforced by a guard Action). Defect links remain editable after close — native (you can always
edit an Issue).

## Creating a run — the `create-run` function

[`create-run`](functions.md#create-run) is a `workflow_dispatch` / `repository_dispatch` Action.
This is the heart of your model. Inputs and behaviour:

**Inputs**
- `scope`: how to select cases — file globs, folder paths, a list of IDs, or an **OQL** query
  (resolved by [`oql-search`](functions.md#oql-search)).
- `repos`: which **target** repositories to create tasks in. Defaults to each case's front-matter
  `targets[]` (the system(s) under test); falls back to the current repo. This is the cross-repo
  case in your description — the test-case **ID stays source-based** (`LOGIN-0042`) while the task
  is created in the target repo and gets that repo's native issue number (`app-web#318`). See
  [ID scheme](01-test-case-management.md#identifier-scheme--source_key-number-decided).
- `project`: target org **Project** (create or reuse).
- `name`, `environment`, `build`, `release`/`milestone`, `assignees` (round-robin or by
  CODEOWNERS).

**Behaviour**
1. Resolve the scope to a concrete list of test-case files (per repo).
2. For each case, **create an Issue** ("task") in the **target** repo (from `targets[]`) using a
   template — title `LOGIN-0042 — <title>` (the source-based case ID), body = rendered steps as a
   checklist + context + a link back to the source test-case file, labels mirrored from
   front-matter (tags, priority, category). The Issue gets the target repo's native number.
3. **Add every Issue to the Project**, set fields (`Result=not_run`, `Run=<name>`, `Environment`,
   `Build`, iteration), assign testers.
4. Create/Update the **parent run-Issue** linking all execution Issues as **sub-issues** (run →
   executions hierarchy).
5. Output the Project URL — *surfaced to the testing team*.

```yaml
# .github/workflows/create-run.yml  (sketch)
on:
  workflow_dispatch:
    inputs:
      name: { required: true }
      scope: { description: "OQL or folder/glob/ids", required: true }
      environment: { required: false }
      project_url: { required: false }
jobs:
  create-run:
    runs-on: ubuntu-latest
    concurrency: run-${{ github.run_id }}
    steps:
      - uses: actions/checkout@v4
      - id: select
        run: ./.onetest/bin/oql-search "${{ inputs.scope }}" > selected.json
      - run: ./.onetest/bin/create-run --name "${{ inputs.name }}" \
               --from selected.json --project "${{ inputs.project_url }}" \
               --env "${{ inputs.environment }}"
        env: { GH_TOKEN: ${{ secrets.GH_TOKEN }} }
```

## Recording results

### Manual (testing team on the board)
A tester opens the execution Issue, walks the step checklist, sets the Project **`Result`** field,
adds notes/evidence as comments/attachments, and on failure picks a `failure_reason` and links the
defect Issue. No backend — just GitHub UI. (Optional [`sync-execution`](functions.md#sync-execution)
Action can mirror the result back into a results file for reporting/traceability.)

### AI-agent (`/qa-onetest`-style)
The existing **Claude Code** agent path maps almost unchanged: instead of OneTest MCP tools it uses
a **GitHub MCP server + repo MCP** to read test-case files, drive a real browser (CDP), and **write
results to Issues/Project** and evidence to `assets/`/artifacts. Run it interactively or as an
[`ai-run`](functions.md#ai-run) Action on a schedule. Exploratory findings → new Issues (and, via
`push findings`, new test-case files in a PR). Parallel execution → matrix jobs.

### Personal queue
`/me/executions` → a **Project view filtered by assignee = @me**.

## Evidence & defects

- **Evidence**: screenshots/logs attach to the execution Issue (drag-drop) or are committed under
  `assets/run-<id>/` (Git LFS) / uploaded as Actions artifacts for agent runs.
- **Defects**: a defect is a bug **Issue**; `defect_links` = native Issue links / "linked pull
  requests"/references. `known_issues` in a test-case file can reference these Issues.

## What disappears / changes

- The `test_runs`/`test_executions` tables → Issues + a Project; "frozen scope" = the created Issue
  set.
- Run analytics endpoint → a reporting function over the Project's Issues (see
  [Reporting](04-correlations-and-reporting.md)).
- Per-product `failure_reason` allow-list → label set defined in `.onetest/fields.yml`, applied as
  labels.
- The execution REST/MCP API → Actions (`create-run`, `complete-run`, `sync-execution`) + native
  GitHub UI/API.
