// Smoke test: spawn the server over stdio and exercise the read-only tools.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.resolve(DIR, "../server.js");

const transport = new StdioClientTransport({ command: process.execPath, args: [SERVER] });
const client = new Client({ name: "onetest-gh-test", version: "0.0.0" });
await client.connect(transport);

const { tools } = await client.listTools();
console.log("tools (%d): %s", tools.length, tools.map((t) => t.name).join(", "));

let failures = 0;
async function call(name, args) {
  const r = await client.callTool({ name, arguments: args });
  const txt = (r.content?.[0]?.text || "").trim();
  const head = txt.split("\n").slice(0, 6).join("\n");
  console.log(`\n# ${name} ${r.isError ? "[ERROR]" : "[ok]"}\n${head}${txt.split("\n").length > 6 ? "\n…" : ""}`);
  if (r.isError) failures++;
  return r;
}

await call("build_index", {});
await call("search_test_cases", { query: "tags CONTAINS 'smoke' AND priority IN (critical, high)", ids: true });
await call("get_test_case", { id: "TMS-0001" });
await call("automation_coverage", {});
await call("create_run", { name: "MCP smoke", oql: "tags CONTAINS 'smoke'", dry_run: true });

await client.close();
console.log(`\n${failures === 0 ? "✅ all read-only tools passed" : `❌ ${failures} tool(s) errored`}`);
process.exit(failures === 0 ? 0 : 1);
