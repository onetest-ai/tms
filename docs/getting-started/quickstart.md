# Quickstart

From zero to your first run in about five minutes. You will find a few cases, start a run, record a
result with evidence, complete the run, and view the report and the board.

This guide drives OneTest TMS through your agent. Each step shows the tool call your agent makes;
you just describe what you want in chat.

## Prerequisites

- **A provisioned TM repo.** You need access to a product test-management repo (for example
  `onetest-ai/tm-shop`) that already contains `.onetest/config.yml` and a `tests/` tree. This guide
  uses the source key `SHOP`, so cases look like `SHOP-0001` and runs like
  `RUN-SHOP-2026-05-29-001`.
- **`gh` authenticated** with access to that repo and to the org **QA Runs** Project:

  ```bash
  gh auth status
  ```

- **The `onetest-tms` MCP server configured** in your agent. Add it to `.mcp.json` (Claude Code) or
  `.vscode/mcp.json` (Copilot):

  ```jsonc
  {
    "mcpServers": {
      "onetest-tms": { "command": "npx", "args": ["-y", "@onetest/tms"] }
    }
  }
  ```

  Restart your agent so it picks up the new server. The tools below should now be available.

- *(Optional)* Install the **companion skill** so your agent knows how to drive the TMS:
  ```bash
  npx skills add onetest-ai/tms --skill onetest-tms -a claude-code
  ```
  See [skills/](https://github.com/onetest-ai/tms/tree/main/skills) for agents and options.

## 1. Find the cases you want to run

Ask your agent to search the TM repo. Search takes an [OQL](../reference/oql.md) query (or a folder,
glob, or list of ids).

```
search_test_cases({ repo: "onetest-ai/tm-shop", query: "tags CONTAINS 'smoke'" })
```

You get back the matching cases with their id, path, title, priority, and targets — for example
`SHOP-0001` at `tests/cart/SHOP-0001_add-to-cart.md`. If a search returns nothing right after cases
changed, refresh the index first with `build_index({ repo: "onetest-ai/tm-shop" })`.

## 2. Create the run

Create a run scoped by the same OQL (or by a `folder`). Pass the environment and, optionally,
assignees.

```
create_run({
  repo: "onetest-ai/tm-shop",
  name: "Cart smoke — staging",
  folder: "tests/cart",          // or: oql: "tags CONTAINS 'smoke'"
  env: "staging"
})
```

This creates a **Test Run** Issue plus one **Test Execution** Issue per case, adds them all to the
**QA Runs** board, and returns:

- the run id, e.g. `RUN-SHOP-2026-05-29-001`,
- the execution issue refs, e.g. `onetest-ai/tm-shop#4`,
- a link to the Project board.

> Tip: add `dry_run: true` to preview the scope and the Issues that would be created before anything
> is written.

## 3. Execute and record a result

Run each case with your test executor (for example a browser agent driving Playwright), capturing a
confirming screenshot or log. Then record the outcome against the execution issue.

A **PASS requires an `evidence` reference** and closes the execution issue:

```
record_result({
  execution: "onetest-ai/tm-shop#4",
  result: "PASS",
  evidence: "reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0001.png"
})
```

For a failure, record the reason and (optionally) link an existing defect in the same call:

```
record_result({
  execution: "onetest-ai/tm-shop#5",
  result: "FAIL",
  failure_reason: "bug_in_app",
  notes: "Expected /cart, got HTTP 500",
  evidence: "reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0002.png",
  defect: "onetest-ai/app-web#9"
})
```

`result` is one of `PASS | FAIL | BLOCKED | SKIPPED`. Always go through `record_result` so the
Project **Result** field and the Issue labels stay in sync — don't hand-edit them.

## 4. Complete the run

When every execution is resolved, complete the run:

```
complete_run({ repo: "onetest-ai/tm-shop", run: "RUN-SHOP-2026-05-29-001" })
```

This aggregates the results, writes the report to `reports/RUN-SHOP-2026-05-29-001.md`, comments the
summary on the run issue, and closes it. (It refuses if anything is still unresolved unless you
force it.)

## 5. View the report and the board

- **Report:** open `reports/RUN-SHOP-2026-05-29-001.md` in the TM repo (linked from the run issue
  comment). It shows pass rate, failures by reason, and per-case metrics.
- **Board:** open the **QA Runs** Project to see the run and its executions, filter by run, and watch
  status live on future runs.

## Doing the same from the CLI

Every tool has an equivalent gh-CLI script, useful in GitHub Actions or scripts:

```bash
onetest-tms create-run   --name "Cart smoke" --folder tests/cart --env staging
onetest-tms record-result --execution onetest-ai/tm-shop#4 --result PASS \
  --evidence reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0001.png
onetest-tms complete-run --run RUN-SHOP-2026-05-29-001
```

## Next steps

- [Running test runs](../guides/running-test-runs.md) — full run lifecycle, adding cases, reruns.
- [Recording results](../guides/recording-results.md) — evidence, failure reasons, defects.
- [Authoring test cases](../guides/authoring-test-cases.md) — write cases via pull request.
- [Automated results](../guides/automated-results.md) and
  [Reports and coverage](../guides/reports-and-coverage.md).
- [Searching with OQL](../guides/searching-with-oql.md) — scope runs and build dynamic suites.
