# tms — OneTest → GitHub-Native Test Management

Working repository for re-platforming **OneTest** ([onetest.ai](https://onetest.ai),
[`onetest-ai`](https://github.com/onetest-ai)) to a **git-native architecture with no backend
services** — test assets as files, runs as Issues/Projects, behaviour as GitHub Actions + an
`onetest-tms` MCP server driven by the [`web-qa`](https://github.com/arozumenko/sdlc-skills/tree/main/bundles/web-qa)
agent family.

The TMS is operated through the **`onetest-tms`** MCP server ([`onetest-tms/`](onetest-tms/)) — a
local stdio process that turns agent tool calls into GitHub Issues, Project items, and committed
reports. Test cases live in [`tests/`](tests/); config in [`.onetest/`](.onetest/).

## Start here

- **[Documentation](docs/)** — the OneTest TMS manual:
  [Introduction](docs/getting-started/introduction.md) ·
  [Quickstart](docs/getting-started/quickstart.md) ·
  [Guides](docs/guides/) · [Reference](docs/reference/).
- **[`onetest-tms/`](onetest-tms/)** — the MCP server + gh-CLI engine (`scripts/`).
- **[`skills/onetest-tms`](skills/onetest-tms/SKILL.md)** — the companion skill for agents consuming the TMS.
- **For contributors:** the design & analysis behind it lives under
  [`design/github-native/`](design/github-native/) and [`design/functionalities`](design/functionalities/) /
  [`design/data-model`](design/data-model/).

## Scope

In scope: **test case management, test execution management, automated test results, correlations
& reporting.** Out of scope: pipelines, credpools, billing/metering.

## Status

The TMS works today via the `onetest-tms` MCP/CLI: provision a repo, author cases, create runs,
record results, ingest automated results, and report coverage — all backed by GitHub. Remaining
packaging steps: publish `onetest-tms` to npm, and strip the engine out of generated product repos
so they're content-only.
