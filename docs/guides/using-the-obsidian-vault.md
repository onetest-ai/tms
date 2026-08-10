# Using the Obsidian vault

Your TM repo's `tests/` folder opens directly as an [Obsidian](https://obsidian.md) vault. Nothing
about how you author or run tests changes — cases are still Markdown files, runs are still GitHub
Issues. The vault is a **read-and-navigate view**: `build-index` generates hub notes so Obsidian's
Graph and Backlinks connect every case to its requirements and suites, giving you a visual, clickable
map of coverage.

See also: [Obsidian vault reference](../reference/obsidian-vault.md) · [Authoring test cases](authoring-test-cases.md) · [Migrating a corpus](migrating-a-corpus.md).

## Open the vault

In Obsidian: **Open folder as vault** → pick your TM repo's `tests/` directory. That's it — no
plugins required. The generated hub notes are ordinary Markdown, so they render and graph with
default settings.

If the Graph looks empty, the hub notes haven't been generated yet — see [Keeping it fresh](#keeping-it-fresh).

## What you'll see

| In Obsidian | What it is |
| --- | --- |
| **Graph view** | Cases cluster around the requirements and suites they belong to. |
| A `<ID>` node | A test case (`tests/<suite>/<ID>_<slug>.md`). |
| A requirement node under `_meta/requirements/` | A generated **proxy note** for a requirement; its `url` property links out to the GitHub issue, and "Covered by" lists every case that references it. |
| An `_index.md` node per folder | A generated **Map of Content** (MOC): links its child cases and sub-suites. Start at `tests/_index.md` to browse the whole vault top-down. |
| The **Backlinks** pane on a case | Shows the case's requirements and its suite MOC — the reverse of the links above. |
| The **tags** pane | Populated from each case's `tags:`; nested tags (`feat/toolkits`) work. |

The connections come from the **generated notes linking to cases**, not from links inside the cases —
so `requirements` in a case stays a plain list of refs. You don't hand-write any `[[wikilinks]]`.

## Navigate coverage

- **From a requirement to its tests:** open the requirement proxy note (search `_meta/requirements`
  or click its node in the graph) → "Covered by" lists every covering case; the `url` property opens
  the issue.
- **From a test to its requirements:** open the case → **Backlinks** shows the requirement proxy
  notes that reference it.
- **Browse a suite:** open `tests/_index.md` (root MOC) → walk into sub-suite `_index.md` notes →
  down to cases.
- **Slice by tag:** use the tag pane / `tag:` search to pull, say, every `smoke` case.

## Author cases in the vault

Authoring is unchanged — a case is still a Markdown file added by pull request (see
[Authoring test cases](authoring-test-cases.md)). Two vault rules:

- Set **`aliases: [<ID>]`** on every case (so hub notes link it as `[[<ID>]]`).
- Keep **`requirements`** as plain refs (e.g. `OWNER/REPO#123`) — **do not** wikilink them. The
  requirement↔case edge is generated for you.
- Optionally add `automation_url` / `doc_url` (or the existing `automation_pr`) — pure-URL
  properties render as clickable links in Obsidian's Properties panel.

**Never hand-edit** `_index.md` or `_meta/requirements/*` — they're regenerated and any manual
change is overwritten.

## Keeping it fresh

The hub notes are derived from the cases, so regenerate them whenever cases change:

```bash
bash onetest-tms/scripts/build-index.sh --dir tests --out index.json
```

(or call the MCP `build_index` tool). This rebuilds `index.json` and regenerates every proxy and
MOC note, pruning any that are now stale. Commit the regenerated notes alongside your case changes.

> Migrating an **existing** repo into this shape (fixing front-matter, deduplicating IDs, adding
> aliases) is a one-time step — see [Migrating a corpus](migrating-a-corpus.md).

## What didn't change

Runs, executions, results, defects, coverage, and OQL all work exactly as before — the vault is
additive. `requirements` values are untouched, so OQL like `requirements CONTAINS "OWNER/REPO#123"`
keeps resolving. The generated hub notes are `id`-less, so they never appear as cases in searches,
runs, or coverage.
