# AI Assistant

OneTest's AI assistant (powered by Claude) is woven across the platform. It is a supporting
capability for the four critical functionalities rather than a fifth domain, but it shapes how
test cases are created and searched, so it is documented here.

Front door: the `gateway` service (conversations, MCP integrations, skills, personas). A
per-product LLM provider must be configured first (Settings → LLM Configuration,
`product_llm_configs`: provider ∈ `azure/bedrock/openai/anthropic`, 3-tier model routing
high/default/low).

Access: `Cmd/Ctrl+K` opens chat (`Esc` close, `↑` edit last, `Cmd/Ctrl+Enter` send).

## Four capabilities

1. **Generate Tests** — describe a test in plain English → a complete, editable test case
   (title, steps + expected results, preconditions, tags, priority, type, pass criteria) shown as
   an **interactive form** that creates real records on submit (no copy-paste). Patterns: single
   test, suite/batch (10–15), from requirements/user stories, from API specs, from screenshots,
   variations across platforms, edge-case focus. Refinable by conversation ("add a 2FA step",
   "split positive/negative"). Context-aware of product type, existing tags, team patterns, and
   `prompt_templates`.
2. **Search Tests** — natural language → AI **translates to [OQL](oql-query-language.md)**
   automatically (e.g. "tests not run in 30 days" → `… ORDER BY …`). The OQL is what actually
   executes.
3. **Ask Questions** — AI has read access to test data; answers about quality metrics, coverage,
   trends, and specific tests ("Why is TC-0042 failing?"), returning insights + recommendations
   (e.g. coverage-gap analysis with suggested missing tests).
4. **Best Practices** — built-in guidance on prompt writing, iteration, do's/don'ts, and a
   pre-save quality checklist.

## Agent-side AI (execution)

Beyond the in-app assistant, AI also **executes** tests via Claude Code:
- `qa-agent` — `/qa-onetest` skill drives runs through the test-management MCP server (real
  Chrome via CDP, screenshots, exploratory findings). See
  [Execution Management](02-test-execution-management.md).
- `octobots` — autonomous multi-agent team (incl. a QA role) coordinated via SQLite + GitHub
  issues + git worktrees.
- `Octo` — the underlying multi-provider LangChain/LangGraph agent CLI engine.
- `mcp-host` — HTTP proxy that spawns STDIO MCP servers on demand.

## Interfaces / data

- `gateway`: `conversations` 1—* `messages` 1—* `message_attachments` (point into `artifacts`);
  `integration_catalog`/`integrations`/`integration_credentials`; `product_skills`,
  `product_personas` (artifact-backed); `qa_agent_connections`; `user_activity` (UI activity used
  as AI context). See [data-model/01-foundational.md](../data-model/01-foundational.md).
- The platform exposes **MCP tool servers** (test-management `/mcp`, `/mcp/cases`, `/mcp/runs`;
  receiver tools) so external AI clients (Claude Code, Cursor, etc.) operate the platform with the
  same operations as the REST API.

## Re-platforming notes

- AI is an interface over the same data, not a separate data store — preserving the REST/MCP
  operation surface keeps AI generation/search/execution working.
- The natural-language→OQL path means OQL remains the stable contract for search.
