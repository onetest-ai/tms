# 1 — Test Case Management

**What it is:** authoring and organising test cases — *what* to test and *how* — within a
product. Implemented by the `test-management` service (REST + MCP) with the `core` React UI.

→ Data model: [data-model/02-test-case-management.md](../data-model/02-test-case-management.md).

## Core concepts

- A **test case** is a stable identity (`TC-NNNN`, auto-assigned, unique per product) plus a
  chain of **immutable, numbered versions**. Editing content creates a new version; metadata-only
  edits (status/owner/type) mutate the case row directly.
- Test cases are organised by **folders** (a tree, with optional dynamic/OQL-backed suites),
  **tags** (cross-cutting labels), and **custom fields**.
- Everything is scoped to a **product** (the tenant/"project").

### Anatomy of a test case (version content)

| Field | Meaning |
| --- | --- |
| Identifier | `TC-0058`, auto-generated, never user-set |
| Title | Recommended "Verify [action] [condition] [expected result]", < 80 chars |
| Description | Purpose/scope |
| `execution_type` | `manual` / `automated` (config-driven allow-list) |
| `test_category` | `functional / performance / security / accessibility / exploratory` (config-driven) |
| `status` | `draft / ready / deprecated` (config-driven; legacy `archived` removed) |
| Priority | `p0–p3` (see [priority mismatch](../overview.md#documented-discrepancies-authoritative-source-wins)) |
| Component | Feature area/module (e.g. `checkout`) |
| Preconditions / Postconditions | State before/after |
| **Steps** | Ordered list; each step = Action + Expected Result (+ optional data, attachments) |
| Step format | `table` or `gherkin` (`gherkin_feature` for BDD) |
| Test data | Inputs/datasets/fixtures |
| Pass/fail criteria | Overall pass conditions |
| Charter / time box | For exploratory testing |
| Parameters | Data-driven values |
| **Requirements** | Linked user-story/requirement IDs (e.g. `US-123`) — traceability |
| **Dependencies** | Test IDs that must run first |
| **Known issues / limitations** | Bug IDs and caveats |
| **`automation_test_id`** | Code reference(s) `file.py:Class.method`, one per line — the key that links to CI/CD results |
| Tags | Free-form labels (lowercase-hyphenated convention) |
| Custom fields | Per-product, typed |

## Capabilities

### Authoring (three ways to create)
1. **AI generation (recommended).** `Cmd/Ctrl+K` → describe the test in plain English → AI
   returns a complete, editable interactive form → Save. Can generate suites/batches at once.
   Context-aware (product type, existing tags, team patterns). See
   [AI Assistant](ai-assistant.md).
2. **Manual.** "+ New Test Case" → fill Title/Description/Priority/Type → "+ Add Step" per step
   (Action + Expected) → set Tags/Folder/Requirements → Save.
3. **Import** from Excel/CSV/JSON/ZIP with column mapping (see *Import/Export* below).

On create the service: auto-allocates the identifier (Postgres advisory lock + max+1), creates
version 1, sets `status=draft`, attaches tags (auto-creating unknown ones), folders, and cred
pools, and validates config-driven field values (HTTP 422 with the allow-list on bad input).

### Versioning & history
- **Every content change auto-creates a new version** (diff computed over title, description,
  pre/postconditions, steps, expected result, pass/fail criteria, parameters, gherkin, charter,
  custom fields, requirements, dependencies, known issues, priority, component,
  `automation_test_id`).
- Versions are **immutable**, numbered, with `author`, `change_reason`, `change_category`
  (`bug_fix/enhancement/refactor/cleanup`), and an approval workflow
  (`pending/approved/rejected`).
- **Diff two versions** (`/diff?v1=&v2=`) returns structured changes including per-step
  add/remove/modify.
- **Activity timeline** (`/history`) merges version + folder + tag audit events with
  before/after snapshots.
- **Execution history** (`/execution-history`) aggregates recent manual + automated results for
  the case (see [Correlations & Reporting](04-correlations-and-reporting.md)).

### Organising
- **Folders/suites:** hierarchical tree (create/move/delete; recursive DISTINCT counts). Static
  folders use the `test_case_folders` junction; **dynamic suites** store an `oql_query` and
  compute membership at read time (no stored membership; cannot have children).
- **Tags:** CRUD with soft-delete (deprecate), per-case add/remove, auto-create on reference;
  deprecated names free up for reuse.
- **Custom fields:** per-product typed field definitions; values stored on the version.
- **Bulk operations:** select multiple cases → **Move** (to a folder), **Tag** (add/remove
  across many, with contradiction/duplicate normalization), **Update** (status/owner/
  execution_type/test_category in batch), **Export**.

### Searching
- **OQL** full query language (`POST /search/.../test-cases`) — see [OQL](oql-query-language.md).
- **Simple contains-search** (`/test-cases/global`) — ILIKE across identifier + latest-version
  fields + tag names.
- **Saved queries** — reusable filters with owner/public/shared visibility.
- **Field-value autosuggest** — distinct component/owner/created_by.

### Attachments
Metadata CRUD for cases and executions; direct upload (10 MB cap, content-type allowlist) to the
`artifacts` service; presigned download URLs; per-step attachment via `step_number`.

### Parameter sets
Data-driven testing: named parameter sets (`schema` + `data_rows`) per test case, with add-row.

### Import / Export
- **Excel (XLSX):** multi-sheet (Test Cases / Steps / Folders / Tags). Export scopes: All /
  Filtered (OQL) / Selected / Unassigned. Columns include identifier, title, type, status,
  priority, description, preconditions, steps (action+expected), tags (comma-sep), folder path,
  created/updated.
- **ZIP:** per-case Markdown/TOON files + `manifest.json`, restoring folders/tags with collision
  handling. *(The Markdown/TOON serializers in `formats/` are directly relevant to git-native
  storage.)*
- **CSV/JSON import** with column → field mapping and preview.
- Jobs tracked in `import_export_jobs`.

### Prompt templates
CLAUDE.md-style instruction snippets (`prompt_templates`) per product, fed into AI test
generation.

## Interfaces

- **REST** (prefix `/api/v1`): test-cases (CRUD, stats, automation-coverage, versions, diff,
  history, execution-history); folders; tags; bulk (move/tag/update); search; saved queries;
  custom-fields; product field-values; parameter-sets; attachments; prompt-templates;
  import/export; audit.
- **MCP** tool servers mounted at `/mcp`, `/mcp/cases`, `/mcp/runs` — the same operations exposed
  to AI agents (Claude Code, qa-agent). Test-case tools (9), suite tools (5), query tools (4).

## Re-platforming notes

- `test_case` + `test_case_versions` ≈ a file with git history. Immutable numbered versions with
  author/reason/category map cleanly onto commits.
- Allowed `status`/`execution_type`/`test_category` are **config**, not enums → a config file.
- `TC-NNNN` allocation currently uses an advisory lock → needs a git-native scheme.
- Dynamic suites are **queries**, not membership lists — keep them as stored OQL.
- M:N folders/tags are the trickiest to make git-native (consider front-matter references).
- Markdown/TOON exporters already exist and are the natural on-disk format.
