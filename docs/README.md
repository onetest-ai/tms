# OneTest TMS — Documentation

**OneTest TMS** is a git-native test management system. Your test cases are files in a GitHub
repo, your test runs and executions are GitHub Issues on a Project board, and your reports are
Markdown committed back to the repo. You operate it by talking to an AI agent (Claude Code,
GitHub Copilot, VS Code) that has the **`onetest-tms`** MCP configured.

New here? Start with the [Introduction](getting-started/introduction.md), then the
[Quickstart](getting-started/quickstart.md).

## Get started
- [Introduction](getting-started/introduction.md) — what OneTest TMS is and how it maps to GitHub
- [Quickstart](getting-started/quickstart.md) — connect the MCP and run your first test run in ~5 minutes
- [Concepts & glossary](getting-started/concepts.md) — cases, runs, executions, the board, coverage

## Guides
- [Authoring test cases](guides/authoring-test-cases.md) — write, organize, and version test cases
- [Running test runs](guides/running-test-runs.md) — create, execute, and complete a run
- [Recording results](guides/recording-results.md) — pass/fail, evidence, defects, re-runs
- [Automated results](guides/automated-results.md) — bring CI/JUnit results in and link them to cases
- [Reports & coverage](guides/reports-and-coverage.md) — run reports, the board, automation coverage
- [Searching with OQL](guides/searching-with-oql.md) — find tests in plain language or OQL

## Reference
- [Test-case format](reference/test-case-format.md) — front-matter fields, body sections, allowed values
- [OQL](reference/oql.md) — query syntax and searchable fields
- [MCP tools](reference/mcp-tools.md) — the `onetest-tms` tool surface
- [Configuration](reference/configuration.md) — the `.onetest/` config files

---

## For contributors (background & design)

These are not user docs — they're the analysis and design behind OneTest TMS, for people building
or extending it.

- **Design of the git-native platform:** [`github-native/`](../design/github-native/) — how OneTest maps onto
  GitHub primitives, the [architecture & delivery](../design/github-native/07-architecture-and-delivery.md)
  model, the [`onetest-tms` spec](../design/github-native/onetest-tms-spec.md), the
  [functions catalog](../design/github-native/functions.md), and the
  [parity audit](../design/github-native/parity-with-onetest.md).
- **Analysis of the original OneTest platform** (reverse-engineered, the source for this
  re-platform): [`overview.md`](../design/overview.md), [`functionalities/`](../design/functionalities/),
  [`data-model/`](../design/data-model/).
