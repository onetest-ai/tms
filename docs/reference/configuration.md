# Configuration (`.onetest/`)

All configuration for a test-management (TM) repo lives in the `.onetest/` directory. These files define the repo's identity, the field allow-lists, custom fields, the org Project binding, and labels. They are plain YAML, version-controlled, and changed by **pull request** — the `validate-test-case` check enforces the allow-lists on every PR.

See also: [Test-case format](test-case-format.md) · [MCP tools](mcp-tools.md) · [Concepts](../getting-started/concepts.md).

| File | Controls |
| --- | --- |
| [`config.yml`](#configyml) | Repo identity, routing, Project binding, environments, paths. |
| [`fields.yml`](#fieldsyml) | Allowed values + defaults for the enum front-matter fields. |
| [`custom-fields.yml`](#custom-fieldsyml) | Project-defined custom fields stored under a case's `custom_fields`. |
| [`project.yml`](#projectyml) | The org Project (v2) field schema. |
| [`labels.yml`](#labelsyml) | Repo labels for runs, executions, results, defects. |

---

## `config.yml`

The per-repo identity and routing config.

| Key | Meaning |
| --- | --- |
| `schema_version` | Config schema version. |
| `source_key` | ID prefix for this repo's cases (e.g. `TMS` → `TMS-0001`). Immutable; never reuse IDs. |
| `name` | Human name of the TM repo. |
| `product_type` | `webapp`, `api`, or `mobile`. |
| `id_format` | Case-ID template, e.g. `{source_key}-{seq:04d}`. |
| `default_targets` | Fallback target repos when a case has no `targets`. Empty = execution Issues created in this repo (centralized-QA mode). |
| `project.org` / `project.number` | The org Project the runs board lives on. |
| `environments[]` | Named run environments, each `{ name, url, default }`. The chosen environment's `url` substitutes `{{base_url}}` in case bodies. |
| `paths.tests` / `paths.reports` / `paths.index` | Locations of cases, reports/evidence, and the generated index. |
| `automation.normalize_refs` | Normalize `automation_test_id` and CI `code_ref` to `file:Class.method` for correlation. |
| `reporting.pages_path` | Where `publish_report` writes HTML for GitHub Pages. |
| `reporting.pass_rate` | Canonical pass-rate definition (`passed_over_total` = passed / total). |

**To change environments / the project binding:** edit `environments` (add/remove `{ name, url, default }`) or `project.org` / `project.number`, then open a PR. For a new product TM repo, change `source_key`, `name`, and the routing (`default_targets`) to match that product.

## `fields.yml`

The config-driven allow-lists for the enum front-matter fields — the git-native replacement for OneTest's product/workspace field values. `validate-test-case` checks every case's front-matter against these on each PR.

| Field | Default | Values |
| --- | --- | --- |
| `status` | `draft` | `draft`, `ready`, `deprecated` |
| `execution_type` | `manual` | `manual`, `automated` |
| `test_category` | `functional` | `functional`, `performance`, `security`, `accessibility`, `exploratory` |
| `priority` | `medium` | `critical`, `high`, `medium`, `low` |
| `size` | — | `S`, `M`, `L` |
| `failure_reason` | — | `bug_in_app`, `test_data_issue`, `environment_issue`, `test_needs_update`, `blocked_by_other`, `other` |

**To change an allowed field value:** edit the relevant `values` list (and `default` if needed) and open a PR. Adding a value lets new cases use it; removing one will fail validation for cases that still use it. Org-wide defaults can live in the org `.github` repo and be layered under these per-repo values.

## `custom-fields.yml`

Per-repo custom field definitions. Values are stored in each case's front-matter under `custom_fields`. Empty by default.

Each entry:

| Key | Meaning |
| --- | --- |
| `name` | Field key (`^[a-z][a-z0-9_]*$`). |
| `label` | Display label. |
| `type` | `text`, `textarea`, `select`, `multiselect`, `number`, `date`, or `checkbox`. |
| `options` | Allowed values, for `select` / `multiselect`. |
| `required` | Whether a value is required. |

```yaml
fields:
  - name: jira_ticket
    label: Jira Ticket
    type: text
    required: false
```

**To add a custom field:** add an entry under `fields`, then open a PR. `validate-test-case` enforces the definitions against each case's `custom_fields`.

## `project.yml`

The org Project (v2) field schema for the run/quality board, created/ensured by `scripts/bootstrap-project.sh`. The MCP server resolves and caches these field/option node IDs at runtime; `create_run` and `record_result` set these fields.

| Field | Type | Options |
| --- | --- | --- |
| `Result` | single-select | Not run, In progress, Passed, Failed, Blocked, Skipped |
| `Run` | text | run ID (`RUN-YYYY-MM-DD-NNN`) |
| `Case` | text | source case ID (e.g. `TMS-0001`) |
| `Target` | single-select | populated from `default_targets` |
| `Priority` | single-select | critical, high, medium, low |
| `Size` | single-select | S, M, L |
| `Failure reason` | single-select | bug_in_app, test_data_issue, environment_issue, test_needs_update, blocked_by_other, other |

Built-in fields (Assignees, Status, Iteration) are also used. The file also declares saved `views` (e.g. *By run*, *My queue*, *Failures*). Edit `project.org` / `project.number` / `title` to bind to a different Project; re-run `bootstrap-project.sh` to apply field changes.

## `labels.yml`

Repo-scoped labels applied with `scripts/apply-labels.sh`. They cover:

| Group | Examples |
| --- | --- |
| Kind | `kind:run`, `kind:execution`, `kind:defect`, `kind:finding` |
| Run status | `run:planned`, `run:in-progress`, `run:completed`, `run:aborted` |
| Result (mirror of the Project Result field) | `result:not-run`, `result:passed`, `result:failed`, `result:blocked`, `result:skipped` |
| Priority | `priority:critical`, `priority:high`, `priority:medium`, `priority:low` |
| Failure reason | `fail:bug-in-app`, `fail:test-data`, `fail:environment`, `fail:test-needs-update`, `fail:blocked-by-other`, `fail:other` |
| Misc | `onetest`, `defect-linked`, `exploratory` |

**To change labels:** edit the `labels` list (each `{ name, color, description }`), open a PR, then apply with `scripts/apply-labels.sh`.
