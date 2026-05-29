#!/usr/bin/env python3
"""Resolve an environment's base URL from .onetest/config.yml (no yaml dep).

Usage: _cfg.py --env staging [--config .onetest/config.yml]
Prints the URL for the named env, else the default env's URL, else nothing.
"""
import argparse, re


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", default="")
    ap.add_argument("--config", default=".onetest/config.yml")
    a = ap.parse_args()
    try:
        lines = open(a.config, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        return
    envs, inblk, cur = [], False, None
    for ln in lines:
        if re.match(r"^environments:\s*$", ln):
            inblk = True; continue
        if inblk:
            if re.match(r"^\S", ln):
                inblk = False
                continue
            m = re.match(r"\s*-\s*name:\s*(.+?)\s*$", ln)
            if m:
                cur = {"name": m.group(1).strip("\"'"), "url": "", "default": False}; envs.append(cur); continue
            m = re.match(r"\s*url:\s*(.+?)\s*$", ln)
            if m and cur:
                cur["url"] = m.group(1).strip().strip("\"'"); continue
            m = re.match(r"\s*default:\s*(.+?)\s*$", ln)
            if m and cur:
                cur["default"] = m.group(1).strip().lower() == "true"
    url = next((e["url"] for e in envs if a.env and e["name"] == a.env), "")
    if not url:
        url = next((e["url"] for e in envs if e["default"]), "")
    if url:
        print(url)


if __name__ == "__main__":
    main()
