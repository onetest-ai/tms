# Running test runs

A **test run** is a scoped batch of test cases your team executes together against one
environment. In OneTest TMS a run is a *Test Run* issue plus one *Test Execution* issue per case,
all surfaced on the org **QA Runs** Project board. You drive the whole lifecycle by talking to an
AI agent (Claude Code / Copilot / VS Code) that holds the `onetest-tms` MCP, calling tools like
`create_run({ ... })`. Every tool has a `gh`-CLI equivalent under `scripts/` if you prefer the
terminal.

This guide takes you from picking a scope to closing the run. To record individual outcomes, see
[Recording results](recording-results.md).

## Before you start

- The `onetest-tms` MCP is configured for your host and `gh` is authenticated against the target
  TM repo and the org Project. See the [quickstart](../getting-started/quickstart.md).
- You know your **TM repo** (the product repo that owns the cases, e.g. `onetest-ai/tm-shop`).
  Pass it as `repo` on every tool; never the template repo.
- You understand runs, executions, and the board — see [concepts](../getting-started/concepts.md).

## 1. Choose a scope

The scope is the set of cases the run executes. Pick whichever selector fits:

| Selector | When to use | Example |
| --- | --- | --- |
| `oql` | Query by tags, priority, status, type | `tags CONTAINS "smoke" AND priority IN (critical, high)` |
| `folder` | Run everything under a path | `tests/cart` |
| `glob` | Match a file pattern | `tests/**/checkout/*.md` |
| `files` | Hand-pick specific cases | `tests/cart/SHOP-0001_add-to-cart.md` |

Preview a query first so you know exactly what you'll run:

```
search_test_cases({ repo: "onetest-ai/tm-shop", query: "tags CONTAINS 'smoke'", ids: true })
```

See the [OQL reference](../reference/oql.md) for the full query grammar and the
[test case format](../reference/test-case-format.md) for the front-matter fields you can filter on.

## 2. Create the run

`create_run` resolves the scope to a concrete list of cases and materializes the run.

```
create_run({
  repo: "onetest-ai/tm-shop",        // TM repo that owns the cases
  name: "Cart smoke",                // human-readable run name
  oql: "tags CONTAINS 'smoke'",      // or folder / glob / files
  env: "staging",                    // environment label (default: staging)
  target: "onetest-ai/app-web",      // optional: override the target repo for all cases
  assignees: ["alice", "bob"],       // optional: round-robin across executions
  dry_run: false                     // true → show the plan, create nothing
})
```

| Parameter | Meaning |
| --- | --- |
| `name` | The run name shown on the run issue and report. |
| `repo` | The TM repo holding the cases. Omit to use the server default. |
| `oql` / `folder` / `glob` / `files` | How cases are selected (one of these). |
| `env` | Environment the run targets; resolves `{{base_url}}` in each execution body. |
| `target` | Override the destination repo for executions. Omit to use each case's `targets[0]`, falling back to the TM repo. |
| `assignees` | GitHub handles, assigned round-robin to the executions. |
| `dry_run` | When `true`, returns the resolved scope and the issues it *would* open without touching any repo. |

Always run a `dry_run` first when the scope is broad — it prints the run id, each selected case,
its priority/size, and the target repo, so you can confirm before opening real issues.

### What gets created

A successful `create_run` produces:

- **One Test Run issue** in the TM repo, titled `RUN-SHOP-2026-05-29-001 — Cart smoke`, labeled
  `kind:run` and `run:in-progress`. Its body lists every execution as a checklist.
- **One Test Execution issue per case**, in that case's target repo, titled
  `SHOP-0001 — Add item to cart`. The body is the rendered step checklist with `{{base_url}}`
  resolved for the chosen environment, plus a link back to the source case. Same-repo executions
  are linked as **sub-issues** of the run; cross-repo ones are referenced in the run body.
- **Board items** for the run and every execution on the org **QA Runs** Project, with fields set:
  `Result = Not run`, `Run`, `Case`, `Priority`, and `Size`. Executions are mirrored with a
  `result:not-run` label and assigned to testers.

`create_run` returns the **run id** (`RUN-SHOP-2026-05-29-001`) and the execution refs
(`onetest-ai/app-web#4`, `…#5`, …). Use those refs when recording results.

The `gh`-CLI equivalent:

```
scripts/create-run.sh --name "Cart smoke" --oql "tags CONTAINS 'smoke'" \
  --env staging --target onetest-ai/app-web --assignees alice,bob --dry-run
```

## 3. Work the run

The run is now live on the board. The testing team opens the QA Runs Project, filters to the run,
and executes each case. There are three ways to do that — all write to the **same** issues and
Project fields, so a run can mix modes.

| Mode | Who acts | How |
| --- | --- | --- |
| **Manual** | A tester | Open the execution issue, walk the step checklist, and record the outcome with `record_result`. The fallback that always works. |
| **Agent-assisted** (default) | You + an agent | The agent drives a real browser (Playwright MCP), proposes each step, you confirm, and it records the result and uploads evidence. |
| **Autonomous** | An agent | The agent runs the whole suite headlessly (e.g. in Actions) and records every result; you review afterwards. |

Each execution moves `Not run → In progress → Passed/Failed/Blocked/Skipped`. To record an
outcome, including the **evidence-before-PASS** rule, step results, failure reasons, and defects,
see [Recording results](recording-results.md).

### Find your queue

A tester's personal queue is a board view filtered to **assignee = @me**. Ask the agent to list
your open executions, or filter the QA Runs Project by assignee and `Result = Not run`.

## 4. Add, copy, and rerun

Runs are not frozen — you can grow or repeat them.

**Add cases to a running run** — `add_to_run` resolves a new scope, opens the extra execution
issues, links them as sub-issues, and adds them to the board under the same run.

```
add_to_run({ repo: "onetest-ai/tm-shop", run: "RUN-SHOP-2026-05-29-001", folder: "tests/checkout" })
```

**Rerun one execution** — `rerun_execution` opens a *fresh* execution issue linked to the original
(handy for a flaky case after a redeploy). The new issue starts at `Result = Not run`, inherits the
case, run, and priority, and links back to the one it replaces.

```
rerun_execution({ execution: "onetest-ai/app-web#4", reason: "flaky — staging redeploy" })
// → new execution onetest-ai/app-web#40
```

The original execution is not modified; both stay on the board so the history is preserved.

`gh`-CLI: `scripts/rerun.sh --execution onetest-ai/app-web#4 --reason "flaky — staging redeploy"`.

## 5. Complete the run

When every execution has a result, close the run with `complete_run`. It refuses to complete while
any execution is still `Not run` or `In progress` unless you pass `force: true` with a reason.

```
complete_run({ repo: "onetest-ai/tm-shop", run: "RUN-SHOP-2026-05-29-001" })
```

`complete_run`:

- Aggregates every execution's result from the board.
- Writes the report to `reports/RUN-SHOP-2026-05-29-001.md` in the TM repo and commits it.
- Comments the pass/fail summary on the run issue.
- Relabels the run `run:completed` and closes it.

`gh`-CLI: `scripts/complete-run.sh --run RUN-SHOP-2026-05-29-001 --env staging`. Add `--no-commit`
to skip the git commit, `--no-close` to leave the issue open, or `--force` to complete with
unresolved executions.

## Worked example — an agent transcript

A smoke run, end to end, as tool calls an agent makes:

```
// 1. Preview the scope
search_test_cases({ repo: "onetest-ai/tm-shop", query: "tags CONTAINS 'smoke'", ids: true })
// → SHOP-0001, SHOP-0002, SHOP-0003

// 2. Dry-run, then create
create_run({ repo: "onetest-ai/tm-shop", name: "Cart smoke",
             oql: "tags CONTAINS 'smoke'", env: "staging", dry_run: true })
create_run({ repo: "onetest-ai/tm-shop", name: "Cart smoke",
             oql: "tags CONTAINS 'smoke'", env: "staging" })
// → RUN-SHOP-2026-05-29-001
//   executions onetest-ai/tm-shop#4, #5, #6

// 3. Execute and record (assisted: agent drives the browser, captures a snapshot)
record_result({ execution: "onetest-ai/tm-shop#4", result: "PASS",
                evidence: "reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0001.png" })

// 4. A failure → open and link a defect, leave the execution open
record_result({ execution: "onetest-ai/tm-shop#5", result: "FAIL",
                failure_reason: "bug_in_app", notes: "Cart total wrong after coupon",
                defect: "onetest-ai/tm-shop#9" })

// 5. Rerun a flaky case
rerun_execution({ execution: "onetest-ai/tm-shop#6", reason: "timeout — redeploy" })
record_result({ execution: "onetest-ai/tm-shop#40", result: "PASS",
                evidence: "reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0003.png" })

// 6. Close it out
complete_run({ repo: "onetest-ai/tm-shop", run: "RUN-SHOP-2026-05-29-001" })
```

## Related

- [Recording results](recording-results.md) — outcomes, evidence, failure reasons, defects.
- [MCP tools reference](../reference/mcp-tools.md) — full parameter list for every tool.
- [OQL reference](../reference/oql.md) — scope query grammar.
- [Test case format](../reference/test-case-format.md) — case front-matter and steps.
- [Concepts](../getting-started/concepts.md) — runs, executions, and the board.
