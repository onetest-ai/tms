# Test-case format

A test case in OneTest TMS is a single Markdown file with YAML front-matter, stored in the test-management (TM) repo under `tests/`. The folder tree under `tests/` is the suite structure. Cases are authored and changed by **pull request** to the TM repo — there is no MCP write tool for cases; the agent reads them with `get_test_case` and `search_test_cases`.

See also: [Concepts](../getting-started/concepts.md) · [OQL reference](oql.md) · [Configuration reference](configuration.md) · [Running test runs](../guides/running-test-runs.md).

## Location and naming

```
tests/<suite>/<sub>/<ID>_<slug>.md
```

Example: `tests/authentication/login/TMS-0001_valid-login.md`

| Part | Rule |
| --- | --- |
| `tests/` | Root configured by `paths.tests` in [`.onetest/config.yml`](configuration.md). |
| `<suite>/<sub>/` | Any folder depth. The folder path **is** the suite. A folder may hold a `_suite.yml` (`dynamic: true` + `oql:`) for a query-defined suite. |
| `<ID>` | `<source_key>-<seq>`, e.g. `TMS-0001`. `source_key` comes from `.onetest/config.yml`; `seq` is allocated per repo. IDs are immutable and never reused — never hand-set them. |
| `<slug>` | Short kebab-case description, for human readability only. |

## Front-matter fields

Front-matter is validated against [`.onetest/fields.yml`](configuration.md) and [`.onetest/custom-fields.yml`](configuration.md) by the `validate-test-case` check on every PR. Allowed values for the enum fields below are exactly the allow-lists in `fields.yml`.

| Field | Type | Required | Allowed values | Meaning |
| --- | --- | --- | --- | --- |
| `id` | string | yes | `<source_key>-NNNN` | Immutable case identifier. Never reused. |
| `title` | string | yes | — | One-line case name. |
| `priority` | enum | yes | `critical`, `high`, `medium`, `low` | Execution priority; maps to the Project **Priority** field and `priority:*` labels. |
| `type` | enum | yes | `functional`, `regression`, `smoke`, `integration`, `exploratory` | Test category (web-qa `type`; OneTest `test_category`). |
| `module` | string | yes | — | Functional area under test (e.g. `authentication`). |
| `status` | enum | yes | `draft`, `ready`, `deprecated` | Lifecycle state. Default `draft`. |
| `execution_type` | enum | yes | `manual`, `automated` | Whether the case is run manually or by an automated test. Drives automation coverage. Default `manual`. |
| `size` | enum | no | `S`, `M`, `L` | Agent-execution cost; maps to the Project **Size** field. |
| `targets` | array(string) | no | `OWNER/REPO` entries | Repos under test. Execution Issues are created here. Falls back to `default_targets` in `config.yml` when empty. |
| `automation_test_id` | array(string) | no | `file:Class.method` entries | Automated-test references; correlated against CI `code_ref`. |
| `requirements` | array(string) | no | — | Linked requirement IDs (e.g. `REQ-001`). |
| `tags` | array(string) | no | — | Free-form labels for OQL filtering (e.g. `smoke`, `happy-path`). |
| `custom_fields` | map | no | per `custom-fields.yml` | Project-defined fields. Empty unless `custom-fields.yml` declares any. |
| `aliases` | array(string) | no | `[<ID>]` | Obsidian alias so generated hubs link the case as `[[<ID>]]`. Set to the case `id`. |
| `automation_pr` / `automation_url` / `doc_url` | array/string | no | URLs | Clickable external links in Obsidian's Properties panel (not graph nodes). |

> **Obsidian vault:** `requirements` stays a plain list of refs (e.g. `OWNER/REPO#N`) — do **not** wikilink it. The requirement↔case graph edge is generated as a proxy note that links back to covering cases. See [Obsidian vault](obsidian-vault.md).

> The `failure_reason` allow-list (`bug_in_app`, `test_data_issue`, `environment_issue`, `test_needs_update`, `blocked_by_other`, `other`) is **not** a case field — it is recorded at execution time via `record_result`. See [MCP tools](mcp-tools.md).

## Body sections

After the front-matter, the body uses these sections in order:

| Section | Content |
| --- | --- |
| `# <ID>: <Title>` | Heading. An optional metadata line (`**Module:** … · **Priority:** …`) may follow. |
| `## Preconditions` | Bullet list of required state before execution. |
| `## Test Data` | Table of inputs (`Field` / `Value`). |
| `## Steps` | Table with columns `#`, `Action`, `Expected Result`. One row per step. |
| `## Expected Final State` | The end state if all steps pass. |
| `## Teardown` | Cleanup actions after execution. |

## The `{{base_url}}` rule

URLs in the body use the `{{base_url}}` placeholder (e.g. `{{base_url}}/login`). It is substituted at run time from the run's environment URL (see `environments` in [`.onetest/config.yml`](configuration.md)), keeping cases environment-agnostic. Never hard-code an environment host in a case.

## Complete example

`tests/authentication/login/TMS-0001_valid-login.md`:

```markdown
---
id: TMS-0001
title: Login with valid credentials
priority: critical
type: functional
module: authentication
status: ready
execution_type: automated
size: M
targets: [onetest-ai/app-web]
automation_test_id:
  - tests/e2e/login.spec.ts:Login.valid
requirements: [REQ-001]
tags: [smoke, login, happy-path]
---

# TMS-0001: Login with Valid Credentials

**Module:** Authentication · **Priority:** Critical · **Type:** Functional / Smoke

## Preconditions
- App is accessible at `{{base_url}}`
- Test user exists: email=`test@example.com`, password=`Test1234!`
- Browser cache and cookies are cleared

## Test Data

| Field    | Value            |
|----------|------------------|
| Email    | test@example.com |
| Password | Test1234!        |

## Steps

| # | Action                                          | Expected Result                              |
|---|-------------------------------------------------|----------------------------------------------|
| 1 | Navigate to `{{base_url}}/login`                | Login page loads; Email and Password visible |
| 2 | Fill Email with `test@example.com`              | Email value is set                           |
| 3 | Fill Password with `Test1234!`                  | Password input is masked                     |
| 4 | Click "Sign In"                                 | Redirects to `/dashboard`                    |
| 5 | Check header for "Welcome, Test User"           | Welcome message is visible                   |

## Expected Final State
User is authenticated and on the dashboard. No error messages. URL is `{{base_url}}/dashboard`.

## Teardown
- Navigate to `{{base_url}}/logout`
```
