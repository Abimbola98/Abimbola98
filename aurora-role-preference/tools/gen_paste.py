#!/usr/bin/env python3
"""
Generate paste/<screen>.controls.yaml from Src/<screen>.pa.yaml.

Power Apps Studio's Code View paste expects a TOP-LEVEL LIST OF CONTROLS on the
clipboard, not the `Screens:` document that .pa.yaml (pack/unpack) format uses.
This strips the wrapper and normalises the result to what the deserializer
accepts:

  Src/scrX.pa.yaml                     paste/scrX.controls.yaml
  --------------------------------     -------------------------------
  Screens:                             - conRoot:
    scrX:                                  Control: GroupContainer@1.5.0
      Properties:            ---->         ...
        Fill: =...                     - conSomeOverlay:
      Children:                            ...
        - conRoot:
            Control: ...

Three transformations, all required:

  1. Drop everything up to and including the screen's `Children:` line. Screen
     PROPERTIES (Fill, OnVisible) are NOT carried by a control paste - they must
     be set by hand in Studio. See paste/HOW-TO-PASTE.md.
  2. Dedent by 6 spaces so the first control sits at column 0.
  3. Strip `#` comments and blank lines. Studio's YAML parser rejects them with
     `PA1001 ... YamlInvalidSyntax`. The Src files keep their comments for Git.

Usage:  python3 tools/gen_paste.py scrLanding
        python3 tools/gen_paste.py            # all screens
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Src")
OUT = os.path.join(ROOT, "paste")

SCREENS = [
    "scrLanding", "scrForm", "scrDetail", "scrReview",
    "scrQuestions", "scrCompleted", "scrOverview", "scrSubmissions",
    # Phase 2 - role alignment accept/reject
    "scrAlignment", "scrRejection", "scrAlignLocked",
]


def block(name):
    lines = open(os.path.join(SRC, name + ".pa.yaml")).read().split("\n")
    out, started = [], False
    for ln in lines:
        if not started:
            # the screen's own `    Children:` - 4 spaces, not deeper
            if ln.startswith("    Children:") and not ln.startswith("     "):
                started = True
            continue
        s = ln.strip()
        if s == "" or s.startswith("#"):
            continue
        out.append(ln[6:] if ln.startswith("      ") else ln)
    return "\n".join(out).rstrip() + "\n"


def main():
    names = sys.argv[1:] or SCREENS
    for name in names:
        text = block(name)
        with open(os.path.join(OUT, name + ".controls.yaml"), "w") as fh:
            fh.write(text)
        print(f"wrote {name}.controls.yaml ({len(text)} bytes)")


if __name__ == "__main__":
    main()
