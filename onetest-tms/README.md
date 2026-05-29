# onetest-tms MCP server

Stdio MCP server that exposes the TMS [gh-CLI scripts](scripts) as MCP tools, so
Claude Code / Copilot / VS Code agents (e.g. the `web-qa` `test-run-lead`) drive runs on GitHub.
Thin adapter — all logic lives in `scripts/` (and their Python helpers). Implements the
[`onetest-tms` spec](../design/github-native/onetest-tms-spec.md).

## Tools

`build_index`, `search_test_cases`, `get_test_case`, `automation_coverage`, `create_run`,
`record_result`, `complete_run`, `add_to_run`, `rerun_execution`, `create_defect`,
`ingest_results`, `correlate_results`.

## Requirements

The server is Node, but the engine shells out to standard tools. On the machine that runs it:
- **Node ≥ 20**
- **`gh`** (GitHub CLI), authenticated (`gh auth login`) with `repo` + `read:org` (and `admin:org`
  / `project` for setup tasks)
- **`git`**, **`bash`**, and **`python3`** on `PATH`

## Install (in a client)

Claude Code (`.mcp.json`) / VS Code Copilot (`.vscode/mcp.json`):
```jsonc
{ "mcpServers": { "onetest-tms": {
  "type": "stdio", "command": "npx", "args": ["-y", "onetest-tms"]
} } }
```
For local development, point at the checkout instead:
`{ "command": "node", "args": ["/absolute/path/to/tms/onetest-tms/server.js"] }`.
`OT_REPO_ROOT` sets the default working repo when a tool call omits `repo`.

## Develop / test

```bash
cd onetest-tms && npm install
npm test            # spawns the server and exercises the read-only tools
```

## Publish

```bash
npm login           # once
npm publish         # publishes onetest-tms (public)
```
Or cut a GitHub Release to publish via the `publish-onetest-tms` workflow (needs the `NPM_TOKEN`
repo secret).
