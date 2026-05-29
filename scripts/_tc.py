#!/usr/bin/env python3
"""Minimal test-case front-matter + steps reader (no external deps).

Usage:
  _tc.py --tsv   FILE   # id<TAB>title<TAB>priority<TAB>size<TAB>targets(csv)<TAB>tags(csv)
  _tc.py --steps FILE   # "- [ ] N. action -> expected" lines (from the ## Steps table)
"""
import sys


def read_frontmatter(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, lines
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return {}, lines
    fm, body = {}, lines[end + 1:]
    key = None
    for ln in lines[1:end]:
        if ln.lstrip().startswith("- ") and key and isinstance(fm.get(key), list):
            fm[key].append(_strip_comment(ln.split("- ", 1)[1].strip()).strip("\"'"))
            continue
        if ":" not in ln or ln.startswith(" "):
            continue
        key, val = ln.split(":", 1)
        key, val = key.strip(), val.strip()
        if val.startswith("["):                              # inline list (maybe trailing comment)
            inner = val[1:val.index("]")] if "]" in val else val[1:]
            fm[key] = [x.strip().strip("\"'") for x in inner.split(",") if x.strip()]
            continue
        val = val if val[:1] in ("'", '"') else _strip_comment(val)
        fm[key] = [] if val == "" else val.strip("\"'")      # "" → opens a block list
    return fm, body


def _strip_comment(v):
    """Drop a trailing ' #...' comment from an unquoted scalar."""
    i = v.find(" #")
    return (v[:i] if i != -1 else v).strip()


def csv(v):
    return ",".join(v) if isinstance(v, list) else (v or "")


def steps(body):
    out, in_steps = [], False
    for ln in body:
        if ln.strip().lower().startswith("## steps"):
            in_steps = True
            continue
        if in_steps and ln.startswith("## "):
            break
        if in_steps and ln.lstrip().startswith("|"):
            cells = [c.strip() for c in ln.strip().strip("|").split("|")]
            if len(cells) >= 3 and cells[0].isdigit():
                out.append(f"- [ ] {cells[0]}. {cells[1]} -> {cells[2]}")
    return out


def main():
    mode, path = sys.argv[1], sys.argv[2]
    fm, body = read_frontmatter(path)
    if mode == "--tsv":
        print("\t".join([fm.get("id", ""), fm.get("title", ""),
                         fm.get("priority", ""), fm.get("size", ""),
                         csv(fm.get("targets", "")), csv(fm.get("tags", ""))]))
    elif mode == "--steps":
        print("\n".join(steps(body)))


if __name__ == "__main__":
    main()
