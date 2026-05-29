# Architecture & Delivery

How the pieces relate and how they're delivered. This is the canonical reference; it supersedes
looser wording in earlier docs.

## Provider vs consumer (two separate products)

| | **onetest-tms** (provider) | **web-qa** (consumer) |
| --- | --- | --- |
| Is | the **TMS** | a **test executor** agent |
| Owns | test cases, runs, executions, results, reports, coverage (on GitHub) | the capability to *actually run tests* (browser/Playwright, steps, evidence) |
| Surface | MCP server (the [12 tools](onetest-tms-spec.md)) | an agent/skill bundle ([`sdlc-skills/web-qa`](https://github.com/arozumenko/sdlc-skills/tree/main/bundles/web-qa)) |
| Role | **provides TMS to the QA** | **consumes** the TMS |

web-qa is **not** shipped by onetest-tms. web-qa is an independent agent that *connects to*
onetest-tms, pulls a run's cases, executes them with its own engine, and pushes results back.

```
QA engineer's agent runtime (Claude Code / Copilot)
   ├─ web-qa            — the executor (HOW to run tests)        ← its own capability
   ├─ Playwright MCP    — drives the browser / app under test
   └─ onetest-tms MCP   — the TMS provider ──▶ GitHub (cases, runs, results, reports)

flow:  web-qa ──pull cases / record results──▶ onetest-tms ──▶ GitHub
       web-qa ──run steps, screenshots──────▶ Playwright  ──▶ app under test
```

## Where each calculation happens

The compute is split along the same provider/consumer line — they never overlap:

| Calculation | Lives in | Runs where |
| --- | --- | --- |
| TMS logic — OQL, index, coverage matching, report aggregation, issue/Project orchestration | **onetest-tms** | the onetest-tms process |
| Test execution — browser actions, step verification, evidence capture | **web-qa + Playwright** | the QA agent's runtime |
| Judgment — pass/fail calls, "is this a real bug" | the **model** | the agent |

## Delivery decision — per-consumer local process (no backend)

**onetest-tms runs as a local stdio process on each consumer's machine** (via `npx`), alongside
web-qa. There is **no hosted backend.**

- **TMS calculation runs locally**, per consumer.
- **GitHub is the only shared state / system of record.** Because the TMS calc is *deterministic
  from GitHub state* (issues, Project board, repo files), every consumer's local process computes
  the same answers — consistency comes from GitHub, not from a shared server.
- The local process pulls content (cases, config) from the target repo at call time via the `repo`
  argument, so **push-to-main propagates** on the next call.

Tradeoff accepted: there is no central TMS service, so anything that would need a single always-on
authority (e.g. cross-consumer locks, server-side scheduled rollups) isn't available. If that's
needed later, the same server can be deployed as a thin stateless **hosted** endpoint without
changing the tools — but that's explicitly **out of scope for now**.

## How a consumer is wired

One MCP config in the QA engineer's environment (`.mcp.json` / `.vscode/mcp.json`):

```jsonc
{ "mcpServers": {
  "onetest-tms": { "command": "npx", "args": ["-y", "@onetest/tms"] },   // the TMS provider (local process)
  "playwright":  { "command": "npx", "args": ["@playwright/mcp@latest"] }   // execution
} }
```
…plus the **web-qa** bundle installed into that agent runtime (its own delivery). web-qa then calls
`onetest-tms` tools (`create_run`, `get_test_case`, `record_result`, …) and `playwright` to run.

### Delivery channels for the onetest-tms server
- **Published:** `npx -y @onetest/tms` — published to npm from the server repo via a
  release Action. Zero clone; `npx` fetches the latest server; the `repo` arg pulls content.
- **Local development:** `node <local-clone>/onetest-tms/server.js` — runs from a checkout. Same local-process
  model.

Content (cases/results) always flows **through onetest-tms to GitHub**; the server never bundles a
product's data.

## Consequences / cleanups

- **The server is published once, not embedded per repo.** Product TM repos (`tm-shop`, …) are
  **content-only** (`.onetest/` + `tests/`); they should *not* carry a copy of `mcp/`. (The template
  currently copies it — a cleanup: strip `mcp/`/`scripts/` from the template once the server is
  published, and have repos reference the published package.)
- **Naming:** the provider is "onetest-tms"; it is currently implemented as the `onetest-tms` MCP
  server / `onetest-tms` package. Rename to `onetest-tms` is optional and not yet done.

## Status

| Component | State |
| --- | --- |
| onetest-tms server (local stdio, repo-parameterized) | built (`onetest-tms/server.js` v0.2.0) |
| Delivery as local process | **decided: per-consumer `npx`/local, no backend** |
| Publish to npm | ✅ done — `@onetest/tms` (`npx -y @onetest/tms`) |
| Strip server out of the template (content-only product repos) | not done |
| web-qa consumer wiring to onetest-tms | works (separate bundle) |
