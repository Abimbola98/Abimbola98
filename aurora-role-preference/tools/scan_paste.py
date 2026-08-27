#!/usr/bin/env python3
"""
Pre-push scanner for the generated paste files.

Every rule below encodes a failure that actually happened when pasting into this
environment's Power Apps Studio. Run it after tools/gen_paste.py and before any
commit; a clean run is the closest thing this project has to a test suite,
because "correct" here means "Studio accepts the paste and the screen renders".

Rules
  1  valid YAML, and the document is a top-level LIST (not the Screens: mapping)
  2  no `#` comments, no blank lines            -> PA1001 YamlInvalidSyntax
  3  control ids are version-pinned and known   -> silently dropped on paste
  4  inside `|-` block scalars: no line starts `Name: value`, no bare braces
                                                -> PA1001 "found invalid mapping"
  5  no `: ` inside a single-line `=...` value  -> same; use a |- block scalar
  6  no duplicate property keys in one Properties: block
                                                -> PA1001 Duplicate name 'X'
  7  no line over 260 chars                     -> precautionary
  8  every control referenced by a height/visibility formula exists on the SAME
     screen and collides with no control on another screen. Studio renames a
     clashing pasted control (lblFoo -> lblFoo_1), which would silently point a
     parent's Height formula at the wrong control.

Exit status 1 if anything is reported.
"""
import glob
import os
import re
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASTE = os.path.join(ROOT, "paste")
SRC = os.path.join(ROOT, "Src")

# Version-pinned control ids confirmed in this environment. A control whose id
# Studio does not recognise is dropped from the paste WITHOUT an error - that is
# what produced an empty container in early rounds.
OK_CONTROLS = {
    "GroupContainer@1.5.0",
    "Label@2.5.1",
    "Gallery@2.15.0",
    "Classic/DropDown@2.3.1",
    "Classic/TextInput@2.3.2",
}

problems = 0


def bad(where, msg):
    global problems
    problems += 1
    print(f"  !! {where}: {msg}")


def scan_file(path):
    f = os.path.basename(path)
    raw = open(path).read()
    lines = raw.split("\n")

    # 1 - valid YAML, top-level list
    try:
        doc = yaml.safe_load(raw)
        if not isinstance(doc, list):
            bad(f, f"top level is {type(doc).__name__}, expected list")
    except Exception as exc:
        bad(f, f"YAML parse error: {exc}")
        return

    # 2 - comments and blank lines
    for i, ln in enumerate(lines, 1):
        if ln.strip().startswith("#"):
            bad(f, f"line {i}: comment survived generation")
        if ln.strip() == "" and i < len(lines):
            bad(f, f"line {i}: blank line survived generation")

    # 3 - control ids
    for i, ln in enumerate(lines, 1):
        m = re.match(r"\s*Control:\s*(\S+)", ln)
        if m and m.group(1) not in OK_CONTROLS:
            bad(f, f"line {i}: unknown/unversioned control '{m.group(1)}'")

    # 4 - block-scalar hazards
    in_block, block_indent = False, 0
    for i, ln in enumerate(lines, 1):
        stripped = ln.strip()
        if in_block:
            indent = len(ln) - len(ln.lstrip())
            if stripped and indent < block_indent:
                in_block = False
            else:
                if re.match(r"^[A-Za-z_][A-Za-z0-9_ ]*:\s", stripped):
                    bad(f, f"line {i}: block-scalar line starts 'Name: value'")
                if stripped in ("{", "}", "},", "{,"):
                    bad(f, f"line {i}: bare brace on its own line in a block scalar")
                continue
        if re.search(r":\s*\|-\s*$", ln):
            in_block = True
            block_indent = len(ln) - len(ln.lstrip()) + 1

    # 5 - ': ' inside a single-line value
    for i, ln in enumerate(lines, 1):
        m = re.match(r"\s*([A-Za-z]+):\s*=(.*)$", ln)
        if m and ": " in m.group(2):
            bad(f, f"line {i}: ': ' in a single-line value - use a |- block scalar")

    # 6 - duplicate property keys
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s*)Properties:\s*$", lines[i])
        if m:
            base = len(m.group(1))
            seen, j = {}, i + 1
            while j < len(lines):
                ln = lines[j]
                if not ln.strip():
                    j += 1
                    continue
                ind = len(ln) - len(ln.lstrip())
                if ind <= base:
                    break
                if ind == base + 2:
                    km = re.match(r"\s*([A-Za-z0-9_]+):", ln)
                    if km:
                        k = km.group(1)
                        if k in seen:
                            bad(f, f"line {j+1}: duplicate property '{k}' (first at line {seen[k]})")
                        seen[k] = j + 1
                j += 1
            i = j
        else:
            i += 1

    # 7 - long lines
    for i, ln in enumerate(lines, 1):
        if len(ln) > 260:
            bad(f, f"line {i}: {len(ln)} chars (>260)")

    print(f"  ok  {f} ({len(lines)} lines)")


def scan_cross_screen_names():
    names = {
        os.path.basename(p): set(
            re.findall(r"^\s*- ([A-Za-z][A-Za-z0-9_]*):\s*$", open(p).read(), re.M)
        )
        for p in glob.glob(os.path.join(PASTE, "*.controls.yaml"))
    }
    for f, ns in sorted(names.items()):
        txt = open(os.path.join(PASTE, f)).read()
        refs = set(re.findall(r"\b([a-z][A-Za-z0-9_]*)\.(?:Height|Width|Text|Visible)\b", txt))
        for r in sorted(refs):
            if r in ("Parent", "Self", "ThisItem"):
                continue
            if r not in ns:
                bad(f, f"formula references '{r}', which is not a control on this screen")
            else:
                clash = [g for g, n in names.items() if g != f and r in n]
                if clash:
                    bad(f, f"'{r}' is referenced by formula but also exists on {clash}")


def main():
    for path in sorted(glob.glob(os.path.join(PASTE, "*.controls.yaml"))):
        scan_file(path)
    scan_cross_screen_names()
    for path in sorted(glob.glob(os.path.join(SRC, "*.pa.yaml"))):
        try:
            yaml.safe_load(open(path).read())
        except Exception as exc:
            bad(os.path.basename(path), f"Src YAML parse error: {exc}")
    print("\nPROBLEMS:", problems)
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
