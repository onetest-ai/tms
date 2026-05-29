# Skills

[Agent Skills](https://agentskills.io)–compatible skills shipped with OneTest TMS. Each skill is a
folder with a `SKILL.md` (YAML front-matter: `name`, `description`, …; Markdown body).

| Skill | Purpose |
| --- | --- |
| [`onetest-tms`](onetest-tms/SKILL.md) | How to **consume** the TMS through the `onetest-tms` MCP (the provider's companion skill). |

> This is *consumer guidance* for the TMS — not a test executor. The executor (e.g.
> [`web-qa`](https://github.com/arozumenko/sdlc-skills/tree/main/bundles/web-qa)) is a separate
> product that uses this skill + the `onetest-tms` tools. See
> [Architecture & Delivery](../design/github-native/07-architecture-and-delivery.md).

## Install

Use the [`skills`](https://github.com/vercel-labs/skills) CLI — it discovers `skills/<name>/SKILL.md`
in a repo:

```bash
# list the skills this repo offers
npx skills add onetest-ai/tms --list

# install the onetest-tms skill into your agent(s)
npx skills add onetest-ai/tms --skill onetest-tms -a claude-code -a cursor

# install globally (user-level), non-interactive (CI)
npx skills add onetest-ai/tms --skill onetest-tms -g -y
```

You can also point at the skill directly:
`npx skills add https://github.com/onetest-ai/tms/tree/main/skills/onetest-tms`.

Supported agents include `claude-code`, `cursor`, `copilot`, `codex`, `opencode`. Pair the skill
with the `onetest-tms` MCP server (see the [quickstart](../docs/getting-started/quickstart.md)).

## Distribution

- **As files (today):** `npx skills add …` (above), or copy `onetest-tms/` into your agent's skills
  directory (e.g. `.claude/skills/`). The skill is self-contained — it bundles its own
  [`references/test-case-format.md`](onetest-tms/references/test-case-format.md).
- **Over MCP (target):** served as `skill://onetest-tms/SKILL.md` with the enumerable
  `index.json` here, per the [Skills Over MCP](https://modelcontextprotocol.io/community/skills-over-mcp/charter)
  convention — so a client discovers *how to use the TMS* from the same place it gets the tools.
