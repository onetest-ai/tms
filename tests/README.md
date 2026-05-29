# Test cases

The folder tree under `tests/` **is** the suite structure (OneTest `test_folders`). Each test
case is one Markdown file with YAML front-matter:

```
tests/<suite>/<sub>/<ID>_<slug>.md      e.g. tests/authentication/login/TMS-0001_valid-login.md
```

- **ID** = `<source_key>-<seq>` from [`.onetest/config.yml`](../.onetest/config.yml), allocated by
  the `allocate-id` function — never hand-set, never reused.
- **Front-matter** must satisfy [`.onetest/fields.yml`](../.onetest/fields.yml) and
  [`.onetest/custom-fields.yml`](../.onetest/custom-fields.yml); enforced by the
  `validate-test-case` check on every PR.
- **URLs** use `{{base_url}}` — substituted at run time, keeping cases environment-agnostic.
- **Format** follows the
  [web-qa test-case format](https://github.com/arozumenko/sdlc-skills/blob/main/bundles/web-qa/knowledge/test-case-format.md)
  and the [GitHub-native test-case mapping](../design/github-native/01-test-case-management.md).

### Dynamic suites
A folder may contain a `_suite.yml` with `dynamic: true` and an `oql:` query; its membership is
computed on demand rather than stored.

```yaml
# tests/regression/_suite.yml
dynamic: true
oql: "tags CONTAINS 'regression' AND status = 'ready'"
```
