# onetest-tms MCP server

Stdio MCP server that exposes the TMS [gh-CLI scripts](scripts) as MCP tools, so
Claude Code / Copilot / VS Code agents (e.g. the `web-qa` `test-run-lead`) drive runs on GitHub.
Thin adapter — all logic lives in `scripts/` (and their Python helpers). Implements the
[`onetest-tms` spec](../docs/github-native/onetest-tms-spec.md).

## Tools

`build_index`, `search_test_cases`, `get_test_case`, `automation_coverage`, `create_run`,
`record_result`, `complete_run`, `add_to_run`, `rerun_execution`, `create_defect`,
`ingest_results`, `correlate_results`.

## Run / test

```bash
cd mcp && npm install
npm test            # spawns the server and exercises the read-only tools
```

Requires `gh` authenticated (the tools shell out to `gh`) and Node ≥ 20.
`OT_REPO_ROOT` overrides the repo root (defaults to the parent of `mcp/`).

## Configure in a client

Claude Code (`.mcp.json`) / VS Code Copilot (`.vscode/mcp.json`):
```jsonc
{ "mcpServers": { "onetest-tms": {
  "type": "stdio",
  "command": "node",
  "args": ["/absolute/path/to/tms/onetest-tms/server.js"]
} } }
```
Once published to npm, this becomes `"command": "npx", "args": ["-y", "onetest-tms"]`.
