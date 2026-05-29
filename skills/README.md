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

## Distribution

- **As files (today):** install into an agent runtime (e.g. copy into `.claude/skills/`), or read
  directly from this repo.
- **Over MCP (target):** served as `skill://onetest-tms/SKILL.md` with the enumerable
  `index.json` here, per the [Skills Over MCP](https://modelcontextprotocol.io/community/skills-over-mcp/charter)
  convention — so a client discovers *how to use the TMS* from the same place it gets the tools.
