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
