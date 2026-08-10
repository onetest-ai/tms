import os, shutil, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
import _index, _vault  # noqa: E402

CASE_A = """---
id: ELITEA-1368
title: SQL Toolkit runs
module: alita-sdk
requirements: [EliteaAI/elitea_issues#4972]
---
# body
"""
CASE_B = """---
id: ELITEA-1400
title: SQL Toolkit errors
module: alita-sdk
requirements: [EliteaAI/elitea_issues#4972, ProjectAlita/projectalita.github.io#10]
---
# body
"""


def index_cases(tests_dir):
    out = []
    for root, _, files in os.walk(tests_dir):
        for f in sorted(files):
            if f.endswith(".md") and f != "README.md":
                c = _index.case(os.path.join(root, f))
                if c:
                    out.append(c)
    return out


class RequirementProxyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.tests = os.path.join(self.tmp, "tests")
        d = os.path.join(self.tests, "alita-sdk")
        os.makedirs(d)
        with open(os.path.join(d, "ELITEA-1368_sql.md"), "w") as f:
            f.write(CASE_A)
        with open(os.path.join(d, "ELITEA-1400_sql-err.md"), "w") as f:
            f.write(CASE_B)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_sanitize_and_derive(self):
        self.assertEqual(_vault.safe_name("EliteaAI/elitea_issues#4972"),
                         "EliteaAI-elitea_issues-4972")
        self.assertEqual(_vault.derive_url("EliteaAI/elitea_issues#4972", None),
                         "https://github.com/EliteaAI/elitea_issues/issues/4972")
        self.assertIsNone(_vault.derive_url("4972", None))
        self.assertEqual(_vault.derive_url("4972", "EliteaAI/elitea_issues"),
                         "https://github.com/EliteaAI/elitea_issues/issues/4972")

    def test_proxy_note(self):
        cases = index_cases(self.tests)
        covers = _vault.collect_requirements(cases)
        self.assertEqual(sorted(covers["EliteaAI/elitea_issues#4972"]),
                         ["ELITEA-1368", "ELITEA-1400"])
        _vault.write_requirements(self.tests, covers)
        p = os.path.join(self.tests, "_meta", "requirements",
                         "EliteaAI-elitea_issues-4972.md")
        with open(p) as f:
            note = f.read()
        self.assertIn('aliases: ["EliteaAI/elitea_issues#4972"]', note)
        self.assertIn("url: https://github.com/EliteaAI/elitea_issues/issues/4972", note)
        self.assertIn("[[ELITEA-1368]]", note)
        self.assertIn("[[ELITEA-1400]]", note)
        self.assertIn(_vault.GEN_MARK, note)
        self.assertIsNone(_index.case(p))  # id-less → excluded


class MocTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.tests = os.path.join(self.tmp, "tests")
        d = os.path.join(self.tests, "alita-sdk", "jira")
        os.makedirs(d)
        with open(os.path.join(d, "ELITEA-1368_sql.md"), "w") as f:
            f.write(CASE_A.replace("alita-sdk", "jira"))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_moc_tree_and_links(self):
        cases = index_cases(self.tests)
        _vault.write_mocs(self.tests, cases)
        with open(os.path.join(self.tests, "_index.md")) as f:
            root = f.read()
        self.assertIn("[[alita-sdk/_index|alita-sdk]]", root)
        with open(os.path.join(self.tests, "alita-sdk", "_index.md")) as f:
            mid = f.read()
        self.assertIn("[[alita-sdk/jira/_index|jira]]", mid)
        with open(os.path.join(self.tests, "alita-sdk", "jira", "_index.md")) as f:
            leaf = f.read()
        self.assertIn("[[ELITEA-1368]] — SQL Toolkit runs", leaf)
        self.assertIsNone(_index.case(os.path.join(self.tests, "_index.md")))


class PruneTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.tests = os.path.join(self.tmp, "tests")
        d = os.path.join(self.tests, "alita-sdk")
        os.makedirs(d)
        with open(os.path.join(d, "ELITEA-1368_sql.md"), "w") as f:
            f.write(CASE_A)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_prune_removes_stale_keeps_authored(self):
        cases = index_cases(self.tests)
        written = _vault.write_requirements(self.tests, _vault.collect_requirements(cases)) \
            + _vault.write_mocs(self.tests, cases)
        stale = os.path.join(self.tests, "_meta", "requirements", "OLD-1.md")
        with open(stale, "w") as f:
            f.write(f"---\naliases: [OLD-1]\n---\n# OLD\n<!-- {_vault.GEN_MARK} -->\n")
        authored = os.path.join(self.tests, "alita-sdk", "notes.md")
        with open(authored, "w") as f:
            f.write("# keep me\n")
        removed = _vault.prune(self.tests, written)
        self.assertIn(os.path.normpath(stale), [os.path.normpath(p) for p in removed])
        self.assertFalse(os.path.exists(stale))
        self.assertTrue(os.path.exists(authored))
        self.assertTrue(os.path.exists(os.path.join(self.tests, "_index.md")))


if __name__ == "__main__":
    unittest.main()
