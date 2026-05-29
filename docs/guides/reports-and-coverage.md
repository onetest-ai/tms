# Reports and coverage

OneTest TMS gives you three places to see what happened: the **run report** (a committed Markdown
file per run), the **QA Runs board** (the org GitHub Project, with views and Insights charts), and
the **automation coverage report** (how much of your suite is actually covered by CI). This guide
shows where each lives, what it contains, and how to read it.

For producing results in the first place, see [Running test runs](running-test-runs.md),
[Recording results](recording-results.md), and [Automated results](automated-results.md).

## The run report

When you close a run with `complete_run`, OneTest TMS aggregates every execution and writes a
report into the TM repo's `reports/` folder, named after the run (for example
`reports/RUN-SHOP-2026-05-29-001.md`).

Agent (MCP):

```
complete_run({ repo: "onetest-ai/tm-shop", run: "RUN-SHOP-2026-05-29-001" })
```

gh-CLI equivalent:

```
scripts/complete-run.sh --run RUN-SHOP-2026-05-29-001
```

`complete_run` also comments the summary on the run issue and closes it. The report contains:

- **Summary table** — total, passed, failed, blocked, skipped, not run; `pass_rate` (passed /
  total) and `completion` ((total − not_run) / total).
- **Results** — every case with its outcome, and breakdowns by priority and size.
- **Failed tests** — each failure with its `failure_reason`, details, and linked evidence/defects.

Because reports are committed files, they are versioned and diffable like any other artifact, and
can be published to GitHub Pages for a shareable link.

## The QA Runs board

The board is the org GitHub Project named **QA Runs** (configured in
[`.onetest/config.yml`](../reference/configuration.md)). Every run issue and every execution issue
lands on it. Each execution carries Project fields: **Result**, **Run**, **Case**, **Target**,
**Priority**, **Size**, **Failure reason**, **Assignees**.

### Views and filters

Build saved views by filtering on those fields:

- **By run** — `Run = RUN-SHOP-2026-05-29-001` to see one run's executions.
- **By assignee** — your own outstanding work, or load-balance across the team.
- **By result** — `Result = Failed` for a triage queue; `Result = Not run` for remaining work.
- **By priority / target** — focus on critical cases or one app under test.

Because tags are mirrored onto execution issues as labels, you can also filter the board by tag.

### Insights charts

GitHub Projects **Insights** gives native charts with no setup: status breakdown (Result
distribution), burn-up/down by iteration, and field distributions across Priority, Target, and
Failure reason. Configure saved charts on the QA Runs Project to track a run's progress or compare
runs over time.

## Automation coverage

`automation_coverage` measures how much of your suite is genuinely covered by CI — not just *marked*
automated, but actually **linked to a CI result**. It reads the search index and the correlation
file (see [Automated results](automated-results.md)) and writes a coverage report into the TM repo's
`reports/` folder (`reports/coverage.md`).

Agent (MCP):

```
automation_coverage({ repo: "onetest-ai/tm-shop" })
```

gh-CLI equivalent:

```
scripts/automation-coverage.sh --commit
```

### What each metric means

| Metric | Meaning |
| --- | --- |
| **Total test cases** | All cases in the suite. |
| **Marked automated** | Cases with `execution_type: automated`. |
| **Linked to CI results** | Marked automated **and** whose `automation_test_id` matched a CI `code_ref`. This is real coverage. |
| **No automation ref set** | Marked automated but with no `automation_test_id` — nothing to match against. |
| **Automation gap (ref, no CI match)** | Marked automated, has an `automation_test_id`, but it matched **no** CI `code_ref`. |
| **Automation gap %** | Share of marked-automated cases that are gaps. |

The report also includes a **by-priority breakdown** (total / automated / gap % per priority) so you
can see whether your critical cases are the ones falling through.

### Reading and closing gaps

A gap means a case claims to be automated but its CI test never reports — usually because:

- The `automation_test_id` is wrong or stale (the test was renamed or moved). **Fix the ref** on the
  case to match the current `code_ref`.
- The automated test isn't actually running in CI, or its JUnit report wasn't ingested. **Wire CI**
  to emit and ingest the report (see [Automated results](automated-results.md)).
- The case isn't really automated. **Revert it to `execution_type: manual`** so it stops counting as
  an expected-but-missing automated case.

Example coverage summary:

```markdown
| Metric | Count |
|--------|-------|
| Total test cases | 1 |
| Marked automated | 1 |
| Linked to CI results | 0 |
| No automation ref set | 0 |
| Automation gap (ref, no CI match) | 1 |
| Automation gap % | 100.0% |
```

Re-run `automation_coverage` after fixing refs or ingesting fresh results to confirm gaps close.

## See also

- [Running test runs](running-test-runs.md) — create and complete runs.
- [Recording results](recording-results.md) — set each execution's outcome.
- [Automated results](automated-results.md) — feed CI results into correlation and coverage.
- [Configuration](../reference/configuration.md) — the QA Runs Project and `pass_rate` definition.
- [MCP tools reference](../reference/mcp-tools.md) — `complete_run`, `automation_coverage`.
