#!/usr/bin/env node
// onetest-tms — MCP (stdio) server. Thin adapter exposing the gh-CLI scripts as
// MCP tools; all real processing stays in scripts/ (and their python helpers).
//
// Repo-parameterized (Tier 1): tools accept an optional `repo` (OWNER/NAME).
// The server clones/pulls that repo into a workspace and runs the *package's*
// scripts there (cwd = the checkout), so one server serves any TM repo without
// a per-repo restart. Precedence for the working repo:
//   tool arg `repo`  >  env OT_REPO_ROOT (a local checkout)  >  the package dir.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile, execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import os from "node:os";
import path from "node:path";

const DIR = path.dirname(fileURLToPath(import.meta.url));      // the onetest-tms package dir
const SCRIPTS = path.join(DIR, "scripts");                     // engine ships inside the package
const DEFAULT_CWD = process.env.OT_REPO_ROOT || path.resolve(DIR, ".."); // when no `repo` arg is given
const WS = process.env.OT_WORKSPACE || path.join(os.homedir(), ".onetest-workspaces");

// CLI face: `onetest-tms <command> [args]` runs the matching scripts/<command>.sh in the current
// directory (for terminals and GitHub Actions). With no command, start the stdio MCP server.
{
  const argv = process.argv.slice(2);
  if (argv.length > 0 && !argv[0].startsWith("-")) {
    const script = path.join(SCRIPTS, `${argv[0]}.sh`);
    if (!existsSync(script)) {
      console.error(`onetest-tms: unknown command '${argv[0]}'`);
      process.exit(2);
    }
    try {
      execFileSync("bash", [script, ...argv.slice(1)], { stdio: "inherit", env: process.env });
      process.exit(0);
    } catch (e) {
      process.exit(typeof e.status === "number" ? e.status : 1);
    }
  }
}

function execP(cmd, args, opts = {}) {
  return new Promise((res, rej) =>
    execFile(cmd, args, { maxBuffer: 16 * 1024 * 1024, env: process.env, ...opts },
      (e, so, se) => (e ? rej(new Error(se || e.message)) : res(so))));
}

// Resolve the working directory for a tool call. With `repo`, ensure a checkout
// at $OT_WORKSPACE/<owner>/<name> (clone or fast-forward pull) and use it.
async function workspace(repo) {
  if (!repo) return DEFAULT_CWD;
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error(`bad repo: ${repo}`);
  const dir = path.join(WS, repo);
  if (existsSync(path.join(dir, ".git"))) {
    await execP("git", ["-C", dir, "pull", "-q", "--ff-only"]).catch(() => {});
  } else {
    await execP("mkdir", ["-p", path.dirname(dir)]);
    await execP("gh", ["repo", "clone", repo, dir]);
  }
  return dir;
}

function sh(script, args = [], cwd = DEFAULT_CWD) {
  return new Promise((resolve) => {
    execFile("bash", [path.join(SCRIPTS, script), ...args],
      { cwd, maxBuffer: 16 * 1024 * 1024, env: process.env },
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
const f = (name, v) =>
  v === undefined || v === null || v === false || v === "" ? [] : v === true ? [name] : [name, String(v)];
const REPO = { repo: z.string().optional().describe("TM repo OWNER/NAME; defaults to the server's repo") };

const server = new McpServer({ name: "onetest-tms", version: "0.2.0" });

server.registerTool("build_index",
  { description: "Rebuild index.json from tests/ front-matter (backs search & coverage).", inputSchema: { ...REPO } },
  async ({ repo }) => out(await sh("build-index.sh", [], await workspace(repo))));

server.registerTool("search_test_cases",
  { description: "Run an OQL query over the test-case index. Returns matching file paths (or ids).",
    inputSchema: { query: z.string(), ids: z.boolean().optional(), ...REPO } },
  async ({ query, ids, repo }) => out(await sh("oql-search.sh", [query, ...(ids ? ["--ids"] : [])], await workspace(repo))));

server.registerTool("get_test_case",
  { description: "Return the full Markdown of a test case by id (e.g. TMS-0001).",
    inputSchema: { id: z.string(), ...REPO } },
  async ({ id, repo }) => {
    const cwd = await workspace(repo);
    const r = await sh("oql-search.sh", [`id = "${id}"`], cwd);
    const p = r.stdout.trim().split("\n").filter(Boolean)[0];
    if (!p) return { content: [{ type: "text", text: `not found: ${id}` }], isError: true };
    return { content: [{ type: "text", text: await readFile(path.join(cwd, p), "utf8") }] };
  });

server.registerTool("automation_coverage",
  { description: "Compute automation coverage (code_ref ⇄ automation_test_id) → reports/coverage.md.", inputSchema: { ...REPO } },
  async ({ repo }) => out(await sh("automation-coverage.sh", [], await workspace(repo))));

server.registerTool("create_run",
  { description: "Create a test run: execution issues in target repos + Project board items from a scope.",
    inputSchema: { name: z.string(), oql: z.string().optional(), folder: z.string().optional(),
      glob: z.string().optional(), env: z.string().optional(), target: z.string().optional(),
      assignees: z.string().optional(), project: z.string().optional(), dry_run: z.boolean().optional(), ...REPO } },
  async (a) => out(await sh("create-run.sh", ["--name", a.name,
      ...f("--oql", a.oql), ...f("--folder", a.folder), ...f("--glob", a.glob),
      ...f("--env", a.env), ...f("--target", a.target), ...f("--assignees", a.assignees),
      ...f("--project", a.project), ...(a.dry_run ? ["--dry-run"] : [])], await workspace(a.repo))));

server.registerTool("record_result",
  { description: "Record one execution's outcome; closes the issue on PASS (evidence required).",
    inputSchema: { execution: z.string(), result: z.enum(["PASS", "FAIL", "BLOCKED", "SKIPPED"]),
      failure_reason: z.string().optional(), notes: z.string().optional(),
      evidence: z.string().optional(), defect: z.string().optional(), force: z.boolean().optional(), ...REPO } },
  async (a) => out(await sh("record-result.sh", ["--execution", a.execution, "--result", a.result,
      ...f("--failure-reason", a.failure_reason), ...f("--notes", a.notes),
      ...f("--evidence", a.evidence), ...f("--defect", a.defect), ...(a.force ? ["--force"] : [])], await workspace(a.repo))));

server.registerTool("complete_run",
  { description: "Aggregate a run → report (reports/RUN-*.md) → comment on the run issue → close.",
    inputSchema: { run: z.string(), suite: z.string().optional(), env: z.string().optional(),
      no_commit: z.boolean().optional(), force: z.boolean().optional(), ...REPO } },
  async (a) => out(await sh("complete-run.sh", ["--run", a.run, ...f("--suite", a.suite),
      ...f("--env", a.env), ...(a.no_commit ? ["--no-commit"] : []), ...(a.force ? ["--force"] : [])], await workspace(a.repo))));

server.registerTool("add_to_run",
  { description: "Add cases to an existing run.",
    inputSchema: { run: z.string(), oql: z.string().optional(), folder: z.string().optional(),
      target: z.string().optional(), assignees: z.string().optional(), dry_run: z.boolean().optional(), ...REPO } },
  async (a) => out(await sh("add-to-run.sh", ["--run", a.run, ...f("--oql", a.oql),
      ...f("--folder", a.folder), ...f("--target", a.target), ...f("--assignees", a.assignees),
      ...(a.dry_run ? ["--dry-run"] : [])], await workspace(a.repo))));

server.registerTool("rerun_execution",
  { description: "Re-run one execution as a new linked execution issue.",
    inputSchema: { execution: z.string(), reason: z.string().optional(), ...REPO } },
  async (a) => out(await sh("rerun.sh", ["--execution", a.execution, ...f("--reason", a.reason)], await workspace(a.repo))));

server.registerTool("create_defect",
  { description: "Open a Defect issue in a target repo and link it to an execution.",
    inputSchema: { target: z.string(), title: z.string(), severity: z.string().optional(),
      from_execution: z.string().optional(), body: z.string().optional(), evidence: z.string().optional(), ...REPO } },
  async (a) => out(await sh("create-defect.sh", ["--target", a.target, "--title", a.title,
      ...f("--severity", a.severity), ...f("--from-execution", a.from_execution),
      ...f("--body", a.body), ...f("--evidence", a.evidence)], await workspace(a.repo))));

server.registerTool("ingest_results",
  { description: "Parse a JUnit XML report into reports/automated/*.json.",
    inputSchema: { file: z.string(), ...REPO } },
  async (a) => out(await sh("ingest-results.sh", ["--file", a.file], await workspace(a.repo))));

server.registerTool("correlate_results",
  { description: "Correlate automated results with cases → reports/correlation.json.",
    inputSchema: { automated: z.string(), ...REPO } },
  async (a) => out(await sh("correlate-results.sh", ["--automated", a.automated], await workspace(a.repo))));

await server.connect(new StdioServerTransport());
