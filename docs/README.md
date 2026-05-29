# OneTest — Functionality & Data Model Reference

This folder documents the **OneTest** platform (https://onetest.ai, GitHub org
[`onetest-ai`](https://github.com/onetest-ai)) as it exists today, ahead of a planned
**re-platforming to a git-native architecture with no backend services**.

It captures *what the product does* and *how its data is modelled and related*, so the
git-native target can preserve behaviour while replacing the Postgres-per-service backend
with files in a repository.

> **Scope.** This documentation covers the four critical functionalities only:
> 1. [Test Case Management](functionalities/01-test-case-management.md)
> 2. [Test Execution Management](functionalities/02-test-execution-management.md)
> 3. [Automated Test Results Management](functionalities/03-automated-test-results-management.md)
> 4. [Correlations & Reporting](functionalities/04-correlations-and-reporting.md)
>
> **Pipelines** and **CredPools** are explicitly **out of scope** and only mentioned where
> a foreign key or column references them.

## How to read this

| Folder | Purpose |
| --- | --- |
| [`overview.md`](overview.md) | Platform summary, service/repo map, and git-native re-platforming considerations. |
| [`functionalities/`](functionalities/) | Behaviour-oriented docs — one file per critical functionality, plus AI assistant and the OQL query language. |
| [`data-model/`](data-model/) | Schema-oriented docs — every entity, column, key, enum, and relationship, organised by domain, plus a consolidated relationship map. |
| [`github-native/`](github-native/) | **Re-platform target** — feature-to-feature mapping of OneTest onto GitHub primitives (org/repos/Projects/Actions), with a functions catalog. |

## Functionalities

- [01 — Test Case Management](functionalities/01-test-case-management.md)
- [02 — Test Execution Management](functionalities/02-test-execution-management.md)
- [03 — Automated Test Results Management](functionalities/03-automated-test-results-management.md)
- [04 — Correlations & Reporting](functionalities/04-correlations-and-reporting.md)
- [AI Assistant](functionalities/ai-assistant.md)
- [OQL — OneTest Query Language](functionalities/oql-query-language.md)

## Data model

- [Conventions & overview](data-model/README.md)
- [01 — Foundational / shared entities](data-model/01-foundational.md)
- [02 — Test Case Management](data-model/02-test-case-management.md)
- [03 — Test Execution](data-model/03-test-execution.md)
- [04 — Automated Results](data-model/04-automated-results.md)
- [Cross-domain relationship map](data-model/relationships.md)

## GitHub-native re-platform mapping

- [Mapping overview, principles & master feature table](github-native/README.md)
- [Repository topology (no co-location: TM repos vs target repos)](github-native/00-repo-topology.md)
- [01 — Test Case Management → files + git + PRs](github-native/01-test-case-management.md)
- [02 — Test Execution → Projects + Issues](github-native/02-test-execution-management.md)
- [03 — Automated Results → Actions + artifacts](github-native/03-automated-test-results.md)
- [04 — Correlations & Reporting → functions + Pages + Insights](github-native/04-correlations-and-reporting.md)
- [05 — Test Run UX (Copilot/Claude/VS Code agents + MCP)](github-native/05-test-run-ux.md)
- [`onetest-tms` MCP tool spec (buildable contract)](github-native/onetest-tms-spec.md)
- [Parity with OneTest (TCM + Execution audit)](github-native/parity-with-onetest.md)
- [Functions catalog (the Actions that replace the backend)](github-native/functions.md)

## Source of this documentation

Compiled by reading the org's repositories directly (private repos read via authenticated
GitHub access) and the public docs site. Where the published `schema.sql` lags behind ORM
models and later migrations, **the ORM + latest migrations are treated as authoritative** and
the drift is flagged inline. Where the user-facing docs describe aspirational fields that do
not exist in code, that is flagged too.

Primary sources per domain:

| Domain | Repos / files |
| --- | --- |
| Foundational | `membership`, `onetest-auth`, `gateway`, `artifacts` |
| Test Case Management | `test-management` (`schema.sql`, `migrations/001–022`, `src/.../db/models.py`) |
| Test Execution | `test-management`, `core` (React UI), `qa-agent`, `octobots`, `Octo`, `mcp-host` |
| Automated Results | `receiver`, `onetest-otel` |
| Correlations / OQL / Reporting | `onetest-oql`, `test-management` (`api/search.py`, `api/reporting.py`, `db/repository.py`) |
| User-facing docs | `docs` (Mintlify MDX) and https://onetest.ai |
