#!/usr/bin/env python3
"""Repair a test-case corpus for the Obsidian vault (dry-run unless --apply).

Fixes: BOM/leading-blank before front-matter; reassigns duplicate IDs
(keep canonical, renumber the rest); inserts `aliases: [<ID>]`.
"""
import argparse, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# id line, tolerant of optional surrounding quotes: `id: ELITEA-1` or `id: "ELITEA-1"`
_ID_LINE = re.compile(r'^id:\s*["\']?([^"\'\s]+)')


def needs_fm_fix(text):
    if text.startswith("﻿"):
        return True
    i = 0
    lines = text.splitlines()
    while i < len(lines) and lines[i].strip() == "":
        i += 1
    return i > 0 and i < len(lines) and lines[i].strip() == "---"


def fix_fm(text):
    if text.startswith("﻿"):
        text = text[1:]
    lines = text.splitlines(keepends=True)
    while lines and lines[0].strip() == "":
        lines.pop(0)
    return "".join(lines)


ID_RE = re.compile(r"^([A-Za-z][A-Za-z0-9]*)-(\d+)$")


def scan(tests_dir):
    recs = []
    for root, _, files in os.walk(tests_dir):
        for f in sorted(files):
            if not f.endswith(".md") or f == "README.md":
                continue
            p = os.path.join(root, f)
            with open(p, encoding="utf-8") as fh:
                text = fh.read()
            if needs_fm_fix(text):
                # in-memory only — scan() must never write to disk
                text = fix_fm(text)
            lines = text.splitlines()
            if not lines or lines[0].strip() != "---":
                continue
            end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
            if end is None:
                continue
            cid = None
            for ln in lines[1:end]:
                m = _ID_LINE.match(ln)
                if m:
                    cid = m.group(1)
                    break
            if not isinstance(cid, str) or not ID_RE.match(cid):
                continue
            recs.append({"id": cid, "path": p, "seq": int(ID_RE.match(cid).group(2))})
    return recs


def max_seq(records):
    return max((r["seq"] for r in records), default=0)


def _key(cid):
    return ID_RE.match(cid).group(1)


def plan_reassign(records):
    by_id = {}
    for r in records:
        by_id.setdefault(r["id"], []).append(r)
    nxt = max_seq(records) + 1
    plan = []
    for cid, group in sorted(by_id.items()):
        if len(group) < 2:
            continue
        # canonical = smallest path; renumber the rest
        for r in sorted(group, key=lambda x: x["path"])[1:]:
            new_id = f"{_key(cid)}-{nxt:04d}"
            nxt += 1
            slug = os.path.basename(r["path"]).split("_", 1)[1] if "_" in os.path.basename(r["path"]) else os.path.basename(r["path"])
            new_path = os.path.join(os.path.dirname(r["path"]), f"{new_id}_{slug}")
            plan.append({"old_id": cid, "new_id": new_id, "path": r["path"], "new_path": new_path})
    return plan


def apply_reassign(item):
    with open(item["path"], encoding="utf-8") as f:
        text = f.read()
    text = re.sub(rf"(?m)^id:\s*{re.escape(item['old_id'])}\s*$", f"id: {item['new_id']}", text)
    text = re.sub(rf"(?m)^duplicate_of:\s*{re.escape(item['old_id'])}\s*$",
                  f"duplicate_of: {item['new_id']}", text)
    with open(item["new_path"], "w", encoding="utf-8") as f:
        f.write(text)
    if os.path.normpath(item["new_path"]) != os.path.normpath(item["path"]):
        os.remove(item["path"])


def add_alias(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return False
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return False
    fm = lines[1:end]
    if any(re.match(r"^\s*aliases:", ln) for ln in fm):
        return False
    idx = next((i for i, ln in enumerate(fm) if _ID_LINE.match(ln)), None)
    if idx is None:
        return False
    cid = _ID_LINE.match(fm[idx]).group(1)
    fm.insert(idx + 1, f"aliases: [{cid}]\n")
    new = lines[:1] + fm + lines[end:]
    with open(path, "w", encoding="utf-8") as f:
        f.write("".join(new))
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="tests")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    # 1) FM fix
    fm_fixes = []
    for root, _, files in os.walk(a.dir):
        for f in files:
            if f.endswith(".md") and f != "README.md":
                p = os.path.join(root, f)
                with open(p, encoding="utf-8") as fh:
                    t = fh.read()
                if needs_fm_fix(t):
                    fm_fixes.append(p)
                    if a.apply:
                        with open(p, "w", encoding="utf-8") as fh:
                            fh.write(fix_fm(t))

    # 2) reassign duplicate IDs
    plan = plan_reassign(scan(a.dir))
    if a.apply:
        for it in plan:
            apply_reassign(it)

    # 3) aliases (after reassignment so IDs are unique)
    alias_added = 0
    for r in scan(a.dir):
        if a.apply and add_alias(r["path"]):
            alias_added += 1

    mode = "APPLIED" if a.apply else "DRY-RUN"
    print(f"[{mode}] fm-fix: {len(fm_fixes)} files")
    print(f"[{mode}] reassign: {len(plan)} files (old->new):")
    for it in plan:
        print(f"    {it['old_id']} -> {it['new_id']}  {it['new_path']}")
    print(f"[{mode}] aliases added: {alias_added}" if a.apply
          else f"[{mode}] aliases: would add to cases missing one")


if __name__ == "__main__":
    main()
