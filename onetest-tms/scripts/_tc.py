#!/usr/bin/env python3
"""Test-case front-matter + body reader (no external deps).

Modes:
  _tc.py --tsv       FILE                   id<TAB>title<TAB>priority<TAB>size<TAB>targets(csv)<TAB>tags(csv)
  _tc.py --steps     FILE [--base-url URL]   "- [ ] N. action → expected" checklist
  _tc.py --exec-body FILE [--base-url URL]   full execution-issue body (preconditions, test data,
                                             steps, expected final state) with {{base_url}} substituted
"""
import sys

# Windows stdout defaults to the system codepage (cp1252) and crashes on UTF-8
# characters (≥ → □) common in test-case bodies. Force UTF-8 when printing.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def read_frontmatter(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
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
        if val.startswith("["):
            inner = val[1:val.index("]")] if "]" in val else val[1:]
            fm[key] = [x.strip().strip("\"'") for x in inner.split(",") if x.strip()]
            continue
        val = val if val[:1] in ("'", '"') else _strip_comment(val)
        fm[key] = [] if val == "" else val.strip("\"'")
    return fm, body


def _strip_comment(v):
    i = v.find(" #")
    return (v[:i] if i != -1 else v).strip()


def csv(v):
    return ",".join(v) if isinstance(v, list) else (v or "")


def sections(body):
    """Map '## Heading' (lowercased) -> list of lines, trimmed of blank ends."""
    out, cur = {}, None
    for ln in body:
        if ln.startswith("## "):
            cur = ln[3:].strip().lower(); out[cur] = []
        elif cur is not None:
            out[cur].append(ln)
    for k in out:
        while out[k] and not out[k][0].strip():
            out[k].pop(0)
        while out[k] and not out[k][-1].strip():
            out[k].pop()
    return out


def step_rows(body):
    rows, in_steps = [], False
    for ln in body:
        low = ln.strip().lower()
        if low.startswith("## steps"):
            in_steps = True; continue
        if in_steps and ln.startswith("## "):
            break
        if in_steps and ln.lstrip().startswith("|"):
            cells = [c.strip() for c in ln.strip().strip("|").split("|")]
            if len(cells) >= 3 and cells[0].isdigit():
                rows.append((cells[0], cells[1], cells[2]))
    return rows


def checklist(body, base):
    return [f"- [ ] {n}. {sub(a, base)} → {sub(e, base)}" for n, a, e in step_rows(body)]


def sub(s, base):
    return s.replace("{{base_url}}", base) if base else s


def exec_body(body, base):
    sec = sections(body)
    out = []
    if "preconditions" in sec:
        out += ["## Preconditions", *[sub(x, base) for x in sec["preconditions"]], ""]
    if "test data" in sec:
        out += ["## Test Data", *[sub(x, base) for x in sec["test data"]], ""]
    out += ["## Steps", *checklist(body, base), ""]
    if "expected final state" in sec:
        out += ["## Expected Final State", *[sub(x, base) for x in sec["expected final state"]], ""]
    return "\n".join(out).rstrip()


def main():
    args = sys.argv[1:]
    mode, path = args[0], args[1]
    base = args[args.index("--base-url") + 1] if "--base-url" in args else ""
    fm, body = read_frontmatter(path)
    if mode == "--tsv":
        print("\t".join([fm.get("id", ""), fm.get("title", ""), fm.get("priority", ""),
                          fm.get("size", ""), csv(fm.get("targets", "")), csv(fm.get("tags", ""))]))
    elif mode == "--steps":
        print("\n".join(checklist(body, base)))
    elif mode == "--exec-body":
        print(exec_body(body, base))


if __name__ == "__main__":
    main()
