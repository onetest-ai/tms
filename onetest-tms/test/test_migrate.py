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


if __name__ == "__main__":
    unittest.main()
