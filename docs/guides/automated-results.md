# Automated test results

When your CI runs automated tests, OneTest TMS pulls those results in and links each one back to a
test case. The link is made by matching a case's `automation_test_id` to the `code_ref` of a result
in your JUnit report. Once linked, the case counts as covered by CI and shows up in the
[coverage report](reports-and-coverage.md).

You bring results in with two steps your agent runs (or CI runs via the gh-CLI): **ingest** the
JUnit report into a normalized JSON file, then **correlate** it against your cases. This guide
covers wiring a case to its CI test and getting results to flow.

## 1. Mark the case automated and set its `automation_test_id`

On the test case front-matter, set `execution_type: automated` and add one or more
`automation_test_id` entries pointing at the automated test that covers it:

```yaml
execution_type: automated
automation_test_id:
  - tests/e2e/login.spec.ts:Login.valid
```

The value is the test's identity in your code, written as `file:Class.method`. A case can list
several ids — any one matching a CI result links the case. Edit this through the normal
[authoring PR workflow](authoring-test-cases.md).

## 2. Have CI emit a JUnit report

Your existing test workflow runs the suite and writes a JUnit XML report, then uploads it:

```yaml
- run: npx playwright test --reporter=junit   # or: pytest --junitxml=results.xml
  continue-on-error: true
- uses: actions/upload-artifact@v4
  if: always()
  with: { name: junit, path: results.xml }
```

No change to *how* you test — OneTest TMS only needs the report.

## 3. Ingest the report

`ingest_results` parses the JUnit XML into a normalized launch record at
`reports/automated/<run>.json` — totals plus a per-test entry (`code_ref`, status, duration,
failure message).

Agent (MCP):

```
ingest_results({ file: "results.xml" })
// → writes reports/automated/results.json
```

gh-CLI equivalent:

```
scripts/ingest-results.sh --file results.xml --commit
```

## 4. Correlate to test cases

`correlate_results` reads the launch JSON and the search index, normalizes every case's
`automation_test_id` and every result's `code_ref` to the same `file:Class.method` form, matches
them, and writes `reports/correlation.json`.

Agent (MCP):

```
correlate_results({ automated: "reports/automated/results.json" })
// → writes reports/correlation.json
```

gh-CLI equivalent:

```
scripts/correlate-results.sh --automated reports/automated/results.json --commit
```

The correlation record lists, per match: `{ test_case_id, code_ref, status, workflow_run,
confidence }`, plus any `code_ref`s that matched no case.

## How matching works

Matching is purely by reference, normalized on both sides:

```
case front-matter:   automation_test_id: tests/e2e/login.spec.ts:Login.valid
CI JUnit result:     code_ref:           tests/e2e/login.spec.ts::Login::valid
normalize both →     tests/e2e/login.spec.ts:Login.valid    ✓ linked
```

Normalization collapses framework-specific separators (for example pytest's `::`) to the canonical
`file:Class.method`, so a result links a case when **any** of the case's `automation_test_id`
values normalizes to the same string as the result's `code_ref`. A case marked automated whose ids
match nothing in CI is an **automation gap** (see below).

## Where results show up

- **`reports/correlation.json`** — the authoritative case-to-CI mapping.
- **`reports/coverage.md`** — `automation_coverage` reads the correlation file to report how many
  automated cases are actually linked to CI results. See
  [Reports and coverage](reports-and-coverage.md).
- **The case's execution history** — manual and automated outcomes merge per case.
- **CI job summary** — when ingest runs in CI, a pass/fail breakdown is emitted to the workflow run
  page (and can comment on the PR).

## Cross-repo note

If your test cases live in the TM repo but CI runs in a separate app/target repo, ingest happens in
the app repo (it owns the JUnit artifact) and the normalized results are dispatched to the TM repo,
where correlation and coverage run (it owns the `automation_test_id` refs). Both steps are the same
tools — only *where* they run differs.

## See also

- [Reports and coverage](reports-and-coverage.md) — read coverage and close gaps.
- [Test case format reference](../reference/test-case-format.md) — `execution_type`,
  `automation_test_id`.
- [MCP tools reference](../reference/mcp-tools.md) — `ingest_results`, `correlate_results`,
  `automation_coverage`.
- [Authoring test cases](authoring-test-cases.md) — edit a case to add its `automation_test_id`.
