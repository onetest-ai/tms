import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
import _migrate  # noqa: E402


class FmFixTest(unittest.TestCase):
    def test_bom_and_blank(self):
        bom = "﻿---\nid: X\n---\n# b\n"
        blank = "\n\n---\nid: X\n---\n# b\n"
        clean = "---\nid: X\n---\n# b\n"
        self.assertTrue(_migrate.needs_fm_fix(bom))
        self.assertTrue(_migrate.needs_fm_fix(blank))
        self.assertFalse(_migrate.needs_fm_fix(clean))
        self.assertEqual(_migrate.fix_fm(bom), clean)
        self.assertEqual(_migrate.fix_fm(blank), clean)
        self.assertEqual(_migrate.fix_fm(clean), clean)

    def test_body_only_no_frontmatter(self):
        body = "# Title\nContent\n"
        self.assertFalse(_migrate.needs_fm_fix(body))
        self.assertEqual(_migrate.fix_fm(body), body)


import shutil, tempfile  # noqa: E402


class ReassignTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.t = os.path.join(self.tmp, "tests")
        os.makedirs(os.path.join(self.t, "a"))
        os.makedirs(os.path.join(self.t, "b"))
        # ELITEA-10 collides across a/ and b/; ELITEA-12 is unique
        with open(os.path.join(self.t, "a", "ELITEA-10_x.md"), "w") as f:
            f.write("---\nid: ELITEA-10\ntitle: X\n---\n# x\n")
        with open(os.path.join(self.t, "b", "ELITEA-10_y.md"), "w") as f:
            f.write("---\nid: ELITEA-10\ntitle: Y\nduplicate_of: ELITEA-10\n---\n# y\n")
        with open(os.path.join(self.t, "a", "ELITEA-12_z.md"), "w") as f:
            f.write("---\nid: ELITEA-12\ntitle: Z\n---\n# z\n")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_plan_and_apply(self):
        recs = _migrate.scan(self.t)
        self.assertEqual(_migrate.max_seq(recs), 12)
        plan = _migrate.plan_reassign(recs)
        self.assertEqual(len(plan), 1)                       # only the non-canonical ELITEA-10
        item = plan[0]
        self.assertEqual(item["old_id"], "ELITEA-10")
        self.assertEqual(item["new_id"], "ELITEA-0013")      # max+1, 4-digit
        self.assertTrue(item["path"].endswith(os.path.join("b", "ELITEA-10_y.md")))  # b > a → non-canonical
        _migrate.apply_reassign(item)
        self.assertFalse(os.path.exists(item["path"]))
        with open(item["new_path"]) as f:
            new = f.read()
        self.assertIn("id: ELITEA-0013", new)
        self.assertIn("duplicate_of: ELITEA-0013", new)      # self-ref updated
        # no duplicate IDs remain
        ids = [r["id"] for r in _migrate.scan(self.t)]
        self.assertEqual(len(ids), len(set(ids)))


if __name__ == "__main__":
    unittest.main()
