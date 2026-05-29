# Searching with OQL

OQL (OneTest Query Language) is how you find and group test cases — for search, for dynamic suites,
and for selecting a run's scope. You rarely write it from scratch: ask your AI agent (Claude Code /
Copilot / VS Code) in plain language and it translates your request into OQL, then runs it. This
guide covers day-to-day searching; for the full grammar see the [OQL reference](../reference/oql.md).

## Ask in natural language

Tell your agent what you want; it emits the OQL and runs `search_test_cases` for you:

```
"Find all critical smoke tests for authentication that are ready to run."
→ search_test_cases({ repo: "onetest-ai/tm-shop",
    query: "tags CONTAINS 'smoke' AND priority = critical
            AND module = 'authentication' AND status = 'ready'",
    ids: true })
```

gh-CLI equivalent:

```
scripts/oql-search.sh "tags CONTAINS 'smoke' AND priority = critical"
```

Add `ids: true` to list just the matching case IDs so you can preview exactly what a query selects
before acting on it.

## Common queries

| Goal | OQL |
| --- | --- |
| By tag | `tags CONTAINS "smoke"` |
| Multiple tags (any/all) | `tags CONTAINS ANY ("smoke", "login")` · `tags CONTAINS ALL ("smoke", "regression")` |
| By priority | `priority IN (critical, high)` |
| By status | `status = "ready"` |
| By component / module | `module = "authentication"` |
| By owner | `owner = "alice"` |
| Automated only | `execution_type = "automated"` |
| Missing automation link | `execution_type = "automated" AND automation_test_id IS EMPTY` |
| Combined, ordered | `tags CONTAINS "regression" AND priority IN (critical, high) ORDER BY priority` |

Queries combine with `AND` / `OR` / `NOT` and parentheses, and support `ORDER BY`, `LIMIT`, and
`OFFSET`. Operators include `= != ~ !~ ^ $ > >= < <=`, `IN (...)`, `CONTAINS [ANY|ALL] (...)`, and
`IS [NOT] NULL|EMPTY`. See the [OQL reference](../reference/oql.md) for the complete list.

## Use a query as a run scope

The same OQL that finds cases can define what a run executes. Pass it as the `oql` scope to
`create_run`:

```
create_run({ repo: "onetest-ai/tm-shop", name: "Critical smoke",
             oql: "tags CONTAINS 'smoke' AND priority = critical",
             env: "staging" })
```

The run materializes one execution per matching case. See
[Running test runs](running-test-runs.md) for the full run lifecycle. You can also add more cases to
an existing run by query with `add_to_run`.

## Saved queries and dynamic suites

For queries you reuse, you have two options:

- **Saved queries** — store an OQL string as a file in `.onetest/queries/*.oql` in the TM repo (or
  as a Project saved view on the QA Runs board). Reference it by name later.
- **Dynamic suites** — make a folder's membership a query. Add a `_suite.yml` with `dynamic: true`
  and an `oql:` query; the suite's members are computed on demand (for example when you build a run
  scoped to that folder):

  ```yaml
  # tests/regression/_suite.yml
  dynamic: true
  oql: "tags CONTAINS 'regression' AND status = 'ready'"
  ```

A dynamic suite always reflects the current state of your cases — add a matching case and it joins
the suite automatically, with no manual upkeep. See
[Authoring test cases](authoring-test-cases.md#dynamic-suites-oql) for more.

## See also

- [OQL reference](../reference/oql.md) — full syntax, operators, and fields.
- [Running test runs](running-test-runs.md) — use a query as a run scope.
- [Authoring test cases](authoring-test-cases.md) — dynamic suites and tags.
- [Test case format reference](../reference/test-case-format.md) — the fields you can query.
