# Obsidian-first vault: graph-connected, discoverable test cases

**Date:** 2026-08-07
**Status:** Approved (design) — pending implementation plan
**Topic:** Make the `tests/` tree open as a complete, graph-connected Obsidian vault so every test case, its requirements, and its external resources are discoverable through Obsidian's graph and backlinks.

## Problem

The TMS stores test cases as GitHub-native Markdown. Nothing in the repo targets Obsidian, so opening `tests/` as a vault yields an **empty graph**: Obsidian builds its graph only from `[[wikilinks]]`, and the cases use `requirements: [REQ-001]` arrays plus `[text](path.md)` links — neither is a graph edge. Cross-case, case→requirement, and suite navigation are therefore invisible in Obsidian.

**Goal:** the `tests/` folder opens as a self-maintaining Obsidian vault where the graph connects every case to its requirements and suites, external resources are reachable, and the machine tooling (OQL search, MCP server, coverage, CI validation) keeps working unchanged.

## Decisions (locked with user)

1. **Direction:** Obsidian-first for the *vault view*; front-matter stays the single source of truth for machine data. (Approach A of the brainstorm.)
2. **Hub notes are auto-generated** by tooling (extend `build-index`), so the vault stays complete without manual upkeep.
3. **Link style:** clean IDs via `aliases` — each case gets `aliases: [<ID>]`, everything links as `[[TMS-0001]]`.
4. **Traceability lives in front-matter**, not a body section — as wikilink-valued properties (Obsidian 1.4+ graphs link-typed Properties). The generator never edits case bodies.
5. **External resources** split by need: requirements become graph-clustering **proxy notes**; automation / defects / targets / docs are **clickable URL properties**, not graph nodes. External URLs are **declared on the case**.

## Vault layout & node types

Vault root = `tests/`. Every node is a real `.md` file (graph + backlinks work). Generated notes **omit `id:`**, which is exactly how `_index.py` already distinguishes cases — so hub notes are invisible to the index, OQL, and coverage by construction.

| Node | File | Has `id`? | Author |
| --- | --- | --- | --- |
| Test case | `tests/<suite>/<sub>/<ID>_<slug>.md` | yes | human/agent (as today) |
| Requirement proxy | `tests/_meta/requirements/REQ-NNN.md` | no | generated |
| Suite/module MOC | `tests/<suite>/<sub>/_index.md` (recursive) | no | generated |
| Vault root MOC | `tests/_index.md` | no | generated |
| Tag hubs | — native Obsidian tags from front-matter `tags:` | — | free |

**Edges.**
- Case → requirement: case front-matter `requirements: ["[[REQ-001]]"]` → clusters every covering case around the requirement proxy note.
- Suite spine: each MOC lists its child cases (`[[TMS-…]]`) and child MOCs; root MOC lists top-level MOCs. Open any case → backlinks pane shows its module MOC + requirements, with zero edits to the case body.
- Case → case (optional): `related: ["[[TMS-0002]]"]`.

## Case front-matter — additions

Only front-matter changes; body sections, `{{base_url}}`, steps tables, etc. are untouched.

```yaml
id: TMS-0001
title: Login with valid credentials
aliases: [TMS-0001]                 # NEW — clean inbound wikilinks from hubs
priority: critical
type: functional
module: authentication
status: ready
execution_type: automated
size: M
targets: [onetest-ai/app-web]
automation_test_id:
  - tests/e2e/login.spec.ts:Login.valid
requirements:                        # CHANGED — block-list of wikilinks (was inline [REQ-001])
  - "[[REQ-001]]"
related:                             # NEW (optional) — case→case edges
  - "[[TMS-0002]]"
requirement_links:                   # NEW (optional) — "ID | URL", feeds requirement proxy notes
  - "REQ-001 | https://jira.example.com/browse/REQ-001"
automation_url:                      # NEW (optional) — clickable in Obsidian Properties panel
  - "https://github.com/onetest-ai/app-web/blob/main/tests/e2e/login.spec.ts"
doc_url:                             # NEW (optional) — arbitrary external docs, clickable
  - "https://.../login-design"
tags: [smoke, login, happy-path]     # unchanged — native Obsidian tags
```

**Field roles**

| Field | New/changed | Graph? | Indexed for OQL? | Notes |
| --- | --- | --- | --- | --- |
| `aliases` | new | resolves inbound `[[ID]]` | no | `[<ID>]` inline array, plain strings — parser-safe. |
| `requirements` | changed to `"[[REQ-NNN]]"` block-list | yes (edge) | yes (normalized) | Was `[REQ-001]`. `_index.py` strips `[[ ]]` when indexing. |
| `related` | new | yes (edge) | no | Optional case→case links. |
| `requirement_links` | new | no | no | `ID \| URL`; generator-only, feeds proxy notes; not indexed. |
| `automation_url`, `doc_url` | new | no (clickable property) | no | Pure-URL block-lists; Obsidian renders them clickable. |
| `targets`, `automation_test_id`, `tags` | unchanged | tags→tag pane | yes | As today. |

## External resources

Obsidian graphs only internal `[[wikilinks]]`; a pure-URL property is clickable but is not a graph node. External refs are therefore split by whether they should cluster the graph or merely be reachable.

**Requirements — graph nodes + external link.** `requirements: ["[[REQ-001]]"]` gives the internal clustering edge. The generator builds `tests/_meta/requirements/REQ-001.md` and injects a clickable `url:` property + body link from the matching `requirement_links` entry. Path: case → `[[REQ-001]]` (clusters all covering cases) → proxy note → one click out to Jira/tracker.
- URL source: **declared on the case** via `requirement_links` (`ID | URL`).
- Conflict rule: if multiple cases declare the same REQ with different URLs, the generator uses the **first seen** and **logs a conflict warning** (accepted drift risk of on-the-case declaration).
- A requirement with no `requirement_links` entry anywhere still gets a proxy note (bare hub, no `url`).

**Automation / defects / targets / docs — reachable, not graphed.** Declared as pure-URL front-matter properties (`automation_url`, `doc_url`, …), rendered clickable in the case's Properties panel with no body edits and no one-off external graph nodes. `targets` (repos) and defects (GitHub issues) are already GitHub and URL-derivable, so the generator may render those clickable too. Arbitrary body links (`[text](https://…)`) remain allowed for anything ad hoc.

## Generator — `build-index` extension

`_index.py` / `build-index.sh` gain a **vault-emit pass** that runs after `index.json` is written. It reads the (normalized) index and:

1. **Requirement proxy notes** `tests/_meta/requirements/REQ-NNN.md` — front-matter `aliases: [REQ-NNN]` + `url:` (from `requirement_links`, first-seen); body lists `[[TMS-…]]` of every covering case. One note per distinct requirement referenced anywhere.
2. **MOC notes** `tests/<folder>/_index.md` (recursive) + root `tests/_index.md` — each lists child cases (`[[ID]] — title`) and child MOC links.
3. **Idempotent & self-maintaining:** the `_meta/` and `_index.md` set is fully regenerated each run (stale generated files pruned). Refresh runs via the local `build-index.sh` (used by the MCP `build_index` tool). Note: `.github/workflows/build-index.yml` is currently a **stub** (echoes a TODO, does not run the script). Wiring that Action to actually run `build-index.sh` and commit the index + generated notes on every merge is part of this work (or a documented follow-up if the wider `onetest-gh` packaging is doing it); the vault does not auto-refresh in CI until then.

**Normalization (the one parser-touching change):** when `_index.py` reads a list value, strip surrounding `[[ ]]` from each item before storing. So `index.json` holds `requirements: ["REQ-001"]` (OQL `requirements CONTAINS "REQ-001"` keeps working) while the case file holds `"[[REQ-001]]"` for Obsidian. Applies to `requirements` and `related`. `requirement_links`, `automation_url`, `doc_url` are read only by the generator, not emitted to `index.json`.

**No external deps:** all new fields are block-lists of plain strings, which the existing hand-rolled `read_frontmatter` already parses (the `- "…"` branch). No nested YAML maps (the parser skips indented lines), so no PyYAML.

## Docs & skill

- **New reference** `docs/reference/obsidian-vault.md` — vault layout, node types, wikilink/`aliases` convention, external-resource split, how the graph is generated and refreshed. Cross-linked from `test-case-format.md` and `tests/README.md`.
- **Update** `docs/reference/test-case-format.md` — add `aliases`, `related`, `requirement_links`, `automation_url`/`doc_url`, and the wikilink form of `requirements`.
- **Update** `tests/README.md` — note the vault view + generated hub notes.
- **Skill** `skills/onetest-tms/SKILL.md` — instruct authoring agents to emit `aliases` + wikilink `requirements` (+ optional `related`/`requirement_links`); create the referenced-but-missing `skills/onetest-tms/references/test-case-format.md`.

## Testing

- `_index.py` unit checks: wikilink normalization (`[[REQ-001]]` → `REQ-001`); requirement-proxy + MOC generation from a fixture tree; `id`-less generated notes excluded from `cases`; `requirement_links` conflict → first-seen + warning.
- Regression: existing `--tsv` / `--steps` / `--exec-body` and `index.json` shape for scalar/inline-array/block-list front-matter unchanged.
- Migrate the existing `TMS-0001_valid-login.md` to the new front-matter as the worked example; run `build-index`, open `tests/` in Obsidian, confirm the graph connects `TMS-0001 ↔ REQ-001` and the module MOC, and the requirement proxy links out to its URL.

## Out of scope

- Rewriting OQL/`_tc.py` to parse wikilinks in place (Approach B).
- Injecting a generated `## Traceability` body section into cases.
- A central requirements registry (`.onetest/requirements.yml`) — URLs are declared on cases.
- Bundling an `.obsidian/` config/theme; the vault works with default Obsidian settings.
- Graph nodes for one-off automation/defect/doc URLs.

## Affected files (for the plan)

- `onetest-tms/scripts/_index.py` — normalization + vault-emit pass.
- `onetest-tms/scripts/build-index.sh` — invoke/emit vault notes; usage text.
- `onetest-tms/scripts/_tc.py` — verify block-list parsing of new fields (likely no change).
- `.github/workflows/build-index.yml` — currently a stub; wire it to run `build-index.sh` and commit index + generated notes (or document as follow-up).
- `docs/reference/obsidian-vault.md` (new), `docs/reference/test-case-format.md`, `tests/README.md`.
- `skills/onetest-tms/SKILL.md`, `skills/onetest-tms/references/test-case-format.md` (new).
- `tests/authentication/login/TMS-0001_valid-login.md` — migrate as worked example.
