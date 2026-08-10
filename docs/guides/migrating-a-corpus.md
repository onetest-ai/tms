# Migrating a corpus to the Obsidian vault

When you adopt the vault on an **existing** test-case repo — especially one imported or
hand-grown over time — the cases usually need repair before the graph is clean: some files have
encoding cruft, IDs may have collided, and none of them carry the `aliases` that hub notes link
through. The `migrate-vault.sh` tool does that repair and then builds the vault, in one pass.

It ships with the `onetest-tms` package: [`onetest-tms/scripts/migrate-vault.sh`](../../onetest-tms/scripts/migrate-vault.sh)
(and the engine it drives, [`_migrate.py`](../../onetest-tms/scripts/_migrate.py)).

See also: [Obsidian vault](../reference/obsidian-vault.md) · [Test-case format](../reference/test-case-format.md).

## Safety model

- **Dry-run by default.** Running the tool with no `--apply` **changes nothing on disk** — it
  reads every case, computes the repair plan, and prints it. Re-run with `--apply` to write.
- **Run on a branch.** The apply renames files and rewrites front-matter across the whole tree;
  do it on a fresh branch with a clean working tree so the whole change is one reviewable diff.
- **Idempotent.** Running it twice is safe: files already fixed are skipped, cases that already
  have an `aliases` line are left alone, and there are no new collisions to resolve.

## What it does, in order

`migrate-vault.sh` runs the repair engine, then (only on `--apply`) rebuilds the index and the
vault:

```
_migrate.py  →  (1) front-matter fix  →  (2) duplicate-ID reassignment  →  (3) alias insertion
             then on --apply:  _index.py  →  index.json
                               _vault.py  →  _meta/requirements/*.md + _index.md MOCs
```

### 1. Front-matter fix (BOM / leading blank)

The front-matter parser requires the opening `---` to be the **first line** of the file. A
UTF-8 byte-order mark or a stray blank line before it makes the parser skip the file entirely —
so those cases would be invisible to the index, OQL, and coverage. The tool detects
(`needs_fm_fix`) and strips (`fix_fm`) a leading BOM and any leading blank lines so `---` is line 1.

This runs **first** because the later steps read front-matter: the collision scan applies the same
fix *in memory* before parsing each file's `id`, so the dry-run preview counts collisions in
BOM-afflicted files too (even though it writes nothing).

### 2. Duplicate-ID reassignment

IDs are meant to be unique and immutable, but an imported corpus can have the same ID on genuinely
different cases. The tool makes IDs unique again by **renumbering the duplicates**:

1. **Scan** every case for its `id` (tolerant of optional surrounding quotes).
2. **Group** by ID; any ID on two or more files is a collision.
3. **Keep the canonical file** — the one with the **lexicographically smallest repo-relative
   path** (deterministic, independent of filesystem walk order). It keeps the original ID.
4. **Reassign the rest.** Each other file gets a fresh ID from a single allocator that starts at
   `max_seq + 1` (one past the highest existing numeric ID) and increments per file — so no new ID
   can collide with an existing one or with another reassignment. New IDs keep the same
   `<SOURCE_KEY>-` prefix and are zero-padded to 4 digits.
5. For each reassigned file the tool **renames** it to `<new_id>_<slug>.md`, rewrites its `id:`
   line, and updates a `duplicate_of:` line if it pointed at the reassigned ID.

The dry-run prints the full `old → new` mapping so you can review every renumbering before applying.

> **Note:** this resolves ID *collisions* only — it renumbers files that happen to share an ID. It
> does **not** detect or merge cases whose *content* is duplicated. That's a separate, human review.

### 3. Alias insertion

Every case gets `aliases: [<ID>]` inserted right after its `id:` line (idempotent — skipped if an
`aliases` line already exists). This is what lets the generated hub notes link a case as
`[[<ID>]]` and resolve. It runs **after** reassignment so aliases are unique.

### Then: build the vault

On `--apply`, the script rebuilds `index.json` from the (now clean) front-matter and runs the
vault generator, which writes the `id`-less hub notes — requirement proxy notes and `_index.md`
MOCs. See [Obsidian vault](../reference/obsidian-vault.md) for what those are and how the graph
connects. Pass `--default-repo OWNER/REPO` to derive issue URLs for requirements written as a bare
issue number.

## Running it

```bash
# 0. clean branch in the TM repo
cd path/to/your-tm-repo
git checkout -b vault-migration        # ensure `git status` is clean first

# 1. preview — writes nothing
bash path/to/onetest-tms/scripts/migrate-vault.sh --dir tests

#    reads e.g.:
#      [DRY-RUN] fm-fix: 33 files
#      [DRY-RUN] reassign: 207 files (old->new):
#          ELITEA-1327 -> ELITEA-2616  tests/.../ELITEA-2616_....md
#          ...
#      [DRY-RUN] aliases: would add to cases missing one

# 2. apply on the branch, deriving requirement URLs from the issue tracker
bash path/to/onetest-tms/scripts/migrate-vault.sh --dir tests --apply --default-repo OWNER/issues-repo
```

`--dir` defaults to `tests`; `--default-repo` is optional (only affects bare-number requirement refs).

## Verify after applying

```bash
# no duplicate IDs remain
python3 -c "import json;c=json.load(open('index.json'))['cases'];i=[x['id'] for x in c];print('dupes:',len(i)-len(set(i)))"

# every case has an alias (prints nothing = all good)
grep -L 'aliases:' $(find tests -name '*.md' ! -name 'README.md' ! -name '_index.md')

# OQL still resolves (bare requirement refs are unchanged)
python3 path/to/onetest-tms/scripts/_oql.py --query "requirements IS NOT EMPTY" --index index.json --ids | head
```

Then open `tests/` in Obsidian and confirm the Graph connects cases ↔ requirements ↔ suites, and a
requirement proxy note under `_meta/requirements/` shows a clickable issue URL plus its "Covered by"
backlinks. Commit the branch when it looks right.

## Limits & edge cases

- **ID rewrite scope.** The `id:`/`duplicate_of:` rewrite is anchored to a standalone line; a case
  whose *body* contained a standalone line reading `id: <the-colliding-id>` could in principle be
  matched. Test-case bodies use step tables, so this is not expected, but review the dry-run mapping.
- **Odd slugs.** A colliding file whose name has no `_` separator yields a cosmetically odd new name
  (`<new_id>_<old-basename>.md`); harmless and unique.
- **Requirement filename collisions.** Two requirement refs that sanitize to the same filename (e.g.
  differing only by `/` vs a literal `-`) would share one proxy note. Not expected with GitHub refs.
- **What it never does:** it does not push, does not edit case bodies (beyond the ID line), and does
  not merge content-duplicate cases.

## Worked example — the Elitea corpus

Migrating a real 2,789-case repo produced, on dry-run: **33** front-matter fixes and **207** ID
reassignments (169 IDs collided across 376 files; the canonical file of each kept its ID), with the
corpus left byte-for-byte unchanged until `--apply`.
