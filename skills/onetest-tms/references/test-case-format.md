# Test-case format (authoring)

One Markdown file with YAML front-matter under `tests/<suite>/<sub>/<ID>_<slug>.md`.
Authored by pull request — no MCP write tool for cases.

## Required front-matter
`id`, `title`, `priority` (critical|high|medium|low), `type`, `module`,
`status` (draft|ready|deprecated), `execution_type` (manual|automated).

## Obsidian vault fields
- `aliases: [<ID>]` — always, so generated hubs link the case as `[[<ID>]]`.
- `requirements: [<ref>, …]` — plain refs (e.g. `OWNER/REPO#N`); **do NOT wikilink**.
  The requirement↔case graph edge is generated as a proxy note.
- `automation_pr` / `automation_url` / `doc_url` — optional pure-URL properties (clickable).

Do NOT create `_index.md` or `_meta/requirements/*` by hand — `build-index` generates them.

## Body sections (in order)
`# <ID>: <Title>`, optional metadata line, `## Preconditions`, `## Test Data`
(Field/Value table), `## Steps` (`# | Action | Expected Result` table),
`## Expected Final State`, `## Teardown`. Body URLs use `{{base_url}}`.

Full reference: docs/reference/test-case-format.md and docs/reference/obsidian-vault.md.
