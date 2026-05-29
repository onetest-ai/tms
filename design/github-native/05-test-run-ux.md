# GitHub-Native: Test Run UX (Agent + MCP)

How the test-run lifecycle *feels* to use when the interface is **Copilot / Claude / VS Code
agents**. This is **not greenfield** — it builds on the existing
[`web-qa` bundle](https://github.com/arozumenko/sdlc-skills/tree/main/bundles/web-qa), which
already ships the agent team, the file formats, and the local run loop. The git-native work is to
**graft a GitHub system-of-record onto that team via an npx stdio MCP**.

## Three layers

| Layer | Role | Status |
| --- | --- | --- |
| **Agent team** (`web-qa` bundle) | brains + UX — onboard, author, size, run, report | **ships today** (Claude agents + Playwright MCP) |
| **npx stdio MCP** (`@onetest/tms`) | engine + GitHub bridge; processing in code | ✅ published |
| **GitHub** | system of record — Issues, Projects, Actions, files, Pages | native |

Principle: **the agent is the brains, the MCP server (code) is the engine, GitHub is the truth.**
The agent calls a tool; the server does the GitHub orchestration, OQL resolution, correlation, and
report rendering deterministically — not the model reasoning through raw API calls.

## The existing foundation (web-qa bundle)

Already in place — we reuse it verbatim:

| Agent | Invoke | Does |
| --- | --- | --- |
| `app-profiler` | profiler | onboards the app; writes `.agents/web-qa/app_profile.md` (URLs, auth, selectors, fragile areas) |
| `test-author` | author | writes `tasks/<suite>/TC-NNN_<slug>.md` from descriptions |
| `test-sizer` | sizer | scores cases **S/M/L** (agent-execution cost) into front-matter |
| **`test-run-lead`** | **lead** | **the run orchestrator** (active agent) — assembles the suite, dispatches a `test-runner` per case, triggers `test-reporter` |
| `test-runner` | runner | runs one case live via **Playwright MCP**, captures a confirming snapshot, emits a JSON result |
| `test-reporter` | reporter | writes `reports/RUN-YYYY-MM-DD-NNN.md` (+ screenshots) |

Artifacts (today, local):
- **Test case** — `tasks/<suite>/TC-NNN_<slug>.md`, front-matter `id, title, priority
  (critical/high/medium/low), type, module, size (S/M/L), requirements[], tags[]`, body =
  Preconditions / Test Data / Steps table / Expected Final State / Teardown, URLs as `{{base_url}}`.
- **Run** — `RUN-YYYY-MM-DD-NNN` (per-day sequence); `test-runner` JSON result per case (`result:
  PASS|FAIL|BLOCKED`, steps, screenshot, console_errors, duration); report aggregates them, with a
  **Performance Metrics** section (tokens / tool_uses / duration per case).
- **Evidence-before-PASS** rule: a PASS is invalid without a confirming Playwright snapshot.

## What github-native adds

The web-qa team is local and single-user today. Grafting GitHub turns it into a team platform:

| Today (web-qa, local) | + github-native |
| --- | --- |
| cases in `tasks/` | cases in **dedicated TM repos** (source, PR-reviewed) — [topology](00-repo-topology.md) |
| run = `reports/` files | run also = **execution Issues** in target repos + an **org Project** the testing team works |
| local, one user | **assigned queues**, cross-repo, team board, Projects **Insights** |
| `app_profile.md` only | + **automated-result correlation** (`automation_test_id ⇄ code_ref`) and coverage |
| autonomous-ish runs | **assisted by default** (human confirms), autonomous supported |

These additions live in the **MCP server's code**, so the agents barely change — `test-run-lead`
gains a `create_run` tool call that materializes Issues+Project; `test-reporter` gains a
`publish_report` call.

## Architecture

```
 You ──▶ test-run-lead (active agent)
            │  Agent tool (sub-agents)         MCP (stdio)
            ├─▶ test-author / test-sizer        ┌───────────────────────────┐
            ├─▶ test-runner ──▶ Playwright MCP   │  onetest-tms  (npx stdio)  │
            └─▶ test-reporter ──────────────────▶│  • resolve OQL → scope    │
                                                 │  • create_run → Issues+Proj│──▶ GitHub
            calls onetest-tms tools ─────────────▶│  • record_result          │   (Issues,
                                                 │  • correlate / coverage   │    Projects,
                                                 │  • publish_report → Pages │    Actions,
                                                 └───────────────────────────┘    files, Pages)
```

Same npx binary runs two ways: **stdio MCP** for agents (interactive) and **CLI** for GitHub
Actions (autonomous/CI) — logic written once in code. See
[functions = one npx package](functions.md#packaging-one-npx-binary-stdio-mcp--cli).

## Three execution modes (assisted is the default)

| Mode | Default? | Who acts | Surface |
| --- | --- | --- | --- |
| **Assisted** | ✅ default | human confirms each step / the agent proposes, you approve | Copilot Chat / Claude + Playwright MCP — the shipped **web manual tester** |
| **Autonomous** | opt-in | agent runs the whole suite, you review after | `test-run-lead` headless in Actions (`ai-run`) |
| **Manual (no agent)** | always available | human | Project board + Issue (fallback) |

**Assisted is the default; autonomous is fully supported.** The web manual tester already exists.
It is the first of a **family of QA bundles** (mobile, accessibility, …) delivered as `web-qa`
improvements — each adds its own domain MCP (Playwright for web, Appium/mobile for mobile,
an a11y/axe MCP for accessibility) but **reuses `test-run-lead` orchestration and the same GitHub
system-of-record + `onetest-tms` MCP unchanged**. The platform layer in these docs is
bundle-agnostic.

## The run lifecycle, mapped to GitHub

`test-run-lead`'s existing steps, now writing to GitHub via the MCP:

| web-qa step | + github-native (MCP, in code) |
| --- | --- |
| 1. assemble suite (author/size) | resolve scope via `search_test_cases(oql)`; authoring → a PR in the TM repo |
| 2. create Run ID `RUN-YYYY-MM-DD-NNN` | `create_run` also creates **execution Issues** in target repos + a parent **run-Issue** + adds all to the **org Project**; keeps `RUN-…` as the human id, GitHub gives the system id |
| 3. dispatch `test-runner` per case | runner executes (Playwright MCP); `record_result` writes status to the execution **Issue + Project field**, uploads the snapshot as evidence |
| 3a. on FAIL | `create_defect` opens a bug Issue (repro + screenshot + console) and `link_defect`s it |
| 4. `test-reporter` writes report | `publish_report` commits `reports/RUN-…md` to the TM repo **and** posts the summary on the run-Issue / **GitHub Pages**; closes the run-Issue |
| (new) | `correlate_results` + `get_automation_coverage` after automated runs land |

The testing team watches the **org Project**; `RUN-YYYY-MM-DD-NNN` ties the GitHub run-Issue back
to the committed report.

## MCP delivery — one npx stdio package, processing in code

You called this: **npx stdio MCP with a fair portion of processing in the code.** So the
[functions catalog](functions.md) ships as **one npx package** exposing:
- a **stdio MCP server** (for Claude Code, Copilot, VS Code agents),
- a **CLI** (the same logic, for GitHub Actions / autonomous runs).

The model does judgment (is this a real bug? is the snapshot confirming?); the **server code** does
everything deterministic — OQL→scope, GitHub API orchestration (create N Issues, set Project
fields), `code_ref ⇄ automation_test_id` matching, coverage math, report rendering. This keeps runs
cheap, repeatable, and identical between chat and CI.

Config (one file per host): `.mcp.json` (Claude Code) / `.vscode/mcp.json` (Copilot):
```jsonc
{ "mcpServers": {
    "onetest-tms": { "type": "stdio", "command": "npx",
      "args": ["-y", "@onetest/tms"],
      "env": { "GITHUB_TOKEN": "${OT_GH_APP_TOKEN}", "OT_TM_REPO": "org/tm-login" } } } }
```

### Tool surface (maps to web-qa steps + the functions catalog)
| MCP tool | Used by | Backed by |
| --- | --- | --- |
| `search_test_cases(oql)` / `get_test_case(id)` | lead, author | `oql-search` over `index.json` |
| `create_run(scope, targets, env, assignees)` | lead | `create-run` → Issues + Project + run-Issue |
| `record_result(exec, status, failure_reason, evidence, defects)` | lead (from runner JSON) | execution Issue + Project field |
| `record_step_result` / `attach_evidence` | runner/lead | Issue checklist + upload |
| `create_defect` / `link_defect` | lead | GitHub Issues |
| `rerun_execution(id, reason)` | lead | child Issue |
| `complete_run(id)` / `publish_report(run)` | lead, reporter | `complete-run` → `generate-report` → Pages |
| `get_run_analytics(id)` | lead, leads/Q&A | over run Issues |
| `parse_automated_results` / `correlate_results` / `get_automation_coverage` | CI + Q&A | receiver-replacement + coverage |

## Surface matrix

| Persona | Surface | Does |
| --- | --- | --- |
| QA engineer | Claude Code / Copilot Chat → **`test-run-lead`** | dispatch & supervise runs, triage |
| Manual tester | Copilot Chat (assisted) + Project board | step through "my queue" with the web manual tester |
| Automation eng | `test-run-lead` (CLI) in Actions | autonomous runs, coverage gaps |
| Developer | Copilot in VS Code | smoke on their PR preview |
| QA lead | chat Q&A + Project **Insights** | triage, reruns, coverage/reporting |
| On-the-go | GitHub Mobile | approve case PRs, triage |

## Guardrails

- **Preview-then-write** on every mutating MCP tool; `create_run --dry-run` shows the scope and the
  Issues it would open before touching target repos.
- **Evidence-before-PASS** (web-qa rule) carries over — `record_result(PASS)` requires a confirming
  snapshot reference.
- **Branch protection** on case *edits* (PRs in the TM repo); runs/executions are lower-stakes
  Issues/fields.
- **Scoped GitHub App token** ([topology auth](00-repo-topology.md#auth-for-cross-repo-work)).
- `complete_run` refuses unless all executions are resolved (or `--force` + reason).
- Full audit free via Issue/PR/Project timelines.

## Artifact reconciliation (web-qa ⇄ github-native)

The web-qa front-matter is the **shipping** schema; the OneTest-derived fields are what
coverage/correlation need. Merge them:

```yaml
id: LOGIN-0042            # <SOURCE_KEY>-<n> — github-native identity (was TC-NNN per-suite)
title: Login with valid credentials
priority: critical        # web-qa scheme: critical|high|medium|low  ← RECOMMEND adopting org-wide
type: functional          # web-qa: functional|regression|smoke|integration|exploratory
module: authentication    # web-qa "module" == OneTest "component"
size: M                   # web-qa S|M|L — agent-execution cost (NEW vs OneTest; keep)
status: ready             # OneTest lifecycle (config-driven) — optional, for TMS parity
execution_type: automated # OneTest manual|automated — needed for coverage
automation_test_id:       # OneTest CI correlation key — needed for coverage
  - tests/e2e/login.spec.ts:Login.valid
targets: [app-web]        # github-native routing (which repo gets the task)
requirements: [REQ-001]   # traceability
tags: [smoke, login]
```

Deltas to decide/keep:
- **Priority scheme — recommend `critical/high/medium/low`** (web-qa, shipping). This supersedes the
  earlier OneTest `p0–p3`/`p1–p4`/`P0–P4` confusion flagged in
  [overview](../overview.md#documented-discrepancies-authoritative-source-wins) — pick one, and
  web-qa already shipped this one.
- **`size` (S/M/L)** and **report Performance Metrics (tokens/tool_uses/duration)** are new,
  agent-economics concepts with no OneTest equivalent — adopt them for **run cost estimation and
  reporting analytics**. They do **not** drive scheduling — parallelism is governed by **system
  resources** (see Resolved decisions #2).
- **`type` vs OneTest's `execution_type`+`test_category`** — web-qa folds these into one `type`.
  Keep `type` for humans; keep `execution_type` only because **automation coverage** needs the
  manual/automated split.
- **Run report** — adopt web-qa's `test-run-report-format.md` as *the* run-report format; the
  `publish_report`/`generate-report` function emits exactly it (plus a link from the run-Issue).
- **Run ID** — keep `RUN-YYYY-MM-DD-NNN` as the human id on the run-Issue; the GitHub Issue number
  is the system id (same two-number pattern as case `id` vs target issue number).

## Resolved decisions

1. **GitHub writes are direct.** The agents call the `onetest-tms` MCP tools directly —
   `test-run-lead` calls `create_run` / `record_result` / `complete_run`, `test-reporter` calls
   `publish_report`. No file-watcher/sync layer; one orchestrator, the board is updated as the run
   happens (immediate truth).
2. **Parallelism is resource-based, not size-based.** Concurrency is bounded by **system
   resources** (available browser instances / CDP ports / CPU / memory), not by test-case `size`.
   `size` stays purely an economics/reporting signal (cost estimation, analytics) and never gates
   scheduling. The runner pool fills to the resource ceiling regardless of case size.
3. **A family of QA bundles, one platform layer.** `web-qa` is first; mobile, accessibility, etc.
   ship as `web-qa` improvements. Each swaps in its **domain MCP** (Playwright / Appium / a11y) but
   reuses `test-run-lead`, the `onetest-tms` MCP, and the GitHub system-of-record **unchanged**.
   Everything in these github-native docs is written to be bundle-agnostic.
