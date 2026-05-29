#!/usr/bin/env python3
"""Automation coverage from index.json (+ optional correlation.json).

Mirrors OneTest's automation-coverage: marked_automated, linked_to_results,
no_automation_ref, automation_gap (+%), and a per-priority breakdown.
Writes a Markdown report; prints a one-line summary.
"""
import argparse, json, os, sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", default="index.json")
    ap.add_argument("--correlation", default="reports/correlation.json")
    ap.add_argument("--out", default="reports/coverage.md")
    a = ap.parse_args()
    cases = json.load(open(a.index, encoding="utf-8")).get("cases", [])
    linked = set()
    if os.path.exists(a.correlation):
        for m in json.load(open(a.correlation, encoding="utf-8")).get("matched", []):
            linked.add(m["case_id"])

    total = len(cases)
    autos = [c for c in cases if c.get("execution_type") == "automated"]
    marked = len(autos)
    linked_to = sum(1 for c in autos if c["id"] in linked)
    no_ref = sum(1 for c in autos if not c.get("automation_test_id"))
    gap = sum(1 for c in autos if c.get("automation_test_id") and c["id"] not in linked)
    gap_pct = (100 * gap / marked) if marked else 0.0

    prios = {}
    for c in cases:
        p = c.get("priority") or "—"
        prios.setdefault(p, {"total": 0, "automated": 0})
        prios[p]["total"] += 1
        if c.get("execution_type") == "automated":
            prios[p]["automated"] += 1

    L = ["# Automation Coverage\n", "## Summary\n",
         "| Metric | Count |", "|--------|-------|",
         f"| Total test cases | {total} |",
         f"| Marked automated | {marked} |",
         f"| ✅ Linked to CI results | {linked_to} |",
         f"| 🟧 No automation ref set | {no_ref} |",
         f"| 🟥 Automation gap (ref, no CI match) | {gap} |",
         f"| Automation gap % | {gap_pct:.1f}% |",
         "\n## Coverage by priority\n",
         "| Priority | Total | Automated | Gap % |", "|----------|-------|-----------|-------|"]
    for p in ("critical", "high", "medium", "low", "—"):
        if p in prios:
            t, au = prios[p]["total"], prios[p]["automated"]
            L.append(f"| {p} | {t} | {au} | {(100*(t-au)/t):.1f}% |")
    L += ["\n> 🟥 gaps = cases marked automated with an `automation_test_id` that matched no CI "
          "`code_ref`. Fix the ref, or revert to manual.\n"]
    open(a.out, "w", encoding="utf-8").write("\n".join(L))
    print(f"total={total} automated={marked} linked={linked_to} no_ref={no_ref} gap={gap} ({gap_pct:.1f}%)")


if __name__ == "__main__":
    main()
