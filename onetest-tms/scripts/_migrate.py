#!/usr/bin/env python3
"""Repair a test-case corpus for the Obsidian vault (dry-run unless --apply).

Fixes: BOM/leading-blank before front-matter; reassigns duplicate IDs
(keep canonical, renumber the rest); inserts `aliases: [<ID>]`.
"""
import argparse, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _tc import read_frontmatter  # noqa: E402


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
            fm, _b = read_frontmatter(p)
            cid = fm.get("id")
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
