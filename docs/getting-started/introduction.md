# Introduction to OneTest TMS

OneTest TMS is a **git-native test management system**. Your test cases, test runs, results, and
reports all live in GitHub — as files, Issues, a Project board, and committed Markdown. There is no
separate database and no web app to log into: **GitHub is the system of record.**

You operate OneTest TMS by talking to your coding agent (Claude Code, GitHub Copilot, or VS Code)
that has the `onetest-tms` MCP server configured. You ask it to find cases, start a run, record what
happened, and publish a report; the MCP server does the GitHub work for you.

## What you can do with it

- **Manage test cases** as Markdown files with YAML front-matter, reviewed and versioned through
  pull requests. Full history, diff, and authorship come from git.
- **Run test runs** that materialize as GitHub Issues on a shared team board, with one execution per
  case, assignees, and an environment.
- **Record results** (passed / failed / blocked / skipped) against each execution, with evidence and
  failure reasons, and file defects for failures.
- **Ingest automated results** from CI (JUnit/JSON) and correlate them back to your cases.
- **Report coverage** — see which cases are automated, which are linked to CI results, and where the
  gaps are.

## Who it's for

- **QA engineers and leads** who plan, execute, triage, and report on test runs day to day.
- **Manual testers** who step through an assigned queue of executions.
- **Developers** who run a quick smoke run on a pull-request preview.
- **Automation engineers** who land JUnit results in CI and track automation coverage.

## How it feels to use

You drive everything through your agent. The agent calls `onetest-tms` tools on your behalf — for
example:

```
search_test_cases({ repo: "onetest-ai/tm-shop", query: "tags CONTAINS 'smoke'" })
create_run({ repo: "onetest-ai/tm-shop", name: "Cart smoke", folder: "tests/cart", env: "staging" })
record_result({ execution: "onetest-ai/tm-shop#4", result: "PASS",
                evidence: "reports/RUN-SHOP-2026-05-29-001/screenshots/SHOP-0001.png" })
complete_run({ repo: "onetest-ai/tm-shop", run: "RUN-SHOP-2026-05-29-001" })
```

Most tools take an optional `repo` (`OWNER/NAME`) — the product **test-management repo** you want to
operate on (for example `onetest-ai/tm-shop`). Omit it to use the server's default repo.

Every tool also has an equivalent **gh-CLI script**, so the same actions run unattended in GitHub
Actions for autonomous and CI-driven runs.

> OneTest TMS stores and tracks your tests; it does not run them. Your **test executor** — for
> example a browser agent driving Playwright — actually performs the steps and hands results back to
> OneTest TMS. See [Concepts](concepts.md) for the provider/consumer split.

## How it maps to GitHub

| In OneTest TMS | In GitHub |
| --- | --- |
| Test case | Markdown file in the TM repo under `tests/**`, e.g. `tests/cart/SHOP-0001_add-to-cart.md` |
| Case versions / history | Git commits and pull requests on that file |
| Test run | A **Test Run** Issue in the TM repo (human id `RUN-SHOP-2026-05-29-001`) |
| Execution | One **Test Execution** Issue per case (in the case's target repo), linked to the run |
| Board | An org **GitHub Project** ("QA Runs") tracking every run and execution |
| Result / status | A single-select **Result** field on the Project (Not run / In progress / Passed / Failed / Blocked / Skipped) |
| Evidence | Screenshots/logs committed under `reports/<run>/screenshots/`, linked from the Issue |
| Defect | An Issue labeled `defect` in the target repo, cross-referenced from the execution |
| Report | Markdown committed to `reports/RUN-….md` in the TM repo |

## Next steps

- [Quickstart](quickstart.md) — go from zero to your first run in about five minutes.
- [Concepts](concepts.md) — the core ideas and glossary the rest of the docs rely on.
- Guides: [Authoring test cases](../guides/authoring-test-cases.md),
  [Running test runs](../guides/running-test-runs.md),
  [Recording results](../guides/recording-results.md),
  [Automated results](../guides/automated-results.md),
  [Reports and coverage](../guides/reports-and-coverage.md),
  [Searching with OQL](../guides/searching-with-oql.md).
- Reference: [Test-case format](../reference/test-case-format.md), [OQL](../reference/oql.md),
  [MCP tools](../reference/mcp-tools.md), [Configuration](../reference/configuration.md).
