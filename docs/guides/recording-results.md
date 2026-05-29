# Recording results

Every test case in a run is a *Test Execution* issue on the QA Runs board. Recording its outcome
sets the Project **Result** field, mirrors a `result:*` label, posts a structured comment, and —
on a pass — closes the issue. You record results by talking to an AI agent holding the
`onetest-tms` MCP, calling `record_result({ ... })`. The `gh`-CLI equivalent is
`scripts/record-result.sh`.

This guide covers a single execution's outcome. To create and complete the run itself, see
[Running test runs](running-test-runs.md).

> Always record through `record_result` — never hand-edit the `Result` field or `result:*` labels.
> The tool keeps the Project field and the labels in sync; editing them by hand drifts the board.

## Result values

`record_result` accepts one `result`:

| Result | Board field | Meaning | Issue state |
| --- | --- | --- | --- |
| `PASS` | Passed | The case met its expected final state. **Requires `evidence`.** | Closed |
| `FAIL` | Failed | The case did not meet expectations. Carries a `failure_reason`. | Stays open |
| `BLOCKED` | Blocked | Could not be executed (dependency, missing data, broken env). | Stays open |
| `SKIPPED` | Skipped | Intentionally not run this cycle. | Stays open |

A PASS closes the execution so the board shows only outstanding work. FAIL, BLOCKED, and SKIPPED
stay open for triage and rerun.

## Step results

Each execution issue body is a checklist of the case's steps. As you work a case (manually or
assisted), tick the steps you complete. When the agent drives the run it ticks them for you and, on
a failure, records which step failed. The aggregate (e.g. `4/5` steps) and any failure step land in
the result comment `record_result` posts.

## The evidence-before-PASS rule

A PASS is only valid with proof. `record_result` **rejects `PASS` when `evidence` is empty** — the
agent (or you) must attach a confirming reference first. Evidence is a screenshot or log: a repo
path, a raw URL, or a comma-separated list of them.

```
record_result({
  execution: "onetest-ai/tm-shop#4",
  result: "PASS",
  evidence: "reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0001.png"
})
```

When an agent drives a browser, it captures the confirming snapshot and commits it under
`reports/<RUN>/screenshots/`, then passes that path as `evidence`. For a manual run, drop the
screenshot or log into the execution issue (or commit it) and pass its URL/path. The evidence links
appear in the result comment.

The rule can be overridden only deliberately — `record_result.sh --force` allows a PASS without
evidence. Avoid it; an unevidenced pass is not trustworthy.

## Failure reasons

A FAIL should classify *why* it failed. Pass `failure_reason` (one of the allow-list); it sets the
Project **Failure reason** field and adds a `fail:*` label.

| `failure_reason` | Use when |
| --- | --- |
| `bug_in_app` | The application under test is wrong — a real defect. |
| `test_data_issue` | The test data was bad or missing. |
| `environment_issue` | The environment was down, misconfigured, or flaky. |
| `test_needs_update` | The case is stale; the app changed intentionally. |
| `blocked_by_other` | Blocked by another failure or dependency. |
| `other` | None of the above (explain in `notes`). |

Add a `notes` string for free-text detail (what you expected vs. what happened). For an
agent-driven run, console errors and duration are captured automatically into the comment.

## Creating and linking a defect

When a FAIL is a real `bug_in_app`, file a defect. Two ways:

**File and link in one step** — `create_defect` opens a *Defect* issue in the target repo, links it
back to the execution, and labels the execution `defect-linked`.

```
create_defect({
  target: "onetest-ai/app-web",
  title: "Cart total wrong after coupon (staging)",
  body_md: "Steps to reproduce… Expected 90.00, got 100.00",
  severity: "High",
  evidence: ["reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0002.png"],
  from_execution: "onetest-ai/tm-shop#5"
})
// → defect onetest-ai/app-web#9
```

**Link an existing defect** — pass `defect` to `record_result` to attach an already-open issue:

```
record_result({ execution: "onetest-ai/tm-shop#5", result: "FAIL",
                failure_reason: "bug_in_app", defect: "onetest-ai/app-web#9" })
```

Either way the execution gets a cross-reference comment and the `defect-linked` label.

`gh`-CLI: `scripts/create-defect.sh --target onetest-ai/app-web --title "…" --severity High
--from-execution onetest-ai/tm-shop#5`.

## Rerunning a flaky case

If a failure looks like flakiness (a timeout, a transient environment blip) rather than a real bug,
rerun the case instead of recording a misleading FAIL. `rerun_execution` opens a fresh execution
issue linked to the original; record the result on the new one.

```
rerun_execution({ execution: "onetest-ai/tm-shop#6", reason: "timeout — staging redeploy" })
// → new execution onetest-ai/tm-shop#40
record_result({ execution: "onetest-ai/tm-shop#40", result: "PASS",
                evidence: "reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0003.png" })
```

Both executions stay on the board, so the rerun history is visible. See
[Running test runs](running-test-runs.md#4-add-copy-and-rerun).

## Find your queue

Your work is the set of executions assigned to you that still need a result. Open the QA Runs
Project, filter to **assignee = @me** and **Result = Not run**, or ask the agent to list your open
executions. Work each one and record its result.

## Worked example — a PASS

```
// Walk the steps, capture a confirming snapshot, then record
record_result({
  execution: "onetest-ai/tm-shop#4",
  result: "PASS",
  evidence: "reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0001.png",
  notes: "Item added; cart count incremented to 1"
})
// Board: Result → Passed, label result:passed, issue closed, comment posted
```

`gh`-CLI:

```
scripts/record-result.sh --execution onetest-ai/tm-shop#4 --result PASS \
  --evidence reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0001.png \
  --notes "Item added; cart count incremented to 1"
```

## Worked example — a FAIL with a defect

```
// 1. File the defect against the app
create_defect({ target: "onetest-ai/app-web",
                title: "Cart total wrong after coupon (staging)",
                body_md: "Apply COUPON10 to a $100 cart. Expected $90.00, got $100.00.",
                severity: "High",
                evidence: ["reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0002.png"],
                from_execution: "onetest-ai/tm-shop#5" })
// → onetest-ai/app-web#9

// 2. Record the failure, linking the defect (execution stays open)
record_result({ execution: "onetest-ai/tm-shop#5",
                result: "FAIL",
                failure_reason: "bug_in_app",
                notes: "Coupon not applied to subtotal",
                evidence: "reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0002.png",
                defect: "onetest-ai/app-web#9" })
// Board: Result → Failed, Failure reason → bug_in_app,
//        labels result:failed + fail:bug-in-app + defect-linked, issue open
```

`gh`-CLI:

```
scripts/record-result.sh --execution onetest-ai/tm-shop#5 --result FAIL \
  --failure-reason bug_in_app --notes "Coupon not applied to subtotal" \
  --evidence reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0002.png \
  --defect onetest-ai/app-web#9
```

## Related

- [Running test runs](running-test-runs.md) — create, work, and complete a run.
- [MCP tools reference](../reference/mcp-tools.md) — full parameters for `record_result`, `create_defect`, `rerun_execution`.
- [Test case format](../reference/test-case-format.md) — steps and expected final state.
- [Concepts](../getting-started/concepts.md) — executions, evidence, and defects.
