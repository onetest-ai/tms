#!/usr/bin/env node
// onetest-gh — MCP (stdio) server. Thin adapter exposing the gh-CLI scripts as
// MCP tools; all real processing stays in scripts/ (and their python helpers).
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO = process.env.OT_REPO_ROOT || path.resolve(DIR, "..");
const SCRIPTS = path.join(REPO, "scripts");

function sh(script, args = []) {
  return new Promise((resolve) => {
    execFile("bash", [path.join(SCRIPTS, script), ...args],
      { cwd: REPO, maxBuffer: 16 * 1024 * 1024, env: process.env },
      (err, stdout, stderr) =>
        resolve({ code: err ? (typeof err.code === "number" ? err.code : 1) : 0,
                  stdout: stdout || "", stderr: stderr || "" }));
  });
}
function out(r) {
  const text = [r.stdout.trim(), r.stderr.trim()].filter(Boolean).join("\n---\n") || "(no output)";
  return r.code === 0 ? { content: [{ type: "text", text }] }
                      : { content: [{ type: "text", text }], isError: true };
}
// build flag args; false/undefined/"" omit, true → bare flag, else --flag value
const f = (name, v) =>
  v === undefined || v === null || v === false || v === "" ? [] : v === true ? [name] : [name, String(v)];

const server = new McpServer({ name: "onetest-gh", version: "0.1.0" });

server.registerTool("build_index",
  { description: "Rebuild index.json from tests/ front-matter (backs search & coverage).", inputSchema: {} },
  async () => out(await sh("build-index.sh")));

server.registerTool("search_test_cases",
  { description: "Run an OQL query over the test-case index. Returns matching file paths (or ids with ids=true).",
    inputSchema: { query: z.string(), ids: z.boolean().optional() } },
  async ({ query, ids }) => out(await sh("oql-search.sh", [query, ...(ids ? ["--ids"] : [])])));

server.registerTool("get_test_case",
  { description: "Return the full Markdown of a test case by id (e.g. TMS-0001).",
    inputSchema: { id: z.string() } },
  async ({ id }) => {
    const r = await sh("oql-search.sh", [`id = "${id}"`]);
    const p = r.stdout.trim().split("\n").filter(Boolean)[0];
    if (!p) return { content: [{ type: "text", text: `not found: ${id}` }], isError: true };
    return { content: [{ type: "text", text: await readFile(path.join(REPO, p), "utf8") }] };
  });

server.registerTool("automation_coverage",
  { description: "Compute automation coverage (code_ref ⇄ automation_test_id) → reports/coverage.md.", inputSchema: {} },
  async () => out(await sh("automation-coverage.sh")));

server.registerTool("create_run",
  { description: "Create a test run: execution issues in target repos + Project board items from a scope.",
    inputSchema: { name: z.string(), oql: z.string().optional(), folder: z.string().optional(),
      glob: z.string().optional(), env: z.string().optional(), target: z.string().optional(),
      assignees: z.string().optional(), dry_run: z.boolean().optional() } },
  async (a) => out(await sh("create-run.sh", ["--name", a.name,
      ...f("--oql", a.oql), ...f("--folder", a.folder), ...f("--glob", a.glob),
      ...f("--env", a.env), ...f("--target", a.target), ...f("--assignees", a.assignees),
      ...(a.dry_run ? ["--dry-run"] : [])])));

server.registerTool("record_result",
  { description: "Record one execution's outcome; closes the issue on PASS (evidence required).",
    inputSchema: { execution: z.string(), result: z.enum(["PASS", "FAIL", "BLOCKED", "SKIPPED"]),
      failure_reason: z.string().optional(), notes: z.string().optional(),
      evidence: z.string().optional(), defect: z.string().optional(), force: z.boolean().optional() } },
  async (a) => out(await sh("record-result.sh", ["--execution", a.execution, "--result", a.result,
      ...f("--failure-reason", a.failure_reason), ...f("--notes", a.notes),
      ...f("--evidence", a.evidence), ...f("--defect", a.defect), ...(a.force ? ["--force"] : [])])));

server.registerTool("complete_run",
  { description: "Aggregate a run → report (reports/RUN-*.md) → comment on the run issue → close.",
    inputSchema: { run: z.string(), suite: z.string().optional(), env: z.string().optional(),
      no_commit: z.boolean().optional(), force: z.boolean().optional() } },
  async (a) => out(await sh("complete-run.sh", ["--run", a.run, ...f("--suite", a.suite),
      ...f("--env", a.env), ...(a.no_commit ? ["--no-commit"] : []), ...(a.force ? ["--force"] : [])])));

server.registerTool("add_to_run",
  { description: "Add cases to an existing run.",
    inputSchema: { run: z.string(), oql: z.string().optional(), folder: z.string().optional(),
      target: z.string().optional(), assignees: z.string().optional(), dry_run: z.boolean().optional() } },
  async (a) => out(await sh("add-to-run.sh", ["--run", a.run, ...f("--oql", a.oql),
      ...f("--folder", a.folder), ...f("--target", a.target), ...f("--assignees", a.assignees),
      ...(a.dry_run ? ["--dry-run"] : [])])));

server.registerTool("rerun_execution",
  { description: "Re-run one execution as a new linked execution issue.",
    inputSchema: { execution: z.string(), reason: z.string().optional() } },
  async (a) => out(await sh("rerun.sh", ["--execution", a.execution, ...f("--reason", a.reason)])));

server.registerTool("create_defect",
  { description: "Open a Defect issue in a target repo and link it to an execution.",
    inputSchema: { target: z.string(), title: z.string(), severity: z.string().optional(),
      from_execution: z.string().optional(), body: z.string().optional(), evidence: z.string().optional() } },
  async (a) => out(await sh("create-defect.sh", ["--target", a.target, "--title", a.title,
      ...f("--severity", a.severity), ...f("--from-execution", a.from_execution),
      ...f("--body", a.body), ...f("--evidence", a.evidence)])));

server.registerTool("ingest_results",
  { description: "Parse a JUnit XML report into reports/automated/*.json.",
    inputSchema: { file: z.string() } },
  async (a) => out(await sh("ingest-results.sh", ["--file", a.file])));

server.registerTool("correlate_results",
  { description: "Correlate automated results with cases → reports/correlation.json.",
    inputSchema: { automated: z.string() } },
  async (a) => out(await sh("correlate-results.sh", ["--automated", a.automated])));

await server.connect(new StdioServerTransport());
