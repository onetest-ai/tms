#!/usr/bin/env python3
"""Build index.json from test-case front-matter (backs oql-search & coverage)."""
import argparse, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _tc import read_frontmatter

SCALARS = ["id", "title", "status", "execution_type", "type", "priority", "size", "module", "owner"]
LISTS = ["tags", "requirements", "automation_test_id", "targets", "dependencies", "known_issues"]


def case(path):
    fm, _ = read_frontmatter(path)
    if not fm.get("id"):
        return None
    d = {k: fm.get(k, "") for k in SCALARS}
    for k in LISTS:
        v = fm.get(k, [])
        d[k] = v if isinstance(v, list) else ([v] if v else [])
    d["path"] = path
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="tests")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    cases = []
    for root, _, files in os.walk(a.dir):
        for f in sorted(files):
            if f.endswith(".md") and f != "README.md":
                c = case(os.path.join(root, f))
                if c:
                    cases.append(c)
    out = json.dumps({"cases": cases}, indent=2, ensure_ascii=False)
    if a.out:
        open(a.out, "w", encoding="utf-8").write(out + "\n")
    print(f"{len(cases)} cases indexed", file=sys.stderr)
    if not a.out:
        print(out)


if __name__ == "__main__":
    main()
