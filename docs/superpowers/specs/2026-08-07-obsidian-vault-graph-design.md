# Obsidian-first vault: graph-connected, discoverable test cases

**Date:** 2026-08-07
**Status:** Approved (design), revised after corpus audit — pending implementation plan
**Topic:** Make the `tests/` tree open as a complete, graph-connected Obsidian vault so every test case, its requirements, and its external resources are discoverable through Obsidian's graph and backlinks — and migrate/repair a real 2,789-case corpus into that shape.

## Revision note (post-audit)

The initial design assumed requirements were clean `REQ-001` tokens and put wikilinks in the case front-matter. Auditing the real corpus (`onetest-ai-tm-Elitea`, 2,789 cases) overturned two assumptions:

- **Requirements are GitHub issue refs** (`OWNER/REPO#N`, e.g. `ProjectAlita/projectalita.github.io#3937`), which contain `/` and `#` and cannot be naive Obsidian wikilinks (`#` = heading anchor). ~1,700 cases carry them; ~1,100 are empty; a few are bare issue numbers.
- **The corpus is a "hot mess":** 169 duplicate IDs across 376 files (genuinely different tests colliding on one ID), 33 files with a BOM/blank line before front-matter, and a `type` enum that uses values (`regression`, `integration`) absent from `.onetest/fields.yml`.

Two decisions follow (user-approved):
1. **Edge model flips to proxy→case.** Keep `requirements:` bare (OQL-safe, unchanged); the generated requirement **proxy note links back to its cases** (`[[<ID>]]`). Obsidian graph edges are undirected, so this yields the identical cluster with no wikilink-mangling and **no front-matter normalization**. Requirement URLs **derive** from the GitHub ref (`OWNER/REPO#N` → `https://github.com/OWNER/REPO/issues/N`).
2. **One combined plan** delivers the vault feature (Part A) *and* the data-repair migration (Part B), including **reassigning fresh IDs** to the 207 non-canonical collision files.

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

**Edges (proxy→case direction).**
- Case ↔ requirement: the generated **requirement proxy note lists `[[<ID>]]`** for every covering case. The undirected Obsidian edge clusters all covering cases; the case's Backlinks pane shows its requirements. `requirements:` in the case stays **bare** (`OWNER/REPO#N`) — no wikilinks, no edits.
- Suite spine: each MOC lists its child cases (`[[<ID>]]`) and child MOCs; root MOC lists top-level MOCs.
- The **only wikilinks in the vault live in generated notes**; case files contain none. Case↔hub resolution works because every case carries `aliases: [<ID>]`.

## Case front-matter — additions

Only additive front-matter; body sections, `{{base_url}}`, steps tables, and existing `requirements:` values are untouched. `requirements` stays exactly as the corpus has it (bare `OWNER/REPO#N`).

```yaml
id: ELITEA-1368
title: "SQL Toolkit — execute_sql Runs With Valid Credentials"
aliases: [ELITEA-1368]               # NEW — so generated hubs link the case as [[ELITEA-1368]]
priority: critical
type: functional
module: alita-sdk
status: ready
execution_type: manual
tags: [feat/toolkits, int/sql, r-2.0.3]
requirements: [EliteaAI/elitea_issues#4972]   # UNCHANGED — bare GitHub issue ref
automation_pr: https://github.com/EliteaAI/elitea-testing-public/pull/1170  # already a clickable URL property
```

**Field roles**

| Field | New/changed | Graph? | Indexed for OQL? | Notes |
| --- | --- | --- | --- | --- |
| `aliases` | new (added by migration) | resolves inbound `[[<ID>]]` | no | `[<ID>]` inline array — parser-safe. |
| `requirements` | **unchanged** (bare `OWNER/REPO#N`) | via proxy backlink | yes | No wikilinks in the case; proxy note links back. |
| `automation_pr`, `automation_url`, `doc_url` | existing / optional | no (clickable property) | no | Pure-URL properties; Obsidian renders them clickable in the Properties panel. |
| `targets`, `automation_test_id`, `tags` | unchanged | tags→tag pane (nested tags via `/` work) | yes | As today. |

No `_index.py` normalization is needed, because no wikilinks enter the case front-matter.

## External resources

Obsidian graphs only internal `[[wikilinks]]`; a pure-URL property is clickable but is not a graph node. External refs are split by whether they should cluster the graph or merely be reachable.

**Requirements — graph nodes via proxy, external link derived.** The generator emits one proxy note per distinct requirement ref, `tests/_meta/requirements/<safe>.md`, where `<safe>` sanitizes `/` and `#` to `-` (e.g. `ProjectAlita-projectalita.github.io-3937.md`). Its front-matter carries `aliases: ["<original ref>"]` and a derived clickable `url:`; its body lists `[[<ID>]]` for every covering case. Path: open a case → Backlinks shows its requirement → proxy note → one click to the GitHub issue.
- **URL derivation:** `OWNER/REPO#N` → `https://github.com/OWNER/REPO/issues/N`. A bare issue number (`#N` with no repo) uses `default_requirements_repo` from `.onetest/config.yml` if set, else the proxy note has no `url` (still a graph node). An optional `requirement_links` (`ref | url`) on a case overrides derivation for non-GitHub refs.
- Empty `requirements: []` → no proxy, no edge (that case just isn't requirement-linked).

**Automation / defects / targets / docs — reachable, not graphed.** Pure-URL properties (`automation_pr` already present on 146 cases; optional `automation_url`/`doc_url`) render clickable in the case's Properties panel — no body edits, no one-off external graph nodes. `targets` (repos) and defects (GitHub Issues) are URL-derivable. Arbitrary body links (`[text](https://…)`) remain allowed.

## Generator — `build-index` extension

`build-index.sh` runs a new `_vault.py` **vault-emit pass** after `index.json` is written. Reading the index (bare requirement refs) plus each case's front-matter:

1. **Requirement proxy notes** `tests/_meta/requirements/<safe>.md` — `aliases: ["<ref>"]` + derived `url:`; body lists `[[<ID>]]` of every covering case. One per distinct ref.
2. **MOC notes** `tests/<folder>/_index.md` (recursive) + root `tests/_index.md` — each lists child cases (`[[<ID>]] — title`) and child MOC links.
3. **Idempotent:** the `_meta/requirements/*` and `_index.md` set is fully regenerated each run (stale marker-bearing generated files pruned). Refresh runs via `build-index.sh` (the MCP `build_index` tool). `.github/workflows/build-index.yml` is currently a **stub**; wiring it to run the script and commit is a documented follow-up (out of scope for the graph itself).

**Exclusion invariant:** generated notes **omit `id:`**, so `_index.case()` returns `None` for them — they never enter `index.json`, OQL, or coverage. They carry a `generated by onetest-tms build-index` marker so pruning only ever deletes generated files.

**No external deps / no parser change:** the generator reads existing block-list/inline-array fields via `read_frontmatter`; requirement refs are consumed as-is. No nested YAML maps, no PyYAML, no normalization.

## Part B — Migration & data repair (Elitea corpus)

The target repo `onetest-ai-tm-Elitea` (2,789 cases) is migrated by a shipped `_migrate.py` / `migrate-vault.sh`. **Dry-run by default; `--apply` writes.** Steps:

1. **BOM / leading-blank fix (33 files):** strip a UTF-8 BOM and any leading blank lines so `---` is line 1 (the parser requires it). Safe, mechanical.
2. **Duplicate-ID reassignment (169 IDs / 376 files → 207 reassigned):** for each colliding ID, keep the **canonical** file (lexicographically smallest path — deterministic/reproducible) and assign the others fresh IDs from a sequence allocator starting at `max_seq + 1` (corpus max = `ELITEA-2615` → new IDs from `ELITEA-2616`, 4-digit zero-pad). Each reassigned file: rewrite `id:`, rename the file to the new `<ID>_<slug>.md`, and update the single internal `duplicate_of:` cross-ref if it points at a reassigned ID. Emit an old→new mapping report.
3. **Add `aliases: [<ID>]`** to every case (idempotent; after dedup so aliases are unique). Runs only after the corpus is collision-free.
4. **Enum reconcile (config, not per-file):** `.onetest/fields.yml` currently exposes `test_category: [functional, performance, security, accessibility, exploratory]`, but cases use a `type` field with values `functional, regression, smoke, integration, security, performance`. Resolve by defining a canonical **`type`** allow-list = union covering the corpus: `[functional, regression, smoke, integration, security, performance, accessibility, exploratory]`, keyed as `type` (the field cases actually use). **Open call — confirm at spec review.** No per-case edits (all corpus values fall inside the union).
5. **Generate the vault:** run `build-index.sh` on the repo → proxy + MOC notes; verify zero duplicate IDs, OQL still resolves, and the Obsidian graph connects cases ↔ requirements ↔ suites.

`automation_pr` is already a clickable URL property — left as-is (optionally documented as the automation link).

## Docs & skill

- **New reference** `docs/reference/obsidian-vault.md` — vault layout, node types, wikilink/`aliases` convention, external-resource split, how the graph is generated and refreshed. Cross-linked from `test-case-format.md` and `tests/README.md`.
- **Update** `docs/reference/test-case-format.md` — add `aliases` (and the optional `automation_url`/`doc_url` clickable properties); document that `requirements` stays bare and the requirement→case graph comes from generated proxy notes.
- **Update** `tests/README.md` — note the vault view + generated hub notes.
- **Skill** `skills/onetest-tms/SKILL.md` — instruct authoring agents to set `aliases: [<ID>]`, keep `requirements` as bare refs, and never hand-edit generated `_index.md`/`_meta/` notes; create the referenced-but-missing `skills/onetest-tms/references/test-case-format.md`.

## Testing

- **`_vault.py` unit checks:** requirement-ref sanitization (`ProjectAlita/projectalita.github.io#3937` → filename `ProjectAlita-projectalita.github.io-3937`) and GitHub URL derivation; proxy note links every covering case and carries `aliases`+`url`; recursive MOC generation; `id`-less generated notes excluded from `cases`; stale-note pruning keeps authored notes.
- **`_migrate.py` unit checks:** BOM/leading-blank stripping; duplicate-ID detection; canonical selection (smallest path) + sequential reassignment from `max+1`; file rename + `id:` rewrite + `duplicate_of` fix; `aliases` insertion is idempotent; dry-run writes nothing.
- **Regression:** existing `_index.py --tsv/--steps/--exec-body` and `index.json` shape unchanged (no normalization added); OQL over the migrated index still resolves `requirements CONTAINS "…"`.
- **Corpus acceptance (manual):** run the full migration `--apply` on `onetest-ai-tm-Elitea`, then `build-index`; assert 0 duplicate IDs, all cases have `aliases`, requirement proxies + MOCs exist, and Obsidian graph connects cases ↔ requirements ↔ suites with clickable issue URLs.

## Out of scope

- Rewriting OQL/`_tc.py` to parse wikilinks in place.
- Wikilinks inside case front-matter or a generated `## Traceability` body section.
- `_index.py` normalization (not needed — no wikilinks in cases).
- Bundling an `.obsidian/` config/theme (the Elitea repo already has one).
- Graph nodes for one-off automation/defect/doc URLs.
- Semantic de-duplication of *content*-duplicate cases; Part B only fixes ID *collisions* by renumbering.

## Affected files (for the plan)

**Part A — vault feature (generic):**
- `onetest-tms/scripts/_vault.py` (new) — proxy + MOC generation, URL derivation, pruning, CLI.
- `onetest-tms/scripts/build-index.sh` — invoke `_vault.py` after the index; `--commit` adds generated notes; usage text.
- `onetest-tms/test/test_vault.py` (new).
- `docs/reference/obsidian-vault.md` (new), `docs/reference/test-case-format.md`, `tests/README.md`.
- `skills/onetest-tms/SKILL.md`, `skills/onetest-tms/references/test-case-format.md` (new).

**Part B — migration/repair (Elitea corpus):**
- `onetest-tms/scripts/_migrate.py` (new) — BOM fix, dedup/reassign, alias insertion; dry-run/`--apply`.
- `onetest-tms/scripts/migrate-vault.sh` (new) — orchestrates `_migrate.py` then `build-index.sh`.
- `onetest-tms/test/test_migrate.py` (new).
- `.onetest/fields.yml` — canonical `type` allow-list (enum reconcile).
- `.onetest/config.yml` — optional `default_requirements_repo` for bare issue numbers.
- `.github/workflows/build-index.yml` — stub; wiring to run + commit is a documented follow-up.
