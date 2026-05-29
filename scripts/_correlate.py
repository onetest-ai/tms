#!/usr/bin/env python3
"""Correlate automated results (code_ref) with test cases (automation_test_id).

Both sides normalize to file:Class.method (pytest '::' -> ':', whitespace -> none).
Writes reports/correlation.json: {matched:[{case_id,code_ref,status}], unmatched_refs:[...]}.
"""
import argparse, json, sys


def norm(ref):
    return ref.strip().replace("::", ":").replace(" ", "").lower()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", default="index.json")
    ap.add_argument("--automated", required=True, help="launch JSON from _junit.py / ingest")
    ap.add_argument("--out", default="reports/correlation.json")
    a = ap.parse_args()
    cases = json.load(open(a.index, encoding="utf-8")).get("cases", [])
    launch = json.load(open(a.automated, encoding="utf-8"))
    items = launch.get("items", [])

    # map normalized code_ref -> status
    code = {}
    for it in items:
        if it.get("code_ref"):
            code[norm(it["code_ref"])] = it.get("status", "")

    matched, used = [], set()
    for c in cases:
        for ref in c.get("automation_test_id", []):
            nr = norm(ref)
            if nr in code:
                matched.append({"case_id": c["id"], "code_ref": ref, "status": code[nr]})
                used.add(nr)
    unmatched = [it["code_ref"] for it in items if it.get("code_ref") and norm(it["code_ref"]) not in used]

    out = {"matched": matched, "unmatched_refs": sorted(set(unmatched))}
    open(a.out, "w", encoding="utf-8").write(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    print(f"matched {len(matched)} case-ref pair(s); {len(out['unmatched_refs'])} unmatched code_ref(s)", file=sys.stderr)


if __name__ == "__main__":
    main()
