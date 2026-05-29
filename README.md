# tms — OneTest → GitHub-Native Test Management

Working repository for re-platforming **OneTest** ([onetest.ai](https://onetest.ai),
[`onetest-ai`](https://github.com/onetest-ai)) to a **git-native architecture with no backend
services** — test assets as files, runs as Issues/Projects, behaviour as GitHub Actions + an
`onetest-tms` MCP server driven by the [`web-qa`](https://github.com/arozumenko/sdlc-skills/tree/main/bundles/web-qa)
agent family.

> **Status:** documentation / design only. This precedes the actual scaffolding automation and MCP
> implementation — it's the shared source of truth those will be built from.

## Start here

- **[`docs/`](docs/)** — the full reference.
  - [`docs/README.md`](docs/README.md) — index.
  - [`docs/overview.md`](docs/overview.md) — platform & architecture, re-platforming notes.
  - [`docs/functionalities/`](docs/functionalities/) — what OneTest does (behaviour).
  - [`docs/data-model/`](docs/data-model/) — every entity, column, key, relation.
  - [`docs/github-native/`](docs/github-native/) — the GitHub-native target: topology, per-domain
    mapping, [test-run UX](docs/github-native/05-test-run-ux.md),
    [`onetest-tms` MCP spec](docs/github-native/onetest-tms-spec.md),
    [parity audit](docs/github-native/parity-with-onetest.md), and the
    [functions catalog](docs/github-native/functions.md).

## Scope

In scope: **test case management, test execution management, automated test results, correlations
& reporting.** Out of scope: pipelines, credpools, billing/metering.

## Next steps (not yet done)

1. Scaffolding automation (repo templates, `.onetest/` config, reusable Actions).
2. The `onetest-tms` npx package (stdio MCP + CLI) per the spec.
3. `web-qa` agent diffs to call the MCP instead of writing local files.
