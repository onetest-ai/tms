#!/usr/bin/env python3
"""Minimal OQL evaluator over index.json (a practical subset of OneTest OQL).

Supports: = != ~ !~ ^ $ > >= < <= , IN/NOT IN (...), CONTAINS [ANY|ALL] (...),
IS [NOT] NULL/EMPTY, LIKE, AND/OR/NOT, parentheses, ORDER BY f [ASC|DESC],
LIMIT n, OFFSET n. String compares are case-insensitive.

Usage: _oql.py --query "tags CONTAINS 'smoke' AND priority IN (critical, high)" \
               [--index index.json] [--ids|--json]
"""
import argparse, json, re, sys

KW = {"AND", "OR", "NOT", "IN", "CONTAINS", "ANY", "ALL", "IS", "NULL", "EMPTY",
      "ORDER", "BY", "ASC", "DESC", "LIMIT", "OFFSET", "LIKE", "BETWEEN"}
TWO = {"!=", ">=", "<=", "!~", "~="}


def tokenize(s):
    toks, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c in " \t\r\n":
            i += 1; continue
        if c == "#":
            while i < n and s[i] != "\n":
                i += 1
            continue
        if c in "'\"":
            j = i + 1; buf = ""
            while j < n and s[j] != c:
                buf += s[j]; j += 1
            toks.append(("str", buf)); i = j + 1; continue
        if s[i:i + 2] in TWO:
            toks.append(("op", s[i:i + 2])); i += 2; continue
        if c in "=<>~^$(),":
            toks.append(("op", c)); i += 1; continue
        m = re.match(r"-?\d+(\.\d+)?", s[i:])
        if m and c not in "_":
            toks.append(("num", m.group(0))); i += len(m.group(0)); continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_.]*", s[i:])
        if m:
            w = m.group(0); i += len(w)
            toks.append(("kw", w.upper()) if w.upper() in KW else ("ident", w)); continue
        raise SystemExit(f"OQL: unexpected character {c!r}")
    toks.append(("end", ""))
    return toks


class P:
    def __init__(self, toks): self.t, self.i = toks, 0
    def peek(self): return self.t[self.i]
    def nx(self): self.i += 1; return self.t[self.i - 1]
    def eat(self, val):
        k, v = self.peek()
        if v != val and k != val:
            raise SystemExit(f"OQL: expected {val!r}, got {v!r}")
        return self.nx()

    def parse(self):
        node = None
        if self.peek()[1] not in ("ORDER", "LIMIT", "OFFSET", ""):
            node = self.or_()
        order = limit = offset = None
        order_dir = "ASC"
        if self.peek()[1] == "ORDER":
            self.nx(); self.eat("BY"); order = self.nx()[1]
            if self.peek()[1] in ("ASC", "DESC"):
                order_dir = self.nx()[1]
        if self.peek()[1] == "LIMIT":
            self.nx(); limit = int(self.nx()[1])
        if self.peek()[1] == "OFFSET":
            self.nx(); offset = int(self.nx()[1])
        return node, order, order_dir, limit, offset

    def or_(self):
        n = self.and_()
        while self.peek()[1] == "OR":
            self.nx(); n = {"t": "or", "l": n, "r": self.and_()}
        return n

    def and_(self):
        n = self.not_()
        while self.peek()[1] == "AND":
            self.nx(); n = {"t": "and", "l": n, "r": self.not_()}
        return n

    def not_(self):
        if self.peek()[1] == "NOT":
            self.nx(); return {"t": "not", "x": self.not_()}
        return self.prim()

    def prim(self):
        if self.peek()[1] == "(":
            self.nx(); n = self.or_(); self.eat(")"); return n
        return self.cond()

    def val(self):
        k, v = self.nx()
        return v

    def vlist(self):
        self.eat("("); vals = [self.val()]
        while self.peek()[1] == ",":
            self.nx(); vals.append(self.val())
        self.eat(")"); return vals

    def cond(self):
        field = self.nx()[1]
        k, v = self.peek()
        if v == "IN":
            self.nx(); return {"t": "c", "f": field, "op": "in", "v": self.vlist()}
        if v == "NOT" and self.t[self.i + 1][1] == "IN":
            self.nx(); self.nx(); return {"t": "c", "f": field, "op": "not in", "v": self.vlist()}
        if v == "CONTAINS":
            self.nx()
            if self.peek()[1] == "ANY":
                self.nx(); return {"t": "c", "f": field, "op": "contains_any", "v": self.vlist()}
            if self.peek()[1] == "ALL":
                self.nx(); return {"t": "c", "f": field, "op": "contains_all", "v": self.vlist()}
            return {"t": "c", "f": field, "op": "contains", "v": self.val()}
        if v == "IS":
            self.nx(); neg = False
            if self.peek()[1] == "NOT":
                self.nx(); neg = True
            w = self.nx()[1]  # NULL | EMPTY
            return {"t": "c", "f": field, "op": ("is_not" if neg else "is"), "v": w.lower()}
        if v == "LIKE":
            self.nx(); return {"t": "c", "f": field, "op": "like", "v": self.val()}
        # binary operator
        op = self.nx()[1]
        return {"t": "c", "f": field, "op": op, "v": self.val()}


def _as_list(x):
    return x if isinstance(x, list) else ([] if x in (None, "") else [x])


def cond(rec, f, op, v):
    fv = rec.get(f)
    low = lambda x: str(x).lower()
    if op == "in":
        opts = [low(o) for o in v]
        return any(low(x) in opts for x in _as_list(fv))
    if op == "not in":
        return not cond(rec, f, "in", v)
    if op == "contains":
        return low(v) in [low(x) for x in _as_list(fv)]
    if op == "contains_any":
        return bool({low(x) for x in _as_list(fv)} & {low(x) for x in v})
    if op == "contains_all":
        return {low(x) for x in v} <= {low(x) for x in _as_list(fv)}
    if op in ("is", "is_not"):
        empty = (fv in (None, "")) or (isinstance(fv, list) and not fv)
        return empty if op == "is" else (not empty)
    if isinstance(fv, list) and op in ("=", "~", "~=", "like"):
        items = [low(x) for x in fv]
        return low(v) in items if op == "=" else any(low(v).strip("%") in x for x in items)
    sv = "" if fv is None else (",".join(map(str, fv)) if isinstance(fv, list) else str(fv))
    o = str(v)
    if op == "=":  return sv.lower() == o.lower()
    if op == "!=": return sv.lower() != o.lower()
    if op in ("~", "~=", "like"): return o.lower().strip("%") in sv.lower()
    if op == "!~": return o.lower() not in sv.lower()
    if op == "^":  return sv.lower().startswith(o.lower())
    if op == "$":  return sv.lower().endswith(o.lower())
    if op in (">", ">=", "<", "<="):
        try:
            a, b = float(sv), float(o)
        except ValueError:
            a, b = sv.lower(), o.lower()
        return {">": a > b, ">=": a >= b, "<": a < b, "<=": a <= b}[op]
    raise SystemExit(f"OQL: unknown operator {op!r}")


def ev(node, rec):
    if node is None:
        return True
    t = node["t"]
    if t == "and": return ev(node["l"], rec) and ev(node["r"], rec)
    if t == "or":  return ev(node["l"], rec) or ev(node["r"], rec)
    if t == "not": return not ev(node["x"], rec)
    return cond(rec, node["f"], node["op"], node["v"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query", required=True)
    ap.add_argument("--index", default="index.json")
    ap.add_argument("--ids", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    cases = json.load(open(a.index, encoding="utf-8")).get("cases", [])
    ast, order, odir, limit, offset = P(tokenize(a.query)).parse()
    res = [c for c in cases if ev(ast, c)]
    if order:
        res.sort(key=lambda c: str(c.get(order, "")).lower(), reverse=(odir == "DESC"))
    if offset:
        res = res[offset:]
    if limit is not None:
        res = res[:limit]
    if a.json:
        print(json.dumps(res, indent=2, ensure_ascii=False))
    elif a.ids:
        print("\n".join(c["id"] for c in res))
    else:
        print("\n".join(c["path"] for c in res))


if __name__ == "__main__":
    main()
