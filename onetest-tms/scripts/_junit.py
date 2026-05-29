#!/usr/bin/env python3
"""Parse a JUnit XML report into the normalized launch JSON (receiver-equivalent)."""
import argparse, json, sys, xml.etree.ElementTree as ET


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    root = ET.parse(a.file).getroot()
    items = []
    total = passed = failed = skipped = 0
    for tc in root.iter("testcase"):
        cls, name = tc.get("classname", ""), tc.get("name", "")
        code_ref = f"{cls}.{name}" if cls else name
        dur = int(float(tc.get("time", "0") or 0) * 1000)
        f, e, sk = tc.find("failure"), tc.find("error"), tc.find("skipped")
        if f is not None or e is not None:
            el = f if f is not None else e
            status = "failed"
            msg = ((el.get("message") or "") + " " + (el.text or "")).strip()
        elif sk is not None:
            status, msg = "skipped", ""
        else:
            status, msg = "passed", ""
        total += 1
        passed += status == "passed"; failed += status == "failed"; skipped += status == "skipped"
        items.append({"code_ref": code_ref, "name": name, "status": status,
                      "duration_ms": dur, "failure_message": msg})
    out = {"launch": {"total": total, "passed": passed, "failed": failed, "skipped": skipped},
           "items": items}
    s = json.dumps(out, indent=2, ensure_ascii=False)
    if a.out:
        open(a.out, "w", encoding="utf-8").write(s + "\n")
    print(f"parsed {total} tests ({passed} passed, {failed} failed, {skipped} skipped)", file=sys.stderr)
    if not a.out:
        print(s)


if __name__ == "__main__":
    main()
