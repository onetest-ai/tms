# GitHub-Native: The TMS Scaffold (`tms` repo)

`onetest-ai/tms` is the **scaffold / reference test-management repo**. It defines the standard
layout, config-as-code, issue types, labels, templates, and function stubs that product TM repos
are generated from (mark it a GitHub **template repository**). It implements
[topology](00-repo-topology.md), the [data model](../data-model/), and the
[`onetest-gh` spec](onetest-gh-mcp-spec.md).

## Layout

```
.onetest/                 config-as-code (the "backend config", versioned)
  config.yml              repo identity: source_key, targets, project, environments, paths
  fields.yml              status/execution_type/test_category/priority/size/failure_reason allow-lists
  custom-fields.yml       custom field definitions
  labels.yml              repo label set (kind/run/result/priority/fail/…)
  issue-types.yml         org Issue Types (Test Run/Execution/Defect/Finding) — needs admin:org
  project.yml             org Project (v2) field schema
  queries/*.oql           saved queries / dynamic-suite sources
.github/
  ISSUE_TEMPLATE/         forms: test-run, test-execution, defect, exploratory-finding (+ config)
  workflows/              function stubs: validate-test-case, build-index, create-run
  CODEOWNERS              review routing (QA teams)
tests/<suite>/            test cases (MD + front-matter); _suite.yml for dynamic suites
reports/                  generated run reports, evidence, automated results, correlation, coverage
scripts/                  apply-labels.sh, apply-issue-types.sh, bootstrap-project.sh
docs/                     this documentation set
```

## Config-as-code ⇄ OneTest mapping

| File | Replaces (OneTest) |
| --- | --- |
| `.onetest/config.yml` | `products` row + environments + project binding |
| `.onetest/fields.yml` | `product_field_values` + `workspace_field_values` (the 422 allow-lists) |
| `.onetest/custom-fields.yml` | `custom_field_definitions` |
| `.onetest/labels.yml` | execution/run status, priority, failure_reason vocabularies |
| `.onetest/issue-types.yml` | the *kind* of work item (run/execution/defect/finding) |
| `.onetest/project.yml` | the run board schema (was the runs/executions UI) |
| `.onetest/queries/` | `saved_queries` + dynamic suites |

## Bringing a new product TM repo online

1. **Create from template:** `gh repo create onetest-ai/tm-<product> --private --template onetest-ai/tms`.
2. Edit `.onetest/config.yml` → set `source_key`, `name`, `default_targets`.
3. `scripts/apply-labels.sh` (repo-scoped).
4. `scripts/apply-issue-types.sh` (once per org; `admin:org`).
5. `scripts/bootstrap-project.sh` (once per org/board; `project` scope) → write the project number
   back into `.onetest/config.yml`.
6. Add the GitHub App token secret `OT_GH_APP_TOKEN` for cross-repo run creation.
7. Author cases under `tests/` (via PR / `test-author`); enable branch protection on `main`.

## Status of the stubs

The `.github/workflows/*` are **placeholders** that document intent and stay green until the
[`onetest-gh`](onetest-gh-mcp-spec.md) npx package ships; then each calls the real CLI.

Already applied to `onetest-ai`: the org **Issue Types** (Test Run, Test Execution, Defect,
Exploratory Finding) and the repo **labels** — so the issue forms set `type:` directly. Still
pending (need extra scopes / the GitHub App): the org **Project** (`scripts/bootstrap-project.sh`,
`project` scope) and the `OT_GH_APP_TOKEN` secret for cross-repo run creation.
